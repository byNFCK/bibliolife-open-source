package app.bibliolife.reader.readium

import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicLong
import org.readium.r2.navigator.epub.AndroidSelectionHandleMode
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.DecorableNavigator
import org.readium.r2.navigator.html.HtmlDecorationTemplates

/** Stable values shared by the native and Dart selection-action contracts. */
internal object ReadiumSelectionInteractionProtocol {
    const val HIGHLIGHT = "highlight"
    const val NOTE = "note"
    const val HIGHLIGHT_AND_NOTE = "highlightAndNote"
    const val COPY = "copy"
    const val COMMITTED = "committed"
    const val FAILED = "failed"
    const val CANCELLED = "cancelled"
    const val PERSISTENT_HIGHLIGHTS = "PERSISTENT_HIGHLIGHTS"
    const val SEARCH_RESULT = "SEARCH_RESULT"
}

internal enum class ReadiumSelectionAction(val wireValue: String) {
    HIGHLIGHT(ReadiumSelectionInteractionProtocol.HIGHLIGHT),
    NOTE(ReadiumSelectionInteractionProtocol.NOTE),
    HIGHLIGHT_AND_NOTE(ReadiumSelectionInteractionProtocol.HIGHLIGHT_AND_NOTE),
}

internal enum class ReadiumSelectionActionOutcome(val wireValue: String) {
    COMMITTED(ReadiumSelectionInteractionProtocol.COMMITTED),
    FAILED(ReadiumSelectionInteractionProtocol.FAILED),
    CANCELLED(ReadiumSelectionInteractionProtocol.CANCELLED),
}

internal data class ReadiumSelectionActionRequest(
    val requestId: Long,
    val instanceId: String,
    val selectionSessionId: Long,
    val action: ReadiumSelectionAction,
    val locatorJson: String,
    val selectedText: String,
    val style: String? = null,
    val color: String? = null,
)

internal data class ReadiumSelectionActionResolution(
    val requestId: Long,
    val selectionSessionId: Long,
    val outcome: ReadiumSelectionActionOutcome,
    val annotationId: String? = null,
    val errorCode: String? = null,
)

internal enum class ReadiumAnnotationAction(val wireValue: String) {
    DELETE("delete"),
    RECOLOR("recolor"),
}

internal data class ReadiumAnnotationActionRequest(
    val requestId: Long,
    val instanceId: String,
    val annotationId: String,
    val action: ReadiumAnnotationAction,
    val color: String? = null,
)

internal data class ReadiumAnnotationActionResolution(
    val requestId: Long,
    val outcome: ReadiumSelectionActionOutcome,
    val errorCode: String? = null,
)

/** Keeps native presentation separate from Flutter-owned annotation persistence. */
internal class ReadiumAnnotationActionHost(
    private val instanceId: String,
    private val emit: (ReadiumAnnotationActionRequest) -> Unit,
    private val requestIds: AtomicLong = AtomicLong(0),
) {
    private val pending = linkedMapOf<Long, ReadiumAnnotationActionRequest>()
    private var disposed = false

    fun requestDelete(annotationId: String): Boolean =
        request(annotationId, ReadiumAnnotationAction.DELETE)

    fun requestRecolor(annotationId: String, color: ReaderHighlightColor): Boolean =
        request(annotationId, ReadiumAnnotationAction.RECOLOR, color.storageValue)

    fun resolve(resolution: ReadiumAnnotationActionResolution): String {
        if (disposed) return "disposed"
        return if (pending.remove(resolution.requestId) != null) "resolved" else "stale"
    }

    fun dispose() {
        disposed = true
        pending.clear()
    }

    private fun request(
        annotationId: String,
        action: ReadiumAnnotationAction,
        color: String? = null,
    ): Boolean {
        if (disposed || instanceId.isBlank() || annotationId.isBlank()) return false
        val request = ReadiumAnnotationActionRequest(
            requestId = requestIds.incrementAndGet(),
            instanceId = instanceId,
            annotationId = annotationId,
            action = action,
            color = color,
        )
        pending[request.requestId] = request
        emit(request)
        return true
    }
}

