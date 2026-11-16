package app.bibliolife.reader.readium

import android.view.ViewGroup
import androidx.fragment.app.FragmentActivity
import java.lang.ref.WeakReference

/**
 * Rendition-neutral native attachment seam. It deliberately keeps only weak
 * UI references: a session may outlive an Activity during PlatformView rebind.
 */
internal class ReadiumNativeRenditionHost internal constructor(
    container: ViewGroup,
    val generation: Long,
) {
    private val containerReference = WeakReference(container)

    fun containerOrNull(): ViewGroup? = containerReference.get()

    fun activityOrNull(): FragmentActivity? = containerOrNull()?.context as? FragmentActivity

    fun isValid(expectedGeneration: Long): Boolean =
        expectedGeneration == generation && containerOrNull()?.isAttachedToWindow == true
}
