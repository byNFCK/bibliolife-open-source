package app.bibliolife.reader.readium

import android.view.ActionMode
import android.view.Menu
import android.view.MenuInflater
import android.view.MenuItem
import android.view.View
import java.lang.reflect.Proxy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReaderSelectionActionModeCallbackTest {
    @Test fun `clears the system menu without finishing or clearing selection`() {
        var clears = 0
        var createdItems = -1
        var preparedItems = -1
        var destroyed = 0
        val menu = Proxy.newProxyInstance(Menu::class.java.classLoader, arrayOf(Menu::class.java)) { _, method, _ ->
            when (method.name) {
                "clear" -> clears++
                "size" -> 0
                else -> null
            }
        } as Menu
        val mode = fakeMode(menu)
        val callback = ReaderSelectionActionModeCallback(
            onCreated = { createdItems = it },
            onPrepared = { preparedItems = it },
            onDestroyed = { destroyed++ },
        )

        assertTrue(callback.onCreateActionMode(mode, menu))
        assertTrue(callback.onCreateActionMode(mode, menu))
        assertTrue(callback.onPrepareActionMode(mode, menu))
        assertTrue(callback.onActionItemClicked(mode, fakeItem()))
        callback.onDestroyActionMode(mode)

        assertEquals(3, clears)
        assertEquals(0, createdItems)
        assertEquals(0, preparedItems)
        assertEquals(1, destroyed)

        assertTrue(callback.onCreateActionMode(mode, menu))
        assertEquals(0, createdItems)
    }

    private fun fakeMode(menu: Menu) = object : ActionMode() {
        override fun setTitle(title: CharSequence?) = Unit
        override fun setTitle(resId: Int) = Unit
        override fun getTitle(): CharSequence? = null
        override fun setSubtitle(subtitle: CharSequence?) = Unit
        override fun setSubtitle(resId: Int) = Unit
        override fun getSubtitle(): CharSequence? = null
        override fun setCustomView(view: View?) = Unit
        override fun getCustomView(): View? = null
        override fun getMenu(): Menu = menu
        override fun getMenuInflater(): MenuInflater = throw UnsupportedOperationException()
        override fun invalidate() = Unit
        override fun finish() = error("ActionMode must remain active")
    }

    private fun fakeItem() = Proxy.newProxyInstance(
        MenuItem::class.java.classLoader,
        arrayOf(MenuItem::class.java),
    ) { _, _, _ -> null } as MenuItem
}
