package org.readium.r2.navigator.pager

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicBoolean

class OwnedLocatorApplyTest {
    @Test
    fun `invalidation during suspended locator lookup prevents fallback scroll`() = runBlocking {
        val current = AtomicBoolean(true)
        val lookupStarted = CompletableDeferred<Unit>()
        val finishLookup = CompletableDeferred<Boolean>()
        var idLookups = 0
        var fallbackWrites = 0

        val result = async {
            applyLocatorWithOrigin(
                isCurrent = current::get,
                findText = {
                    lookupStarted.complete(Unit)
                    finishLookup.await()
                },
                findId = {
                    idLookups += 1
                    false
                },
                applyFallback = { fallbackWrites += 1 },
            )
        }

        lookupStarted.await()
        current.set(false)
        finishLookup.complete(false)

        assertFalse(result.await())
        assertEquals(0, idLookups)
        assertEquals(0, fallbackWrites)
    }

    @Test
    fun `current request reaches fallback after both locator lookups miss`() = runBlocking {
        var fallbackWrites = 0

        assertTrue(
            applyLocatorWithOrigin(
                isCurrent = { true },
                findText = { false },
                findId = { false },
                applyFallback = { fallbackWrites += 1 },
            ),
        )
        assertEquals(1, fallbackWrites)
    }
}
