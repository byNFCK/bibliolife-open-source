package org.readium.r2.navigator.epub

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class EpubWebResourceIdentityTest {
    @Test fun `resource identities keep href index and generation explicit`() {
        val first = EpubWebResourceIdentity(0, "text/one.xhtml", 4)
        val second = EpubWebResourceIdentity(1, "text/two.xhtml", 4)

        assertEquals("text/one.xhtml", first.href)
        assertEquals(1, second.readingOrderIndex)
        assertEquals(4, second.generation)
    }

    @Test fun `resource identities reject stale structural inputs`() {
        assertFailsWith<IllegalArgumentException> { EpubWebResourceIdentity(-1, "a.xhtml", 0) }
        assertFailsWith<IllegalArgumentException> { EpubWebResourceIdentity(0, "", 0) }
        assertFailsWith<IllegalArgumentException> { EpubWebResourceIdentity(0, "a.xhtml", -1) }
    }
}
