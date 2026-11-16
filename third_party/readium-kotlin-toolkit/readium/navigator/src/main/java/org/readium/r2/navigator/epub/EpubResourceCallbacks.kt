@file:OptIn(InternalReadiumApi::class)

package org.readium.r2.navigator.epub

import org.readium.r2.navigator.R2BasicWebView
import org.readium.r2.shared.InternalReadiumApi

/** Rendition-neutral callbacks bound to one immutable EPUB resource identity. */
internal interface EpubResourceCallbacks : R2BasicWebView.Listener {
    val resourceIdentity: EpubWebResourceIdentity
}

/**
 * Legacy-only adapter. The shared factory never sees a Fragment; it receives
 * this resource-scoped contract instead.
 */
internal class LegacyEpubResourceCallbacksAdapter(
    override val resourceIdentity: EpubWebResourceIdentity,
    private val legacy: R2BasicWebView.Listener,
) : EpubResourceCallbacks, R2BasicWebView.Listener by legacy
