package org.readium.r2.navigator.epub.continuous

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ContinuousPresentationTest {
    @Test fun `real continuous webview command requests vertical scroll without pagination semantics`() {
        assertTrue(ContinuousPresentation.scrollMode)
        assertFalse(ContinuousPresentation.paginationColumnsEnabled)
        assertFalse(ContinuousPresentation.pageWidthPaginationEnabled)
        assertFalse(ContinuousPresentation.spreadPagingEnabled)
    }

    @Test fun `continuous presentation has no viewport height minimum`() {
        assertFalse(ContinuousPresentation.viewportHeightMinimumEnabled)
    }

    @Test fun `continuous presentation never maps horizontal gestures to resource navigation`() {
        assertFalse(ContinuousPresentation.userPageNavigationEnabled)
    }
}
