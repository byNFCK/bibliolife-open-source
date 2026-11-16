package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadiumEpubBackendResolverTest {
    @Test fun `paginated always resolves legacy without reading cutover control`() {
        val resolution = ReadiumEpubBackendResolver { error("must not be read") }.resolve(
            request(ReadiumEpubRequestedMode.PAGINATED, ReadiumEpubPublicationType.EPUB),
        )

        assertEquals(ReadiumEpubRenditionBackend.LEGACY, resolution.backend)
        assertEquals(ReadiumEpubBackendResolutionSource.PAGINATED_MODE, resolution.source)
    }

    @Test fun `scroll uses legacy by default when internal control is absent`() {
        val resolution = resolver(null).resolve(scrollEpub())

        assertEquals(ReadiumEpubRenditionBackend.LEGACY, resolution.backend)
        assertEquals(ReadiumEpubBackendResolutionSource.DEFAULT_LEGACY, resolution.source)
        assertEquals(
            "READIUM_RENDITION_BACKEND requestedMode=scroll resolved=legacy source=default",
            resolution.diagnosticMessage(),
        )
    }

    @Test fun `scroll uses legacy when internal control is disabled malformed or throws`() {
        listOf("false", "", "yes", "1", " true-ish ").forEach { raw ->
            assertEquals(
                "control=$raw",
                ReadiumEpubRenditionBackend.LEGACY,
                resolver(raw).resolve(scrollEpub()).backend,
            )
        }
        assertEquals(
            ReadiumEpubRenditionBackend.LEGACY,
            ReadiumEpubBackendResolver { error("unavailable") }.resolve(scrollEpub()).backend,
        )
    }

    @Test fun `scroll selects continuous only for exact affirmative internal control`() {
        listOf("true", " TRUE ").forEach { raw ->
            val resolution = resolver(raw).resolve(scrollEpub())
            assertEquals(ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL, resolution.backend)
            assertEquals(ReadiumEpubBackendResolutionSource.INTERNAL_CUTOVER_ENABLED, resolution.source)
        }
    }

    @Test fun `explicit false is the production rollback control`() {
        val resolution = resolver("false").resolve(scrollEpub())

        assertEquals(ReadiumEpubRenditionBackend.LEGACY, resolution.backend)
        assertEquals(ReadiumEpubBackendResolutionSource.DEFAULT_LEGACY, resolution.source)
    }

    @Test fun `only EPUB route and converted EPUB routes are eligible`() {
        val enabled = resolver("true")
        listOf(
            ReadiumEpubPublicationType.EPUB,
            ReadiumEpubPublicationType.CONVERTED_FB2_EPUB,
            ReadiumEpubPublicationType.CONVERTED_TXT_EPUB,
        ).forEach { publicationType ->
            assertEquals(
                publicationType.name,
                ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL,
                enabled.resolve(request(ReadiumEpubRequestedMode.SCROLL, publicationType)).backend,
            )
        }
    }

    @Test fun `PDF and comic containers never resolve continuous`() {
        val enabled = resolver("true")
        listOf(
            ReadiumEpubPublicationType.PDF,
            ReadiumEpubPublicationType.CBZ,
            ReadiumEpubPublicationType.CBR,
            ReadiumEpubPublicationType.UNKNOWN,
        ).forEach { publicationType ->
            val resolution = enabled.resolve(request(ReadiumEpubRequestedMode.SCROLL, publicationType))
            assertEquals(publicationType.name, ReadiumEpubRenditionBackend.LEGACY, resolution.backend)
            assertEquals(ReadiumEpubBackendResolutionSource.INELIGIBLE_PUBLICATION, resolution.source)
        }
    }

    @Test fun `resolution is immutable one-backend session input`() {
        val resolution = resolver("true").resolve(scrollEpub())
        assertTrue(resolution.backend === ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL)
        assertFalse(resolution.backend == ReadiumEpubRenditionBackend.LEGACY)
    }

    private fun resolver(value: String?): ReadiumEpubBackendResolver =
        ReadiumEpubBackendResolver { value }

    private fun scrollEpub(): ReadiumEpubBackendRequest =
        request(ReadiumEpubRequestedMode.SCROLL, ReadiumEpubPublicationType.EPUB)

    private fun request(
        mode: ReadiumEpubRequestedMode,
        publicationType: ReadiumEpubPublicationType,
    ) = ReadiumEpubBackendRequest(mode, publicationType)
}
