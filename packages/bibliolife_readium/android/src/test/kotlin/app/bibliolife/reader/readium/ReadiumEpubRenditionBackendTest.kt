package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadiumEpubRenditionBackendTest {
    @Test fun `legacy decision attaches the existing navigator path`() {
        assertEquals(
            ReadiumEpubRenditionBootstrapAction.AttachLegacyNavigator,
            ReadiumEpubRenditionBackend.LEGACY.bootstrapAction(),
        )
    }

    @Test fun `experimental decision enters pending without a legacy fallback`() {
        val action = ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL.bootstrapAction()
        assertEquals(ReadiumEpubRenditionBootstrapAction.EnterContinuousPending, action)
        assertFalse(action is ReadiumEpubRenditionBootstrapAction.AttachLegacyNavigator)
    }

    @Test fun `backend choices are stable immutable enum values for a session lifecycle`() {
        val selected = ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL
        assertTrue(selected === ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL)
        assertEquals(
            ReadiumEpubRenditionBootstrapAction.EnterContinuousPending,
            selected.bootstrapAction(),
        )
    }
}
