package app.bibliolife.reader.readium

/** Immutable native-only choice made before any EPUB rendition is attached. */
public enum class ReadiumEpubRenditionBackend {
    LEGACY,
    CONTINUOUS_EXPERIMENTAL,

    ;
}

/**
 * The single, immutable decision made after opening a Publication and before
 * any legacy Fragment work. C-2 supplies the actual continuous rendition.
 */
internal sealed class ReadiumEpubRenditionBootstrapAction {
    data object AttachLegacyNavigator : ReadiumEpubRenditionBootstrapAction()
    data object EnterContinuousPending : ReadiumEpubRenditionBootstrapAction()
}

internal fun ReadiumEpubRenditionBackend.bootstrapAction(): ReadiumEpubRenditionBootstrapAction = when (this) {
    ReadiumEpubRenditionBackend.LEGACY -> ReadiumEpubRenditionBootstrapAction.AttachLegacyNavigator
    ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL ->
        ReadiumEpubRenditionBootstrapAction.EnterContinuousPending
}
