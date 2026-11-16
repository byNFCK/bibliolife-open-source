package app.bibliolife.reader.readium

import org.readium.r2.navigator.input.InputListener
import org.readium.r2.navigator.input.TapEvent
import java.util.concurrent.atomic.AtomicLong
import android.util.Log

/** UI-independent native interaction envelope delivered from the PlatformView to Flutter. */
internal sealed interface ReadiumReaderInteraction {
    data class ContentTap(
        val interactionId: Long,
        val viewportGeneration: Long,
        val region: ReadiumContentTapRegion? = null,
    ) : ReadiumReaderInteraction

    data class SelectionActionRequested(
        val request: ReadiumSelectionActionRequest,
    ) : ReadiumReaderInteraction

    data class DecorationActivated(
        val activation: ReadiumDecorationActivation,
    ) : ReadiumReaderInteraction

    data class AnnotationActionRequested(
        val request: ReadiumAnnotationActionRequest,
    ) : ReadiumReaderInteraction
}

/** One and only one semantic owner for a completed content interaction. */
internal sealed interface ReadiumTapDisposition {
    data object ToggleChrome : ReadiumTapDisposition
    data object NavigatePrevious : ReadiumTapDisposition
    data object NavigateNext : ReadiumTapDisposition
    data object ActivateLink : ReadiumTapDisposition
    data object ActivateDecoration : ReadiumTapDisposition
    data object ActivateSearchResult : ReadiumTapDisposition
    data object SelectionInteraction : ReadiumTapDisposition
    data object Ignore : ReadiumTapDisposition
}

internal data class ReadiumTapDecision(
    val disposition: ReadiumTapDisposition,
    val consumed: Boolean,
    val interaction: ReadiumReaderInteraction.ContentTap? = null,
)

internal enum class ReadiumContentTapRegion {
    CENTER,
    LEADING,
    TRAILING,
}

/**
 * Validation seam for the Readium content-tap callback. The callback is only installed on the
 * active EPUB navigator, after Readium has filtered links, decorations and gesture consumption.
 * The explicit flags keep the safety contract pure and deterministic in JVM tests.
 */
internal data class ReadiumContentTapCandidate(
    val viewportGeneration: Long,
    val expectedViewportGeneration: Long,
    val activeHost: Boolean = true,
    val activeNavigator: Boolean = true,
    val interactionBlocked: Boolean = false,
    val pointerSequenceCompleted: Boolean = true,
    val movementWithinSlop: Boolean = true,
    val longPress: Boolean = false,
    val doubleTap: Boolean = false,
    val pageTurn: Boolean = false,
    val linkActivation: Boolean = false,
    val decorationActivation: Boolean = false,
    val searchResultActivation: Boolean = false,
    val selectionStarted: Boolean = false,
    val selectionActive: Boolean = false,
    val selectionHandleDragging: Boolean = false,
    val actionModeActive: Boolean = false,
    val consumedByReadium: Boolean = false,
    val sourceInteractionId: Long? = null,
    val region: ReadiumContentTapRegion? = null,
)

/**
 * Generates per-platform-view interaction IDs and rejects stale or duplicate candidates before
 * they reach the event hub. No Android input object is retained in this coordinator.
 */
