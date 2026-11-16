/*
 * Copyright 2018 Readium Foundation. All rights reserved.
 * Use of this source code is governed by the BSD-style license
 * available in the top-level LICENSE file of the project.
 */

@file:OptIn(ExperimentalReadiumApi::class, InternalReadiumApi::class)

package org.readium.r2.navigator

import android.content.Context
import android.graphics.PointF
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.util.AttributeSet
import android.util.Log
import android.view.*
import android.webkit.URLUtil
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import androidx.annotation.RequiresApi
import kotlin.coroutines.resume
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.jsoup.Jsoup
import org.jsoup.safety.Safelist
import org.readium.r2.navigator.extensions.optRectF
import org.readium.r2.navigator.input.InputModifier
import org.readium.r2.navigator.input.Key
import org.readium.r2.navigator.input.KeyEvent
import org.readium.r2.navigator.preferences.ReadingProgression
import org.readium.r2.navigator.epub.EpubNavigatorFragment.ProgressNavigationOrigin
import org.readium.r2.navigator.epub.continuous.ContinuousLocatorPointGeometry
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.extensions.optNullableString
import org.readium.r2.shared.extensions.tryOrLog
import org.readium.r2.shared.extensions.tryOrNull
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.data.decodeString
import org.readium.r2.shared.util.flatMap
import org.readium.r2.shared.util.resource.Resource
import org.readium.r2.shared.util.use
import timber.log.Timber

internal data class R2PaginatedGeometrySample(
    val scrollX: Int,
    val viewportWidth: Int,
    val contentWidth: Int,
    val pageCount: Int,
)

@OptIn(ExperimentalReadiumApi::class)
/**
 * The sole resource-local boundary for the external WebView JavaScript effect.
 *
 * It deliberately transports only the generated command and Android's raw
 * callback representation. Locator parsing stays in [R2BasicWebView].
 */
internal fun interface R2JavascriptExecutor {
    fun evaluate(webView: R2BasicWebView, javascript: String, callback: (String) -> Unit)
}

internal object RuntimeR2JavascriptExecutor : R2JavascriptExecutor {
    override fun evaluate(webView: R2BasicWebView, javascript: String, callback: (String) -> Unit) {
        webView.evaluateJavascriptAtWebViewBoundary(javascript, callback)
    }
}

