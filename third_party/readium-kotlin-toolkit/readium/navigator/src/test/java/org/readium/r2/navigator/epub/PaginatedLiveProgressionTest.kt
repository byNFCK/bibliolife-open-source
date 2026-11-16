package org.readium.r2.navigator.epub

import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.Test

class PaginatedLiveProgressionTest {
    @Test
    fun `physical sample maps absolute scroll extent including whole and fractional pages`() {
        val progression = paginatedLocalProgression(
            scrollX = 13279,
            contentWidth = 50713,
            viewportWidth = 1079,
            pageCount = 47,
            rtl = false,
        )

        assertEquals(0.2675383809485433, progression, 1e-12)
    }

    @Test
    fun `fractional horizontal movement changes progression smoothly`() {
        val first = paginatedLocalProgression(12000, 50713, 1079, 47, rtl = false)
        val second = paginatedLocalProgression(12001, 50713, 1079, 47, rtl = false)

        assertEquals(1.0 / (50713 - 1079), second - first, 1e-12)
    }

    @Test
    fun `progression is monotonic and continuous around page boundaries`() {
        val boundary = 12 * 1079
        val before = paginatedLocalProgression(boundary - 1, 47 * 1079, 1079, 47, rtl = false)
        val at = paginatedLocalProgression(boundary, 47 * 1079, 1079, 47, rtl = false)
        val after = paginatedLocalProgression(boundary + 1, 47 * 1079, 1079, 47, rtl = false)

        assertTrue(before < at && at < after)
        assertEquals(2.0 / (46 * 1079), after - before, 1e-12)
    }

    @Test
    fun `start end and overscroll clamp to unit interval`() {
        val content = 50713
        val viewport = 1079

        assertEquals(0.0, paginatedLocalProgression(0, content, viewport, 47, false), 0.0)
        assertEquals(1.0, paginatedLocalProgression(content - viewport, content, viewport, 47, false), 0.0)
        assertEquals(0.0, paginatedLocalProgression(-5, content, viewport, 47, false), 0.0)
        assertEquals(1.0, paginatedLocalProgression(content, content, viewport, 47, false), 0.0)
    }

    @Test
    fun `actual extent accounts for page margins and RTL reverses logical direction`() {
        val viewport = 1079
        val contentWithMargins = 47 * viewport + 46 * 8
        val maxScroll = contentWithMargins - viewport
        val physicalHalfway = paginatedLocalProgression(maxScroll / 2, contentWithMargins, viewport, 47, false)
        val logicalStartRtl = paginatedLocalProgression(maxScroll, contentWithMargins, viewport, 47, true)
        val logicalEndRtl = paginatedLocalProgression(0, contentWithMargins, viewport, 47, true)

        assertEquals(0.5, physicalHalfway, 1.0 / maxScroll)
        assertEquals(0.0, logicalStartRtl, 0.0)
        assertEquals(1.0, logicalEndRtl, 0.0)
    }

    @Test
    fun `single page and zero extent are finite zero`() {
        assertEquals(0.0, paginatedLocalProgression(30, 1079, 1079, 1, false), 0.0)
        assertEquals(0.0, paginatedLocalProgression(0, 900, 1079, 3, false), 0.0)
        assertEquals(0.0, paginatedLocalProgression(0, 100, 0, 3, false), 0.0)
    }

    @Test
    fun `canonical resource span maps local progression using Readium endpoints`() {
        assertEquals(0.45, paginatedTotalProgression(0.4, 0.25, 0.75)!!, 1e-12)
        assertEquals(0.4, paginatedTotalProgression(0.4, 0.0, 1.0)!!, 1e-12)
    }

    @Test
    fun `last resource uses Readium one endpoint and local value stays clamped`() {
        assertEquals(1.0, paginatedTotalProgression(1.5, 0.25, null)!!, 1e-12)
        assertEquals(0.25, paginatedTotalProgression(-2.0, 0.25, null)!!, 1e-12)
    }

    @Test
    fun `missing or invalid canonical span does not invent a global value`() {
        assertNull(paginatedTotalProgression(0.4, null, 0.75))
        assertNull(paginatedTotalProgression(Double.NaN, 0.25, 0.75))
        assertNull(paginatedTotalProgression(0.4, 0.8, 0.75))
        assertNull(paginatedTotalProgression(0.4, 0.25, Double.NaN))
    }
}