internal class ReadiumContentTapCoordinator(
    private val interactionIds: AtomicLong = AtomicLong(0),
) {
    private var disposed = false
    private var lastSourceInteractionId: Long? = null
    private var currentViewportGeneration = 0L

    fun setViewportGeneration(generation: Long) {
        if (generation >= 0) currentViewportGeneration = generation
    }

    fun resolve(candidate: ReadiumContentTapCandidate): ReadiumTapDecision {
        if (disposed || candidate.viewportGeneration < 0 ||
            candidate.viewportGeneration != candidate.expectedViewportGeneration ||
            candidate.viewportGeneration != currentViewportGeneration ||
            !candidate.activeHost || !candidate.activeNavigator ||
            !candidate.pointerSequenceCompleted || !candidate.movementWithinSlop ||
            candidate.longPress || candidate.doubleTap || candidate.consumedByReadium
        ) return ReadiumTapDecision(ReadiumTapDisposition.Ignore, consumed = false)

        // Readium normally handles these before InputListener.onTap. Keeping
        // the priority here makes the arbitration contract explicit and safe
        // if a future navigator forwards a classified event to this seam.
        when {
            candidate.selectionStarted || candidate.selectionActive ||
                candidate.selectionHandleDragging || candidate.actionModeActive ||
                candidate.interactionBlocked ->
                return ReadiumTapDecision(ReadiumTapDisposition.SelectionInteraction, consumed = true)
            candidate.linkActivation ->
                return ReadiumTapDecision(ReadiumTapDisposition.ActivateLink, consumed = true)
            candidate.decorationActivation ->
                return ReadiumTapDecision(ReadiumTapDisposition.ActivateDecoration, consumed = true)
            candidate.searchResultActivation ->
                return ReadiumTapDecision(ReadiumTapDisposition.ActivateSearchResult, consumed = true)
            candidate.pageTurn -> {
                val disposition = when (candidate.region) {
                    ReadiumContentTapRegion.LEADING -> ReadiumTapDisposition.NavigatePrevious
                    ReadiumContentTapRegion.TRAILING -> ReadiumTapDisposition.NavigateNext
                    else -> ReadiumTapDisposition.Ignore
                }
                // A classified page gesture already belongs to native
                // navigation, including the no-op fallback for an unknown
                // region. Consume it so the same pointer cannot fall through
                // to chrome classification.
                return ReadiumTapDecision(disposition, consumed = true)
            }
        }

        candidate.sourceInteractionId?.let { sourceId ->
            if (sourceId < 1 || sourceId == lastSourceInteractionId) {
                return ReadiumTapDecision(ReadiumTapDisposition.Ignore, consumed = false)
            }
            lastSourceInteractionId = sourceId
        }
        val interaction = ReadiumReaderInteraction.ContentTap(
            interactionId = interactionIds.incrementAndGet(),
            viewportGeneration = candidate.viewportGeneration,
            region = candidate.region,
        )
        return ReadiumTapDecision(
            disposition = ReadiumTapDisposition.ToggleChrome,
            consumed = true,
            interaction = interaction,
        )
    }

    fun accept(candidate: ReadiumContentTapCandidate): ReadiumReaderInteraction.ContentTap? =
        resolve(candidate).interaction

    fun dispose() {
        disposed = true
    }
}

/**
 * Readium's high-level callback is the only production tap classifier. R2BasicWebView calls it
 * only after links/default-prevented taps and decoration activation have been handled internally.
 */
internal class ReadiumContentTapInputListener(
    private val coordinator: ReadiumContentTapCoordinator,
    private val viewportGeneration: () -> Long,
    private val isHostActive: () -> Boolean,
    private val isNavigatorActive: () -> Boolean,
    private val isInteractionBlocked: () -> Boolean = { false },
    private val onBlockedTap: () -> Boolean = { false },
    private val isSelectionActive: () -> Boolean,
    private val emit: (ReadiumReaderInteraction.ContentTap) -> Unit,
) : InputListener {
    override fun onTap(event: TapEvent): Boolean = onContinuousContentTap()

    /** Reuses the exact legacy ContentTap decision path for a filtered continuous WebView tap. */
    fun onContinuousContentTap(): Boolean {
        // Popup content consumes its own touches. An unclaimed WebView tap
        // while EDIT is visible is therefore an outside tap: dismiss EDIT
        // without forwarding the same gesture as a Flutter chrome toggle.
        if (isInteractionBlocked() && onBlockedTap()) return true
        val generation = viewportGeneration().coerceAtLeast(0)
        coordinator.setViewportGeneration(generation)
        // The stable reader treats every unclaimed single tap as its chrome
        // toggle. Page navigation is a separate drag/swipe path, so this
        // callback has no leading/trailing tap zones to dispatch.
        val region = ReadiumContentTapRegion.CENTER
        val decision = coordinator.resolve(
            ReadiumContentTapCandidate(
                viewportGeneration = generation,
                expectedViewportGeneration = generation,
                activeHost = isHostActive(),
                activeNavigator = isNavigatorActive(),
                interactionBlocked = isInteractionBlocked(),
                selectionActive = isSelectionActive(),
                region = region,
            ),
        )
        val interaction = decision.interaction ?: return decision.consumed
        Log.d("BiblioLifeReadium", "CONTENT_TAP_EMITTED id=${interaction.interactionId} epoch=${interaction.viewportGeneration}")
        emit(interaction)
        return decision.consumed
    }
}
