package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EpubSearchNavigationCoordinatorTest {
    @Test fun `active id delegates exactly once to injected ordinary navigation path`() {
        val target = EpubSearchResultMapper.map(hit("active"), "1:active:0")
        var calls = 0
        var animated = true
        val coordinator = EpubSearchNavigationCoordinator(
            resolve = { EpubSearchController.TargetResolution.Current(target) },
            navigate = { _, requestedAnimated -> calls++; animated = requestedAnimated; EpubSearchNavigationOutcome.Completed },
        )

        assertEquals(EpubSearchNavigationOutcome.Completed, coordinator.goTo("active", animated = false))
        assertEquals(1, calls)
        assertEquals(false, animated)
    }

    @Test fun `unknown and obsolete ids are typed and do not navigate`() {
        var calls = 0
        val coordinator = EpubSearchNavigationCoordinator(
            resolve = { id ->
                when (id) {
                    "old" -> EpubSearchController.TargetResolution.Obsolete
                    else -> EpubSearchController.TargetResolution.Unknown
                }
            },
            navigate = { _, _ -> calls++; EpubSearchNavigationOutcome.Completed },
        )

        assertEquals(EpubSearchNavigationOutcome.ObsoleteResultId, coordinator.goTo("old", false))
        assertEquals(EpubSearchNavigationOutcome.UnknownResultId, coordinator.goTo("missing", false))
        assertTrue(calls == 0)
    }

    private fun hit(text: String) = EpubSearchHit(
        href = "chapter.xhtml",
        title = "Chapter",
        before = "before",
        highlight = text,
        after = "after",
        position = 1,
        progression = .25,
    )
}
