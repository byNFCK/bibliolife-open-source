package app.bibliolife.reader.readium

import kotlinx.coroutines.withTimeoutOrNull

// Eight seconds is 10x the reported ~800ms cross-resource navigation. Unlike
// startup's 30s readiness budget this applies only to an already-dispatched seek.
internal const val PROGRESS_NAVIGATION_WATCHDOG_MS = 8_000L

/** Late automatic locators cannot persist an unverified recovered viewport. */
internal class RecoveredProgressPublicationFence {
    private var generation: Long? = null
    fun recover(value: Long) { generation = value }
    fun manualDragStarted() { generation = null }
    fun mayPublish(value: Long, automatic: Boolean): Boolean = !automatic || value != generation
}

/** One dispatched owner; cancellation unwinds its work before the mutex releases. */
internal class ProgressNavigationLease(
    val owner: ProgressNavigationOwner,
    val generation: Long,
    private val timeoutMs: Long = PROGRESS_NAVIGATION_WATCHDOG_MS,
    private val diagnostic: (String, Map<String, Any?>) -> Unit = { _, _ -> },
) {
    var verified = false
        private set
    var timedOut = false
        private set
    var terminalResult: String? = null
        private set

    fun markVerified() { verified = true }

    private fun emit(kind: String, fields: Map<String, Any?>) {
        runCatching { diagnostic(kind, fields) }
    }

    suspend fun <T : Any> awaitVerification(block: suspend () -> T): T? {
        val started = System.nanoTime()
        fun elapsedMs() = (System.nanoTime() - started) / 1_000_000L
        emit("progress_navigation_watchdog", mapOf("result" to "armed", "activeOwnerMatches" to true,
            "timeoutMs" to timeoutMs))
        var delivered: T? = null
        try {
            val result = withTimeoutOrNull(timeoutMs) { block().also { delivered = it } }
            // A10 evidence produced at the deadline wins over prompt cancellation
            // of result delivery. This never fabricates an unobserved success.
            if (result != null || verified) return result ?: delivered
            timedOut = true
            emit("progress_navigation_watchdog", mapOf("result" to "fired", "activeOwnerMatches" to true,
                "reason" to "no_terminal_callback", "elapsedMs" to elapsedMs()))
            return null
        } finally {
            if (!timedOut) emit("progress_navigation_watchdog", mapOf("result" to "cancelled",
                "activeOwnerMatches" to true, "elapsedMs" to elapsedMs(),
                "reason" to if (verified) "viewport_verified" else "navigation_terminal"))
        }
    }

    @Synchronized
    fun finish(result: String, release: () -> Unit): Boolean {
        if (terminalResult != null) {
            emit("progress_navigation_watchdog", mapOf("result" to "ignored_stale", "activeOwnerMatches" to false))
            return false
        }
        terminalResult = result
        release()
        return true
    }
}
