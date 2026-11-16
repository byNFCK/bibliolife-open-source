package org.readium.r2.navigator.epub

/** Android WebView handle policy for paginated reflowable EPUB selections. */
public enum class AndroidSelectionHandleMode {
    NATIVE,
    CUSTOM_FOR_UNSAFE_RANGES,
    CUSTOM_FOR_ALL_PAGINATED_SELECTIONS,
}
