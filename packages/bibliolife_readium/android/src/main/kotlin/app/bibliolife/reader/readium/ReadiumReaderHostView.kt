package app.bibliolife.reader.readium

import android.content.Context
import android.util.AttributeSet
import android.util.Log
import android.view.View
import android.widget.FrameLayout

/**
 * Reusable native viewport for the Readium navigator fragment.
 *
 * The host owns only its view identity and attachment lifecycle. Input stays
 * with Readium's navigator listeners; the PlatformView root never intercepts
 * selection, popup, link, or content-tap gestures.
 */
internal class ReadiumReaderHostView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {
    private var nativeRenditionGeneration = 0L
    private var stableContainerId: Int = 0
    private val bindingCoordinator: ReadiumHostBindingCoordinator

    init {
        stableContainerId = stableReadiumHostContainerId(id) { View.generateViewId() }
        id = stableContainerId
        bindingCoordinator = ReadiumHostBindingCoordinator(::fragmentContainerId)
    }

    /** Programmatic construction path with a stable resource ID supplied by the owner. */
    constructor(context: Context, containerId: Int) : this(context) {
        stableContainerId = if (containerId > 0) containerId else stableContainerId
        id = stableContainerId
    }

    val fragmentContainerId: Int
        get() = stableContainerId

    val attachmentState: ReadiumHostAttachmentState
        get() = bindingCoordinator.state

    fun bind(binding: ReadiumReaderHostBinding): ReadiumHostBindingToken? =
        bindingCoordinator.bind(binding)

    fun unbind(token: ReadiumHostBindingToken): Boolean = bindingCoordinator.unbind(token)

    /** A future non-Fragment rendition receives the existing PlatformView container. */
    fun nativeRenditionHost(): ReadiumNativeRenditionHost =
        ReadiumNativeRenditionHost(this, nativeRenditionGeneration)

    /** Explicit final owner disposal; a temporary window detach never calls this. */
    fun disposeHostBinding() = bindingCoordinator.dispose()

    override fun onAttachedToWindow() {
        nativeRenditionGeneration += 1
        super.onAttachedToWindow()
        Log.d("BiblioLifeReadium", "READIUM_HOST_VISUAL_ATTACH generation=$nativeRenditionGeneration bounds=$left,$top,$right,$bottom")
        bindingCoordinator.onAttached()
    }

    override fun onDetachedFromWindow() {
        Log.d("BiblioLifeReadium", "READIUM_HOST_VISUAL_DETACH generation=$nativeRenditionGeneration bounds=$left,$top,$right,$bottom")
        bindingCoordinator.onDetached()
        super.onDetachedFromWindow()
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        val width = right - left
        val height = bottom - top
        bindingCoordinator.onLaidOut(width, height)
    }
}

/** Validates and preserves one host ID for the entire host lifetime. */
internal fun stableReadiumHostContainerId(currentId: Int, generateId: () -> Int): Int {
    if (currentId > 0) return currentId
    return generateId().takeIf { it > 0 }
        ?: error("Readium host requires a positive container ID")
}
