package app.bibliolife.reader.readium

import android.content.Context
import android.graphics.Color
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.PopupWindow
import androidx.appcompat.view.ContextThemeWrapper
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.google.android.material.button.MaterialButton
import com.google.android.material.color.MaterialColors
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.roundToInt

internal enum class ReaderHighlightToolbarControl(val color: ReaderHighlightColor?) {
    COPY(null),
    YELLOW(ReaderHighlightColor.Yellow),
    GREEN(ReaderHighlightColor.Green),
    BLUE(ReaderHighlightColor.Blue),
    PINK(ReaderHighlightColor.Pink),
    DELETE(null),
}

internal object ReaderHighlightToolbarComposition {
    val CREATE_CONTROLS = listOf(
        ReaderHighlightToolbarControl.COPY,
        ReaderHighlightToolbarControl.YELLOW,
        ReaderHighlightToolbarControl.GREEN,
        ReaderHighlightToolbarControl.BLUE,
        ReaderHighlightToolbarControl.PINK,
    )
    val EDIT_CONTROLS = CREATE_CONTROLS + ReaderHighlightToolbarControl.DELETE
}

/** Window focus differs by mode: CREATE must preserve native selection handles, EDIT owns Back. */
internal object ReaderHighlightToolbarWindowPolicy {
    fun isFocusable(mode: HighlightToolbarMode): Boolean = mode == HighlightToolbarMode.EDIT
    fun isOutsideTouchable(mode: HighlightToolbarMode): Boolean = mode == HighlightToolbarMode.EDIT
}

internal enum class HighlightToolbarMode { CREATE, EDIT }

internal sealed interface ReaderHighlightToolbarSelectionDecision {
    data object Wait : ReaderHighlightToolbarSelectionDecision
    data object Dismiss : ReaderHighlightToolbarSelectionDecision
    data class ShowCreate(
        val selectedText: String,
        val rect: ReadiumSelectionRect,
    ) : ReaderHighlightToolbarSelectionDecision
}

internal object ReaderHighlightToolbarSelectionResolver {
    fun resolve(
        selection: ReadiumSelectionState,
        viewport: ReadiumSelectionRect,
    ): ReaderHighlightToolbarSelectionDecision {
        if (selection.status == ReadiumSelectionStatus.PENDING) {
            return ReaderHighlightToolbarSelectionDecision.Wait
        }
        val snapshot = selection.selection
        if (selection.status != ReadiumSelectionStatus.ACTIVE ||
            snapshot == null ||
            snapshot.selectedText.isBlank()
        ) {
            return ReaderHighlightToolbarSelectionDecision.Dismiss
        }
        val rect = ReaderSelectionRectNormalizer.normalize(snapshot.rect, viewport)
            ?: return ReaderHighlightToolbarSelectionDecision.Wait
        return ReaderHighlightToolbarSelectionDecision.ShowCreate(
            selectedText = snapshot.selectedText,
            rect = rect,
        )
    }
}

