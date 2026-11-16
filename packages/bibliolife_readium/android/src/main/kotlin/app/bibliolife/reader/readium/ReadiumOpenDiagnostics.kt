package app.bibliolife.reader.readium

import android.system.ErrnoException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import org.readium.r2.shared.util.Error
import org.readium.r2.shared.util.ThrowableError

internal object ReadiumOpenDiagnostics {
    const val CATEGORY = "Reader.Open"

    fun stage(
        stage: String,
        result: String,
        component: String,
        facts: Map<String, Any?> = emptyMap(),
    ): Map<String, Any?> = mapOf(
        "category" to CATEGORY,
        "stage" to stage,
        "result" to result,
        "component" to component,
    ) + facts

    fun readiumFailure(error: Error?): Map<String, Any?> {
        if (error == null) return emptyMap()
        val causes = generateSequence(error) { it.cause }.take(5).toList()
        val throwable = causes.mapNotNull { (it as? ThrowableError<*>)?.throwable }.lastOrNull()
        val messages = causes.mapNotNull { safeMessage(it.message) }.distinct()
        return mapOf(
            "readiumErrorCategory" to error.javaClass.simpleName,
            "readiumCauseType" to error.cause?.javaClass?.simpleName,
            "exceptionType" to (throwable?.javaClass?.simpleName ?: causes.last().javaClass.simpleName),
            "message" to messages.takeLast(3).joinToString("; ").takeIf { it.isNotEmpty() },
            "osErrorCode" to (throwable as? ErrnoException)?.errno,
        )
    }

    fun exception(error: Throwable): Map<String, Any?> {
        val cause = generateSequence(error) { it.cause }.take(5).last()
        return mapOf(
            "exceptionType" to cause.javaClass.simpleName,
            "message" to safeMessage(cause.message),
            "osErrorCode" to (cause as? ErrnoException)?.errno,
        )
    }

    // Readium errors can contain manifest text, locator data or filenames.
    // Only fixed error phrases and OS failure codes may leave the native side.
    private val safePhrases = Regex(
        "EACCES|EPERM|ENOENT|ENOTDIR|EIO|permission denied|operation not permitted|no such file or directory|" +
            "asset format is not supported|asset is not supported|an error occurred (?:while )?trying to read (?:the )?asset|" +
            "an error occurred while attempting to (?:access data|decode the content)|the resource is too large to be read on this device|" +
            "missing OPF file|invalid OPF file|couldn't decode resource|end of central directory|zip END header not found|" +
            "invalid (?:zip|CEN|LOC) header|unexpected end of (?:file|stream)|navigator fragment was not attached",
        RegexOption.IGNORE_CASE,
    )

    private fun safeMessage(message: String?): String? =
        message?.let { safePhrases.findAll(it).map { match -> match.value }.distinct().take(3).joinToString("; ") }
            ?.takeIf { it.isNotEmpty() }
}

/** Keeps the last failed restore stage available to the existing fatal error path. */
internal class ReadiumInitialLocatorDiagnostics(
    private val openAttemptId: Long,
    private val locatorSource: String?,
    private val clockMs: () -> Long,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private var startedAtMs: Long? = null
    private var lastStage: String? = null
    private val facts = mutableMapOf<String, Any?>()
    var terminal: Map<String, Any?>? = null
        private set

    fun stage(stage: String, result: String, fields: Map<String, Any?> = emptyMap()) {
        if (terminal != null) return
        if (startedAtMs == null) startedAtMs = clockMs()
        lastStage = stage
        facts.putAll(fields)
        emit(snapshot(stage, result))
    }

    fun record(fields: Map<String, Any?>) {
        if (terminal == null) facts.putAll(fields)
    }

    fun finish(result: String, cause: Throwable? = null, reason: String? = null): Map<String, Any?> {
        terminal?.let { return it }
        if (cause != null) facts.putAll(ReadiumOpenDiagnostics.exception(cause))
        if (result == "failed") {
            facts["failureReason"] = when (cause) {
                is TimeoutCancellationException -> "restoration_timeout"
                is CancellationException -> "restoration_cancelled"
                null -> facts["failureReason"] ?: reason
                else -> facts["failureReason"] ?: reason ?: "unexpected_exception"
            }
        } else if (result == "skipped") {
            facts["skipReason"] = reason
        }
        val finished = mapOf(
            "requestedReadingOrderIndex" to null,
            "requestedResourceProgression" to null,
            "requestedHrefMatchesPublication" to null,
            "resolvedReadingOrderIndex" to null,
            "actualReadingOrderIndex" to null,
            "actualResourceProgression" to null,
            "viewportAnchorIndex" to null,
            "viewportVerification" to null,
            "restorationStage" to lastStage,
        ) + snapshot("restoration_terminal", result)
        terminal = finished
        emit(finished)
        return finished
    }

    private fun snapshot(stage: String, result: String): Map<String, Any?> =
        ReadiumOpenDiagnostics.stage(stage, result, "readium_initial_locator", mapOf(
            "kind" to "initial_locator_restoration",
            "openAttemptId" to openAttemptId,
            "locatorSource" to locatorSource,
            "elapsedMs" to startedAtMs?.let { clockMs() - it },
        ) + facts)
}
