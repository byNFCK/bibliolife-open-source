package org.readium.r2.navigator.epub.continuous

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ContinuousReflowDiagnosticOwnerRegistryTest {
    @Test
    fun lateMeasurementResolvesItsCapturedLayoutOwnerAfterANewerGeneration() {
        val registry = ContinuousReflowDiagnosticOwnerRegistry()
        registry.record(11, owner(gestureId = 101, transactionGeneration = 1))
        registry.record(12, owner(gestureId = 202, transactionGeneration = 2))

        // A delayed callback carries layoutGeneration=11; resolving by that
        // immutable source generation must never borrow the current owner 202.
        assertEquals(101L, registry.ownerFor(11)?.context?.gestureId)
        assertEquals(1L, registry.ownerFor(11)?.transactionGeneration)
        assertEquals(202L, registry.ownerFor(12)?.context?.gestureId)
    }

    @Test
    fun evictedGenerationIsReportedAsUnknownInsteadOfUsingTheLatestOwner() {
        val registry = ContinuousReflowDiagnosticOwnerRegistry(capacity = 2)
        registry.record(1, owner(gestureId = 1, transactionGeneration = 1))
        registry.record(2, owner(gestureId = 2, transactionGeneration = 2))
        assertEquals(1, registry.record(3, owner(gestureId = 3, transactionGeneration = 3)))

        assertNull(registry.ownerFor(1))
        assertEquals(3L, registry.ownerFor(3)?.context?.gestureId)
    }

    @Test
    fun ownerWithoutSettingsContextStillRetainsItsContinuousGenerationIdentity() {
        val registry = ContinuousReflowDiagnosticOwnerRegistry()
        val owner = owner(gestureId = 1, transactionGeneration = 2).copy(context = null)

        registry.record(21, owner)

        assertEquals(null, registry.ownerFor(21)?.context)
        assertEquals(2L, registry.ownerFor(21)?.transactionGeneration)
        assertEquals(7, registry.ownerFor(21)?.anchorIndex)
    }

    private fun owner(gestureId: Long, transactionGeneration: Long) = ReflowDiagnosticOwner(
        context = EpubContinuousReflowDiagnosticContext(
            gestureId = gestureId,
            slider = "fontSize",
            applyId = transactionGeneration,
            normalizedValue = 1.25,
        ),
        preferenceGeneration = transactionGeneration,
        transactionGeneration = transactionGeneration,
        anchorIndex = 7,
        anchorBeforeY = 120.0,
    )
}