/** Consumes the exact ACTIVE state produced by native selection serialization. */
internal class ReadiumResolvedSelectionToolbarAdapter(
    private val viewportProvider: () -> ReadiumSelectionRect?,
    private val showCreate: (ReadiumSelectionRect, String) -> Unit,
    private val hide: (String) -> Unit,
    private val trace: (String) -> Unit = {},
) {
    fun onResolvedSelection(selection: ReadiumSelectionState) {
        val snapshot = selection.selection
        val rawRect = snapshot?.rect
        trace(
            "READIUM_SELECTION_RESOLVED_ACTIVE hasText=${snapshot?.selectedText?.isNotBlank() == true} " +
                "hasRect=${rawRect != null}" +
                (rawRect?.let {
                    " rectLeft=${it.left} rectTop=${it.top} rectRight=${it.right} rectBottom=${it.bottom}"
                } ?: ""),
        )
        val viewport = viewportProvider() ?: run {
            trace("HIGHLIGHT_FLOAT_RECT accepted=false reason=viewport_unavailable")
            return
        }
        when (val decision = ReaderHighlightToolbarSelectionResolver.resolve(selection, viewport)) {
            ReaderHighlightToolbarSelectionDecision.Wait -> trace(
                "HIGHLIGHT_FLOAT_RECT accepted=false raw_present=${rawRect != null} " +
                    "viewport=${viewport.right - viewport.left}x${viewport.bottom - viewport.top}",
            )
            ReaderHighlightToolbarSelectionDecision.Dismiss -> hide("selection_not_active")
            is ReaderHighlightToolbarSelectionDecision.ShowCreate -> {
                trace("HIGHLIGHT_FLOAT_FROM_RESOLVED_SELECTION generation=${selection.generation}")
                trace(
                    "HIGHLIGHT_FLOAT_RECT accepted=true rect=${decision.rect.left},${decision.rect.top}," +
                        "${decision.rect.right},${decision.rect.bottom} " +
                        "viewport=${viewport.right - viewport.left}x${viewport.bottom - viewport.top}",
                )
                showCreate(decision.rect, decision.selectedText)
            }
        }
    }

    fun onSelectionStateChanged(selection: ReadiumSelectionState) {
        if (selection.status == ReadiumSelectionStatus.INACTIVE ||
            selection.status == ReadiumSelectionStatus.DISPOSED
        ) {
            hide("selection_not_active")
        }
    }
}

internal object ReaderHighlightToolbarMetrics {
    const val PILL_HEIGHT_DP = 56
    const val ACTION_HIT_TARGET_DP = 48
    const val CREATE_ACTION_COUNT = 5
    const val EDIT_ACTION_COUNT = 6
    const val COLOR_CIRCLE_DP = 30
    const val ICON_DP = 24
    const val ICON_FOREGROUND_ROLE = "colorOnSurface"
    const val OUTLINE_DP = 1
    const val OUTLINE_ROLE = "colorOutline"
    const val SURFACE_ROLE = "colorSurfaceContainer"
    const val CORNER_RADIUS_DP = 32
    const val ELEVATION_DP = 8
    const val CONTENT_PADDING_DP = 4
    const val SAFE_MARGIN_DP = 8
    const val SELECTION_GAP_DP = 24

    const val CREATE_WIDTH_DP =
        CONTENT_PADDING_DP * 2 + ACTION_HIT_TARGET_DP * CREATE_ACTION_COUNT
    const val EDIT_WIDTH_DP =
        CONTENT_PADDING_DP * 2 + ACTION_HIT_TARGET_DP * EDIT_ACTION_COUNT
}

internal data class HighlightToolbarState(
    val mode: HighlightToolbarMode,
    val targetId: String?,
    val selectedText: String,
    val selectionValid: Boolean,
    val attached: Boolean,
    val generation: Long,
)

internal class HighlightToolbarStateController {
    var state: HighlightToolbarState? = null
        private set
    private var generation = 0L

    fun showCreate(validSelection: Boolean, selectedText: String): HighlightToolbarState? {
        if (!validSelection) {
            state = null
            return null
        }
        return HighlightToolbarState(
            HighlightToolbarMode.CREATE,
            null,
            selectedText,
            true,
            true,
            ++generation,
        )
            .also { state = it }
    }

    fun updateCreate(selectedText: String): HighlightToolbarState? {
        val current = state?.takeIf {
            it.mode == HighlightToolbarMode.CREATE && it.attached
        } ?: return null
        return current.copy(selectedText = selectedText).also { state = it }
    }

    fun showEdit(id: String, selectedText: String): HighlightToolbarState? {
        if (id.isBlank()) {
            state = null
            return null
        }
        return HighlightToolbarState(
            HighlightToolbarMode.EDIT,
            id,
            selectedText,
            false,
            true,
            ++generation,
        ).also { state = it }
    }

    fun selectColor(color: ReaderHighlightColor): HighlightToolbarAction? {
        val current = state?.takeIf { it.attached } ?: return null
        val action = when (current.mode) {
            HighlightToolbarMode.CREATE ->
                color.takeIf { current.selectionValid }?.let(HighlightToolbarAction::Create)
            HighlightToolbarMode.EDIT -> current.targetId
                ?.takeIf(String::isNotBlank)
                ?.let { HighlightToolbarAction.Recolor(it, color) }
        }
        if (action != null && current.mode == HighlightToolbarMode.EDIT) state = null
        return action
    }

