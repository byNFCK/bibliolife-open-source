package app.bibliolife.reader.readium

import android.graphics.RectF

internal enum class ReaderHighlightToolbarPlacementSide { ABOVE, BELOW, OVERLAP }

internal data class ReaderHighlightToolbarPlacement(
    val left: Int,
    val top: Int,
    val side: ReaderHighlightToolbarPlacementSide,
)

internal data class ReaderHighlightToolbarBounds(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
) {
    val centerX: Float get() = (left + right) / 2f
    val centerY: Float get() = (top + bottom) / 2f

    companion object {
        fun from(rect: RectF) = ReaderHighlightToolbarBounds(rect.left, rect.top, rect.right, rect.bottom)
    }
}

/** Exact stable placement policy for the native Readium selection rectangle. */
internal object ReaderHighlightToolbarPlacementCalculator {
    fun place(
        selection: RectF,
        toolbarWidth: Int,
        toolbarHeight: Int,
        safeBounds: RectF,
        gapPx: Int,
    ): ReaderHighlightToolbarPlacement = place(
        ReaderHighlightToolbarBounds.from(selection),
        toolbarWidth,
        toolbarHeight,
        ReaderHighlightToolbarBounds.from(safeBounds),
        gapPx,
    )

    fun place(
        selection: ReaderHighlightToolbarBounds,
        toolbarWidth: Int,
        toolbarHeight: Int,
        safeBounds: ReaderHighlightToolbarBounds,
        gapPx: Int,
    ): ReaderHighlightToolbarPlacement {
        val left = (selection.centerX - toolbarWidth / 2f).toInt()
            .coerceIn(
                safeBounds.left.toInt(),
                (safeBounds.right - toolbarWidth).toInt()
                    .coerceAtLeast(safeBounds.left.toInt()),
            )
        val above = selection.top - gapPx - toolbarHeight
        val below = selection.bottom + gapPx
        val top = when {
            above >= safeBounds.top -> above.toInt() to ReaderHighlightToolbarPlacementSide.ABOVE
            below + toolbarHeight <= safeBounds.bottom -> below.toInt() to ReaderHighlightToolbarPlacementSide.BELOW
            else -> (selection.centerY - toolbarHeight / 2f).toInt()
                .coerceIn(
                    safeBounds.top.toInt(),
                    (safeBounds.bottom - toolbarHeight).toInt()
                        .coerceAtLeast(safeBounds.top.toInt()),
                ) to ReaderHighlightToolbarPlacementSide.OVERLAP
        }
        return ReaderHighlightToolbarPlacement(left, top.first, top.second)
    }
}
