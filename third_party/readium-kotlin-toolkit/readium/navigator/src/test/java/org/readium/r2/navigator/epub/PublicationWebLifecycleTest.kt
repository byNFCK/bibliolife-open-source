package org.readium.r2.navigator.epub

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class PublicationWebLifecycleTest {

    @Test
    fun `disposal is synchronous idempotent and cannot reactivate`() {
        var serverStops = 0
        val server = PublicationWebLifecycle { serverStops += 1 }
        val environment = PublicationWebLifecycle(server::dispose)

        environment.dispose()
        environment.dispose()
        environment.dispose()

        assertTrue(environment.isDisposed)
        assertTrue(server.isDisposed)
        assertEquals(1, serverStops)
        assertFailsWith<IllegalStateException> { environment.checkActive("environment") }
    }

    @Test
    fun `resource eviction lifecycle does not own the shared environment`() {
        var environmentDisposals = 0
        val environment = PublicationWebLifecycle { environmentDisposals += 1 }
        val resourceDisposals = mutableListOf<String>()

        resourceDisposals += "A"
        resourceDisposals += "B"
        resourceDisposals += "C"

        assertEquals(listOf("A", "B", "C"), resourceDisposals)
        assertTrue(!environment.isDisposed)
        assertEquals(0, environmentDisposals)

        environment.dispose()
        assertEquals(1, environmentDisposals)
    }
}
