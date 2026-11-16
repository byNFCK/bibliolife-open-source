package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import android.graphics.PointF
import org.readium.r2.navigator.input.TapEvent

class ReadiumReaderInteractionTest {
    @Test fun `ordinary content tap emits one normalized event`() {
        val coordinator = ReadiumContentTapCoordinator()
        coordinator.setViewportGeneration(4)
        val decision = coordinator.resolve(candidate(4, sourceId = 1, region = ReadiumContentTapRegion.CENTER))
        assertEquals(ReadiumTapDisposition.ToggleChrome, decision.disposition)
        assertTrue(decision.consumed)
        val event = decision.interaction as ReadiumReaderInteraction.ContentTap
        assertEquals(1, event.interactionId)
        assertEquals(4, event.viewportGeneration)
        assertEquals(ReadiumContentTapRegion.CENTER, event.region)
    }

    @Test fun `chrome toggle is natively consumed and emits one event`() {
        val coordinator = ReadiumContentTapCoordinator().also { it.setViewportGeneration(0) }
        val emitted = mutableListOf<ReadiumReaderInteraction.ContentTap>()
        val listener = ReadiumContentTapInputListener(
            coordinator = coordinator,
            viewportGeneration = { 0 },
            isHostActive = { true },
            isNavigatorActive = { true },
            isSelectionActive = { false },
            emit = emitted::add,
        )
        assertTrue(listener.onTap(TapEvent(PointF(20f, 20f))))
        assertEquals(1, emitted.size)
    }

    @Test fun `duplicate source callback is suppressed`() {
        val coordinator = ReadiumContentTapCoordinator().also { it.setViewportGeneration(1) }
        assertNotNull(coordinator.accept(candidate(1, sourceId = 9)))
        assertNull(coordinator.accept(candidate(1, sourceId = 9)))
    }

    @Test fun `invalid interaction categories are suppressed`() {
        val flags = listOf(
            candidate(1, longPress = true),
            candidate(1, doubleTap = true),
            candidate(1, pageTurn = true),
            candidate(1, linkActivation = true),
            candidate(1, decorationActivation = true),
            candidate(1, searchResultActivation = true),
            candidate(1, selectionStarted = true),
            candidate(1, selectionActive = true),
            candidate(1, selectionHandleDragging = true),
            candidate(1, actionModeActive = true),
            candidate(1, consumedByReadium = true),
            candidate(1, pointerSequenceCompleted = false),
            candidate(1, movementWithinSlop = false),
        )
        flags.forEach { value ->
            val coordinator = ReadiumContentTapCoordinator().also { it.setViewportGeneration(1) }
            assertNull(coordinator.accept(value))
        }
    }

    @Test fun `stale viewport and inactive identities are suppressed`() {
        val coordinator = ReadiumContentTapCoordinator().also { it.setViewportGeneration(3) }
        assertNull(coordinator.accept(candidate(2)))
        assertNull(coordinator.accept(candidate(3, activeHost = false)))
        assertNull(coordinator.accept(candidate(3, activeNavigator = false)))
    }

    @Test fun `ids are monotonic and isolated per platform view`() {
        val first = ReadiumContentTapCoordinator().also { it.setViewportGeneration(0) }
        val second = ReadiumContentTapCoordinator().also { it.setViewportGeneration(0) }
        val firstOne = first.accept(candidate(0, sourceId = 1)) as ReadiumReaderInteraction.ContentTap
        val firstTwo = first.accept(candidate(0, sourceId = 2)) as ReadiumReaderInteraction.ContentTap
        val secondOne = second.accept(candidate(0, sourceId = 1)) as ReadiumReaderInteraction.ContentTap
        assertEquals(1, firstOne.interactionId)
        assertEquals(2, firstTwo.interactionId)
        assertEquals(1, secondOne.interactionId)
    }

    @Test fun `disposed coordinator emits no event`() {
        val coordinator = ReadiumContentTapCoordinator().also { it.setViewportGeneration(0); it.dispose() }
        assertNull(coordinator.accept(candidate(0, sourceId = 1)))
    }

    @Test fun `Readium tap callback is the single production event source`() {
        val coordinator = ReadiumContentTapCoordinator().also { it.setViewportGeneration(0) }
        val emitted = mutableListOf<ReadiumReaderInteraction.ContentTap>()
        val listener = ReadiumContentTapInputListener(
            coordinator = coordinator,
            viewportGeneration = { 0 },
            isHostActive = { true },
            isNavigatorActive = { true },
            isSelectionActive = { false },
            emit = emitted::add,
        )
        assertTrue(listener.onTap(TapEvent(PointF(1f, 1f))))
        assertEquals(1, emitted.size)
    }

    @Test fun `outside tap dismisses edit popup without toggling Flutter chrome`() {
        val coordinator = ReadiumContentTapCoordinator().also { it.setViewportGeneration(0) }
        val emitted = mutableListOf<ReadiumReaderInteraction.ContentTap>()
        var dismissCount = 0
        val listener = ReadiumContentTapInputListener(
            coordinator = coordinator,
            viewportGeneration = { 0 },
            isHostActive = { true },
            isNavigatorActive = { true },
            isInteractionBlocked = { true },
            onBlockedTap = {
                dismissCount++
                true
            },
            isSelectionActive = { false },
            emit = emitted::add,
        )

        assertTrue(listener.onTap(TapEvent(PointF(1f, 1f))))
        assertEquals(1, dismissCount)
        assertTrue(emitted.isEmpty())
    }

