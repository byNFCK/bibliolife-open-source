package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.readium.r2.shared.util.data.ReadError
import org.readium.r2.streamer.PublicationOpener

class ReadiumOpenDiagnosticsTest {
    @Test
    fun restorationRecordsSuccessOrConcreteFailureAtTheLastNativeStage() {
        val outcomes = listOf(
            Triple("target_resource_resolution", "target_not_in_reading_order", null),
            Triple("post_restore_layout", "cancelled", null),
            Triple("viewport_verification", "viewport_locator_did_not_converge", "not_verified"),
            Triple("viewport_verification", null, "verified"),
        )
        for ((stage, reason, verification) in outcomes) {
            val events = mutableListOf<Map<String, Any?>>()
            var now = 10L
            val diagnostics = ReadiumInitialLocatorDiagnostics(4, "saved_progress", { now }, events::add)
            diagnostics.stage(stage, "started")
            now += 12
            val result = if (reason == null) "success" else "failed"
            diagnostics.stage(stage, result, mapOf(
                "failureReason" to reason,
                "viewportVerification" to verification,
            ))
            val terminal = diagnostics.finish(result)
            assertEquals(listOf("started", result, result), events.map { it["result"] })
            assertEquals(stage, terminal["restorationStage"])
            assertEquals(reason, terminal["failureReason"])
            assertEquals(verification, terminal["viewportVerification"])
            assertEquals(12L, terminal["elapsedMs"])
            assertEquals(4L, terminal["openAttemptId"])
            assertSame(terminal, diagnostics.finish(result))
            assertEquals(3, events.size)
        }
    }

    @Test
    fun restorationExceptionKeepsSanitizedNativeCause() {
        val diagnostics = ReadiumInitialLocatorDiagnostics(5, "launch_request", { 1L }) {}
        diagnostics.stage("locator_offset", "started")
        val terminal = diagnostics.finish("failed", IllegalStateException("permission denied at /data/private.epub"))
        assertEquals("unexpected_exception", terminal["failureReason"])
        assertEquals("IllegalStateException", terminal["exceptionType"])
        assertEquals("permission denied", terminal["message"])
    }

    @Test
    fun publicationFailureKeepsReadiumCategoryAndExceptionWithoutPrivateData() {
        val error = PublicationOpener.OpenError.Reading(
            ReadError.Decoding(IllegalStateException("Invalid OPF file at /data/private.epub token=secret")),
        )
        val failure = ReadiumOpenDiagnostics.readiumFailure(error)

        assertEquals("Reading", failure["readiumErrorCategory"])
        assertEquals("Decoding", failure["readiumCauseType"])
        assertEquals("IllegalStateException", failure["exceptionType"])
        val message = failure["message"] as String
        assertTrue(message.contains("Invalid OPF file"))
        assertFalse(message.contains("private.epub"))
        assertFalse(message.contains("secret"))
    }
}