    fun deleteAction(
        expectedGeneration: Long = state?.generation ?: -1,
    ): HighlightToolbarAction.Delete? {
        val current = state?.takeIf {
            it.attached && it.generation == expectedGeneration
        } ?: return null
        val action = current.targetId
            ?.takeIf { current.mode == HighlightToolbarMode.EDIT && it.isNotBlank() }
            ?.let(HighlightToolbarAction::Delete)
        if (action != null) state = null
        return action
    }

    fun dismiss() {
        state = null
    }
}

internal sealed interface HighlightToolbarAction {
    data class Create(val color: ReaderHighlightColor) : HighlightToolbarAction
    data class Delete(val id: String) : HighlightToolbarAction
    data class Recolor(
        val id: String,
        val color: ReaderHighlightColor,
    ) : HighlightToolbarAction
}

/**
 * Root-thread popup work is asynchronous. A newer selection owns the
 * presentation state, so a delayed clear or unavailable-root callback from an
 * older selection must be ignored instead of clearing the newer toolbar.
 */
internal class HighlightToolbarPresentationGate {
    private var generation = 0L

    fun begin(): Long = ++generation

    fun current(): Long = generation

    fun isCurrent(candidate: Long): Boolean = candidate == generation
}

/** Direct port of the stable native PopupWindow menu, rooted in the active PlatformView host. */
internal class ReaderHighlightToolbarPresenter(
    private val context: Context,
    private val rootProvider: () -> View?,
    private val onCopyCreateSelection: () -> Unit,
    private val onCreate: (ReaderHighlightColor) -> Unit,
    private val onDelete: (String) -> Unit,
    private val onRecolor: (String, ReaderHighlightColor) -> Unit,
    private val onVisibilityChanged: (Boolean) -> Unit = {},
) {
    private val presenterId = nextPresenterId.incrementAndGet()
    private val presentationContext = ContextThemeWrapper(context, R.style.BiblioLifeReadiumPopupTheme)
    private val controller = HighlightToolbarStateController()
    private val presentationGate = HighlightToolbarPresentationGate()
    private var popup: PopupWindow? = null
    private var internalDismissReason: String? = null
    @Volatile private var createToolbarVisible = false
    @Volatile private var activeEditId: String? = null
    @Volatile private var createToolbarContentHiddenForCustomDrag = false

    init {
        diagnose("HIGHLIGHT_FLOAT_PRESENTER_CREATED id=$presenterId")
    }

    fun showCreate(anchor: RectF?, validSelection: Boolean, selectedText: String) {
        val presentation = presentationGate.begin()
        activeEditId = null
        createToolbarVisible = validSelection
        notifyVisibilityChanged()
        runOnRootThread(presentation) { root ->
            if (popup?.isShowing == true && controller.updateCreate(selectedText) != null) {
                if (createToolbarContentHiddenForCustomDrag) {
                    popup?.contentView?.visibility = View.VISIBLE
                    createToolbarContentHiddenForCustomDrag = false
                }
                updatePopupPosition(root, anchor)
                return@runOnRootThread
            }
            dismissOnRootThread("selection_cleared", presentation)
            controller.showCreate(validSelection, selectedText)?.let { showOnRootThread(root, it, anchor, presentation) }
        }
    }

    @Suppress("UNUSED_PARAMETER")
    fun showEdit(
        id: String,
        color: ReaderHighlightColor,
        selectedText: String,
        anchor: RectF?,
    ) {
        if (id.isBlank() || activeEditId == id) return
        val presentation = presentationGate.begin()
        activeEditId = id
        createToolbarVisible = false
        notifyVisibilityChanged()
        runOnRootThread(presentation) { root ->
            if (activeEditId != id) return@runOnRootThread
            dismissOnRootThread("activation_changed", presentation)
            // Dismissing a CREATE popup runs its listener synchronously and
            // clears ownership fields. Restore EDIT ownership before showing
            // the replacement popup from the same tap.
            activeEditId = id
            createToolbarVisible = false
            notifyVisibilityChanged()
            controller.showEdit(id, selectedText)?.let {
                showOnRootThread(root, it, anchor, presentation)
            }
        }
    }

    fun dismiss(reason: String) {
        val presentation = presentationGate.begin()
        activeEditId = null
        createToolbarVisible = false
        notifyVisibilityChanged()
        runOnRootThread(presentation) { dismissOnRootThread(reason, presentation) }
    }

    fun detach() {
        dismiss("destroy")
    }
    fun dismissCreateToolbar(reason: String = "selection_cleared"): Boolean {
        // A late native selection-end callback belongs only to CREATE mode.
        // It must never tear down an EDIT popup that already superseded it.
        if (!isCreateToolbarShowing()) return false
        val presentation = presentationGate.begin()
        createToolbarVisible = false
        notifyVisibilityChanged()
        runOnRootThread(presentation) { dismissOnRootThread(reason, presentation) }
        return true
    }

    fun setCreateInteractionEnabled(enabled: Boolean) {
        val presentation = presentationGate.current()
        runOnRootThread(presentation) {
            val active = popup?.takeIf { it.isShowing } ?: return@runOnRootThread
            setEnabledRecursively(active.contentView, enabled)
        }
    }

    fun isCreateToolbarShowing(): Boolean = createToolbarVisible
    fun isEditToolbarShowing(id: String? = null): Boolean =
        activeEditId?.let { id == null || it == id } == true
    fun isVisible(): Boolean = isCreateToolbarShowing() || isEditToolbarShowing()

    fun dismissEditToolbar(reason: String = "edit_dismissed"): Boolean {
        if (!isEditToolbarShowing()) return false
        val presentation = presentationGate.begin()
        activeEditId = null
        runOnRootThread(presentation) { dismissOnRootThread(reason, presentation) }
        return true
    }

    fun dismissOnBack(): Boolean {
        if (!isCreateToolbarShowing() && !isEditToolbarShowing()) return false
        dismiss("back")
        return true
    }

    /** Mirrors stable custom-handle behavior: hide content, keep the retained popup. */
    fun hideCreateToolbarContentForCustomDrag() {
        if (!isCreateToolbarShowing()) return
        val presentation = presentationGate.current()
        runOnRootThread(presentation) {
            val active = popup?.takeIf { it.isShowing } ?: return@runOnRootThread
            active.contentView.visibility = View.INVISIBLE
            createToolbarContentHiddenForCustomDrag = true
        }
    }

    private fun dismissOnRootThread(reason: String, presentation: Long) {
        if (!presentationGate.isCurrent(presentation)) return
        createToolbarContentHiddenForCustomDrag = false
        controller.dismiss()
        val active = popup
        if (active?.isShowing == true) {
            internalDismissReason = reason
            active.dismiss()
            // PopupWindow normally invokes the listener synchronously. Keep
            // a safe fallback without invalidating the listener's identity
            // check before dismiss() is dispatched.
            if (popup === active) {
                popup = null
                internalDismissReason = null
                diagnose("HIGHLIGHT_FLOAT_HIDE reason=$reason showing=false")
            }
        } else {
            popup = null
            diagnose("HIGHLIGHT_FLOAT_HIDE reason=$reason showing=false")
        }
    }

    private fun showOnRootThread(
        root: View,
        state: HighlightToolbarState,
        anchor: RectF?,
        presentation: Long,
    ) {
        if (!presentationGate.isCurrent(presentation)) return
        diagnose(
            "HIGHLIGHT_FLOAT_ROOT attached=${root.isAttachedToWindow} token=${root.windowToken != null} " +
                "size=${root.width}x${root.height}",
        )
        if (!ReaderHighlightToolbarWindowGuard.canShow(root)) {
            onPresentationUnavailable("root_unavailable", presentation)
            return
        }
        val content = buildContent(state)
        content.measure(
            View.MeasureSpec.makeMeasureSpec(root.width.coerceAtLeast(1), View.MeasureSpec.AT_MOST),
            View.MeasureSpec.makeMeasureSpec(root.height.coerceAtLeast(1), View.MeasureSpec.AT_MOST),
        )
        val width = content.measuredWidth
        val height = content.measuredHeight
        diagnose("HIGHLIGHT_FLOAT_MEASURE width=$width height=$height positive=${width > 0 && height > 0}")
        val density = context.resources.displayMetrics.density
        val placement = placementFor(root, anchor, width, height, density)
        lateinit var next: PopupWindow
        val focusable = ReaderHighlightToolbarWindowPolicy.isFocusable(state.mode)
        next = PopupWindow(content, width, height, focusable).apply {
            isOutsideTouchable = ReaderHighlightToolbarWindowPolicy.isOutsideTouchable(state.mode)
            isTouchable = true
            elevation = ReaderHighlightToolbarMetrics.ELEVATION_DP * density
            setBackgroundDrawable(GradientDrawable().apply {
                cornerRadius = ReaderHighlightToolbarMetrics.CORNER_RADIUS_DP * density
                setColor(Color.TRANSPARENT)
            })
            setOnDismissListener {
                if (popup === next && presentationGate.isCurrent(presentation)) {
                    popup = null
                    controller.dismiss()
                    activeEditId = null
                    createToolbarVisible = false
                    notifyVisibilityChanged()
                    diagnose("HIGHLIGHT_FLOAT_HIDE reason=${internalDismissReason ?: "outside"} showing=false")
                    internalDismissReason = null
                }
            }
        }
        diagnose(
            "HIGHLIGHT_FLOAT_POPUP_CREATED id=$presenterId mode=${state.mode.name.lowercase()} " +
                "focusable=$focusable",
        )
        popup = next
        diagnose(
            "HIGHLIGHT_FLOAT_SHOW_CALL x=${placement.left} y=${placement.top} width=$width height=$height",
        )
        next.showAtLocation(root, Gravity.TOP or Gravity.START, placement.left, placement.top)
        diagnose("HIGHLIGHT_FLOAT_SHOW_RESULT isShowing=${next.isShowing}")
    }

    private fun updatePopupPosition(root: View, anchor: RectF?) {
        val active = popup?.takeIf { it.isShowing } ?: return
        val density = context.resources.displayMetrics.density
        val placement = placementFor(root, anchor, active.width, active.height, density)
        active.update(placement.left, placement.top, -1, -1)
        diagnose("HIGHLIGHT_FLOAT_SHOW_RESULT isShowing=${active.isShowing} updated=true x=${placement.left} y=${placement.top}")
    }

    private fun placementFor(
        root: View,
        anchor: RectF?,
        width: Int,
        height: Int,
        density: Float,
    ): ReaderHighlightToolbarPlacement {
        val margin = (ReaderHighlightToolbarMetrics.SAFE_MARGIN_DP * density).roundToInt()
        val location = IntArray(2)
        root.getLocationInWindow(location)
        val systemInsets = ViewCompat.getRootWindowInsets(root)?.getInsets(
            WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout() or WindowInsetsCompat.Type.ime(),
        )
        val safeBounds = RectF(
            (location[0] + margin + (systemInsets?.left ?: 0)).toFloat(),
            (location[1] + margin + (systemInsets?.top ?: 0)).toFloat(),
            (location[0] + root.width - margin - (systemInsets?.right ?: 0)).toFloat(),
            (location[1] + root.height - margin - (systemInsets?.bottom ?: 0)).toFloat(),
        )
        val selectionInWindow = anchor?.let {
            RectF(it).apply { offset(location[0].toFloat(), location[1].toFloat()) }
        }
        return selectionInWindow?.let {
            ReaderHighlightToolbarPlacementCalculator.place(
                selection = it,
                toolbarWidth = width,
                toolbarHeight = height,
                safeBounds = safeBounds,
                gapPx = (ReaderHighlightToolbarMetrics.SELECTION_GAP_DP * density).roundToInt(),
            )
        } ?: ReaderHighlightToolbarPlacementCalculator.place(
            RectF(safeBounds.centerX(), safeBounds.centerY(), safeBounds.centerX(), safeBounds.centerY()),
            width,
            height,
            safeBounds,
            0,
        )
    }

    private fun buildContent(state: HighlightToolbarState): View {
        val density = presentationContext.resources.displayMetrics.density
        return LinearLayout(presentationContext).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                cornerRadius = ReaderHighlightToolbarMetrics.CORNER_RADIUS_DP * density
                setColor(
                    MaterialColors.getColor(
                        presentationContext,
                        com.google.android.material.R.attr.colorSurfaceContainer,
                        Color.WHITE,
                    ),
                )
                setStroke(
                    (ReaderHighlightToolbarMetrics.OUTLINE_DP * density).roundToInt(),
                    MaterialColors.getColor(
                        presentationContext,
                        com.google.android.material.R.attr.colorOutline,
                        0xFF79747E.toInt(),
                    ),
                )
            }
            val contentPadding =
                (ReaderHighlightToolbarMetrics.CONTENT_PADDING_DP * density).roundToInt()
            setPadding(contentPadding, contentPadding, contentPadding, contentPadding)
            val controls = when (state.mode) {
                HighlightToolbarMode.CREATE -> ReaderHighlightToolbarComposition.CREATE_CONTROLS
                HighlightToolbarMode.EDIT -> ReaderHighlightToolbarComposition.EDIT_CONTROLS
            }
            controls.forEach { control ->
                val action = when (control) {
                    ReaderHighlightToolbarControl.COPY -> copyButton(state)
                    ReaderHighlightToolbarControl.DELETE -> deleteButton(state)
                    else -> colorButton(state, requireNotNull(control.color))
                }
                addView(action, touchTarget())
            }
        }
    }

    private fun deleteButton(state: HighlightToolbarState) =
        iconButton(R.drawable.ic_delete_highlight, R.string.delete_highlight).apply {
            setOnClickListener {
                controller.deleteAction(state.generation)?.let { action ->
                    diagnose("ANNOTATION_ACTION_REQUESTED type=delete mode=existing")
                    onDelete(action.id)
                    dismiss("action")
                }
            }
        }

    private fun copyButton(state: HighlightToolbarState) = iconButton(R.drawable.ic_copy_highlight, R.string.copy_highlight).apply {
        isEnabled = state.selectedText.isNotBlank()
        setOnClickListener {
            if (state.mode == HighlightToolbarMode.CREATE) {
                onCopyCreateSelection()
            } else {
                context.getSystemService(android.content.ClipboardManager::class.java)?.setPrimaryClip(
                    android.content.ClipData.newPlainText(
                        "highlight",
                        controller.state?.selectedText ?: state.selectedText,
                    ),
                )
            }
        }
    }

    private fun iconButton(iconRes: Int, descriptionRes: Int) = MaterialButton(presentationContext).apply {
        icon = presentationContext.getDrawable(iconRes)
        iconGravity = MaterialButton.ICON_GRAVITY_TEXT_START
        iconPadding = 0
        text = ""
        contentDescription = presentationContext.getString(descriptionRes)
        iconSize = (ReaderHighlightToolbarMetrics.ICON_DP * presentationContext.resources.displayMetrics.density).roundToInt()
        iconTint = android.content.res.ColorStateList.valueOf(
            MaterialColors.getColor(
                presentationContext,
                com.google.android.material.R.attr.colorOnSurface,
                Color.BLACK,
            ),
        )
        backgroundTintList = android.content.res.ColorStateList.valueOf(Color.TRANSPARENT)
        insetTop = 0
        insetBottom = 0
    }

    private fun colorButton(state: HighlightToolbarState, color: ReaderHighlightColor) = FrameLayout(presentationContext).apply {
        contentDescription = presentationContext.getString(color.description)
        isClickable = true
        isFocusable = true
        addView(View(presentationContext).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(color.argb)
            }
        }, FrameLayout.LayoutParams(
            (ReaderHighlightToolbarMetrics.COLOR_CIRCLE_DP * presentationContext.resources.displayMetrics.density).roundToInt(),
            (ReaderHighlightToolbarMetrics.COLOR_CIRCLE_DP * presentationContext.resources.displayMetrics.density).roundToInt(),
            Gravity.CENTER,
        ))
        setOnClickListener {
            when (val action = controller.selectColor(color)) {
                is HighlightToolbarAction.Create -> onCreate(action.color)
                is HighlightToolbarAction.Recolor -> {
                    diagnose("ANNOTATION_ACTION_REQUESTED type=recolor mode=existing")
                    onRecolor(action.id, action.color)
                    dismiss("action")
                }
                else -> Unit
            }
        }
    }

    private fun touchTarget() = LinearLayout.LayoutParams(
        (ReaderHighlightToolbarMetrics.ACTION_HIT_TARGET_DP * presentationContext.resources.displayMetrics.density).roundToInt(),
        (ReaderHighlightToolbarMetrics.ACTION_HIT_TARGET_DP * presentationContext.resources.displayMetrics.density).roundToInt(),
    )

    private fun setEnabledRecursively(view: View, enabled: Boolean) {
        view.isEnabled = enabled
        if (view is android.view.ViewGroup) {
            for (index in 0 until view.childCount) setEnabledRecursively(view.getChildAt(index), enabled)
        }
    }

    private fun runOnRootThread(presentation: Long, action: (View) -> Unit) {
        if (!presentationGate.isCurrent(presentation)) return
        val root = rootProvider() ?: run {
            onPresentationUnavailable("root_missing", presentation)
            return
        }
        val handler = root.handler ?: run {
            onPresentationUnavailable("handler_missing", presentation)
            return
        }
        val guarded: () -> Unit = guarded@{
            if (!presentationGate.isCurrent(presentation)) return@guarded
            val failure = runCatching { action(root) }.exceptionOrNull()
            if (failure != null) {
                diagnose("HIGHLIGHT_FLOAT_PRESENTATION_FAILED errorType=${failure.javaClass.simpleName}")
                onPresentationUnavailable("operation_failed", presentation)
            }
            Unit
        }
        if (ReaderHighlightToolbarWindowGuard.shouldPostToRootThread(Looper.myLooper() == handler.looper)) {
            handler.post(guarded)
        } else {
            guarded()
        }
    }

    /** Failure is contained to popup presentation and never reaches native selection. */
    private fun onPresentationUnavailable(reason: String, presentation: Long) {
        if (!presentationGate.isCurrent(presentation)) return
        runCatching { popup?.takeIf { it.isShowing }?.dismiss() }
        popup = null
        controller.dismiss()
        activeEditId = null
        createToolbarVisible = false
        createToolbarContentHiddenForCustomDrag = false
        notifyVisibilityChanged()
        diagnose("HIGHLIGHT_FLOAT_SHOW_RESULT isShowing=false reason=$reason")
    }

    private fun notifyVisibilityChanged() = onVisibilityChanged(isVisible())

    private fun diagnose(message: String) {
        if (BuildConfig.DEBUG || Log.isLoggable(TAG, Log.DEBUG)) {
            Log.d(TAG, "HIGHLIGHT_TOOLBAR $message")
        }
    }

    private val ReaderHighlightColor.argb: Int
        get() = when (this) {
            ReaderHighlightColor.Yellow -> 0xFFFDD835.toInt()
            ReaderHighlightColor.Green -> 0xFF43A047.toInt()
            ReaderHighlightColor.Blue -> 0xFF42A5F5.toInt()
            ReaderHighlightColor.Pink -> 0xFFEC407A.toInt()
        }

    private val ReaderHighlightColor.description: Int
        get() = when (this) {
            ReaderHighlightColor.Yellow -> R.string.highlight_color_yellow
            ReaderHighlightColor.Green -> R.string.highlight_color_green
            ReaderHighlightColor.Blue -> R.string.highlight_color_blue
            ReaderHighlightColor.Pink -> R.string.highlight_color_pink
        }

    private companion object {
        const val TAG = "BiblioLifeReadium"
        val nextPresenterId = AtomicLong(0)
    }
}