internal data class ReadiumDecorationActivation(
    val interactionId: Long,
    val instanceId: String,
    val group: String,
    val decorationId: String,
)

internal class ReadiumPlatformViewDecorationActivationListener(
    private val instanceId: String,
    private val emit: (ReadiumDecorationActivation) -> Unit,
    private val interactionIds: AtomicLong = AtomicLong(0),
) : DecorableNavigator.Listener {
    private var disposed = false

    override fun onDecorationActivated(event: DecorableNavigator.OnActivatedEvent): Boolean {
        if (disposed || instanceId.isBlank() || event.decoration.id.isBlank()) return false
        emit(
            ReadiumDecorationActivation(
                interactionId = interactionIds.incrementAndGet(),
                instanceId = instanceId,
                group = when (event.group) {
                    ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS.nativeName ->
                        ReadiumSelectionInteractionProtocol.PERSISTENT_HIGHLIGHTS
                    ReadiumDecorationGroup.SEARCH_RESULT.nativeName ->
                        ReadiumSelectionInteractionProtocol.SEARCH_RESULT
                    else -> event.group
                },
                decorationId = event.decoration.id,
            ),
        )
        // Decoration activation is already consumed by Readium; it must not become a
        // content-tap/chrome toggle in Flutter.
        return true
    }

    fun dispose() {
        disposed = true
    }
}

/** Stable persistent-highlight activation path: Readium geometry directly owns native UI. */
internal data class ReadiumExistingHighlightActivation(
    val id: String,
    val color: ReaderHighlightColor,
    val selectedText: String,
)

internal object ReadiumExistingHighlightActivationResolver {
    fun resolve(
        group: String,
        decorationId: String,
        tint: Int?,
        selectedText: String,
    ): ReadiumExistingHighlightActivation? {
        if (group != ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS.nativeName) return null
        val id = decorationId
            .takeIf { it.startsWith(ANNOTATION_PREFIX) }
            ?.removePrefix(ANNOTATION_PREFIX)
            ?.takeIf(String::isNotBlank)
            ?: return null
        val color = ReaderHighlightColor.entries.firstOrNull {
            (it.rgb and 0x00FFFFFF) == ((tint ?: return null) and 0x00FFFFFF)
        } ?: return null
        return ReadiumExistingHighlightActivation(id, color, selectedText)
    }

    private val ReaderHighlightColor.rgb: Int
        get() = when (this) {
            ReaderHighlightColor.Yellow -> 0x00FDD835
            ReaderHighlightColor.Green -> 0x0043A047
            ReaderHighlightColor.Blue -> 0x0042A5F5
            ReaderHighlightColor.Pink -> 0x00EC407A
        }

    private const val ANNOTATION_PREFIX = "annotation:"
}

internal class ReadiumPersistentHighlightActivationListener(
    private val showEdit: (
        id: String,
        color: ReaderHighlightColor,
        selectedText: String,
        anchor: android.graphics.RectF?,
    ) -> Unit,
) : DecorableNavigator.Listener {
    private var disposed = false

    override fun onDecorationActivated(event: DecorableNavigator.OnActivatedEvent): Boolean {
        if (disposed) return false
        val tint = (event.decoration.style as? org.readium.r2.navigator.Decoration.Style.Tinted)
            ?.tint
        val activation = ReadiumExistingHighlightActivationResolver.resolve(
            group = event.group,
            decorationId = event.decoration.id,
            tint = tint,
            selectedText = event.decoration.locator.text.highlight.orEmpty(),
        ) ?: return false
        showEdit(
            activation.id,
            activation.color,
            activation.selectedText,
            event.rect,
        )
        return true
    }

    fun dispose() {
        disposed = true
    }

}

