package org.readium.r2.navigator.epub.continuous

import android.os.Looper
import android.widget.FrameLayout
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class ContinuousMeasurementDispatcherTest {
    @Test fun `measurement dispatch runs while resource view remains detached`() {
        val detachedResourceView = FrameLayout(RuntimeEnvironment.getApplication())
        var viewPostDelivered = false
        var measurementDelivered = false

        detachedResourceView.post { viewPostDelivered = true }
        ContinuousMeasurementDispatcher().dispatch {
            assertFalse(detachedResourceView.isAttachedToWindow)
            measurementDelivered = true
        }
        shadowOf(Looper.getMainLooper()).idle()

        assertTrue(measurementDelivered)
        assertFalse(viewPostDelivered)
    }

    @Test fun `generation guard rejects a queued measurement after resource replacement`() {
        var currentResourceGeneration = 4L
        var accepted: Boolean? = null
        val callbackGate = ContinuousResourceCallbackGate()

        ContinuousMeasurementDispatcher().dispatch {
            accepted = callbackGate.accepts(
                index = 2,
                resourceGeneration = 4,
                callbackLayoutGeneration = 7,
                currentLayoutGeneration = 7,
                currentResourceGeneration = currentResourceGeneration,
            )
        }
        currentResourceGeneration = 5L
        shadowOf(Looper.getMainLooper()).idle()

        assertFalse(accepted ?: true)
    }
}
