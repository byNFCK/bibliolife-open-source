package app.bibliolife.reader.readium

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReaderHighlightToolbarWindowGuardTest {
    @Test
    fun `popup decor anchors are rejected and foreign threads are posted`() {
        assertTrue(
            ReaderHighlightToolbarWindowGuard.isPopupDecorViewClassName(
                "android.widget.PopupWindow\$PopupDecorView",
            ),
        )
        assertFalse(
            ReaderHighlightToolbarWindowGuard.isPopupDecorViewClassName(
                "app.bibliolife.reader.readium.ReadiumReaderHostView",
            ),
        )
        assertTrue(ReaderHighlightToolbarWindowGuard.shouldPostToRootThread(false))
        assertFalse(ReaderHighlightToolbarWindowGuard.shouldPostToRootThread(true))
    }
}
