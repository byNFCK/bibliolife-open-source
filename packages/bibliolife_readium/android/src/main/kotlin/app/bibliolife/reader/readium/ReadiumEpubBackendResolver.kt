package app.bibliolife.reader.readium

/**
 * The one native-only decision point for the rendition selected for an EPUB
 * session. It is evaluated before a [ReadiumReaderSession] is constructed and
 * intentionally has no connection to persisted reader settings or Flutter UI.
 */
internal class ReadiumEpubBackendResolver(
    private val rawInternalCutoverControl: () -> String? = {
        BuildConfig.BIBLIOLIFE_CONTINUOUS_SCROLL_CUTOVER
    },
) {
    fun resolve(request: ReadiumEpubBackendRequest): ReadiumEpubBackendResolution {
        if (request.requestedMode == ReadiumEpubRequestedMode.PAGINATED) {
            return ReadiumEpubBackendResolution(
                backend = ReadiumEpubRenditionBackend.LEGACY,
                requestedMode = request.requestedMode,
                source = ReadiumEpubBackendResolutionSource.PAGINATED_MODE,
            )
        }
        if (!request.publicationType.isContinuousEligible) {
            return ReadiumEpubBackendResolution(
                backend = ReadiumEpubRenditionBackend.LEGACY,
                requestedMode = request.requestedMode,
                source = ReadiumEpubBackendResolutionSource.INELIGIBLE_PUBLICATION,
            )
        }

        return when (internalCutoverState()) {
            ReadiumEpubInternalCutoverState.ENABLED -> ReadiumEpubBackendResolution(
                backend = ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL,
                requestedMode = request.requestedMode,
                source = ReadiumEpubBackendResolutionSource.INTERNAL_CUTOVER_ENABLED,
            )
            ReadiumEpubInternalCutoverState.DISABLED -> ReadiumEpubBackendResolution(
                backend = ReadiumEpubRenditionBackend.LEGACY,
                requestedMode = request.requestedMode,
                source = ReadiumEpubBackendResolutionSource.DEFAULT_LEGACY,
            )
            ReadiumEpubInternalCutoverState.MALFORMED -> ReadiumEpubBackendResolution(
                backend = ReadiumEpubRenditionBackend.LEGACY,
                requestedMode = request.requestedMode,
                source = ReadiumEpubBackendResolutionSource.INVALID_INTERNAL_CONTROL,
            )
        }
    }

    private fun internalCutoverState(): ReadiumEpubInternalCutoverState = when (
        runCatching { rawInternalCutoverControl() }.getOrNull()?.trim()?.lowercase()
    ) {
        "true" -> ReadiumEpubInternalCutoverState.ENABLED
        "false", null -> ReadiumEpubInternalCutoverState.DISABLED
        else -> ReadiumEpubInternalCutoverState.MALFORMED
    }
}

internal data class ReadiumEpubBackendRequest(
    val requestedMode: ReadiumEpubRequestedMode,
    val publicationType: ReadiumEpubPublicationType,
)

internal enum class ReadiumEpubRequestedMode { PAGINATED, SCROLL }

/**
 * FB2 and TXT are eligible only after the existing conversion path has
 * produced the same native EPUB route. PDF and comic containers never enter
 * this route, and remain explicitly ineligible as a defensive resolver rule.
 */
internal enum class ReadiumEpubPublicationType(val isContinuousEligible: Boolean) {
    EPUB(true),
    CONVERTED_FB2_EPUB(true),
    CONVERTED_TXT_EPUB(true),
    PDF(false),
    CBZ(false),
    CBR(false),
    UNKNOWN(false),
}

internal data class ReadiumEpubBackendResolution(
    val backend: ReadiumEpubRenditionBackend,
    val requestedMode: ReadiumEpubRequestedMode,
    val source: ReadiumEpubBackendResolutionSource,
) {
    /** Deliberately excludes book identity, locators, paths, and content. */
    fun diagnosticMessage(): String =
        "READIUM_RENDITION_BACKEND requestedMode=${requestedMode.logValue} " +
            "resolved=${backend.logValue} source=${source.logValue}"
}

internal enum class ReadiumEpubBackendResolutionSource(val logValue: String) {
    PAGINATED_MODE("paginated_mode"),
    DEFAULT_LEGACY("default"),
    INVALID_INTERNAL_CONTROL("invalid_internal_control"),
    INELIGIBLE_PUBLICATION("ineligible_publication"),
    INTERNAL_CUTOVER_ENABLED("internal_cutover"),
}

private enum class ReadiumEpubInternalCutoverState { ENABLED, DISABLED, MALFORMED }

private val ReadiumEpubRequestedMode.logValue: String
    get() = when (this) {
        ReadiumEpubRequestedMode.PAGINATED -> "paginated"
        ReadiumEpubRequestedMode.SCROLL -> "scroll"
    }

private val ReadiumEpubRenditionBackend.logValue: String
    get() = when (this) {
        ReadiumEpubRenditionBackend.LEGACY -> "legacy"
        ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL -> "continuous_experimental"
    }