internal open class R2BasicWebView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    private val javascriptExecutor: R2JavascriptExecutor = RuntimeR2JavascriptExecutor,
) : WebView(context, attrs) {

    private companion object {
        const val BIBLIOLIFE_TAG = "BiblioLifeReadium"
        const val BIBLIOLIFE_PATCH_ID = "android-custom-selection-handles-v9-verified-activation"
    }

    private var userPageNavigationEnabled: Boolean = true

    // Continuous diagnostics only; never consulted by CSS/geometry decisions.
    internal var continuousTextRenderDiagnosticContext: String? = null

    /**
     * Gates Readium's touch-originated scrollLeft/scrollRight path without
     * changing Android WebView MotionEvent dispatch.
     */
    internal fun setUserPageNavigationEnabled(enabled: Boolean) {
        userPageNavigationEnabled = enabled
    }

    interface Listener {
        val readingProgression: ReadingProgression
        val verticalText: Boolean

        /** Called when the resource content is loaded in the web view. */
        fun onResourceLoaded(webView: R2BasicWebView, link: Link) {}

        /** Called when the target page of the resource is loaded in the web view. */
        fun onPageLoaded(webView: R2BasicWebView, link: Link) {}
        fun onPageChanged(pageIndex: Int, totalPages: Int, url: String) {}
        fun onPageEnded(end: Boolean) {}
        fun onTap(point: PointF): Boolean = false
        fun onDragStart(event: DragEvent): Boolean = false
        fun onDragMove(event: DragEvent): Boolean = false
        fun onDragEnd(event: DragEvent): Boolean = false
        fun onKey(event: KeyEvent): Boolean = false
        fun onDecorationActivated(id: DecorationId, group: String, rect: RectF, point: PointF): Boolean = false
        fun onProgressionChanged(progressOrigin: ProgressNavigationOrigin? = null) {}
        /** Reports a touch-owned paginated drag/settle lifecycle without changing navigation. */
        fun onManualPageActivityChanged(webView: R2BasicWebView, active: Boolean) {}
        /** Reports only a real, discrete page index observed by the pager during manual motion. */
        fun onManualPageIndexChanged(webView: R2BasicWebView, pageIndex: Int, totalPages: Int) {}
        /** Reports bounded raw geometry while a manual paginated drag or settle is active. */
        fun onManualPageGeometrySample(webView: R2BasicWebView, sample: R2PaginatedGeometrySample) {}
        fun onSelectionSessionChanged(active: Boolean, sessionId: Long) {}
        fun onCustomSelectionHandlesPreparing(sessionId: Long) {}
        fun onCustomSelectionHandlesActivated(sessionId: Long) {}
        fun onCustomSelectionHandleDragStarted(sessionId: Long) {}
        fun onCustomSelectionCommitted(sessionId: Long) {}
        fun goForward(animated: Boolean = false): Boolean = false
        fun goBackward(animated: Boolean = false): Boolean = false

        /**
         * Returns the custom [ActionMode.Callback] to be used with the text selection menu.
         */
        val selectionActionModeCallback: ActionMode.Callback? get() = null

        @InternalReadiumApi
        fun javascriptInterfacesForResource(link: Link): Map<String, Any?> = emptyMap()

        @InternalReadiumApi
        fun shouldOverrideUrlLoading(webView: WebView, request: WebResourceRequest): Boolean = false

        @InternalReadiumApi
        fun shouldInterceptRequest(webView: WebView, request: WebResourceRequest): WebResourceResponse? = null

        @InternalReadiumApi
        fun onFootnoteLinkActivated(url: AbsoluteUrl, context: HyperlinkNavigator.FootnoteContext)

        @InternalReadiumApi
        fun resourceAtUrl(url: AbsoluteUrl): Resource? = null

        /**
         * Requests to load the next resource in the reading order.
         *
         * @param jump Indicates whether it's a discontinuous jump from the current locator. Used
         * for scroll mode.
         */
        @InternalReadiumApi
        fun goToNextResource(jump: Boolean, animated: Boolean): Boolean = false

        @InternalReadiumApi
        fun goToPreviousResource(jump: Boolean, animated: Boolean): Boolean = false
    }

    var listener: Listener? = null

    var resourceUrl: AbsoluteUrl? = null

    internal val scrollModeFlow = MutableStateFlow(false)

    /** Indicates that a user text selection is active. */
    internal var isSelecting = false
    private var customSelectionHandlesActive = false
    private var selectionSessionId = 0L
    private var selectionProgressionAtStart: Double? = null
    private var progressionSuppressionLogged = false

    val scrollMode: Boolean get() = scrollModeFlow.value
    var disablePageTurnsWhileScrolling: Boolean = false


    var callback: OnOverScrolledCallback? = null

    private val uiScope = CoroutineScope(Dispatchers.Main)

    init {
        setWebContentsDebuggingEnabled(BuildConfig.DEBUG)
        Log.d(BIBLIOLIFE_TAG, "READIUM_PATCH_RUNTIME_ACTIVE patchId=$BIBLIOLIFE_PATCH_ID class=${javaClass.name}")
    }

    /** Computes the current progression in the resource. */
    val progression: Double get() {
        return if (scrollMode) {
            if (listener?.verticalText == true) {
                val x = scrollX.toDouble()
                val contentWidth = computeHorizontalScrollRange()
                val viewportWidth = computeHorizontalScrollExtent()
                val maxScrollX = (contentWidth - viewportWidth).coerceAtLeast(0)

                var progression = 0.0
                if (maxScrollX > 0) {
                    // Currently, scrollX for page with vertical text starts at maxScrollX
                    progression = ((maxScrollX - x) / contentWidth).coerceIn(0.0, 1.0)
                }
                progression
            } else {
                val y = scrollY.toDouble()
                val contentHeight = computeVerticalScrollRange()

                var progression = 0.0
                if (contentHeight > 0) {
                    progression = (y / contentHeight).coerceIn(0.0, 1.0)
                }
                progression
            }
        } else {
            var x = scrollX.toDouble()
            val pageWidth = computeHorizontalScrollExtent()
            val contentWidth = computeHorizontalScrollRange()

            val isRtl = (listener?.readingProgression == ReadingProgression.RTL)

            // For RTL, we need to add the equivalent of one page to the x position, otherwise the
            // progression will be one page off.
            if (isRtl) {
                x += pageWidth
            }

            var progression = 0.0
            if (contentWidth > 0) {
                progression = (x / contentWidth).coerceIn(0.0, 1.0)
            }
            // For RTL, we need to reverse the progression because the web view is always scrolling
            // from left to right, no matter the reading direction.
            if (isRtl) {
                progression = 1 - progression
            }

            progression
        }
    }

    interface OnOverScrolledCallback {
        fun onOverScrolled(scrollX: Int, scrollY: Int, clampedX: Boolean, clampedY: Boolean)
    }

    fun setOnOverScrolledCallback(callback: OnOverScrolledCallback) {
        this.callback = callback
    }

    override fun onOverScrolled(scrollX: Int, scrollY: Int, clampedX: Boolean, clampedY: Boolean) {
        if (callback != null) {
            callback?.onOverScrolled(scrollX, scrollY, clampedX, clampedY)
        }
        super.onOverScrolled(scrollX, scrollY, clampedX, clampedY)
    }

    override fun onScrollChanged(l: Int, t: Int, oldl: Int, oldt: Int) {
        super.onScrollChanged(l, t, oldl, oldt)
        if (isSelecting) {
            val old = selectionProgressionAtStart
            val attempted = progression
            if (!progressionSuppressionLogged && old != null && old != attempted) {
                progressionSuppressionLogged = true
                Log.d(BIBLIOLIFE_TAG, "READIUM_SELECTION_PROGRESS_CHANGE_SUPPRESSED old=$old attempted=$attempted")
            }
            return
        }
        listener?.onProgressionChanged()
    }

    override fun destroy() {
        // Prevent the web view from leaking when detached
        // See https://github.com/readium/r2-navigator-kotlin/issues/52
        removeJavascriptInterface("Android")

        super.destroy()
    }

    open fun scrollRight(animated: Boolean = false) {
        if (!userPageNavigationEnabled) {
            Log.d(BIBLIOLIFE_TAG, "READIUM_PAGE_TURN_BLOCKED selectionLock=true")
            return
        }
        if (isSelecting) {
            Log.d(BIBLIOLIFE_TAG, "READIUM_PAGE_TURN_REJECTED_DURING_SELECTION direction=right")
            return
        }
        uiScope.launch {
            val listener = listener ?: return@launch

            fun goRight(jump: Boolean) {
                if (listener.readingProgression == ReadingProgression.RTL) {
                    listener.goBackward(animated = animated) // Legacy
                    listener.goToPreviousResource(jump = jump, animated = animated)
                } else {
                    listener.goForward(animated = animated) // Legacy
                    listener.goToNextResource(jump = jump, animated = animated)
                }
            }

            when {
                // If the user is in scrollMode and has disabled swipe pagination, do nothing.
                scrollMode && this@R2BasicWebView.disablePageTurnsWhileScrolling -> {}

                scrollMode ->
                    goRight(jump = true)

                !this@R2BasicWebView.canScrollHorizontally(1) ->
                    goRight(jump = false)

                else ->
                    runJavaScript("readium.scrollRight($animated);") { success ->
                        if (!success.toBoolean()) {
                            goRight(jump = false)
                        }
                    }
            }
        }
    }

    open fun scrollLeft(animated: Boolean = false) {
        if (!userPageNavigationEnabled) {
            Log.d(BIBLIOLIFE_TAG, "READIUM_PAGE_TURN_BLOCKED selectionLock=true")
            return
        }
        if (isSelecting) {
            Log.d(BIBLIOLIFE_TAG, "READIUM_PAGE_TURN_REJECTED_DURING_SELECTION direction=left")
            return
        }
        uiScope.launch {
            val listener = listener ?: return@launch

            fun goLeft(jump: Boolean) {
                if (listener.readingProgression == ReadingProgression.RTL) {
                    listener.goForward(animated = animated) // legacy
                    listener.goToNextResource(jump = jump, animated = animated)
                } else {
                    listener.goBackward(animated = animated) // legacy
                    listener.goToPreviousResource(jump = jump, animated = animated)
                }
            }

            when {
                // If the user is in scrollMode and has disabled swipe pagination, do nothing.
                scrollMode && this@R2BasicWebView.disablePageTurnsWhileScrolling -> {}

                scrollMode ->
                    goLeft(jump = true)

                !this@R2BasicWebView.canScrollHorizontally(-1) ->
                    goLeft(jump = false)

                else ->
                    runJavaScript("readium.scrollLeft($animated);") { success ->
                        if (!success.toBoolean()) {
                            goLeft(jump = false)
                        }
                    }
            }
        }
    }

    /*
     * Returns whether the web view should prevent the default behavior for this tap.
     */
    @android.webkit.JavascriptInterface
    fun onTap(eventJson: String): Boolean {
        // If there's an on-going selection, the tap will dismiss it so we don't forward it.
        if (isSelecting) {
            return false
        }

        val event = TapEvent.fromJSON(eventJson) ?: return false

        // The script prevented the default behavior.
        if (event.defaultPrevented) {
            return false
        }

        // We ignore taps on interactive element, unless it's an element we handle ourselves such as
        // pop-up footnotes.
        if (event.interactiveElement != null) {
            return handleFootnote(event.interactiveElement)
        }

        return runBlocking(uiScope.coroutineContext) { listener?.onTap(event.point) ?: false }
    }

    /**
     * Called from the JS code when a tap on a decoration is detected.
     */
    @android.webkit.JavascriptInterface
    fun onDecorationActivated(eventJson: String): Boolean {
        val obj = tryOrLog { JSONObject(eventJson) }
        val id = obj?.optNullableString("id")
        val group = obj?.optNullableString("group")
        val rect = obj?.optRectF("rect")
        val click = TapEvent.fromJSONObject(obj?.optJSONObject("click"))
        if (id == null || group == null || rect == null || click == null) {
            Timber.e("Invalid JSON for onDecorationActivated: $eventJson")
            return false
        }

        return listener?.onDecorationActivated(id, group, rect, click.point) ?: false
    }

    /** Produced by gestures.js */
    private data class TapEvent(
        val defaultPrevented: Boolean,
        val point: PointF,
        val targetElement: String,
        val interactiveElement: String?,
    ) {
        companion object {
            fun fromJSONObject(obj: JSONObject?): TapEvent? {
                obj ?: return null

                val x = obj.optDouble("x").toFloat()
                val y = obj.optDouble("y").toFloat()

                return TapEvent(
                    defaultPrevented = obj.optBoolean("defaultPrevented"),
                    point = PointF(x, y),
                    targetElement = obj.optString("targetElement"),
                    interactiveElement = obj.optNullableString("interactiveElement")
                )
            }

            fun fromJSON(json: String): TapEvent? =
                fromJSONObject(tryOrNull { JSONObject(json) })
        }
    }

    private fun handleFootnote(html: String): Boolean {
        val resourceUrl = resourceUrl ?: return false

        val href = tryOrNull { Jsoup.parse(html) }
            ?.select("a[epub:type=noteref]")?.first()
            ?.attr("href")
            ?.let { Url(it) }
            ?: return false

        val id = href.fragment ?: return false

        val absoluteUrl = resourceUrl.resolve(href)

        val absoluteUrlWithoutFragment = absoluteUrl.removeFragment()

        val aside = runBlocking {
            tryOrLog {
                listener?.resourceAtUrl(absoluteUrlWithoutFragment)
                    ?.use { res ->
                        res.read()
                            .flatMap { it.decodeString() }
                            .map { Jsoup.parse(it) }
                            .getOrNull()
                    }
                    ?.select("#$id")
                    ?.first()?.html()
            }
        }?.takeIf { it.isNotBlank() }
            ?: return false

        val safe = Jsoup.clean(aside, Safelist.relaxed())
        val context = HyperlinkNavigator.FootnoteContext(
            noteContent = safe
        )

        listener?.onFootnoteLinkActivated(absoluteUrl, context)

        // Consume the event to prevent the Webview from loading the link.
        return true
    }

    @android.webkit.JavascriptInterface
    fun onDragStart(eventJson: String): Boolean {
        val event = DragEvent.fromJSON(eventJson)?.takeIf { it.isValid }
            ?: return false

        return runBlocking(uiScope.coroutineContext) { listener?.onDragStart(event) ?: false }
    }

    @android.webkit.JavascriptInterface
    fun onDragMove(eventJson: String): Boolean {
        val event = DragEvent.fromJSON(eventJson)?.takeIf { it.isValid }
            ?: return false

        return runBlocking(uiScope.coroutineContext) { listener?.onDragMove(event) ?: false }
    }

    @android.webkit.JavascriptInterface
    fun onDragEnd(eventJson: String): Boolean {
        val event = DragEvent.fromJSON(eventJson)?.takeIf { it.isValid }
            ?: return false
        return runBlocking(uiScope.coroutineContext) { listener?.onDragEnd(event) ?: false }
    }

    @android.webkit.JavascriptInterface
    fun onKey(eventJson: String): Boolean {
        val jsonObject = JSONObject(eventJson)
        val event = KeyEvent(
            type = when (jsonObject.optString("type")) {
                "down" -> KeyEvent.Type.Down
                "up" -> KeyEvent.Type.Up
                else -> return false
            },
            key = Key(jsonObject.optString("code")),
            modifiers = inputModifiers(jsonObject),
            characters = jsonObject.optNullableString("characters")?.takeUnless { it.isBlank() }
        )

        return listener?.onKey(event) ?: false
    }

    @android.webkit.JavascriptInterface
    fun onSelectionStart(sessionId: Long) {
        // JavaScript interfaces run on WebView's JavaBridge thread. Selection
        // pinning reaches the RecyclerView hierarchy, so it must be owned by
        // the WebView/UI thread before notifying the rendition.
        post {
            isSelecting = true
            customSelectionHandlesActive = false
            selectionSessionId = sessionId
            selectionProgressionAtStart = progression
            progressionSuppressionLogged = false
            listener?.onSelectionSessionChanged(true, sessionId)
        }
    }

    @android.webkit.JavascriptInterface
    fun onSelectionEnd(sessionId: Long) {
        post {
            if (sessionId != selectionSessionId) return@post
            isSelecting = false
            customSelectionHandlesActive = false
            selectionProgressionAtStart = null
            listener?.onSelectionSessionChanged(false, sessionId)
        }
    }

    @android.webkit.JavascriptInterface
    fun onCustomSelectionHandlesPreparing(sessionId: Long) {
        if (sessionId == selectionSessionId && isSelecting) {
            listener?.onCustomSelectionHandlesPreparing(sessionId)
        }
    }

    @android.webkit.JavascriptInterface
    fun onCustomSelectionCommitted(sessionId: Long) {
        if (sessionId == selectionSessionId && customSelectionHandlesActive) {
            listener?.onCustomSelectionCommitted(sessionId)
        }
    }

    @android.webkit.JavascriptInterface
    fun onCustomSelectionHandlesActivated(sessionId: Long) {
        if (sessionId != selectionSessionId || !isSelecting) return
        customSelectionHandlesActive = true
        listener?.onCustomSelectionHandlesActivated(sessionId)
    }

    @android.webkit.JavascriptInterface
    fun onCustomSelectionHandleDragStarted(sessionId: Long) {
        if (sessionId == selectionSessionId && customSelectionHandlesActive) {
            listener?.onCustomSelectionHandleDragStarted(sessionId)
        }
    }

    /** Produced by gestures.js */
    data class DragEvent(
        val defaultPrevented: Boolean,
        val startPoint: PointF,
        val currentPoint: PointF,
        val offset: PointF,
        val interactiveElement: String?,
    ) {
        internal val isValid: Boolean get() =
            !defaultPrevented && (interactiveElement == null)

        companion object {
            fun fromJSONObject(obj: JSONObject?): DragEvent? {
                obj ?: return null

                return DragEvent(
                    defaultPrevented = obj.optBoolean("defaultPrevented"),
                    startPoint = PointF(
                        obj.optDouble("startX").toFloat(),
                        obj.optDouble("startY").toFloat()
                    ),
                    currentPoint = PointF(
                        obj.optDouble("currentX").toFloat(),
                        obj.optDouble("currentY").toFloat()
                    ),
                    offset = PointF(
                        obj.optDouble("offsetX").toFloat(),
                        obj.optDouble("offsetY").toFloat()
                    ),
                    interactiveElement = obj.optNullableString("interactiveElement")
                )
            }

            fun fromJSON(json: String): DragEvent? =
                fromJSONObject(tryOrNull { JSONObject(json) })
        }
    }

    @android.webkit.JavascriptInterface
    fun getViewportWidth(): Int = width

    @android.webkit.JavascriptInterface
    fun logError(message: String, filename: String, line: Int) {
        Timber.e("JavaScript error: $filename:$line $message")
    }

    @android.webkit.JavascriptInterface
    fun log(message: String) {
        Log.d(BIBLIOLIFE_TAG, message)
    }

    fun Boolean.toInt() = if (this) 1 else 0

    fun scrollToStart() {
        runJavaScript("readium.scrollToStart();")
    }

    fun scrollToEnd() {
        runJavaScript("readium.scrollToEnd();")
    }

    suspend fun scrollToId(htmlId: String): Boolean =
        runJavaScriptSuspend("readium.scrollToId(\"$htmlId\");").toBoolean()

    fun scrollToPosition(progression: Double) {
        runJavaScript("readium.scrollToPosition(\"$progression\");")
    }

    suspend fun scrollToLocator(locator: Locator): Boolean {
        val json = locator.toJSON().toString()
        return runJavaScriptSuspend("readium.scrollToLocator($json);").toBoolean()
    }

    fun setScrollMode(scrollMode: Boolean) {
        // Scroll state is consumed by the native navigator/host. The real
        // readium-reflowable bootstrap exposes `readium`, but no standalone
        // JavaScript `setScrollMode` API. Calling that invented global caused
        // continuous resources to emit ReferenceErrors after bootstrap.
        scrollModeFlow.value = scrollMode
    }

    fun setProperty(key: String, value: String) {
        runJavaScript("readium.setProperty(\"$key\", \"$value\");")
    }

    fun removeProperty(key: String) {
        runJavaScript("readium.removeProperty(\"$key\");")
    }

    fun getCurrentSelectionInfo(callback: (String) -> Unit) {
        runJavaScript("getCurrentSelectionInfo();", callback)
    }

    fun getCurrentSelectionRect(callback: (String) -> Unit) {
        runJavaScript("getSelectionRect();", callback)
    }

    /**
     * Reads the selection owned by this exact WebView. Continuous hosts use
     * this resource-local primitive instead of a navigator-global WebView.
     */
    internal suspend fun currentSelection(locator: Locator): Selection? {
        val json = runJavaScriptSuspend("readium.getCurrentSelection();")
            .let(::javascriptResultObject)
            ?: return null

        return Selection(
            locator = locator.copy(text = Locator.Text.fromJSON(json.optJSONObject("text"))),
            rect = json.optRectF("rect"),
        )
    }

    /** Clears native selection in this exact WebView; it never broadcasts. */
    internal fun clearNativeSelection() {
        runJavaScript("readium.clearSelection();")
    }

    internal suspend fun findFirstVisibleLocator(): Locator? =
        runJavaScriptSuspend("readium.findFirstVisibleLocator();")
            .let(::javascriptResultObject)
            ?.let { Locator.fromJSON(it) }

    /**
     * Returns a Readium Locator for a CSS-pixel point in this WebView's own
     * document. It is intentionally resource-local for continuous hosts.
     */
    internal suspend fun findLocatorAtPoint(x: Double, y: Double, diagnostic: Boolean = true): Locator? {
        val point = continuousDomPoint(
            nativeX = x,
            nativeY = y,
            pixelsPerCssPixel = resources.displayMetrics.density.toDouble(),
        ) ?: return null
        val result = runJavaScriptSuspend(
            javascript = if (diagnostic) continuousLocatorJavascript(point.x, point.y)
                else "readium.findLocatorAtPoint(${point.x}, ${point.y});",
            diagnosticOperation = "CONTINUOUS_LOCATOR_JS",
        )
        val response = javascriptResultObject(result)
        continuousLocatorDiagnosticLogPayload(response?.optJSONObject("diagnostic"))?.let { payload ->
            Log.d(BIBLIOLIFE_TAG, "CONTINUOUS_LOCATOR_DOM_DIAGNOSTIC schema=1 evidence=$payload")
        }
        val json = response?.optJSONObject("locator") ?: response
        if (json == null) {
            Log.w(BIBLIOLIFE_TAG, "CONTINUOUS_LOCATOR_JS_DROP reason=callback_not_locator_json raw=$result")
            return null
        }
        val locator = Locator.fromJSON(json)
        if (locator == null) {
            Log.w(BIBLIOLIFE_TAG, "CONTINUOUS_LOCATOR_JS_DROP reason=callback_invalid_locator")
            return null
        }
        Log.d(BIBLIOLIFE_TAG, "CONTINUOUS_LOCATOR_JS_PARSED href=${locator.href}")
        return locator
    }

    /** Temporary exact text-point anchor, separate from canonical Locator capture. */
    internal suspend fun captureContinuousReadingAnchor(x: Double, y: Double): Locator? {
        val point = continuousDomPoint(x, y, resources.displayMetrics.density.toDouble()) ?: return null
        return runJavaScriptSuspend("readium.captureContinuousReadingAnchor(${point.x}, ${point.y});")
            .let(::javascriptResultObject)?.let { Locator.fromJSON(it) }
    }

    /** Resolves a Locator to a transient CSS-pixel document Y coordinate. */
    internal suspend fun locatorVerticalOffset(
        locator: Locator,
        diagnosticOperation: String? = null,
    ): Double? {
        val json = locator.toJSON().toString()
        val raw = runJavaScriptSuspend(
            "readium.locatorVerticalOffset($json);",
            diagnosticOperation,
        )
        val parsed = raw.toDoubleOrNull()
        diagnosticOperation?.let { operation ->
            Log.d(
                BIBLIOLIFE_TAG,
                "${operation}_PARSED result=${continuousLocatorOffsetRawClassification(raw)}",
            )
        }
        return parsed
    }

    /** Resolves the exact progression caret to live document and viewport CSS coordinates. */
    internal suspend fun continuousLocatorPointGeometry(locator: Locator): ContinuousLocatorPointGeometry? {
        val locatorJson = locator.toJSON().toString()
        val raw = runJavaScriptSuspend(
            "readium.continuousLocatorPointGeometry($locatorJson);",
            diagnosticOperation = "CONTINUOUS_LOCATOR_POINT_VIEWPORT_JS",
        )
        val json = javascriptResultObject(raw) ?: return null
        val documentY = json.optDouble("documentY", Double.NaN)
        val viewportTop = json.optDouble("viewportTop", Double.NaN)
        if (!documentY.isFinite() || documentY < 0.0 || !viewportTop.isFinite()) return null
        return ContinuousLocatorPointGeometry(
            documentY, viewportTop,
            semanticAnchorExact = json.optBoolean("semanticAnchorExact", false),
            anchorIdentityId = json.optString("anchorIdentityId").takeIf { it.isNotBlank() && it != "null" },
            anchorCharacterOffset = if (json.has("anchorCharacterOffset") && !json.isNull("anchorCharacterOffset")) json.optInt("anchorCharacterOffset") else null,
        )
    }

    /**
     * Checks the exact Range resolved from [locator] against the resource-local
     * reading-anchor Y coordinate. The one-layout-pixel bound comes only from
     * the integer RecyclerView restore offset; it is not Locator equivalence.
     */
    internal suspend fun isLocatorRangeAtVerticalAnchor(locator: Locator, nativeY: Double, onDiagnostic: ((Map<String, Any?>) -> Unit)? = null): Boolean {
        val pixelsPerCssPixel = resources.displayMetrics.density.toDouble()
        val point = continuousDomPoint(
            nativeX = 0.0,
            nativeY = nativeY,
            pixelsPerCssPixel = pixelsPerCssPixel,
        ) ?: return false
        val locatorJson = locator.toJSON().toString()
        val maxDistance = 1.0 / pixelsPerCssPixel
        val diagnosticArgument = if (onDiagnostic == null) "" else ", true"
        val raw = runJavaScriptSuspend(
            "readium.isLocatorRangeAtVerticalAnchor($locatorJson, ${point.y}, $maxDistance$diagnosticArgument);",
            diagnosticOperation = "CONTINUOUS_RESTORE_RANGE_ANCHOR_JS",
        )
        val evidence = if (onDiagnostic != null) javascriptResultObject(raw) else null
        if (evidence != null) {
            val fields = mutableMapOf<String, Any?>()
            for (key in listOf("matches", "rangeResolved", "semanticRangeResolved", "finiteInputs", "rangeCollapsed")) {
                if (evidence.opt(key) is Boolean) fields[key] = evidence.getBoolean(key)
            }
            for (key in listOf("rangeTopCssPx", "rangeHeightCssPx", "anchorCssPx", "maxDistanceCssPx", "distanceCssPx", "windowScrollYCssPx")) {
                val value = (evidence.opt(key) as? Number)?.toDouble()
                if (value != null && value.isFinite()) fields[key] = value
            }
            runCatching { onDiagnostic?.invoke(fields) }
            return evidence.optBoolean("matches", false)
        }
        return raw == "true"
    }

    /** Uses the live resource DOM to prove two CSS locators share one block. */
    internal suspend fun locatorsShareMeaningfulBlock(anchor: Locator, observed: Locator): Boolean {
        val anchorJson = anchor.toJSON().toString()
        val observedJson = observed.toJSON().toString()
        return runJavaScriptSuspend(
            "readium.locatorsShareMeaningfulBlock($anchorJson, $observedJson);",
            diagnosticOperation = "CONTINUOUS_LOCAL_DOM_EQUIVALENCE_JS",
        ) == "true"
    }

    fun createHighlight(locator: String?, color: String?, callback: (String) -> Unit) {
        uiScope.launch {
            runJavaScript("createHighlight($locator, $color, true);", callback)
        }
    }

    fun destroyHighlight(id: String) {
        uiScope.launch {
            runJavaScript("destroyHighlight(\"$id\");")
        }
    }

    fun createAnnotation(id: String) {
        uiScope.launch {
            runJavaScript("createAnnotation(\"$id\");")
        }
    }

    fun rectangleForHighlightWithID(id: String, callback: (String) -> Unit) {
        uiScope.launch {
            runJavaScript("rectangleForHighlightWithID(\"$id\");", callback)
        }
    }

    fun runJavaScript(javascript: String, callback: ((String) -> Unit)? = null) {
        if (BuildConfig.DEBUG) {
            val filename = URLUtil.guessFileName(url, null, null)
            Timber.d("runJavaScript in $filename: $javascript")
        }

        executeJavascript(javascript) { result ->
            if (callback != null) callback(result)
        }
    }

    /**
     * Executes one command in this WebView instance. The default reaches
     * [WebView.evaluateJavascript] while tests may control only its raw result.
     */
    internal fun executeJavascript(javascript: String, callback: (String) -> Unit) {
        javascriptExecutor.evaluate(this, javascript, callback)
    }

    /**
     * WebView commands are UI-thread APIs. The continuous rendition can resume
     * a caller after a non-UI suspension, so dispatch the invocation itself to
     * Main and never resume a cancelled resource-generation request.
     */
    internal suspend fun runJavaScriptSuspend(
        javascript: String,
        diagnosticOperation: String? = null,
    ): String = withContext(Dispatchers.Main.immediate) {
        suspendCancellableCoroutine { continuation ->
            diagnosticOperation?.let { operation ->
                Log.d(BIBLIOLIFE_TAG, "${operation}_INVOKE attached=$isAttachedToWindow")
            }
            try {
                executeJavascript(javascript) { result ->
                    diagnosticOperation?.let { operation ->
                        Log.d(BIBLIOLIFE_TAG, "${operation}_CALLBACK raw=$result")
                    }
                    if (continuation.isActive) {
                        continuation.resume(result)
                    } else {
                        diagnosticOperation?.let { operation ->
                            Log.w(BIBLIOLIFE_TAG, "${operation}_DROP reason=continuation_cancelled")
                        }
                    }
                }
            } catch (error: RuntimeException) {
                diagnosticOperation?.let { operation ->
                    Log.w(BIBLIOLIFE_TAG, "${operation}_DROP reason=evaluate_javascript_exception", error)
                }
                if (continuation.isActive) {
                    continuation.resumeWith(Result.failure(error))
                }
            }
        }
    }

    /** Runtime default delegates to the real Android WebView implementation. */
    internal fun evaluateJavascriptAtWebViewBoundary(javascript: String, callback: (String) -> Unit) {
        super.evaluateJavascript(javascript, callback)
    }

    internal fun shouldOverrideUrlLoading(request: WebResourceRequest): Boolean {
        return listener?.shouldOverrideUrlLoading(this, request) ?: false
    }

    internal fun shouldInterceptRequest(webView: WebView, request: WebResourceRequest): WebResourceResponse? {
        // Prevent favicon.ico to be loaded, this was causing a NullPointerException in NanoHttp
        if (!request.isForMainFrame && request.url.path?.endsWith("/favicon.ico") == true) {
            tryOrLog<Unit> {
                return WebResourceResponse("image/png", null, null)
            }
        }

        return listener?.shouldInterceptRequest(webView, request)
    }

    // Text selection ActionMode overrides
    //
    // Since Android 12, overriding Activity.onActionModeStarted doesn't seem to work to customize
    // the text selection menu. As an alternative, we can provide a custom ActionMode.Callback to be
    // used by the web view.

    override fun startActionMode(callback: ActionMode.Callback?): ActionMode? {
        val customCallback = listener?.selectionActionModeCallback
            ?: return super.startActionMode(callback)

        val parent = parent ?: return null
        return parent.startActionModeForChild(this, customCallback)
    }

    /**
     * A wrapper for the app-provided custom [ActionMode.Callback] which clears the selection when
     * activating one of the menu items.
     */
    inner class CallbackWrapper(val callback: ActionMode.Callback) : ActionMode.Callback by callback {
        override fun onActionItemClicked(mode: ActionMode?, item: MenuItem?): Boolean {
            uiScope.launch { clearFocus() }
            return callback.onActionItemClicked(mode, item)
        }
    }

    @RequiresApi(Build.VERSION_CODES.M)
    override fun startActionMode(callback: ActionMode.Callback?, type: Int): ActionMode? {
        val customCallback = listener?.selectionActionModeCallback
            ?: return super.startActionMode(callback, type)

        val parent = parent ?: return null
        val wrapper = Callback2Wrapper(
            customCallback,
            callback2 = callback as? ActionMode.Callback2
        )
        return parent.startActionModeForChild(this, wrapper, type)
    }

    @RequiresApi(Build.VERSION_CODES.M)
    inner class Callback2Wrapper(
        val callback: ActionMode.Callback,
        val callback2: ActionMode.Callback2?,
    ) : ActionMode.Callback by callback, ActionMode.Callback2() {
        override fun onGetContentRect(mode: ActionMode?, view: View?, outRect: Rect?) =
            callback2?.onGetContentRect(mode, view, outRect)
                ?: super.onGetContentRect(mode, view, outRect)
    }
}