/** ActionMode state is view/session scoped; it never becomes a process-global singleton. */
internal class ReadiumSelectionActionModeCoordinator(
    private val requestIds: AtomicLong = AtomicLong(0),
) {
    private var disposed = false
    private var selectionSessionId: Long? = null
    private var activeMode: WeakReference<ActionMode>? = null
    private val pending = linkedMapOf<Long, ReadiumSelectionActionRequest>()
    private val resolutions = linkedMapOf<Long, ReadiumSelectionActionResolution>()

    private companion object {
        const val TERMINAL_HISTORY_LIMIT = 64
    }

    fun nextRequestId(): Long = requestIds.incrementAndGet()

    fun begin(
        request: ReadiumSelectionActionRequest,
        mode: ActionMode,
    ): Boolean {
        return beginInternal(request, mode)
    }

    /** Custom floating-menu actions have no visible system ActionMode owner. */
    fun begin(request: ReadiumSelectionActionRequest): Boolean = beginInternal(request, null)

    private fun beginInternal(
        request: ReadiumSelectionActionRequest,
        mode: ActionMode?,
    ): Boolean {
        if (disposed || request.requestId < 1 || request.selectionSessionId < 1 ||
            request.instanceId.isBlank() || request.locatorJson.isBlank() ||
            request.selectedText.isBlank()
        ) return false
        if (selectionSessionId != null && selectionSessionId != request.selectionSessionId) {
            pending.clear()
        }
        selectionSessionId = request.selectionSessionId
        if (pending.values.any { it.selectionSessionId == request.selectionSessionId }) return false
        pending[request.requestId] = request
        activeMode = mode?.let(::WeakReference)
        return true
    }

    fun resolve(resolution: ReadiumSelectionActionResolution): String {
        if (disposed || resolution.requestId < 1 || resolution.selectionSessionId < 1) return "disposed"
        resolutions[resolution.requestId]?.let { previous ->
            return if (previous == resolution) "alreadyResolved" else "requestMismatch"
        }
        val request = pending[resolution.requestId] ?: return "staleRequest"
        if (request.selectionSessionId != resolution.selectionSessionId) return "foreignSession"
        resolutions[resolution.requestId] = resolution
        while (resolutions.size > TERMINAL_HISTORY_LIMIT) {
            val iterator = resolutions.entries.iterator()
            if (!iterator.hasNext()) break
            iterator.next()
            iterator.remove()
        }
        pending.remove(resolution.requestId)
        if (resolution.outcome == ReadiumSelectionActionOutcome.COMMITTED) {
            activeMode?.get()?.finish()
            activeMode = null
            selectionSessionId = null
        }
        return "accepted"
    }

    fun onSelectionSessionEnded(sessionId: Long) {
        if (selectionSessionId == sessionId) {
            pending.entries.removeIf { it.value.selectionSessionId == sessionId }
            activeMode = null
            selectionSessionId = null
        }
    }

    fun dispose() {
        disposed = true
        pending.clear()
        resolutions.clear()
        activeMode = null
        selectionSessionId = null
    }
}

