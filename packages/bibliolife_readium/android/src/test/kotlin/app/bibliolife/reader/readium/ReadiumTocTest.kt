package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadiumTocTest {
    @Test fun `toc loading starts only once and observer rebinding cannot reload it`() {
        val state = ReadiumReaderSessionState()
        assertTrue(state.startTocLoading())
        assertFalse(state.startTocLoading())
        assertTrue(state.tocReady(emptyList()))
        assertFalse(state.startTocLoading())
    }

    @Test fun `empty toc is a nonfatal empty state`() {
        val state = ReadiumReaderSessionState()
        state.startTocLoading()
        assertTrue(state.tocReady(emptyList()))
        assertEquals(ReadiumTocState.Empty, state.tocState)
        assertFalse(state.phase == ReadiumReaderSessionState.Phase.FAILED)
    }

    @Test fun `nested toc preserves hierarchy and document order`() {
        val index = indexOf(
            Node("One", "one.xhtml", listOf(Node("One A", "one-a.xhtml"))),
            Node("Two", "two.xhtml"),
        )
        assertEquals("One A", index.entries.first().children.single().title)
        assertEquals(listOf("One", "One A", "Two"), index.flattened.map { it.title })
        assertEquals(listOf(0, 1, 0), index.flattened.map { it.level })
    }

    @Test fun `duplicate titles and hrefs receive unique stable ids`() {
        val index = indexOf(Node("Duplicate", "same.xhtml"), Node("Duplicate", "same.xhtml"))
        assertEquals(2, index.flattened.size)
        assertNotEquals(index.flattened[0].id, index.flattened[1].id)
        assertEquals(2, index.targets.size)
    }

    @Test fun `untitled entry retains href for the native presentation fallback`() {
        val entry = indexOf(Node(null, "chapter.xhtml")).entries.single()
        assertEquals("", entry.title)
        assertEquals("chapter.xhtml", entry.href)
    }

    @Test fun `href normalization removes relative prefixes and separates fragment`() {
        val entry = indexOf(Node("Chapter", "./text/../chapter.xhtml#section")).entries.single()
        assertEquals("chapter.xhtml", entry.href)
        assertEquals("section", entry.fragment)
    }

    @Test fun `exact href and fragment match wins over same resource entry`() {
        val index = indexOf(Node("Start", "chapter.xhtml#start"), Node("Middle", "chapter.xhtml#middle"))
        val chapter = ReadiumTocNormalizer.resolveChapter(index, "chapter.xhtml", listOf("middle"), ReadiumChapterState.Unknown)
        assertEquals("Middle", chapter.title)
    }

    @Test fun `resource fallback is deterministic and preserves current same resource chapter`() {
        val index = indexOf(Node("Start", "chapter.xhtml#start"), Node("Middle", "chapter.xhtml#middle"))
        val first = ReadiumTocNormalizer.resolveChapter(index, "chapter.xhtml", emptyList(), ReadiumChapterState.Unknown)
        val retained = ReadiumTocNormalizer.resolveChapter(index, "chapter.xhtml", emptyList(), ReadiumChapterState(index.flattened[1].id, "Middle", "chapter.xhtml"))
        assertEquals("Start", first.title)
        assertEquals("Middle", retained.title)
    }

    @Test fun `unknown locator resolves to deterministic unknown chapter`() {
        val chapter = ReadiumTocNormalizer.resolveChapter(indexOf(Node("One", "one.xhtml")), "missing.xhtml", emptyList(), ReadiumChapterState.Unknown)
        assertEquals(ReadiumChapterState.Unknown, chapter)
    }

    @Test fun `identical chapter state is deduplicated`() {
        val state = ReadiumReaderSessionState()
        val chapter = ReadiumChapterState("one", "One", "one.xhtml")
        assertTrue(state.updateCurrentChapter(chapter))
        assertFalse(state.updateCurrentChapter(chapter))
    }

    @Test fun `locator chapter changes update current chapter`() {
        val index = indexOf(Node("One", "one.xhtml"), Node("Two", "two.xhtml"))
        val one = ReadiumTocNormalizer.resolveChapter(index, "one.xhtml", emptyList(), ReadiumChapterState.Unknown)
        val two = ReadiumTocNormalizer.resolveChapter(index, "two.xhtml", emptyList(), one)
        assertNotEquals(one, two)
        assertEquals("Two", two.title)
    }

    @Test fun `stored id resolves its retained navigation target`() {
        val target = Node("One", "one.xhtml")
        val index = indexOf(target)
        assertEquals(target, index.targets[index.entries.single().id])
        assertNull(index.targets["unknown"])
    }

    @Test fun `stale toc completion after disposal is ignored`() {
        val state = ReadiumReaderSessionState()
        state.startTocLoading()
        state.dispose()
        assertFalse(state.tocReady(indexOf(Node("One", "one.xhtml")).entries))
    }

    @Test fun `toc failure is recoverable and does not move reader to fatal state`() {
        val state = ReadiumReaderSessionState()
        state.startTocLoading()
        assertTrue(state.tocFailed(ReadiumTocError.LoadingFailed()))
        assertTrue(state.tocState is ReadiumTocState.Failed)
        assertFalse(state.phase == ReadiumReaderSessionState.Phase.FAILED)
    }

    @Test fun `failed toc load cannot be restarted by another observer`() {
        val state = ReadiumReaderSessionState()
        state.startTocLoading()
        state.tocFailed(ReadiumTocError.LoadingFailed())
        assertFalse(state.startTocLoading())
    }

    @Test fun `toc normalization caps unexpectedly deep malformed trees`() {
        val deep = generateSequence(Node("Deep", "deep.xhtml")) { parent ->
            Node("Deep", "deep.xhtml", listOf(parent))
        }.drop(80).first()
        assertTrue(indexOf(deep).flattened.size <= 65)
    }

    @Test fun `matching fragment accepts locator fragment marker`() {
        val index = indexOf(Node("Section", "chapter.xhtml#section"))
        val chapter = ReadiumTocNormalizer.resolveChapter(index, "chapter.xhtml", listOf("#section"), ReadiumChapterState.Unknown)
        assertEquals("Section", chapter.title)
    }

    @Test fun `same resource locator changes retain the resolved chapter`() {
        val index = indexOf(Node("One", "one.xhtml"))
        val first = ReadiumTocNormalizer.resolveChapter(index, "one.xhtml", emptyList(), ReadiumChapterState.Unknown)
        val second = ReadiumTocNormalizer.resolveChapter(index, "./one.xhtml", listOf("different-position"), first)
        assertEquals(first, second)
    }

    @Test fun `empty toc leaves current chapter unknown`() {
        val empty = ReadiumTocIndex<Node>(emptyList(), emptyList(), emptyMap())
        assertEquals(
            ReadiumChapterState.Unknown,
            ReadiumTocNormalizer.resolveChapter(empty, "one.xhtml", emptyList(), ReadiumChapterState.Unknown),
        )
    }

    @Test fun `toc state changes do not affect preference coordination`() {
        val preferences = ReadiumPreferenceCoordinator<String>()
        preferences.onNavigatorReady()
        preferences.seedInitialApplied("light")
        val state = ReadiumReaderSessionState()
        state.startTocLoading()
        state.tocReady(indexOf(Node("One", "one.xhtml")).entries)
        assertEquals("light", preferences.snapshot().applied)
        assertEquals(ReadiumPreferenceCoordinator.Action.Unchanged, preferences.request("light"))
    }

    @Test fun `disposed state keeps toc completion and chapter updates ignored`() {
        val state = ReadiumReaderSessionState()
        state.startTocLoading()
        state.dispose()
        assertFalse(state.tocFailed(ReadiumTocError.LoadingFailed()))
        assertFalse(state.updateCurrentChapter(ReadiumChapterState("one", "One", "one.xhtml")))
    }

    private fun indexOf(vararg roots: Node): ReadiumTocIndex<Node> = ReadiumTocNormalizer.normalize(
        roots = roots.toList(),
        titleOf = Node::title,
        hrefOf = Node::href,
        childrenOf = Node::children,
    )

    private data class Node(
        val title: String?,
        val href: String,
        val children: List<Node> = emptyList(),
    )
}