/** Classifies WebView's raw callback without normalizing or changing its numeric parsing. */
internal fun continuousLocatorOffsetRawClassification(raw: String): String = when {
    raw.toDoubleOrNull() != null -> "numeric"
    raw == "null" -> "null"
    raw == "undefined" -> "undefined"
    raw.isEmpty() -> "empty"
    raw == "\"null\"" -> "quoted-null"
    raw.startsWith("\"") || raw.startsWith("{") || raw.startsWith("[") -> "malformed-json"
    else -> "other"
}

/**
 * Android WebView returns JavaScript values as JSON. Object-valued expressions
 * are normally delivered as an object, while some WebView implementations
 * serialize them one additional time as a JSON string. Resource-local locator
 * commands must accept both real callback representations without fabricating
 * a Locator when the script returned null or malformed JSON.
 */
/**
 * Completes the Readium DOM locator only when Android WebView omits the
 * caret-derived progression. The fallback remains inside this exact document:
 * it walks DOM text ranges at the already requested point, then derives a
 * textual offset. It never observes RecyclerView coordinates, resource height
 * or a synthetic chapter percentage.
 */
internal fun continuousLocatorJavascript(x: Double, y: Double): String =
    """
    (function() {
      const locator = readium.findLocatorAtPoint($x, $y);
      const point = readium.findLocatorAtPointDiagnostic($x, $y);
      const diagnostic = point && point.diagnostic ? point.diagnostic : null;
      const response = function(value) { return { locator: value, diagnostic: diagnostic }; };
      if (!locator || !locator.locations || !document.body) return response(locator);
      const existing = Number(locator.locations.progression);
      if (Number.isFinite(existing) && existing >= 0 && existing <= 1) return response(locator);
      const caret = (document.caretRangeFromPoint && document.caretRangeFromPoint($x, $y)) ||
        (document.caretPositionFromPoint && (function(position) {
          if (!position) return null;
          const range = document.createRange();
          range.setStart(position.offsetNode, position.offset);
          range.collapse(true);
          return range;
        })(document.caretPositionFromPoint($x, $y)));
      let range = caret;
      if (!range && document.createTreeWalker && document.elementFromPoint) {
        const element = document.elementFromPoint($x, $y);
        let root = element && element !== document.documentElement ? element : document.body;
        let nearestNode = null;
        let nearestDistance = Number.POSITIVE_INFINITY;
        while (root && !nearestNode) {
          const nodes = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
          let node;
          while ((node = nodes.nextNode())) {
            if (!node.nodeValue || !node.nodeValue.trim()) continue;
            const candidate = document.createRange();
            candidate.selectNodeContents(node);
            for (const rect of candidate.getClientRects()) {
              if (rect.width <= 0 || rect.height <= 0) continue;
              const dx = $x < rect.left ? rect.left - $x : ($x > rect.right ? $x - rect.right : 0);
              const dy = $y < rect.top ? rect.top - $y : ($y > rect.bottom ? $y - rect.bottom : 0);
              const distance = dx * dx + dy * dy;
              if (distance < nearestDistance) {
                nearestDistance = distance;
                nearestNode = node;
              }
            }
          }
          root = root === document.body ? null : root.parentElement;
        }
        if (nearestNode) {
          range = document.createRange();
          range.setStart(nearestNode, 0);
          range.collapse(true);
        }
      }
      if (!range) return response(locator);
      const prefix = document.createRange();
      prefix.setStart(document.body, 0);
      prefix.setEnd(range.startContainer, range.startOffset);
      const total = document.body.textContent.length;
      if (total <= 0) return response(locator);
      const progression = Math.max(0, Math.min(1, prefix.toString().length / total));
      return response(Object.assign({}, locator, {
        locations: Object.assign({}, locator.locations, { progression: progression })
      }));
    })();
    """.trimIndent()

