package app.bibliolife.reader.readium

import android.view.View

internal object ReaderHighlightToolbarWindowGuard {
    fun canShow(root: View): Boolean =
        root.isAttachedToWindow && root.windowToken != null &&
            !isPopupDecorViewClassName(root.javaClass.name)

    fun shouldPostToRootThread(onRootThread: Boolean): Boolean = !onRootThread

    fun isPopupDecorViewClassName(className: String): Boolean =
        className.contains("PopupWindow\$PopupDecorView")
}
