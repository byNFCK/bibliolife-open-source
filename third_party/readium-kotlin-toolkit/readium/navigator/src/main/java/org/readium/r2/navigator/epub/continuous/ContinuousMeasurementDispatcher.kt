package org.readium.r2.navigator.epub.continuous

import android.os.Handler
import android.os.Looper

/** Dispatches resource measurements independently of the resource view's attachment state. */
internal class ContinuousMeasurementDispatcher(
    private val mainHandler: Handler = Handler(Looper.getMainLooper()),
) {
    fun dispatch(callback: () -> Unit) {
        mainHandler.post { callback() }
    }
}