private const val CONTINUOUS_LOCATOR_DIAGNOSTIC_TEXT_LIMIT = 120
private const val CONTINUOUS_LOCATOR_DIAGNOSTIC_SELECTOR_LIMIT = 160
private const val CONTINUOUS_LOCATOR_DIAGNOSTIC_ANCESTOR_LIMIT = 6

/**
 * Serializes only the bounded diagnostic schema emitted by `dom.js`.
 *
 * This is evidence for capture/observation mismatches, not Locator data: it
 * is never persisted, fed back to Readium, or used by convergence logic.
 */
internal fun continuousLocatorDiagnosticLogPayload(diagnostic: JSONObject?): String? {
    if (diagnostic?.optInt("schema", -1) != 1) return null
    val caret = diagnostic.optJSONObject("caret") ?: return null
    val quote = diagnostic.optJSONObject("quote") ?: return null
    val occurrences = (diagnostic.opt("normalizedResourceQuoteOccurrences") as? Number)?.toInt()
        ?.coerceAtLeast(0)
        ?: return null

    val normalizedCaret = JSONObject()
        .put("text", caret.boundedDiagnosticString("text", CONTINUOUS_LOCATOR_DIAGNOSTIC_TEXT_LIMIT))
        .put("offset", (caret.opt("offset") as? Number)?.toInt()?.coerceAtLeast(0) ?: 0)
        .put("parentSelector", caret.boundedDiagnosticString("parentSelector", CONTINUOUS_LOCATOR_DIAGNOSTIC_SELECTOR_LIMIT))
    val normalizedQuote = JSONObject()
        .put("before", quote.boundedDiagnosticString("before", CONTINUOUS_LOCATOR_DIAGNOSTIC_TEXT_LIMIT))
        .put("highlight", quote.boundedDiagnosticString("highlight", CONTINUOUS_LOCATOR_DIAGNOSTIC_TEXT_LIMIT))
        .put("after", quote.boundedDiagnosticString("after", CONTINUOUS_LOCATOR_DIAGNOSTIC_TEXT_LIMIT))
    val normalizedAncestors = org.json.JSONArray()
    val ancestors = diagnostic.optJSONArray("ancestors")
    for (index in 0 until minOf(ancestors?.length() ?: 0, CONTINUOUS_LOCATOR_DIAGNOSTIC_ANCESTOR_LIMIT)) {
        val ancestor = ancestors?.optJSONObject(index) ?: continue
        normalizedAncestors.put(
            JSONObject()
                .put("tag", ancestor.boundedDiagnosticString("tag", CONTINUOUS_LOCATOR_DIAGNOSTIC_SELECTOR_LIMIT))
                .put("id", ancestor.boundedDiagnosticString("id", CONTINUOUS_LOCATOR_DIAGNOSTIC_SELECTOR_LIMIT))
                .put("selector", ancestor.boundedDiagnosticString("selector", CONTINUOUS_LOCATOR_DIAGNOSTIC_SELECTOR_LIMIT)),
        )
    }
    return JSONObject()
        .put("caret", normalizedCaret)
        .put("quote", normalizedQuote)
        .put("ancestors", normalizedAncestors)
        .put("normalizedResourceQuoteOccurrences", occurrences)
        .toString()
}

