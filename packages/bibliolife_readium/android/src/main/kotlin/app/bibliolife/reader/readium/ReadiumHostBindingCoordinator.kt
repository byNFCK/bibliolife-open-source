package app.bibliolife.reader.readium

/** Narrow lifecycle boundary between a reusable host view and its owner. */
internal interface ReadiumReaderHostBinding {
    fun onHostAttached(containerId: Int) = Unit
    fun onHostLaidOut(containerId: Int, width: Int, height: Int) = Unit
    fun onHostDetached() = Unit
    fun onHostDisposed() = Unit
}

internal enum class ReadiumHostAttachmentState {
    UNBOUND,
    BOUND,
    ATTACHED,
    DETACHED,
    DISPOSED,
}

internal data class ReadiumHostBindingToken(val generation: Long)

/**
 * Pure, idempotent host binding state. It never owns a session, publication or
 * navigator and never treats a temporary detach as permanent disposal.
 */
internal class ReadiumHostBindingCoordinator(
    private val containerId: () -> Int,
) {
    private var binding: ReadiumReaderHostBinding? = null
    private var generation = 0L
    private var attached = false
    private var laidOutWidth = 0
    private var laidOutHeight = 0
    private var disposed = false

    var state: ReadiumHostAttachmentState = ReadiumHostAttachmentState.UNBOUND
        private set

    fun bind(owner: ReadiumReaderHostBinding): ReadiumHostBindingToken? {
        if (disposed || containerId() <= 0) return null
        if (binding === owner) return ReadiumHostBindingToken(generation)
        if (binding != null) return null
        val token = ReadiumHostBindingToken(++generation)
        binding = owner
        state = if (attached) ReadiumHostAttachmentState.ATTACHED else ReadiumHostAttachmentState.BOUND
        if (attached) owner.onHostAttached(containerId())
        if (attached && laidOutWidth > 0 && laidOutHeight > 0) {
            owner.onHostLaidOut(containerId(), laidOutWidth, laidOutHeight)
        }
        return token
    }

    fun unbind(token: ReadiumHostBindingToken): Boolean {
        if (disposed || token.generation != generation || binding == null) return false
        if (attached) binding?.onHostDetached()
        binding = null
        state = ReadiumHostAttachmentState.UNBOUND
        laidOutWidth = 0
        laidOutHeight = 0
        generation++
        return true
    }

    fun onAttached() {
        if (disposed || attached) return
        attached = true
        state = if (binding == null) ReadiumHostAttachmentState.UNBOUND else ReadiumHostAttachmentState.ATTACHED
        binding?.onHostAttached(containerId())
        if (laidOutWidth > 0 && laidOutHeight > 0) {
            binding?.onHostLaidOut(containerId(), laidOutWidth, laidOutHeight)
        }
    }

    fun onDetached() {
        if (disposed || !attached) return
        attached = false
        state = if (binding == null) ReadiumHostAttachmentState.UNBOUND else ReadiumHostAttachmentState.DETACHED
        binding?.onHostDetached()
        laidOutWidth = 0
        laidOutHeight = 0
    }

    fun onLaidOut(width: Int, height: Int) {
        if (disposed || width <= 0 || height <= 0) return
        laidOutWidth = width
        laidOutHeight = height
        if (attached) binding?.onHostLaidOut(containerId(), width, height)
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        binding?.onHostDisposed()
        binding = null
        attached = false
        laidOutWidth = 0
        laidOutHeight = 0
        state = ReadiumHostAttachmentState.DISPOSED
        generation++
    }
}
