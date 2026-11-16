@file:OptIn(InternalReadiumApi::class)

package org.readium.r2.navigator.epub

import org.readium.r2.navigator.R2BasicWebView
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Link

/**
 * Configures a resource WebView from the shared EPUB web environment.
 * Pager placement and page transition policy intentionally remain outside this
 * factory; this is the exact common configuration previously in the page fragment.
 */
internal class EpubResourceWebViewFactory(
    private val environment: EpubWebPublicationEnvironment,
) {
    fun configure(
        webView: R2BasicWebView,
        link: Link?,
        callbacks: EpubResourceCallbacks?,
        textZoom: Int,
    ) {
        webView.listener = callbacks
        if (link != null && callbacks != null) {
            for ((name, value) in callbacks.javascriptInterfacesForResource(link)) {
                if (value != null) webView.addJavascriptInterface(value, name)
            }
        }
        webView.settings.javaScriptEnabled = true
        webView.isVerticalScrollBarEnabled = false
        webView.isHorizontalScrollBarEnabled = false
        webView.settings.useWideViewPort = true
        webView.settings.loadWithOverviewMode = true
        webView.settings.setSupportZoom(true)
        webView.settings.builtInZoomControls = true
        webView.settings.displayZoomControls = false
        webView.settings.textZoom = textZoom
        webView.resourceUrl = link?.let(environment::urlTo)
        webView.setPadding(0, 0, 0, 0)
        webView.addJavascriptInterface(webView, "Android")
    }
}
