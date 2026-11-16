package org.readium.r2.navigator.epub.continuous

/** A gesture owns an immutable anchor across transactions, not across reader sessions. */
internal class ContinuousGestureReflowBaseline<A> {
    data class Owner(val gestureId: Long, val slider: String, val revision: Long)
    private var revision = 0L
    private var newestGestureId = 0L
    var owner: Owner? = null
        private set
    var anchor: A? = null
        private set

    fun begin(gestureId: Long, slider: String): Owner {
        val current = owner
        if (current?.gestureId == gestureId && current.slider == slider) return current
        // A delayed begin cannot resurrect an ended gesture or replace a newer one.
        if (gestureId <= newestGestureId) return Owner(gestureId, slider, -1L)
        newestGestureId = gestureId
        anchor = null
        return Owner(gestureId, slider, ++revision).also { owner = it }
    }

    fun install(capturedBy: Owner, value: A): Boolean {
        if (owner != capturedBy || anchor != null) return false
        anchor = value
        return true
    }

    fun matches(gestureId: Long, slider: String): Boolean =
        owner?.let { it.gestureId == gestureId && it.slider == slider } == true

    fun isStale(gestureId: Long, slider: String): Boolean =
        gestureId <= newestGestureId && !matches(gestureId, slider)

    fun invalidate() {
        anchor = null
        owner = owner?.copy(revision = ++revision)
    }

    fun release(gestureId: Long): Boolean {
        if (owner?.gestureId != gestureId) return false
        anchor = null
        owner = null
        ++revision
        return true
    }
}
