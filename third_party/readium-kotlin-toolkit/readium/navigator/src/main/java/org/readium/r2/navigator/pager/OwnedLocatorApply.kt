package org.readium.r2.navigator.pager

/** Applies a locator without allowing an invalidated request to fall through to a later scroll. */
internal suspend fun applyLocatorWithOrigin(
    isCurrent: () -> Boolean,
    findText: suspend () -> Boolean,
    findId: suspend () -> Boolean,
    applyFallback: suspend () -> Unit,
): Boolean {
    if (!isCurrent()) return false

    if (findText()) {
        return isCurrent()
    }
    if (!isCurrent()) return false

    if (findId()) {
        return isCurrent()
    }
    if (!isCurrent()) return false

    applyFallback()
    return isCurrent()
}
