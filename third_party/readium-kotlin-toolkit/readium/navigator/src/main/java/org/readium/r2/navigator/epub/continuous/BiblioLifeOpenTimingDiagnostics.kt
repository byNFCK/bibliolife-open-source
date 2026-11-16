package org.readium.r2.navigator.epub.continuous

import android.os.SystemClock
import android.util.Log
import java.util.concurrent.atomic.AtomicLong

/** Diagnostic-only correlation for one manually observed opening. */
public object BiblioLifeOpenTimingDiagnostics {
    private const val TAG = "BIBLIOLIFE_OPEN_TIMING"
    private val nextAttempt = AtomicLong(0)
    private val lock = Any()
    private var active: Attempt? = null
    private val nextHost = AtomicLong(0)
    public fun nextHostId(): String = "host-${nextHost.incrementAndGet()}"
    public fun lifecycle(stage: String, instanceId: String = "unavailable", sessionId: String = instanceId, hostId: String = "unavailable", generation: Long? = null, resourceGeneration: Long? = null, index: Int? = null, webViewId: Int? = null): Unit = synchronized(lock) {
        val attempt = active
        Log.d(TAG, buildString {
            append("lifecycle=").append(stage)
                .append(" elapsedMs=").append(SystemClock.elapsedRealtime())
                .append(" pid=").append(android.os.Process.myPid())
                .append(" instanceId=").append(instanceId.take(128))
                .append(" sessionId=").append(sessionId.take(128))
                .append(" hostId=").append(hostId.take(128))
                .append(" attempt=").append(attempt?.id ?: "unavailable")
            generation?.let { append(" generation=").append(it) }
            resourceGeneration?.let { append(" resourceGeneration=").append(it) }
            index?.let { append(" index=").append(it) }
            webViewId?.let { append(" webViewId=").append(it) }
        })
    }
    public fun begin(bookId: String): Long = synchronized(lock) {
        val attempt = Attempt(nextAttempt.incrementAndGet(), bookId.take(128))
        active = attempt
        emit(attempt, "T0_BOOK_TAP")
        attempt.id
    }
    public fun claim(bookId: String): Long? = synchronized(lock) {
        val attempt = active?.takeIf { it.bookId == bookId && !it.t1 }
        attempt?.also { it.t1 = true; emit(it, "T1_PLATFORM_VIEW_CREATE") }?.id
    }
    public fun targetMaterialized(index: Int): Unit = markTarget("T2_TARGET_MATERIALIZED", index)
    public fun targetSelected(index: Int): Unit = synchronized(lock) { active?.let { if (it.targetIndex == null) it.targetIndex = index } }
    public fun targetLoadBegin(index: Int): Unit = markTarget("T3_TARGET_WEBVIEW_LOAD_BEGIN", index)
    public fun trueReady(index: Int): Unit = markTarget("T4_TRUE_READY", index)
    public fun visualCommit(index: Int): Unit = markTarget("T5_VISUAL_COMMIT", index)
    public fun pageLifecycle(stage: String, index: Int, webViewId: Int): Unit =
        internal(stage, index, webViewId)
    public fun parserMarker(index: Int, webViewId: Int, label: String, timeMs: Double): Unit =
        synchronized(lock) {
            val attempt = active ?: return@synchronized
            if (attempt.targetIndex != index) return@synchronized
            emit(attempt, "R_PARSER_MARKER", index, webViewId, "label=${label.take(48)} perfNowMs=${timeMs.toLong()}")
        }
    public fun resourceTiming(index: Int, webViewId: Int, type: String, path: String, startMs: Double, durationMs: Double, local: Boolean): Unit =
        synchronized(lock) {
            val attempt = active ?: return@synchronized
            if (attempt.targetIndex != index) return@synchronized
            emit(attempt, "R_RESOURCE_TIMING", index, webViewId, "type=$type local=$local path=${path.takeLast(160)} perfStartMs=${startMs.toLong()} perfDurationMs=${durationMs.toLong()}")
        }
    public fun requestFailure(index: Int, webViewId: Int, kind: String, url: android.net.Uri, code: Int): Unit =
        synchronized(lock) {
            val attempt = active ?: return@synchronized
            if (attempt.targetIndex != index) return@synchronized
            emit(attempt, "R_REQUEST_FAILURE", index, webViewId, "kind=$kind code=$code path=${(url.path ?: "").takeLast(160)}")
        }
    /** Measures delegation only; response stream consumption remains outside this boundary. */
    public fun interceptMainDocument(index: Int, webViewId: Int, delegate: () -> android.webkit.WebResourceResponse?): android.webkit.WebResourceResponse? {
        val attempt = synchronized(lock) { active?.takeIf { it.targetIndex == index } }
        if (attempt == null) return delegate()
        emit(attempt, "M0_MAIN_FRAME_INTERCEPT_ENTER", index, webViewId)
        var outcome = "exception"
        try {
            val response = delegate()
            outcome = if (response == null) "delegated_to_webview" else "response_returned"
            return response
        } finally {
            emit(attempt, "M1_MAIN_FRAME_INTERCEPT_EXIT", index, webViewId, "outcome=$outcome")
        }
    }
    public fun subresourceRequest(index: Int, webViewId: Int, url: android.net.Uri, isMainFrame: Boolean): Unit =
        synchronized(lock) {
            val attempt = active ?: return@synchronized
            if (attempt.targetIndex != index || isMainFrame) return@synchronized
            val path = url.path ?: return@synchronized
            val extension = path.substringAfterLast('.', "").lowercase()
            val type = when (extension) {
                "css" -> "stylesheet"
                "js", "mjs" -> "script"
                "woff", "woff2", "ttf", "otf" -> "font"
                "jpg", "jpeg", "png", "gif", "webp", "avif" -> "image"
                "svg" -> "svg"
                else -> return@synchronized
            }
            val sanitized = path.takeLast(160)
            val local = url.host == "readium_package" || url.host == "readium_assets"
            emit(attempt, "R_REQUEST_START", index, webViewId, "type=$type local=$local path=$sanitized")
        }
    public fun internal(stage: String, index: Int, webViewId: Int? = null): Unit =
        synchronized(lock) {
            val attempt = active ?: return@synchronized
            if (attempt.targetIndex != index) return@synchronized
            emit(attempt, stage, index, webViewId)
        }
    private fun markTarget(stage: String, index: Int): Unit = synchronized(lock) {
        val attempt = active ?: return@synchronized
        if (attempt.targetIndex == null && stage == "T2_TARGET_MATERIALIZED") attempt.targetIndex = index
        if (attempt.targetIndex != index) return@synchronized
        val already = when (stage) { "T2_TARGET_MATERIALIZED" -> attempt.t2; "T3_TARGET_WEBVIEW_LOAD_BEGIN" -> attempt.t3; "T4_TRUE_READY" -> attempt.t4; else -> attempt.t5 }
        if (already) return@synchronized
        when (stage) { "T2_TARGET_MATERIALIZED" -> attempt.t2 = true; "T3_TARGET_WEBVIEW_LOAD_BEGIN" -> attempt.t3 = true; "T4_TRUE_READY" -> attempt.t4 = true; else -> attempt.t5 = true }
        emit(attempt, stage, index)
    }
    private fun emit(attempt: Attempt, stage: String, resource: Int? = null, webViewId: Int? = null, extra: String? = null): Unit {
        Log.d(TAG, buildString {
            append("attempt=").append(attempt.id)
                .append(" stage=").append(stage)
                .append(" elapsedMs=").append(SystemClock.elapsedRealtime())
                .append(" book=").append(attempt.bookId)
            resource?.let { append(" resource=").append(it) }
            webViewId?.let { append(" webViewId=").append(it) }
            extra?.let { append(' ').append(it) }
        })
    }
    private class Attempt(val id: Long, val bookId: String) { var targetIndex: Int? = null; var t1 = false; var t2 = false; var t3 = false; var t4 = false; var t5 = false }
}