/** Reusable native presentation host used by factory-created PlatformViews. */
internal class ReadiumSelectionPresentationHost(
    private val instanceId: String,
    private val selectionProvider: () -> ReadiumSelectionState,
    private val emitSelectionAction: (ReadiumSelectionActionRequest) -> Unit,
    private val onSelectionSessionStarted: (Long) -> Unit = {},
    private val onSelectionSessionEnded: (Long) -> Unit = {},
    private val onActionModeCreated: (Int) -> Unit = {},
    private val onActionModePrepared: (Int) -> Unit = {},
    private val onActionModeDestroyed: () -> Unit = {},
    private val onSelectionHandlesPreparing: (Long) -> Unit = {},
    private val onSelectionHandlesActivated: (Long) -> Unit = {},
    private val onSelectionHandleDragStarted: (Long) -> Unit = {},
    private val onSelectionCommitted: (Long) -> Unit = {},
    private val actionModeCoordinator: ReadiumSelectionActionModeCoordinator =
        ReadiumSelectionActionModeCoordinator(),
) {
    private var disposed = false

    fun createNavigatorConfiguration(): EpubNavigatorFragment.Configuration =
        EpubNavigatorFragment.Configuration(
            // Square, unpadded boxes match Android WebView's native selection
            // rectangles across every line of a multi-line range.
            decorationTemplates = HtmlDecorationTemplates.defaultTemplates(cornerRadius = 0),
            // In Scroll, the legacy resource pager must not turn chapters with
            // horizontal gestures. Paginated navigation remains unchanged.
            disablePageTurnsWhileScrolling = true,
            selectionSessionListener = { active, sessionId ->
                if (disposed) return@Configuration
                if (active) onSelectionSessionStarted(sessionId)
                else {
                    actionModeCoordinator.onSelectionSessionEnded(sessionId)
                    onSelectionSessionEnded(sessionId)
                }
            },
            androidSelectionHandleMode = AndroidSelectionHandleMode.NATIVE,
            customSelectionHandlesPreparationListener = onSelectionHandlesPreparing,
            customSelectionHandlesActivationListener = onSelectionHandlesActivated,
            customSelectionHandleDragStartedListener = onSelectionHandleDragStarted,
            customSelectionCommitListener = onSelectionCommitted,
            // BiblioLife owns selection actions in its Highlight Popup. The
            // callback consumes the platform menu without ending WebView's
            // native selection session, handles, or drag interaction.
            selectionActionModeCallback = ReaderSelectionActionModeCallback(
                onCreated = onActionModeCreated,
                onPrepared = onActionModePrepared,
                onDestroyed = onActionModeDestroyed,
            ),
        )

    fun resolve(resolution: ReadiumSelectionActionResolution): String =
        if (disposed) "disposed" else actionModeCoordinator.resolve(resolution)

    /** Emits one typed action from the stable native floating menu. */
    fun emitFloatingMenuAction(
        action: ReadiumSelectionAction,
        color: ReaderHighlightColor,
        resolvedSelection: ReadiumSelectionSnapshot? = null,
    ): Boolean {
        if (disposed) return false
        val state = selectionProvider()
        val selection = resolvedSelection ?: state.selection ?: return false
        val sessionId = state.nativeSessionId ?: state.sessionId ?: return false
        val selectedText = selection.selectedText.takeIf(String::isNotBlank) ?: return false
        val locatorJson = ReadiumBridgeLocatorMapper.serialize(selection.locator)
            ?.takeIf(String::isNotBlank) ?: return false
        val request = ReadiumSelectionActionRequest(
            requestId = actionModeCoordinator.nextRequestId(),
            instanceId = instanceId,
            selectionSessionId = sessionId,
            action = action,
            locatorJson = locatorJson,
            selectedText = selectedText,
            color = color.storageValue,
        )
        if (!actionModeCoordinator.begin(request)) return false
        emitSelectionAction(request)
        return true
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        actionModeCoordinator.dispose()
    }
}

internal object ReadiumSelectionMenuId {
    const val HIGHLIGHT = 0xB101
    const val NOTE = 0xB102
    const val HIGHLIGHT_AND_NOTE = 0xB103
}

private fun selectionActionFromMenuId(id: Int): ReadiumSelectionAction? = when (id) {
    ReadiumSelectionMenuId.HIGHLIGHT -> ReadiumSelectionAction.HIGHLIGHT
    ReadiumSelectionMenuId.NOTE -> ReadiumSelectionAction.NOTE
    ReadiumSelectionMenuId.HIGHLIGHT_AND_NOTE -> ReadiumSelectionAction.HIGHLIGHT_AND_NOTE
    else -> null
}