private fun JSONObject.boundedDiagnosticString(name: String, limit: Int): String =
    ((opt(name) as? String) ?: "")
        .replace(Regex("[\\p{Cntrl}]"), " ")
        .replace(Regex("\\s+"), " ")
        .trim()
        .take(limit)

internal data class ContinuousDomPoint(val x: Double, val y: Double)

/** Maps Android View pixels to the CSS-pixel coordinate space used by DOM point APIs. */
internal fun continuousDomPoint(
    nativeX: Double,
    nativeY: Double,
    pixelsPerCssPixel: Double,
): ContinuousDomPoint? {
    if (!nativeX.isFinite() || !nativeY.isFinite() || nativeX < 0.0 || nativeY < 0.0) return null
    if (!pixelsPerCssPixel.isFinite() || pixelsPerCssPixel <= 0.0) return null
    return ContinuousDomPoint(nativeX / pixelsPerCssPixel, nativeY / pixelsPerCssPixel)
}

internal fun javascriptResultObject(result: String): JSONObject? =
    javascriptObjectJson(result)?.let { json -> tryOrNull { JSONObject(json) } }

/** Returns an object JSON literal from either WebView callback representation. */
internal fun javascriptObjectJson(result: String): String? {
    val value = result.trim()
    return when {
        value.startsWith('{') && value.endsWith('}') -> value
        value.startsWith('"') && value.endsWith('"') -> decodeJsonString(value)
            ?.takeIf { it.startsWith('{') && it.endsWith('}') }
        else -> null
    }
}

