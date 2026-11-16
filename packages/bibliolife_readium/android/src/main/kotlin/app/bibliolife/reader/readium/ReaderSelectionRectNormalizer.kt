package app.bibliolife.reader.readium

import android.graphics.RectF
import kotlin.math.max
import kotlin.math.min

/** Sanitizes Readium selection geometry for the toolbar without changing the native range. */
internal object ReaderSelectionRectNormalizer {
    fun normalize(raw: ReadiumSelectionRect?, viewport: ReadiumSelectionRect): ReadiumSelectionRect? {
        raw ?: return null
        val values = normalizeValues(
            raw.left,
            raw.top,
            raw.right,
            raw.bottom,
            viewport.left,
            viewport.top,
            viewport.right,
            viewport.bottom,
        ) ?: return null
        return ReadiumSelectionRect(values[0], values[1], values[2], values[3])
    }

    fun normalize(raw: RectF?, viewport: RectF): RectF? {
        raw ?: return null
        val values = normalizeValues(
            raw.left,
            raw.top,
            raw.right,
            raw.bottom,
            viewport.left,
            viewport.top,
            viewport.right,
            viewport.bottom,
        ) ?: return null
        return RectF(values[0], values[1], values[2], values[3])
    }

    private fun normalizeValues(
        rawLeft: Float,
        rawTop: Float,
        rawRight: Float,
        rawBottom: Float,
        viewportLeft: Float,
        viewportTop: Float,
        viewportRight: Float,
        viewportBottom: Float,
    ): FloatArray? {
        if (!rawLeft.isFinite() || !rawTop.isFinite() ||
            !rawRight.isFinite() || !rawBottom.isFinite()
        ) return null
        val left = max(min(rawLeft, rawRight), viewportLeft)
        val right = min(max(rawLeft, rawRight), viewportRight)
        val top = max(min(rawTop, rawBottom), viewportTop)
        val bottom = min(max(rawTop, rawBottom), viewportBottom)
        return floatArrayOf(left, top, right, bottom).takeIf {
            it[2] > it[0] && it[3] > it[1]
        }
    }
}
