package app.bibliolife.reader.readium

import android.view.ActionMode
import android.view.Menu
import android.view.MenuInflater
import android.view.View
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.readium.r2.navigator.Decoration
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadiumSelectionInteractionTest {
    @Test
    fun `general selection resolution presents second valid serialization without ActionMode`() = runBlocking {
        val traces = mutableListOf<String>()
        val shows = mutableListOf<Pair<ReadiumSelectionRect, String>>()
        val hides = mutableListOf<String>()
        val published = mutableListOf<ReadiumSelectionState>()
        var nativeReads = 0
        lateinit var adapter: ReadiumResolvedSelectionToolbarAdapter
        val coordinator = ReadiumSelectionCoordinator(
            scope = CoroutineScope(Dispatchers.Unconfined),
            gateway = object : ReadiumSelectionGateway {
                override suspend fun currentSelection(): ReadiumSelectionSnapshot? {
                    nativeReads++
                    if (nativeReads == 1) return null
                    return ReadiumSelectionSnapshot(
                        locator = null,
                        selectedText = "Selected text",
                        textBefore = null,
                        textAfter = null,
                        href = "chapter.xhtml",
                        progression = null,
                        totalProgression = null,
                        rect = ReadiumSelectionRect(10f, 20f, 110f, 60f),
                    )
                }

                override fun clearSelection() = Unit
            },
            onStateChanged = {
                published += it
                adapter.onSelectionStateChanged(it)
            },
            onResolvedSelection = adapter@{
                adapter.onResolvedSelection(it)
            },
        )
        adapter = ReadiumResolvedSelectionToolbarAdapter(
            viewportProvider = { ReadiumSelectionRect(0f, 0f, 400f, 700f) },
            showCreate = { rect, text -> shows += rect to text },
            hide = hides::add,
            trace = traces::add,
        )
        var posts = 0
        val resolutionHost = ReadiumNativeSelectionResolutionHost(
            beginSession = coordinator::onNativeSelectionSessionStarted,
            activeNativeSessionId = { coordinator.snapshot().nativeSessionId },
            post = { runnable ->
                posts++
                runnable.run()
                true
            },
            requestSelection = coordinator::requestCurrentSelection,
            trace = traces::add,
        )

        resolutionHost.onNativeSelectionSessionStarted(41)
        yield()

        assertEquals(2, posts)
        assertEquals(2, nativeReads)
        assertEquals(
            listOf(ReadiumSelectionRect(10f, 20f, 110f, 60f) to "Selected text"),
            shows,
        )
        assertTrue(hides.isEmpty())
        assertEquals(1, published.count { it.status == ReadiumSelectionStatus.ACTIVE })
        assertTrue(traces.any { it.startsWith("READIUM_SELECTION_RESOLVED_ACTIVE") && it.contains("hasRect=true") })
        assertTrue(traces.any { it.startsWith("HIGHLIGHT_FLOAT_FROM_RESOLVED_SELECTION") })
    }

    @Test
    fun `ActionMode prepare refreshes the authoritative snapshot after native handle movement`() = runBlocking {
        var nativeReads = 0
        val shownTexts = mutableListOf<String>()
        lateinit var adapter: ReadiumResolvedSelectionToolbarAdapter
        val coordinator = ReadiumSelectionCoordinator(
            scope = CoroutineScope(Dispatchers.Unconfined),
            gateway = object : ReadiumSelectionGateway {
                override suspend fun currentSelection(): ReadiumSelectionSnapshot {
                    nativeReads++
                    return ReadiumSelectionSnapshot(
                        locator = null,
                        selectedText = if (nativeReads == 1) "word" else "the whole selected sentence",
                        textBefore = null,
                        textAfter = null,
                        href = "chapter.xhtml",
                        progression = null,
                        totalProgression = null,
                        rect = ReadiumSelectionRect(10f, 20f, 180f, 60f),
                    )
                }

                override fun clearSelection() = Unit
            },
            onStateChanged = { adapter.onSelectionStateChanged(it) },
            onResolvedSelection = { adapter.onResolvedSelection(it) },
        )
        adapter = ReadiumResolvedSelectionToolbarAdapter(
            viewportProvider = { ReadiumSelectionRect(0f, 0f, 400f, 700f) },
            showCreate = { _, text -> shownTexts += text },
            hide = {},
        )
        val resolutionHost = ReadiumNativeSelectionResolutionHost(
            beginSession = coordinator::onNativeSelectionSessionStarted,
            activeNativeSessionId = { coordinator.snapshot().nativeSessionId },
            post = { it.run(); true },
            requestSelection = coordinator::requestCurrentSelection,
        )

        resolutionHost.onNativeSelectionSessionStarted(41)
        yield()
        resolutionHost.refreshActiveSelection()
        yield()

        assertEquals(2, nativeReads)
        assertEquals(listOf("word", "the whole selected sentence"), shownTexts)
        assertEquals("the whole selected sentence", coordinator.snapshot().selection?.selectedText)
    }

    @Test fun `custom ActionMode suppresses system actions while native handles remain enabled`() {
        val host = ReadiumSelectionPresentationHost(
            instanceId = "reader-1",
            selectionProvider = {
                ReadiumSelectionState(
                    status = ReadiumSelectionStatus.INACTIVE,
                    sessionId = null,
                    nativeSessionId = null,
                    generation = 0L,
                    viewportEpoch = 0L,
                    selection = null,
                    retrievalInFlight = false,
                    error = null,
                )
            },
            emitSelectionAction = {},
        )

        val configuration = host.createNavigatorConfiguration()

        assertNotNull(configuration.selectionActionModeCallback)
        assertEquals(org.readium.r2.navigator.epub.AndroidSelectionHandleMode.NATIVE, configuration.androidSelectionHandleMode)
        val highlight = configuration.decorationTemplates[Decoration.Style.Highlight::class]
        assertNotNull(highlight)
        assertTrue(highlight!!.stylesheet.orEmpty().contains("margin: 0px 0px 0 0;"))
        assertTrue(highlight.stylesheet.orEmpty().contains("padding: 0 0px 0px 0;"))
        assertTrue(highlight.stylesheet.orEmpty().contains("border-radius: 0px;"))
    }

    @Test fun `selection action requests are monotonic and one per session`() {
        val coordinator = ReadiumSelectionActionModeCoordinator()
        val mode = fakeMode()
        val first = request(coordinator.nextRequestId())
        assertTrue(coordinator.begin(first, mode))
        assertFalse(coordinator.begin(request(coordinator.nextRequestId()), mode))
        assertEquals("accepted", coordinator.resolve(resolution(first)))
        assertEquals("alreadyResolved", coordinator.resolve(resolution(first)))
        assertEquals("staleRequest", coordinator.resolve(resolution(first.copy(requestId = first.requestId + 10))))
    }

    @Test fun `foreign session cannot resolve a pending request`() {
        val coordinator = ReadiumSelectionActionModeCoordinator()
        val mode = fakeMode()
        val first = request(coordinator.nextRequestId())
        assertTrue(coordinator.begin(first, mode))
        assertEquals(
            "foreignSession",
            coordinator.resolve(resolution(first).copy(selectionSessionId = first.selectionSessionId + 1)),
        )
        assertEquals("accepted", coordinator.resolve(resolution(first)))
    }

    @Test fun `floating menu action uses the same typed idempotent request path`() {
        val coordinator = ReadiumSelectionActionModeCoordinator()
        val first = request(coordinator.nextRequestId()).copy(color = ReaderHighlightColor.Green.storageValue)
        assertTrue(coordinator.begin(first))
        assertFalse(coordinator.begin(request(coordinator.nextRequestId())))
        assertEquals("accepted", coordinator.resolve(resolution(first)))
    }

    @Test fun `existing toolbar delete and recolor emit typed requests for same annotation`() {
        val emitted = mutableListOf<ReadiumAnnotationActionRequest>()
        val host = ReadiumAnnotationActionHost("reader-1", emitted::add)

        assertTrue(host.requestDelete("annotation-1"))
        assertTrue(host.requestRecolor("annotation-1", ReaderHighlightColor.Blue))
        assertEquals(listOf(ReadiumAnnotationAction.DELETE, ReadiumAnnotationAction.RECOLOR), emitted.map { it.action })
        assertEquals(listOf("annotation-1", "annotation-1"), emitted.map { it.annotationId })
        assertEquals(null, emitted.first().color)
        assertEquals("blue", emitted.last().color)
        assertEquals(
            "resolved",
            host.resolve(
                ReadiumAnnotationActionResolution(
                    requestId = emitted.first().requestId,
                    outcome = ReadiumSelectionActionOutcome.COMMITTED,
                ),
            ),
        )
        assertEquals(
            "stale",
            host.resolve(
                ReadiumAnnotationActionResolution(
                    requestId = emitted.first().requestId,
                    outcome = ReadiumSelectionActionOutcome.COMMITTED,
                ),
            ),
        )
    }

    @Test fun `only persistent annotation decorations resolve to existing toolbar metadata`() {
        assertEquals(
            ReadiumExistingHighlightActivation(
                id = "annotation-1",
                color = ReaderHighlightColor.Green,
                selectedText = "Existing text",
            ),
            ReadiumExistingHighlightActivationResolver.resolve(
                group = ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS.nativeName,
                decorationId = "annotation:annotation-1",
                tint = 0x6643A047,
                selectedText = "Existing text",
            ),
        )
        assertEquals(
            null,
            ReadiumExistingHighlightActivationResolver.resolve(
                group = ReadiumDecorationGroup.SEARCH_RESULT.nativeName,
                decorationId = "annotation:annotation-1",
                tint = 0x6643A047,
                selectedText = "Search text",
            ),
        )
        assertEquals(
            null,
            ReadiumExistingHighlightActivationResolver.resolve(
                group = ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS.nativeName,
                decorationId = "search-result",
                tint = 0x6643A047,
                selectedText = "Search text",
            ),
        )
    }

    private fun request(id: Long) = ReadiumSelectionActionRequest(
        requestId = id,
        instanceId = "reader-1",
        selectionSessionId = 7,
        action = ReadiumSelectionAction.HIGHLIGHT,
        locatorJson = "{\"href\":\"chapter.xhtml\"}",
        selectedText = "selected",
    )

    private fun resolution(request: ReadiumSelectionActionRequest) =
        ReadiumSelectionActionResolution(
            requestId = request.requestId,
            selectionSessionId = request.selectionSessionId,
            outcome = ReadiumSelectionActionOutcome.COMMITTED,
            annotationId = "annotation-1",
        )

    private fun fakeMode() = object : ActionMode() {
        override fun setTitle(title: CharSequence?) = Unit
        override fun setTitle(resId: Int) = Unit
        override fun getTitle(): CharSequence? = null
        override fun setSubtitle(subtitle: CharSequence?) = Unit
        override fun setSubtitle(resId: Int) = Unit
        override fun getSubtitle(): CharSequence? = null
        override fun setCustomView(view: View?) = Unit
        override fun getCustomView(): View? = null
        override fun getMenu(): Menu = throw UnsupportedOperationException()
        override fun getMenuInflater(): MenuInflater = throw UnsupportedOperationException()
        override fun invalidate() = Unit
        override fun finish() = Unit
    }

    private fun fakeMenu() = java.lang.reflect.Proxy.newProxyInstance(
        Menu::class.java.classLoader,
        arrayOf(Menu::class.java),
    ) { _, method, _ ->
        when (method.name) {
            "size" -> 0
            else -> null
        }
    } as Menu
}
