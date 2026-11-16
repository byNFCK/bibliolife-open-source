package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReaderHighlightToolbarStateControllerTest {
    @Test
    fun `valid show clear show keeps only the newest popup presentation eligible`() {
        val gate = HighlightToolbarPresentationGate()
        val firstShow = gate.begin()
        val clear = gate.begin()
        val secondShow = gate.begin()

        assertFalse(gate.isCurrent(firstShow))
        assertFalse(gate.isCurrent(clear))
        assertTrue(gate.isCurrent(secondShow))
    }

    @Test
    fun `stale unavailable callback and stale dismissal cannot clear the current presentation`() {
        val gate = HighlightToolbarPresentationGate()
        val staleShow = gate.begin()
        val currentShow = gate.begin()

        assertFalse(gate.isCurrent(staleShow))
        assertTrue(gate.isCurrent(currentShow))
        assertEquals(currentShow, gate.current())
    }

    @Test fun `only existing highlight edit popup owns system Back`() {
        assertFalse(ReaderHighlightToolbarWindowPolicy.isFocusable(HighlightToolbarMode.CREATE))
        assertFalse(ReaderHighlightToolbarWindowPolicy.isOutsideTouchable(HighlightToolbarMode.CREATE))
        assertTrue(ReaderHighlightToolbarWindowPolicy.isFocusable(HighlightToolbarMode.EDIT))
        assertTrue(ReaderHighlightToolbarWindowPolicy.isOutsideTouchable(HighlightToolbarMode.EDIT))
    }

    @Test fun `create toolbar has only Copy followed by the four stable colors`() {
        assertEquals(
            listOf(
                ReaderHighlightToolbarControl.COPY,
                ReaderHighlightToolbarControl.YELLOW,
                ReaderHighlightToolbarControl.GREEN,
                ReaderHighlightToolbarControl.BLUE,
                ReaderHighlightToolbarControl.PINK,
            ),
            ReaderHighlightToolbarComposition.CREATE_CONTROLS,
        )
        assertEquals(
            ReaderHighlightToolbarComposition.CREATE_CONTROLS + ReaderHighlightToolbarControl.DELETE,
            ReaderHighlightToolbarComposition.EDIT_CONTROLS,
        )
    }

    @Test
    fun `active settled selection positively resolves to create float bar`() {
        val snapshot = ReadiumSelectionSnapshot(
            locator = null,
            selectedText = "Selected text",
            textBefore = null,
            textAfter = null,
            href = "chapter.xhtml",
            progression = null,
            totalProgression = null,
            rect = ReadiumSelectionRect(10f, 20f, 110f, 60f),
        )
        val active = ReadiumSelectionState(
            status = ReadiumSelectionStatus.ACTIVE,
            sessionId = 1,
            nativeSessionId = 1,
            generation = 1,
            viewportEpoch = 1,
            selection = snapshot,
            retrievalInFlight = false,
            error = null,
        )

        assertEquals(
            ReaderHighlightToolbarSelectionDecision.ShowCreate(
                selectedText = "Selected text",
                rect = ReadiumSelectionRect(10f, 20f, 110f, 60f),
            ),
            ReaderHighlightToolbarSelectionResolver.resolve(
                active,
                ReadiumSelectionRect(0f, 0f, 400f, 700f),
            ),
        )
        assertEquals(
            ReaderHighlightToolbarSelectionDecision.Wait,
            ReaderHighlightToolbarSelectionResolver.resolve(
                active.copy(status = ReadiumSelectionStatus.PENDING, selection = null),
                ReadiumSelectionRect(0f, 0f, 400f, 700f),
            ),
        )
        assertEquals(
            ReaderHighlightToolbarSelectionDecision.Dismiss,
            ReaderHighlightToolbarSelectionResolver.resolve(
                active.copy(status = ReadiumSelectionStatus.INACTIVE, selection = null),
                ReadiumSelectionRect(0f, 0f, 400f, 700f),
            ),
        )
    }

    @Test
    fun `stable pill metrics retain compact visuals and accessible hit targets`() {
        assertEquals(56, ReaderHighlightToolbarMetrics.PILL_HEIGHT_DP)
        assertEquals(48, ReaderHighlightToolbarMetrics.ACTION_HIT_TARGET_DP)
        assertEquals(5, ReaderHighlightToolbarMetrics.CREATE_ACTION_COUNT)
        assertEquals(6, ReaderHighlightToolbarMetrics.EDIT_ACTION_COUNT)
        assertEquals(248, ReaderHighlightToolbarMetrics.CREATE_WIDTH_DP)
        assertEquals(296, ReaderHighlightToolbarMetrics.EDIT_WIDTH_DP)
        assertEquals(30, ReaderHighlightToolbarMetrics.COLOR_CIRCLE_DP)
        assertEquals(24, ReaderHighlightToolbarMetrics.ICON_DP)
        assertEquals(1, ReaderHighlightToolbarMetrics.OUTLINE_DP)
        assertEquals(32, ReaderHighlightToolbarMetrics.CORNER_RADIUS_DP)
        assertEquals(8, ReaderHighlightToolbarMetrics.ELEVATION_DP)
        assertEquals(4, ReaderHighlightToolbarMetrics.CONTENT_PADDING_DP)
        assertEquals(8, ReaderHighlightToolbarMetrics.SAFE_MARGIN_DP)
        assertEquals(24, ReaderHighlightToolbarMetrics.SELECTION_GAP_DP)
        assertEquals("colorSurfaceContainer", ReaderHighlightToolbarMetrics.SURFACE_ROLE)
        assertEquals("colorOutline", ReaderHighlightToolbarMetrics.OUTLINE_ROLE)
        assertEquals("colorOnSurface", ReaderHighlightToolbarMetrics.ICON_FOREGROUND_ROLE)
    }

    @Test
    fun `placement prefers above then below then overlap within safe bounds`() {
        val safe = ReaderHighlightToolbarBounds(8f, 8f, 400f, 700f)
        assertEquals(
            ReaderHighlightToolbarPlacementSide.ABOVE,
            ReaderHighlightToolbarPlacementCalculator.place(
                ReaderHighlightToolbarBounds(180f, 300f, 220f, 330f),
                200,
                56,
                safe,
                24,
            ).side,
        )
        assertEquals(
            ReaderHighlightToolbarPlacementSide.BELOW,
            ReaderHighlightToolbarPlacementCalculator.place(
                ReaderHighlightToolbarBounds(180f, 20f, 220f, 50f),
                200,
                56,
                safe,
                24,
            ).side,
        )
        val overlap = ReaderHighlightToolbarPlacementCalculator.place(
            ReaderHighlightToolbarBounds(180f, 330f, 220f, 360f),
            200,
            680,
            safe,
            24,
        )
        assertEquals(ReaderHighlightToolbarPlacementSide.OVERLAP, overlap.side)
        assertEquals(100, overlap.left)
    }

    @Test
    fun `selection color creates while selection remains available for persistence`() {
        val controller = HighlightToolbarStateController()
        controller.showCreate(validSelection = true, selectedText = "Selected text")

        assertEquals(
            HighlightToolbarAction.Create(ReaderHighlightColor.Green),
            controller.selectColor(ReaderHighlightColor.Green),
        )
        assertEquals(true, controller.state?.selectionValid)
    }

    @Test
    fun `duplicate active snapshot updates the retained create toolbar state`() {
        val controller = HighlightToolbarStateController()
        val initial = controller.showCreate(validSelection = true, selectedText = "Initial")
        val updated = controller.updateCreate("Updated")

        assertEquals(initial?.generation, updated?.generation)
        assertEquals("Updated", updated?.selectedText)
        assertEquals(true, controller.state?.selectionValid)
    }

    @Test
    fun `native toolbar exposes stable create and existing edit API`() {
        val methodNames = ReaderHighlightToolbarPresenter::class.java.declaredMethods.map { it.name }
        assertEquals(true, methodNames.contains("showEdit"))
        assertEquals(true, methodNames.contains("dismissEditToolbar"))
        assertEquals(true, HighlightToolbarStateController::class.java.declaredMethods.any { it.name == "showEdit" })
    }

    @Test
    fun `existing color recolors same annotation and delete targets same annotation`() {
        val recolor = HighlightToolbarStateController()
        val edit = recolor.showEdit("annotation-id", "Existing text")
        assertEquals(
            HighlightToolbarAction.Recolor("annotation-id", ReaderHighlightColor.Blue),
            recolor.selectColor(ReaderHighlightColor.Blue),
        )
        assertNull(recolor.state)

        val delete = HighlightToolbarStateController()
        val deleteState = delete.showEdit("annotation-id", "Existing text")
        assertEquals(
            HighlightToolbarAction.Delete("annotation-id"),
            delete.deleteAction(deleteState!!.generation),
        )
        assertNull(delete.state)
        assertEquals(HighlightToolbarMode.EDIT, edit!!.mode)
    }

    @Test
    fun `dismissed or invalid create toolbar cannot mutate annotations`() {
        val controller = HighlightToolbarStateController()
        assertNull(controller.selectColor(ReaderHighlightColor.Yellow))
        controller.showCreate(validSelection = true, selectedText = "Text")
        controller.dismiss()
        assertNull(controller.selectColor(ReaderHighlightColor.Pink))
    }
}
