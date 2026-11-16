package app.bibliolife.reader.readium

import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem

/** Keeps native selection and handles alive while BiblioLife owns the visible actions. */
internal class ReaderSelectionActionModeCallback(
    private val onCreated: (visibleItemCount: Int) -> Unit = {},
    private val onPrepared: (visibleItemCount: Int) -> Unit = {},
    private val onDestroyed: () -> Unit = {},
) : ActionMode.Callback {
    override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
        menu.clear()
        onCreated(menu.size())
        return true
    }

    override fun onPrepareActionMode(mode: ActionMode, menu: Menu): Boolean {
        menu.clear()
        onPrepared(menu.size())
        return true
    }

    override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean = true

    /** Readium can recreate ActionMode without clearing the native selection. */
    override fun onDestroyActionMode(mode: ActionMode) {
        onDestroyed()
    }
}
