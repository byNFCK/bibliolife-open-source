/*
 * Copyright 2026 Readium Foundation. All rights reserved.
 * Use of this source code is governed by the BSD-style license
 * available in the top-level LICENSE file of this project.
 */

package org.readium.r2.navigator.epub

import android.net.Uri
import android.webkit.WebResourceRequest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.epub.css.ReadiumCss
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Metadata
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Url
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
@OptIn(ExperimentalReadiumApi::class)
class WebViewServerTest {

    @Test fun `reflowable bootstrap acknowledgement is attached to the real script element`() {
        val tag = readiumReflowableBootstrapScriptTag(
            Url("https://readium_assets/readium/scripts/readium-reflowable.js")!!,
        )

        assertTrue(tag.contains("readium-reflowable.js"))
        assertTrue(tag.contains("onBootstrapScriptLoaded"))
        assertTrue(tag.contains("onBootstrapScriptFailed"))
        assertTrue(tag.indexOf("src=") < tag.indexOf("onload="))
    }

    @Test fun `mandatory reflowable bootstrap is served as bundled JavaScript`() {
        val response = WebViewServer(
            application = RuntimeEnvironment.getApplication(),
            publication = Publication(Manifest(metadata = Metadata())),
            servedAssets = emptyList(),
            disableSelectionWhenProtected = false,
            onResourceLoadFailed = { _, _ -> error("Readium bootstrap must not use publication routing") },
        ).shouldInterceptRequest(
            request = TestWebResourceRequest("https://readium_assets/readium/scripts/readium-reflowable.js"),
            css = ReadiumCss(assetsBaseHref = WebViewServer.assetsBaseHref),
        )

        assertNotNull(response)
        val body = response!!.data.bufferedReader().use { it.readText() }
        assertFalse("The bootstrap route must never fall back to error XHTML", body.trimStart().startsWith("<"))
        assertTrue("The bundled bootstrap must provide Readium", body.contains("window.readium"))
        assertFalse(
            "Continuous code must not invoke a non-existent global instead of the real Readium API",
            body.contains("setScrollMode"),
        )
    }

    private class TestWebResourceRequest(private val requestedUrl: String) : WebResourceRequest {
        override fun getUrl(): Uri = Uri.parse(requestedUrl)
        override fun isForMainFrame(): Boolean = false
        override fun hasGesture(): Boolean = false
        override fun getMethod(): String = "GET"
        override fun getRequestHeaders(): Map<String, String> = emptyMap()
        override fun isRedirect(): Boolean = false
    }
}
