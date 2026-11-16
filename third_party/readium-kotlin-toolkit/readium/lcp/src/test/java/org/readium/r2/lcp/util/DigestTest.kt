/*
 * Copyright 2023 Readium Foundation. All rights reserved.
 * Use of this source code is governed by the BSD-style license
 * available in the top-level LICENSE file of the project.
 */

package org.readium.r2.lcp.util

import java.io.File
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import org.junit.Test

class DigestTest {

    private val file: File =
        File(DigestTest::class.java.getResource("a-fc.jpg")!!.path)

    @OptIn(ExperimentalEncodingApi::class, ExperimentalStdlibApi::class)
    @Test
    fun `sha256 is correct`() {
        val digest = assertNotNull(file.sha256())
        assertEquals("7tt/pc0OxIA8poq/gK6JEhy0nzVjYQEGo078exOD82E=", Base64.encode(digest))
        assertEquals(
            "eedb7fa5cd0ec4803ca68abf80ae89121cb49f3563610106a34efc7b1383f361",
            digest.toHexString()
        )
    }
}
