package app.bibliolife.reader.readium

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ContinuousPositionPublicationGateTest {
    @Test fun `automatic sources may complete a pending final then stop for that context`() {
        val gate = ContinuousPositionPublicationGate()
        val context = context()

        assertTrue(gate.mayPublish(context, context, ContinuousPositionSource.HOST_VIEWPORT, finalPending = true))
        assertTrue(gate.mayPublish(context, context, ContinuousPositionSource.RESOURCE_READY, finalPending = true))

        assertTrue(gate.manualFinalPublished(context, hasCanonicalProgression = true))

        assertFalse(gate.mayPublish(context, context, ContinuousPositionSource.HOST_VIEWPORT, finalPending = false))
        assertFalse(gate.mayPublish(context, context, ContinuousPositionSource.RESOURCE_READY, finalPending = false))
        assertFalse(gate.mayPublish(context, context, ContinuousPositionSource.POSITIONS_READY, finalPending = false))
    }

    @Test fun `already queued force successor cannot publish after final closes the context`() {
        val gate = ContinuousPositionPublicationGate()
        val queued = context()

        assertTrue(gate.mayPublish(queued, queued, ContinuousPositionSource.HOST_VIEWPORT, finalPending = true))
        assertTrue(gate.manualFinalPublished(queued, hasCanonicalProgression = true))

        assertFalse(gate.mayPublish(queued, queued, ContinuousPositionSource.HOST_VIEWPORT, finalPending = false))
    }

    @Test fun `explicit verified navigation and restore remain allowed after final`() {
        val gate = ContinuousPositionPublicationGate()
        val context = context()
        gate.manualFinalPublished(context, hasCanonicalProgression = true)

        assertTrue(gate.mayPublish(context, context, ContinuousPositionSource.VERIFIED_NAVIGATION, finalPending = false))
        assertTrue(gate.mayPublish(context, context, ContinuousPositionSource.INITIAL_RESTORE, finalPending = false))
        assertTrue(gate.mayPublish(context, context, ContinuousPositionSource.PREFERENCES_APPLIED, finalPending = false))
    }

    @Test fun `new scroll navigation preference or rendition context reopens auto publication`() {
        val rendition = Any()
        val variants = listOf(
            context(rendition = rendition, scrollEpoch = 2),
            context(rendition = rendition, navigationGeneration = 3),
            context(rendition = rendition, preferenceGeneration = 4),
            context(rendition = Any()),
        )

        variants.forEach { next ->
            val gate = ContinuousPositionPublicationGate()
            gate.manualFinalPublished(context(rendition = rendition), hasCanonicalProgression = true)
            assertTrue(gate.mayPublish(next, next, ContinuousPositionSource.HOST_VIEWPORT, finalPending = false))
        }
    }

    @Test fun `old in flight automatic result is rejected after context changes`() {
        val gate = ContinuousPositionPublicationGate()
        val rendition = Any()
        val captured = context(rendition = rendition)
        val current = context(rendition = rendition, navigationGeneration = 3)

        assertFalse(gate.mayPublish(captured, current, ContinuousPositionSource.RESOURCE_READY, finalPending = true))
    }

    @Test fun `matching context coalesces while changed preference context remains newest`() {
        val rendition = Any()
        val gate = ContinuousLocatorDispatchGate<ContinuousPositionContext>()
        val first = context(rendition = rendition)
        val duplicate = context(rendition = rendition)
        val changedPreference = context(rendition = rendition, preferenceGeneration = 4)

        assertTrue(first !== duplicate)
        assertTrue(first == duplicate)
        assertFalse(first == changedPreference)
        assertTrue(gate.offer(first) === first)
        assertTrue(gate.offer(duplicate) == null)
        assertTrue(gate.offer(changedPreference) == null)
        assertTrue(gate.complete(first) === changedPreference)
    }

    @Test fun `automatic source cannot publish with mismatched rendition ownership`() {
        val gate = ContinuousPositionPublicationGate()
        val completed = context()
        val otherOwner = context(rendition = Any())
        gate.manualFinalPublished(completed, hasCanonicalProgression = true)

        assertFalse(gate.mayPublish(completed, otherOwner, ContinuousPositionSource.HOST_VIEWPORT, finalPending = false))
    }

    @Test fun `unavailable final progression leaves final pending for a later canonical sample`() {
        val gate = ContinuousPositionPublicationGate()
        val context = context()

        assertFalse(gate.manualFinalPublished(context, hasCanonicalProgression = false))
        assertTrue(gate.mayPublish(context, context, ContinuousPositionSource.RESOURCE_READY, finalPending = true))

        assertTrue(gate.manualFinalPublished(context, hasCanonicalProgression = true))
        assertFalse(gate.mayPublish(context, context, ContinuousPositionSource.RESOURCE_READY, finalPending = false))
    }

    private fun context(
        rendition: Any = Any(),
        scrollEpoch: Long = 1,
        navigationGeneration: Long = 2,
        preferenceGeneration: Long = 3,
    ) = ContinuousPositionContext(rendition, scrollEpoch, navigationGeneration, preferenceGeneration)
}