/** JSON string decoder kept Android-free for local JVM contract tests. */
private fun decodeJsonString(value: String): String? {
    if (value.length < 2 || value.first() != '"' || value.last() != '"') return null
    val decoded = StringBuilder(value.length - 2)
    var index = 1
    while (index < value.lastIndex) {
        val character = value[index++]
        if (character != '\\') {
            decoded.append(character)
            continue
        }
        if (index >= value.lastIndex) return null
        when (val escape = value[index++]) {
            '"', '\\', '/' -> decoded.append(escape)
            'b' -> decoded.append('\b')
            'f' -> decoded.append('\u000C')
            'n' -> decoded.append('\n')
            'r' -> decoded.append('\r')
            't' -> decoded.append('\t')
            'u' -> {
                if (index + 4 > value.lastIndex) return null
                val codePoint = value.substring(index, index + 4).toIntOrNull(16) ?: return null
                decoded.append(codePoint.toChar())
                index += 4
            }
            else -> return null
        }
    }
    return decoded.toString()
}

private fun inputModifiers(json: JSONObject): Set<InputModifier> =
    buildSet {
        if (json.optBoolean("alt")) {
            add(InputModifier.Alt)
        }
        if (json.optBoolean("control")) {
            add(InputModifier.Control)
        }
        if (json.optBoolean("shift")) {
            add(InputModifier.Shift)
        }
        if (json.optBoolean("meta")) {
            add(InputModifier.Meta)
        }
    }
