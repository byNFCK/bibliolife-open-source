/*
 * Copyright 2026 Readium Foundation. All rights reserved.
 * Use of this source code is governed by the BSD-style license
 * available in the top-level LICENSE file of this project.
 */

@file:OptIn(ExperimentalReadiumApi::class, InternalReadiumApi::class, DelicateReadiumApi::class)

package org.readium.r2.navigator.epub

import android.app.Application
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import org.readium.r2.navigator.epub.css.ReadiumCss
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.DelicateReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.resource.Resource

/**
 * BiblioLife local-fork seam for the web resources of one EPUB publication.
 *
 * The environment has no current-resource or pager state. A rendition creates it
 * once, then every resource web view resolves URLs and intercepted requests through
 * this same publication-scoped server.
 */
@OptIn(ExperimentalReadiumApi::class)
internal class EpubWebPublicationEnvironment private constructor(
    val publication: Publication,
    private val server: WebViewServer,
) : AutoCloseable {
    private val lifecycle = PublicationWebLifecycle(server::dispose)

    internal val isDisposed: Boolean get() = lifecycle.isDisposed

    /** Owns the publication server; resource WebViews only use this environment. */
    internal fun dispose() {
        lifecycle.dispose()
    }

    override fun close() = dispose()

    private fun checkActive() {
        lifecycle.checkActive("EpubWebPublicationEnvironment")
    }

    fun urlTo(link: Link): AbsoluteUrl {
        checkActive()
        return server.linkToServedUrl(link)
    }

    fun linkAt(url: AbsoluteUrl): Link? {
        checkActive()
        return server.servedUrlToLink(url)
    }

    fun resourceAt(url: AbsoluteUrl): Resource? =
        linkAt(url)?.let(publication::get)

    fun shouldInterceptRequest(
        request: WebResourceRequest,
        css: ReadiumCss,
    ): WebResourceResponse? = if (lifecycle.isDisposed) null else server.shouldInterceptRequest(request, css)

    companion object {
        fun create(
            application: Application,
            publication: Publication,
            configuration: EpubNavigatorFragment.Configuration,
            onResourceLoadFailed: (Url, org.readium.r2.shared.util.data.ReadError) -> Unit,
        ): EpubWebPublicationEnvironment = EpubWebPublicationEnvironment(
            publication = publication,
            server = WebViewServer(
                application = application,
                publication = publication,
                servedAssets = configuration.servedAssets,
                disableSelectionWhenProtected = configuration.disableSelectionWhenProtected,
                onResourceLoadFailed = onResourceLoadFailed,
            ),
        )
    }
}