    @Test fun `semantic priority protects native actions from chrome`() {
        val priorities = listOf(
            candidate(1, selectionActive = true) to ReadiumTapDisposition.SelectionInteraction,
            candidate(1, linkActivation = true) to ReadiumTapDisposition.ActivateLink,
            candidate(1, decorationActivation = true) to ReadiumTapDisposition.ActivateDecoration,
            candidate(1, searchResultActivation = true) to ReadiumTapDisposition.ActivateSearchResult,
            candidate(1, pageTurn = true, region = ReadiumContentTapRegion.LEADING) to ReadiumTapDisposition.NavigatePrevious,
            candidate(1, pageTurn = true, region = ReadiumContentTapRegion.TRAILING) to ReadiumTapDisposition.NavigateNext,
        )
        priorities.forEach { (input, expected) ->
            val decision = ReadiumContentTapCoordinator().also { it.setViewportGeneration(1) }.resolve(input)
            assertEquals(expected, decision.disposition)
            assertTrue(decision.consumed)
            assertTrue(decision.disposition != ReadiumTapDisposition.ToggleChrome)
            assertTrue(decision.interaction == null)
        }
    }

    @Test fun `event hub fans out typed interaction without replay`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator()
        val native = RecordingListener()
        val flutter = RecordingListener()
        val nativeToken = coordinator.bind(native)!!
        val bridgeToken = coordinator.bindBridgeListener(flutter)!!
        val interaction = ReadiumReaderInteraction.ContentTap(1, 0)
        coordinator.emitInteraction(interaction)
        assertEquals(listOf(interaction), native.interactions)
        assertEquals(listOf(interaction), flutter.interactions)
        coordinator.unbind(nativeToken)
        coordinator.unbindBridgeListener(bridgeToken)
        val rebound = RecordingListener()
        coordinator.bind(rebound)
        assertTrue(rebound.interactions.isEmpty())
    }

    @Test fun `failing interaction consumer does not block the other consumer`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator()
        val healthy = RecordingListener()
        coordinator.bind(object : ReadiumPlatformViewHostListener {
            override fun onStateChanged(state: ReadiumPlatformViewReaderState) = Unit
            override fun onInteraction(interaction: ReadiumReaderInteraction) { error("native failure") }
        })
        coordinator.bindBridgeListener(healthy)
        coordinator.emitInteraction(ReadiumReaderInteraction.ContentTap(1, 0))
        assertEquals(1, healthy.interactions.size)
    }

    @Test fun `content tap serializes codec safe payload`() {
        val event = ReadiumPlatformViewBridgeSerializer.interactionEvent(
            1,
            "reader",
            7,
            ReadiumReaderInteraction.ContentTap(12, 4, ReadiumContentTapRegion.CENTER),
        )!!
        assertEquals("contentTap", event["type"])
        assertEquals(7L, event["sequence"])
        val payload = event["payload"] as Map<*, *>
        assertEquals(12L, payload["interactionId"])
        assertEquals(4L, payload["viewportGeneration"])
        assertEquals("center", payload["region"])
        assertTrue(payload.values.all { it == null || it is Number || it is String })
    }

    @Test fun `existing annotation action serializes typed codec safe payload`() {
        val event = ReadiumPlatformViewBridgeSerializer.interactionEvent(
            1,
            "reader",
            8,
            ReadiumReaderInteraction.AnnotationActionRequested(
                ReadiumAnnotationActionRequest(
                    requestId = 13,
                    instanceId = "reader",
                    annotationId = "annotation-1",
                    action = ReadiumAnnotationAction.RECOLOR,
                    color = "pink",
                ),
            ),
        )!!
        assertEquals("annotationActionRequested", event["type"])
        val payload = event["payload"] as Map<*, *>
        assertEquals(13L, payload["requestId"])
        assertEquals("annotation-1", payload["annotationId"])
        assertEquals("recolor", payload["action"])
        assertEquals("pink", payload["color"])
        assertTrue(payload.values.all { it == null || it is Number || it is String })
    }

    private fun candidate(
        generation: Long,
        sourceId: Long? = null,
        activeHost: Boolean = true,
        activeNavigator: Boolean = true,
        pointerSequenceCompleted: Boolean = true,
        movementWithinSlop: Boolean = true,
        longPress: Boolean = false,
        doubleTap: Boolean = false,
        pageTurn: Boolean = false,
        linkActivation: Boolean = false,
        decorationActivation: Boolean = false,
        searchResultActivation: Boolean = false,
        selectionStarted: Boolean = false,
        selectionActive: Boolean = false,
        selectionHandleDragging: Boolean = false,
        actionModeActive: Boolean = false,
        consumedByReadium: Boolean = false,
        region: ReadiumContentTapRegion? = null,
    ) = ReadiumContentTapCandidate(
        viewportGeneration = generation,
        expectedViewportGeneration = generation,
        activeHost = activeHost,
        activeNavigator = activeNavigator,
        pointerSequenceCompleted = pointerSequenceCompleted,
        movementWithinSlop = movementWithinSlop,
        longPress = longPress,
        doubleTap = doubleTap,
        pageTurn = pageTurn,
        linkActivation = linkActivation,
        decorationActivation = decorationActivation,
        searchResultActivation = searchResultActivation,
        selectionStarted = selectionStarted,
        selectionActive = selectionActive,
        selectionHandleDragging = selectionHandleDragging,
        actionModeActive = actionModeActive,
        consumedByReadium = consumedByReadium,
        sourceInteractionId = sourceId,
        region = region,
    )

    private class RecordingListener : ReadiumPlatformViewHostListener {
        val interactions = mutableListOf<ReadiumReaderInteraction>()
        override fun onStateChanged(state: ReadiumPlatformViewReaderState) = Unit
        override fun onInteraction(interaction: ReadiumReaderInteraction) { interactions += interaction }
    }
}
