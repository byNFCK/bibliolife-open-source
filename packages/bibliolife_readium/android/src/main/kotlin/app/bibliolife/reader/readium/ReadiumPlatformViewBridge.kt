package app.bibliolife.reader.readium

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.publication.Locator
import java.nio.charset.StandardCharsets
import java.util.Base64
import java.util.concurrent.atomic.AtomicBoolean

/** Native bridge protocol is independent from the application version. */
internal object ReadiumPlatformViewBridgeProtocol {
    const val VERSION = 1
    const val NAMESPACE = "app.bibliolife.reader.readium"
    const val COMMAND_SUFFIX = "commands"
    const val EVENT_SUFFIX = "events"

    const val GET_BRIDGE_INFO = "getBridgeInfo"
    const val GET_SNAPSHOT = "getSnapshot"
    const val NEXT = "next"
    const val PREVIOUS = "previous"
    const val GO_TO_PROGRESSION = "goToProgression"
    const val OPEN_PROGRESS_SCRUB_SESSION = "openProgressScrubSession"
    const val INVALIDATE_PROGRESS_SCRUB_SESSION = "invalidateProgressScrubSession"
    const val RESERVE_PROGRESS_SCRUB_FINAL = "reserveProgressScrubFinal"
    const val GO_TO_LOCATOR = "goToLocator"
    const val APPLY_PREFERENCES = "applyPreferences"
    const val SUPERSEDE_SETTINGS_PREVIEWS = "supersedeSettingsPreviews"
    const val SETTINGS_REFLOW_GESTURE = "settingsReflowGesture"
    const val GO_TO_TOC_ENTRY = "goToTocEntry"
    const val SEARCH = "search"
    const val CANCEL_SEARCH = "cancelSearch"
    const val CLEAR_SEARCH = "clearSearch"
    const val GO_TO_SEARCH_RESULT = "goToSearchResult"
    const val SET_DECORATIONS = "setDecorations"
    const val UPSERT_DECORATION = "upsertDecoration"
    const val REMOVE_DECORATION = "removeDecoration"
    const val CLEAR_DECORATIONS = "clearDecorations"
    const val REQUEST_CURRENT_SELECTION = "requestCurrentSelection"
    const val CLEAR_SELECTION = "clearSelection"
    const val RESOLVE_SELECTION_ACTION = "resolveSelectionAction"
    const val RESOLVE_ANNOTATION_ACTION = "resolveAnnotationAction"

    const val SNAPSHOT = "snapshot"
    const val READER_LIFECYCLE_CHANGED = "readerLifecycleChanged"
    const val POSITION_CHANGED = "positionChanged"
    const val MANUAL_SCROLL_ACTIVITY_CHANGED = "manualScrollActivityChanged"
    const val CHAPTER_CHANGED = "chapterChanged"
    const val PREFERENCES_CHANGED = "preferencesChanged"
    const val READER_DIAGNOSTIC = "readerDiagnostic"
    const val TOC_CHANGED = "tocChanged"
    const val SEARCH_CHANGED = "searchChanged"
    const val SELECTION_CHANGED = "selectionChanged"
    const val DECORATION_STATE_CHANGED = "decorationStateChanged"
    const val CONTENT_TAP = "contentTap"
    const val SELECTION_ACTION_REQUESTED = "selectionActionRequested"
    const val DECORATION_ACTIVATED = "decorationActivated"
    const val ANNOTATION_ACTION_REQUESTED = "annotationActionRequested"
    const val READER_ERROR = "readerError"
    const val DISPOSED = "disposed"
}

internal data class ReadiumPlatformViewBridgeChannelNames(
    val command: String,
    val events: String,
    val encodedInstanceId: String,
) {
    companion object {
        private const val MAX_INSTANCE_ID_LENGTH = 512

        fun require(instanceId: String): ReadiumPlatformViewBridgeChannelNames {
            val logical = instanceId.trim()
            require(logical.isNotEmpty()) { "invalid_instance_id" }
            require(logical.length <= MAX_INSTANCE_ID_LENGTH) { "instance_id_too_long" }
            // URL-safe base64 gives deterministic bounded channel components without exposing
            // paths, titles, slash characters or control characters in channel names.
            val encoded = Base64.getUrlEncoder().withoutPadding()
                .encodeToString(logical.toByteArray(StandardCharsets.UTF_8))
            return ReadiumPlatformViewBridgeChannelNames(
                command = "${ReadiumPlatformViewBridgeProtocol.NAMESPACE}/reader/$encoded/${ReadiumPlatformViewBridgeProtocol.COMMAND_SUFFIX}",
                events = "${ReadiumPlatformViewBridgeProtocol.NAMESPACE}/reader/$encoded/${ReadiumPlatformViewBridgeProtocol.EVENT_SUFFIX}",
                encodedInstanceId = encoded,
            )
        }
    }
}

internal interface ReadiumBridgeCommandResult {
    fun success(value: Any?)
}

internal interface ReadiumBridgeEventSink {
    fun success(event: Map<String, Any?>)
    fun error(code: String, message: String? = null, details: Any? = null) = Unit
}

internal fun interface ReadiumBridgeCommandHandler {
    fun onCommand(method: String, arguments: Any?, result: ReadiumBridgeCommandResult)
}

internal interface ReadiumBridgeStreamHandler {
    fun onListen(arguments: Any?, sink: ReadiumBridgeEventSink)
    fun onCancel(arguments: Any?)
}

/** Small transport seam. The bridge core is usable without a Flutter transport in JVM tests. */
internal interface ReadiumBridgeTransport {
    val channelNames: ReadiumPlatformViewBridgeChannelNames
    fun attach(commandHandler: ReadiumBridgeCommandHandler, streamHandler: ReadiumBridgeStreamHandler): Boolean
    fun dispose()
}

/** Production Flutter transport; it owns only per-view channels and no Activity or session. */
internal class ReadiumFlutterBridgeTransport(
    override val channelNames: ReadiumPlatformViewBridgeChannelNames,
    messenger: BinaryMessenger,
) : ReadiumBridgeTransport {
    private val commandChannel = MethodChannel(messenger, channelNames.command)
    private val eventChannel = EventChannel(messenger, channelNames.events)
    private var commandHandler: ReadiumBridgeCommandHandler? = null
    private var streamHandler: ReadiumBridgeStreamHandler? = null
    private var disposed = false
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun attach(
        commandHandler: ReadiumBridgeCommandHandler,
        streamHandler: ReadiumBridgeStreamHandler,
    ): Boolean {
        if (disposed) return false
        if (this.commandHandler != null || this.streamHandler != null) {
            return this.commandHandler === commandHandler && this.streamHandler === streamHandler
        }
        this.commandHandler = commandHandler
        this.streamHandler = streamHandler
        this.commandChannel.setMethodCallHandler { call, result ->
            this.commandHandler?.onCommand(call.method, call.arguments, FlutterBridgeCommandResult(result))
        }
        this.eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                this@ReadiumFlutterBridgeTransport.streamHandler?.onListen(
                    arguments,
                    object : ReadiumBridgeEventSink {
                        override fun success(event: Map<String, Any?>) {
                            // EventSink callbacks are required on Flutter's main thread.
                            if (Looper.myLooper() == Looper.getMainLooper()) events.success(event)
                            else mainHandler.post { events.success(event) }
                        }

                        override fun error(code: String, message: String?, details: Any?) {
                            if (Looper.myLooper() == Looper.getMainLooper()) events.error(code, message, details)
                            else mainHandler.post { events.error(code, message, details) }
                        }
                    },
                )
            }

            override fun onCancel(arguments: Any?) {
                this@ReadiumFlutterBridgeTransport.streamHandler?.onCancel(arguments)
            }
        })
        return true
    }

    override fun dispose() {
        if (disposed) return
        disposed = true
        commandChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        commandHandler = null
        streamHandler = null
    }

    private class FlutterBridgeCommandResult(
        private val result: MethodChannel.Result,
    ) : ReadiumBridgeCommandResult {
        private val completed = AtomicBoolean(false)

        override fun success(value: Any?) {
            if (completed.compareAndSet(false, true)) result.success(value)
        }
    }
}

/** Engine-scoped factory; detachment makes future view creation fail deterministically. */
internal class ReadiumFlutterBridgeTransportFactory(
    private val messenger: BinaryMessenger,
) {
    private var active = true

    fun create(channelNames: ReadiumPlatformViewBridgeChannelNames): ReadiumBridgeTransport {
        if (!active) throw ReadiumPlatformViewCreationException("transport_unavailable")
        return ReadiumFlutterBridgeTransport(channelNames, messenger)
    }

    fun detach() {
        active = false
    }
}

/** Explicit event fan-out boundary: one typed session observer, two consumers. */
internal class ReadiumPlatformViewEventHub(
    private val listenerCoordinator: ReadiumPlatformViewHostListenerCoordinator,
) {
    fun bindFlutterListener(listener: ReadiumPlatformViewHostListener): ReadiumPlatformViewHostListenerToken? =
        listenerCoordinator.bindBridgeListener(listener)

    fun unbindFlutterListener(token: ReadiumPlatformViewHostListenerToken): Boolean =
        listenerCoordinator.unbindBridgeListener(token)

    fun emitInteraction(interaction: ReadiumReaderInteraction) {
        listenerCoordinator.emitInteraction(interaction)
    }
}

private class BridgeArgumentException(
    val code: String,
) : IllegalArgumentException(code)

private fun bridgeMap(value: Any?): Map<*, *> = value as? Map<*, *>
    ?: throw BridgeArgumentException("malformed_command")

private fun bridgeString(map: Map<*, *>, key: String, required: Boolean = true): String? {
    val value = map[key]
    if (value == null && !required) return null
    val string = value as? String ?: throw BridgeArgumentException("invalid_argument_type")
    if (required && string.trim().isEmpty()) throw BridgeArgumentException("missing_argument")
    return string
}

private fun bridgeBoolean(map: Map<*, *>, key: String, default: Boolean): Boolean = when (val value = map[key]) {
    null -> default
    is Boolean -> value
    else -> throw BridgeArgumentException("invalid_argument_type")
}

private fun bridgeDouble(map: Map<*, *>, key: String): Double {
    val value = (map[key] as? Number)?.toDouble()
        ?: throw BridgeArgumentException("missing_argument")
    if (!value.isFinite()) throw BridgeArgumentException("invalid_argument")
    return value
}

internal object ReadiumBridgeLocatorMapper {
    fun parse(json: String): Result<Locator> = runCatching {
        if (json.trim().isEmpty()) error("invalid_locator")
        Locator.fromJSON(JSONObject(json)) ?: error("invalid_locator")
    }

    /** JSON output is kept here so channel serialization has one locator implementation. */
    fun serialize(locator: Locator?): String? = locator?.let {
        buildString {
            append('{')
            append("\"href\":").append(quote(it.href.toString()))
            append(",\"type\":").append(quote(it.mediaType.toString()))
            it.title?.let { title -> append(",\"title\":").append(quote(title)) }
            val locations = buildString {
                var first = true
                fun field(name: String, value: String) {
                    if (!first) append(',') else first = false
                    append(quote(name)).append(':').append(value)
                }
                if (it.locations.fragments.isNotEmpty()) field("fragments", it.locations.fragments.joinToString(prefix = "[", postfix = "]") { fragment -> quote(fragment) })
                it.locations.progression?.takeIf(Double::isFinite)?.let { value -> field("progression", value.toString()) }
                it.locations.position?.let { value -> field("position", value.toString()) }
                it.locations.totalProgression?.takeIf(Double::isFinite)?.let { value -> field("totalProgression", value.toString()) }
                it.locations.otherLocations.forEach { (key, value) ->
                    if (key !in setOf("fragments", "fragment", "progression", "position", "totalProgression")) {
                        field(key, jsonValue(value))
                    }
                }
            }
            if (locations.isNotEmpty()) append(",\"locations\":{").append(locations).append('}')
            val text = buildList {
                it.text.before?.let { value -> add("\"before\":" + quote(value)) }
                it.text.highlight?.let { value -> add("\"highlight\":" + quote(value)) }
                it.text.after?.let { value -> add("\"after\":" + quote(value)) }
            }
            if (text.isNotEmpty()) append(",\"text\":{").append(text.joinToString(",")).append('}')
            append('}')
        }
    }

    private fun quote(value: String): String = buildString {
        append('"')
        value.forEach { character ->
            when (character) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\b' -> append("\\b")
                '\u000C' -> append("\\f")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> if (character.code < 0x20) append("\\u%04x".format(character.code)) else append(character)
            }
        }
        append('"')
    }

    private fun jsonValue(value: Any?): String = when (value) {
        null -> "null"
        is String -> quote(value)
        is Boolean -> value.toString()
        is Number -> value.toDouble().takeIf(Double::isFinite)?.toString() ?: "null"
        is List<*> -> value.joinToString(prefix = "[", postfix = "]") { jsonValue(it) }
        is Map<*, *> -> value.entries.filter { it.key is String }.joinToString(prefix = "{", postfix = "}") {
            quote(it.key as String) + ":" + jsonValue(it.value)
        }
        else -> "null"
    }
}

internal object ReadiumBridgePreferencesMapper {
    private val supportedThemes = setOf("system", "light", "dark", "sepia")

    fun parse(value: Any?): Result<ReaderPreferencesPayload> = runCatching {
        val map = bridgeMap(value)
        val theme = bridgeString(map, "theme")!!.trim().lowercase()
        if (theme !in supportedThemes) throw BridgeArgumentException("invalid_preference_value")
        val fontFamily = bridgeString(map, "fontFamily")!!
        if (fontFamily !in setOf("original", "serif", "sansSerif", "dyslexic", "monospace")) {
            throw BridgeArgumentException("invalid_preference_value")
        }
        val fontSize = boundedNumber(map, "fontSize", .5, 3.0)
        val fontWeight = boundedNumber(map, "fontWeight", 0.0, 2.5)
        val lineHeight = boundedNumber(map, "lineHeight", 1.0, 2.5)
        val pageMargins = boundedNumber(map, "pageMargins", 0.0, 4.0)
        val textAlignment = bridgeString(map, "textAlignment")!!
        if (textAlignment !in setOf("start", "justify")) throw BridgeArgumentException("invalid_preference_value")
        val scroll = map["scroll"] as? Boolean ?: throw BridgeArgumentException("missing_argument")
        val columns = bridgeString(map, "columns")!!
        if (columns !in setOf("auto", "one", "two")) throw BridgeArgumentException("invalid_preference_value")
        val publisherStyles = map["publisherStyles"] as? Boolean
            ?: throw BridgeArgumentException("missing_argument")
        ReaderPreferencesPayload(
            theme = theme,
            fontFamily = fontFamily,
            fontSize = fontSize,
            fontWeight = fontWeight,
            lineHeight = lineHeight,
            pageMargins = pageMargins,
            textAlignment = textAlignment,
            scroll = scroll,
            columns = columns,
            publisherStyles = publisherStyles,
        )
    }

    fun serialize(preferences: EpubPreferences?): Map<String, Any?>? = preferences?.let {
        mapOf(
            "theme" to it.theme?.name?.lowercase(),
            "fontFamily" to when (it.fontFamily?.name) {
                "serif" -> "serif"
                "sans-serif" -> "sansSerif"
                "OpenDyslexic" -> "dyslexic"
                "monospace" -> "monospace"
                else -> "original"
            },
            "fontSize" to finite(it.fontSize),
            "fontWeight" to finite(it.fontWeight),
            "lineHeight" to finite(it.lineHeight),
            "pageMargins" to finite(it.pageMargins),
            "textAlignment" to when (it.textAlign) {
                org.readium.r2.navigator.preferences.TextAlign.JUSTIFY -> "justify"
                else -> "start"
            },
            "scroll" to (it.scroll ?: false),
            "columns" to when (it.columnCount) {
                org.readium.r2.navigator.preferences.ColumnCount.ONE -> "one"
                org.readium.r2.navigator.preferences.ColumnCount.TWO -> "two"
                else -> "auto"
            },
            "publisherStyles" to it.publisherStyles,
        )
    }

    private fun boundedNumber(map: Map<*, *>, key: String, low: Double, high: Double): Double {
        val value = (map[key] as? Number)?.toDouble()
            ?: throw BridgeArgumentException("missing_argument")
        if (!value.isFinite() || value !in low..high) throw BridgeArgumentException("invalid_preference_value")
        return value
    }

    private fun finite(value: Double?): Double? = value?.takeIf(Double::isFinite)
}

internal object ReadiumBridgeDecorationMapper {
    fun parseGroup(value: Any?): Result<ReadiumDecorationGroup> = runCatching {
        val raw = value as? String ?: throw BridgeArgumentException("invalid_decoration_group")
        ReadiumDecorationGroup.entries.firstOrNull { it.name == raw || it.nativeName == raw }
            ?: throw BridgeArgumentException("invalid_decoration_group")
    }

    fun parseList(
        value: Any?,
        locatorParser: (String) -> Result<Locator> = ReadiumBridgeLocatorMapper::parse,
    ): Result<List<ReadiumDecorationSpec>> = runCatching {
        val list = value as? List<*> ?: throw BridgeArgumentException("invalid_argument_type")
        list.map { item ->
            val map = bridgeMap(item)
            val id = bridgeString(map, "id")!!.trim()
            val locatorJson = bridgeString(map, "locatorJson")!!
            val locator = locatorParser(locatorJson).getOrElse {
                throw BridgeArgumentException("invalid_locator")
            }
            val styleMap = bridgeMap(map["style"])
            val styleName = bridgeString(styleMap, "type")!!.lowercase()
            val tint = (styleMap["tint"] as? Number)?.toLong()
                ?.takeIf { it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() }
                ?.toInt()
                ?: throw BridgeArgumentException("invalid_decoration_style")
            val active = bridgeBoolean(styleMap, "active", false)
            val style = when (styleName) {
                "highlight" -> ReadiumDecorationStyle.Highlight(tint, active)
                "underline" -> ReadiumDecorationStyle.Underline(tint, active)
                else -> throw BridgeArgumentException("invalid_decoration_style")
            }
            if (id.isBlank()) throw BridgeArgumentException("missing_argument")
            ReadiumDecorationSpec(id, locator, style)
        }
    }

    fun serialize(group: ReadiumDecorationGroup, state: ReadiumReaderDecorationState): Map<String, Any?> =
        mapOf(
            "group" to group.name,
            "requestedCount" to state.requestedCount,
            "appliedCount" to state.appliedCount,
            "generation" to state.generation,
            "isApplying" to state.isApplying,
            "isReady" to state.isReady,
            "selectionProtected" to state.selectionProtected,
            "hasApplied" to state.hasApplied,
        )
}

internal object ReadiumPlatformViewBridgeSerializer {
    fun info(configuration: ReadiumPlatformViewOpenConfiguration): Map<String, Any?> = mapOf(
        "protocolVersion" to configuration.bridgeProtocolVersion,
        "instanceId" to configuration.instanceId,
        "features" to listOf("commands", "events", "snapshot", "selection", "decorations", "contentTap", "selectionActions", "decorationActivation"),
    )

    fun stateEvent(
        protocolVersion: Int,
        instanceId: String,
        sequence: Long,
        state: ReadiumPlatformViewReaderState,
    ): Map<String, Any?>? {
        val mapped = when (state) {
            ReadiumPlatformViewReaderState.InitializationStarted ->
                ReadiumPlatformViewBridgeProtocol.READER_LIFECYCLE_CHANGED to mapOf("phase" to "initializing")
            is ReadiumPlatformViewReaderState.PublicationOpened ->
                ReadiumPlatformViewBridgeProtocol.READER_LIFECYCLE_CHANGED to mapOf("phase" to "publicationOpened", "publication" to publication(state.info))
            is ReadiumPlatformViewReaderState.NavigatorAttached ->
                ReadiumPlatformViewBridgeProtocol.READER_LIFECYCLE_CHANGED to mapOf("phase" to "navigatorAttached", "reusedRestoredFragment" to state.reusedRestoredFragment)
            ReadiumPlatformViewReaderState.NavigatorReady ->
                ReadiumPlatformViewBridgeProtocol.READER_LIFECYCLE_CHANGED to mapOf("phase" to "navigatorReady")
            is ReadiumPlatformViewReaderState.InitialLocatorRestored ->
                ReadiumPlatformViewBridgeProtocol.READER_LIFECYCLE_CHANGED to mapOf("phase" to "initialLocatorRestored", "navigated" to state.navigated)
            is ReadiumPlatformViewReaderState.PositionChanged -> ReadiumPlatformViewBridgeProtocol.POSITION_CHANGED to
                (position(state.position)?.plus("liveManual" to state.liveManual)?.plus(
                    "progressOwner" to state.progressOwner?.let(::progressOwner),
                ))
            is ReadiumPlatformViewReaderState.ManualScrollActivityChanged ->
                ReadiumPlatformViewBridgeProtocol.MANUAL_SCROLL_ACTIVITY_CHANGED to mapOf("active" to state.active)
            is ReadiumPlatformViewReaderState.NavigationStarted -> ReadiumPlatformViewBridgeProtocol.READER_LIFECYCLE_CHANGED to mapOf(
                "phase" to "navigationStarted",
                "command" to state.command.name.lowercase(),
                "generation" to state.generation,
                "progressOwner" to state.progressOwner?.let(::progressOwner),
            )
            is ReadiumPlatformViewReaderState.NavigationCompleted -> ReadiumPlatformViewBridgeProtocol.READER_LIFECYCLE_CHANGED to mapOf("phase" to "navigationCompleted", "command" to state.command.name.lowercase(), "generation" to state.generation)
            is ReadiumPlatformViewReaderState.NavigationFailed -> ReadiumPlatformViewBridgeProtocol.READER_LIFECYCLE_CHANGED to mapOf("phase" to "navigationFailed", "command" to state.command.name.lowercase(), "error" to error(state.error, false))
            is ReadiumPlatformViewReaderState.PreferencesRequested -> ReadiumPlatformViewBridgeProtocol.PREFERENCES_CHANGED to preferences(state.preferences)
            is ReadiumPlatformViewReaderState.PreferencesApplied -> ReadiumPlatformViewBridgeProtocol.PREFERENCES_CHANGED to preferences(state.preferences) + ("initial" to state.initial)
            is ReadiumPlatformViewReaderState.PreferencesFailed -> ReadiumPlatformViewBridgeProtocol.PREFERENCES_CHANGED to preferences(state.preferences) + ("error" to error(state.error, false))
            is ReadiumPlatformViewReaderState.Diagnostic -> ReadiumPlatformViewBridgeProtocol.READER_DIAGNOSTIC to state.fields
            is ReadiumPlatformViewReaderState.TocStateChanged -> ReadiumPlatformViewBridgeProtocol.TOC_CHANGED to toc(state.toc)
            is ReadiumPlatformViewReaderState.CurrentChapterChanged -> ReadiumPlatformViewBridgeProtocol.CHAPTER_CHANGED to chapter(state.chapter)
            is ReadiumPlatformViewReaderState.SearchStateChanged -> ReadiumPlatformViewBridgeProtocol.SEARCH_CHANGED to search(state.search)
            is ReadiumPlatformViewReaderState.SelectionChanged -> ReadiumPlatformViewBridgeProtocol.SELECTION_CHANGED to selection(state.selection)
            is ReadiumPlatformViewReaderState.DecorationsChanged -> ReadiumPlatformViewBridgeProtocol.DECORATION_STATE_CHANGED to ReadiumBridgeDecorationMapper.serialize(state.group, state.decorations)
            ReadiumPlatformViewReaderState.Disposed -> ReadiumPlatformViewBridgeProtocol.DISPOSED to mapOf("phase" to "disposed")
        }
        return event(protocolVersion, instanceId, sequence, mapped.first, mapped.second)
    }

    fun errorEvent(
        protocolVersion: Int,
        instanceId: String,
        sequence: Long,
        errorValue: ReadiumPlatformViewError,
        fatal: Boolean,
    ): Map<String, Any?> = event(
        protocolVersion,
        instanceId,
        sequence,
        ReadiumPlatformViewBridgeProtocol.READER_ERROR,
        error(errorValue, fatal),
    )

    fun errorMap(errorValue: ReadiumPlatformViewError, fatal: Boolean): Map<String, Any?> =
        error(errorValue, fatal)

    fun interactionEvent(
        protocolVersion: Int,
        instanceId: String,
        sequence: Long,
        interaction: ReadiumReaderInteraction,
    ): Map<String, Any?>? = when (interaction) {
        is ReadiumReaderInteraction.ContentTap -> event(
            protocolVersion,
            instanceId,
            sequence,
            ReadiumPlatformViewBridgeProtocol.CONTENT_TAP,
            mapOf(
                "interactionId" to interaction.interactionId,
                "viewportGeneration" to interaction.viewportGeneration,
                "region" to interaction.region?.name?.lowercase(),
            ),
        )
        is ReadiumReaderInteraction.SelectionActionRequested -> event(
            protocolVersion,
            instanceId,
            sequence,
            ReadiumPlatformViewBridgeProtocol.SELECTION_ACTION_REQUESTED,
            mapOf(
                "requestId" to interaction.request.requestId,
                "instanceId" to interaction.request.instanceId,
                "selectionSessionId" to interaction.request.selectionSessionId,
                "action" to interaction.request.action.wireValue,
                "locatorJson" to interaction.request.locatorJson,
                "selectedText" to interaction.request.selectedText,
                "style" to interaction.request.style,
                "color" to interaction.request.color,
            ),
        )
        is ReadiumReaderInteraction.DecorationActivated -> event(
            protocolVersion,
            instanceId,
            sequence,
            ReadiumPlatformViewBridgeProtocol.DECORATION_ACTIVATED,
            mapOf(
                "interactionId" to interaction.activation.interactionId,
                "instanceId" to interaction.activation.instanceId,
                "group" to interaction.activation.group,
                "decorationId" to interaction.activation.decorationId,
            ),
        )
        is ReadiumReaderInteraction.AnnotationActionRequested -> event(
            protocolVersion,
            instanceId,
            sequence,
            ReadiumPlatformViewBridgeProtocol.ANNOTATION_ACTION_REQUESTED,
            mapOf(
                "requestId" to interaction.request.requestId,
                "instanceId" to interaction.request.instanceId,
                "annotationId" to interaction.request.annotationId,
                "action" to interaction.request.action.wireValue,
                "color" to interaction.request.color,
            ),
        )
    }

    fun snapshot(
        protocolVersion: Int,
        instanceId: String,
        sequence: Long,
        latestState: ReadiumPlatformViewReaderState?,
        publication: ReadiumPlatformViewPublicationInfo?,
        latestError: Map<String, Any?>?,
        controller: ReadiumPlatformViewController,
        configuration: ReadiumPlatformViewOpenConfiguration,
    ): Map<String, Any?> = event(
        protocolVersion,
        instanceId,
        sequence,
        ReadiumPlatformViewBridgeProtocol.SNAPSHOT,
        mapOf(
            "bridge" to info(configuration),
            "lifecycle" to lifecycle(latestState, publication),
            "position" to position(controller.position()),
            "chapter" to chapter(controller.currentChapter()),
            "preferences" to preferences(controller.preferences()),
            "toc" to toc(controller.tocState()),
            "search" to search(controller.searchState()),
            "selection" to selection(controller.selectionState()),
            "decorations" to ReadiumDecorationGroup.entries.associate { group ->
                group.name to ReadiumBridgeDecorationMapper.serialize(group, controller.decorationState(group))
            },
            "error" to latestError,
        ),
    )

    internal fun event(protocolVersion: Int, instanceId: String, sequence: Long, type: String, payload: Any?): Map<String, Any?> = mapOf(
        "protocolVersion" to protocolVersion,
        "instanceId" to instanceId,
        "sequence" to sequence,
        "type" to type,
        "payload" to payload,
    )

    private fun publication(info: ReadiumPlatformViewPublicationInfo) = mapOf("bookId" to info.bookId, "title" to info.title)

    private fun lifecycle(state: ReadiumPlatformViewReaderState?, publication: ReadiumPlatformViewPublicationInfo?): Map<String, Any?> = when (state) {
        ReadiumPlatformViewReaderState.InitializationStarted -> mapOf("phase" to "initializing")
        is ReadiumPlatformViewReaderState.PublicationOpened -> mapOf("phase" to "publicationOpened", "publication" to publication(state.info))
        ReadiumPlatformViewReaderState.NavigatorReady -> mapOf("phase" to "navigatorReady")
        ReadiumPlatformViewReaderState.Disposed -> mapOf("phase" to "disposed")
        null -> mapOf("phase" to "created")
        else -> mapOf(
            "phase" to "ready",
            "publication" to publication?.let(::publication),
        )
    }

    private fun position(value: ReadiumPositionState?): Map<String, Any?>? = value?.let {
        mapOf(
            "locatorJson" to ReadiumBridgeLocatorMapper.serialize(it.locator),
            "href" to it.locator.href.toString(),
            "progression" to finite(it.progression),
            "resourceProgression" to finite(it.locator.locations.progression),
            "readingOrderIndex" to it.readingOrderIndex,
            "totalProgression" to finite(it.locator.locations.totalProgression),
            "position" to it.locator.locations.position,
            "totalLogicalPositions" to it.totalLogicalPositions,
            "fragments" to it.locator.locations.fragments,
            "presentation" to presentation(it.presentation),
        )
    }

    private fun progressOwner(owner: ProgressNavigationOwner): Map<String, Any?> = mapOf(
        "sessionId" to owner.sessionId,
        "requestId" to owner.requestId,
        "phase" to when (owner.phase) {
            ProgressNavigationOwner.Phase.PREVIEW -> "preview"
            ProgressNavigationOwner.Phase.FINAL -> "final"
        },
    )

    private fun presentation(value: ReadiumPresentationState): Map<String, Any?> = when (value) {
        ReadiumPresentationState.Unknown -> mapOf("mode" to "unknown")
        ReadiumPresentationState.Scrolling -> mapOf("mode" to "scrolling")
        is ReadiumPresentationState.Paginated -> mapOf(
            "mode" to "paginated",
            "pageIndex" to value.page.index,
            "pageCount" to value.page.count,
            "progression" to value.page.progression,
            "layoutGeneration" to value.page.layoutGeneration,
            "publicationScoped" to value.page.publicationScoped,
        )
    }

    private fun chapter(value: ReadiumChapterState): Map<String, Any?> = mapOf(
        "entryId" to value.entryId,
        "title" to value.title,
        "href" to value.href,
    )

    private fun preferences(value: ReadiumPlatformViewPreferenceState): Map<String, Any?> = mapOf(
        "requested" to ReadiumBridgePreferencesMapper.serialize(value.requested),
        "applied" to ReadiumBridgePreferencesMapper.serialize(value.applied),
        "generation" to value.generation,
        "isApplying" to value.isApplying,
    )

    private fun toc(value: ReadiumTocState): Map<String, Any?> = when (value) {
        ReadiumTocState.NotLoaded -> mapOf("status" to "notLoaded", "entries" to emptyList<Any>())
        ReadiumTocState.Loading -> mapOf("status" to "loading", "entries" to emptyList<Any>())
        ReadiumTocState.Empty -> mapOf("status" to "empty", "entries" to emptyList<Any>())
        is ReadiumTocState.Ready -> mapOf("status" to "ready", "entries" to value.entries.map(::tocEntry))
        is ReadiumTocState.Failed -> mapOf("status" to "failed", "errorCode" to value.error.code, "entries" to emptyList<Any>())
    }

    private fun tocEntry(value: ReadiumTocEntry): Map<String, Any?> = mapOf(
        "id" to value.id,
        "title" to value.title,
        "href" to value.href,
        "fragment" to value.fragment,
        "level" to value.level,
        "children" to value.children.map(::tocEntry),
    )

    private fun search(value: EpubSearchState): Map<String, Any?> = when (value) {
        EpubSearchState.Idle -> mapOf("status" to "idle", "query" to null, "generation" to null, "results" to emptyList<Any>())
        is EpubSearchState.Loading -> mapOf("status" to "loading", "query" to value.query, "generation" to value.token, "results" to emptyList<Any>())
        is EpubSearchState.Empty -> mapOf("status" to "empty", "query" to value.query, "generation" to value.token, "results" to emptyList<Any>())
        is EpubSearchState.Error -> mapOf("status" to "failed", "query" to value.query, "generation" to value.token, "errorCode" to value.error.name.lowercase(), "results" to emptyList<Any>())
        is EpubSearchState.Results -> mapOf("status" to "ready", "query" to value.query, "generation" to value.token, "loadingMore" to value.loadingMore, "hasMore" to value.hasMore, "results" to value.results.map(::searchResult))
    }

    private fun searchResult(value: EpubSearchResult): Map<String, Any?> = mapOf(
        "id" to value.id,
        "href" to value.href,
        "title" to value.title,
        "before" to value.before,
        "highlight" to value.highlight,
        "after" to value.after,
        "position" to value.position,
        "progression" to finite(value.progression),
    )

    private fun selection(value: ReadiumSelectionState): Map<String, Any?> = mapOf(
        "status" to value.status.name.lowercase(),
        "sessionId" to value.sessionId,
        "nativeSessionId" to value.nativeSessionId,
        "generation" to value.generation,
        "viewportEpoch" to value.viewportEpoch,
        "retrievalInFlight" to value.retrievalInFlight,
        "selection" to value.selection?.let {
            mapOf(
                "locatorJson" to ReadiumBridgeLocatorMapper.serialize(it.locator),
                "selectedText" to it.selectedText,
                "textBefore" to it.textBefore,
                "textAfter" to it.textAfter,
                "href" to it.href,
                "progression" to finite(it.progression),
                "totalProgression" to finite(it.totalProgression),
                "rect" to it.rect?.let { rect -> mapOf("left" to rect.left.toDouble(), "top" to rect.top.toDouble(), "right" to rect.right.toDouble(), "bottom" to rect.bottom.toDouble()) },
            )
        },
        "errorCode" to value.error?.let { "selection_failed" },
    )

    private fun error(value: ReadiumPlatformViewError, fatal: Boolean): Map<String, Any?> = mapOf(
        "code" to safeCode(value.code),
        "messageKey" to safeCode(value.code),
        "fatal" to fatal,
        "retryable" to !fatal,
        "operation" to "reader",
    ) + (value.openFailure?.takeIf { fatal }?.let { mapOf("details" to it) } ?: emptyMap())

    private fun finite(value: Double?): Double? = value?.takeIf(Double::isFinite)
    private fun safeCode(value: String): String {
        if (value.length > 96 || value.any { it == '/' || it == '\\' || it == ':' || it.isWhitespace() }) return "reader_error"
        return value.filter { it.isLetterOrDigit() || it == '_' || it == '-' }.ifBlank { "reader_error" }
    }
}

private class OnceBridgeResult(
    private val delegate: ReadiumBridgeCommandResult,
    private val onCompleted: (OnceBridgeResult) -> Unit = {},
) : ReadiumBridgeCommandResult {
    private val completed = AtomicBoolean(false)
    override fun success(value: Any?) {
        if (completed.compareAndSet(false, true)) {
            onCompleted(this)
            delegate.success(value)
        }
    }
    fun isCompleted(): Boolean = completed.get()
}

/** The command/event bridge core; all commands delegate to the existing controller only. */
internal class ReadiumPlatformViewBridgeCore(
    private val configuration: ReadiumPlatformViewOpenConfiguration,
    private val controller: ReadiumPlatformViewController,
    private val eventHub: ReadiumPlatformViewEventHub,
    private val scope: CoroutineScope,
    private val transport: ReadiumBridgeTransport? = null,
    private val resolveSelectionAction: (ReadiumSelectionActionResolution) -> String = { "unsupported" },
    private val resolveAnnotationAction: (ReadiumAnnotationActionResolution) -> String = { "unsupported" },
    private val parseDispatcher: CoroutineDispatcher = Dispatchers.Default,
    private val mainDispatcher: CoroutineDispatcher = Dispatchers.Main.immediate,
    private val locatorParser: (String) -> Result<Locator> = ReadiumBridgeLocatorMapper::parse,
) : ReadiumBridgeCommandHandler, ReadiumBridgeStreamHandler {
    private val channelNames = ReadiumPlatformViewBridgeChannelNames.require(configuration.instanceId)
    private val pendingResults = mutableSetOf<OnceBridgeResult>()
    private var bridgeListenerToken: ReadiumPlatformViewHostListenerToken? = null
    private var sink: ReadiumBridgeEventSink? = null
    private var listenerGeneration = 0L
    private var activeListenerGeneration = 0L
    private var disposed = false
    private var finalStateSeen = false
    private var sequence = 0L
    private var latestState: ReadiumPlatformViewReaderState? = null
    private var latestPublication: ReadiumPlatformViewPublicationInfo? = null
    private var latestError: Map<String, Any?>? = null
    private var lastPositionPayload: Map<String, Any?>? = null
    private val pendingOpenDiagnostics = ArrayDeque<ReadiumPlatformViewReaderState.Diagnostic>()

    private val listener = object : ReadiumPlatformViewHostListener {
        override fun onStateChanged(state: ReadiumPlatformViewReaderState) {
            if (state !is ReadiumPlatformViewReaderState.Diagnostic) latestState = state
            if (state is ReadiumPlatformViewReaderState.Disposed) finalStateSeen = true
            if (sink == null && state is ReadiumPlatformViewReaderState.Diagnostic &&
                state.fields["category"] == ReadiumOpenDiagnostics.CATEGORY
            ) {
                if (pendingOpenDiagnostics.size == 24) pendingOpenDiagnostics.removeFirst()
                pendingOpenDiagnostics.addLast(state)
                return
            }
            emitState(state)
        }

        override fun onInteraction(interaction: ReadiumReaderInteraction) {
            emitInteraction(interaction)
        }

        override fun onNavigatorReady(info: ReadiumPlatformViewPublicationInfo, host: ReadiumPlatformViewNavigatorHost) {
            latestPublication = info
        }

        override fun onFatalError(error: ReadiumPlatformViewError) {
            latestError = ReadiumPlatformViewBridgeSerializer.errorMap(error, true)
            emitError(error, true)
        }

        override fun onRecoverableError(error: ReadiumPlatformViewError) {
            latestError = ReadiumPlatformViewBridgeSerializer.errorMap(error, false)
            emitError(error, false)
        }
    }

    init {
        configuration.validate()?.let { throw it }
        bridgeListenerToken = eventHub.bindFlutterListener(listener)
            ?: throw ReadiumPlatformViewCreationException("bridge_listener_unavailable")
        transport?.let { attached ->
            require(attached.channelNames == channelNames) { "invalid_channel_identity" }
            if (!attached.attach(this, this)) throw ReadiumPlatformViewCreationException("transport_unavailable")
        }
    }

    override fun onCommand(method: String, arguments: Any?, result: ReadiumBridgeCommandResult) {
        val once = OnceBridgeResult(result) { completed ->
            synchronized(pendingResults) { pendingResults.remove(completed) }
        }
        if (disposed || finalStateSeen) {
            once.success(ReadiumBridgeResultEnvelope.failure("disposed"))
            return
        }
        val suppliedInstanceId = (arguments as? Map<*, *>)?.get("instanceId")
        if (suppliedInstanceId != null && suppliedInstanceId != configuration.instanceId) {
            once.success(ReadiumBridgeResultEnvelope.failure("stale_instance"))
            return
        }
        // Register before parsing/dispatch so disposal also completes a call whose
        // coroutine has not reached the main dispatcher yet.
        register(once)
        scope.launch(parseDispatcher) {
            val parsed = runCatching { parseCommand(method, arguments) }
            withContext(mainDispatcher) {
                if (disposed || finalStateSeen) {
                    once.success(ReadiumBridgeResultEnvelope.failure("disposed"))
                    return@withContext
                }
                parsed.fold(
                    onSuccess = { dispatch(it, once) },
                    onFailure = { error -> once.success(ReadiumBridgeResultEnvelope.failure((error as? BridgeArgumentException)?.code ?: "malformed_command")) },
                )
            }
        }
    }

    override fun onListen(arguments: Any?, sink: ReadiumBridgeEventSink) {
        if (disposed || finalStateSeen) {
            sink.error("disposed", "reader_disposed", null)
            return
        }
        // A second sink deterministically replaces the first. Only bounded
        // opening diagnostics are retained before an event sink attaches.
        this.sink?.error("listener_replaced", "reader_listener_replaced", null)
        this.sink = sink
        val suppliedGeneration = (arguments as? Map<*, *>)?.get("listenerGeneration") as? Number
        activeListenerGeneration = suppliedGeneration?.toLong() ?: ++listenerGeneration
        android.util.Log.d("BiblioLifeReadium", "BRIDGE_LISTEN generation=$activeListenerGeneration")
        while (pendingOpenDiagnostics.isNotEmpty()) emitState(pendingOpenDiagnostics.removeFirst())
        emitSnapshot()
    }

    override fun onCancel(arguments: Any?) {
        val suppliedGeneration = (arguments as? Map<*, *>)?.get("listenerGeneration") as? Number
        // Flutter's EventChannel sends null for cancellation arguments. That
        // cancellation can arrive late from a replaced native stream, after a
        // new listener has already supplied its generation. It must not tear
        // down the current route's only event sink.
        if (suppliedGeneration == null ||
            suppliedGeneration.toLong() != activeListenerGeneration
        ) {
            android.util.Log.d("BiblioLifeReadium", "BRIDGE_CANCEL_IGNORED")
            return
        }
        android.util.Log.d("BiblioLifeReadium", "BRIDGE_CANCELLED generation=$activeListenerGeneration")
        sink = null
        lastPositionPayload = null
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        val pending = synchronized(pendingResults) {
            pendingResults.toList().also { pendingResults.clear() }
        }
        pending.forEach { it.success(ReadiumBridgeResultEnvelope.failure("disposed")) }
        if (!finalStateSeen) {
            finalStateSeen = true
            sendEvent(ReadiumPlatformViewBridgeSerializer.event(configuration.bridgeProtocolVersion, configuration.instanceId, nextSequence(), ReadiumPlatformViewBridgeProtocol.DISPOSED, mapOf("phase" to "disposed")))
        }
        sink = null
        pendingOpenDiagnostics.clear()
        bridgeListenerToken?.let(eventHub::unbindFlutterListener)
        bridgeListenerToken = null
        transport?.dispose()
    }

    private fun emitSnapshot() {
        runCatching {
            sendEvent(
                ReadiumPlatformViewBridgeSerializer.snapshot(
                    configuration.bridgeProtocolVersion,
                    configuration.instanceId,
                    nextSequence(),
                    latestState,
                    latestPublication,
                    latestError,
                    controller,
                    configuration,
                ),
            )
        }.onFailure { emitBridgeSerializationError() }
    }

    private fun emitState(state: ReadiumPlatformViewReaderState) {
        if (disposed) return
        runCatching {
            val eventSequence = nextSequence()
            val event = ReadiumPlatformViewBridgeSerializer.stateEvent(
                configuration.bridgeProtocolVersion,
                configuration.instanceId,
                eventSequence,
                state,
            ) ?: return
            if (state is ReadiumPlatformViewReaderState.PositionChanged) {
                val payload = event["payload"] as? Map<String, Any?>
                if (payload != null && payload == lastPositionPayload) return
                lastPositionPayload = payload
            }
            sendEvent(event)
        }.onFailure { emitBridgeSerializationError() }
    }

    private fun emitInteraction(interaction: ReadiumReaderInteraction) {
        if (disposed || finalStateSeen) return
        runCatching {
            val event = ReadiumPlatformViewBridgeSerializer.interactionEvent(
                configuration.bridgeProtocolVersion,
                configuration.instanceId,
                nextSequence(),
                interaction,
            ) ?: return
            if (interaction is ReadiumReaderInteraction.ContentTap) {
                android.util.Log.d("BiblioLifeReadium", "CONTENT_TAP_BRIDGED id=${interaction.interactionId} sink=${sink != null}")
            }
            sendEvent(event)
        }.onFailure { emitBridgeSerializationError() }
    }

    private fun emitError(error: ReadiumPlatformViewError, fatal: Boolean) {
        if (disposed) return
        runCatching {
            sendEvent(ReadiumPlatformViewBridgeSerializer.errorEvent(configuration.bridgeProtocolVersion, configuration.instanceId, nextSequence(), error, fatal))
        }.onFailure { emitBridgeSerializationError() }
    }

    private fun emitBridgeSerializationError() {
        // Serialization failures are isolated from the session and never expose an exception.
        latestError = mapOf("code" to "serialization_failure", "fatal" to false, "retryable" to false)
    }

    private fun sendEvent(event: Map<String, Any?>) {
        val activeSink = sink ?: run {
            return
        }
        // Retain the listener across a transient initial hand-off so the next
        // full reader state can be delivered once Flutter is ready.
        runCatching {
            activeSink.success(event)
        }
    }

    private fun nextSequence(): Long = ++sequence

    private sealed interface ParsedCommand {
        data object Info : ParsedCommand
        data object Snapshot : ParsedCommand
        data class Navigation(
            val kind: Kind,
            val value: Double? = null,
            val locator: Locator? = null,
            val animated: Boolean,
            val progressOwner: ProgressNavigationOwner? = null,
            val originReadingOrderIndex: Int? = null,
        ) : ParsedCommand {
            enum class Kind { NEXT, PREVIOUS, PROGRESSION, LOCATOR }
        }
        data class ProgressScrubSession(val open: Boolean, val sessionId: Long) : ParsedCommand
        data class ProgressFinalReservation(val owner: ProgressNavigationOwner) : ParsedCommand
        data class Preferences(
            val value: ReaderPreferencesPayload,
            val diagnosticContext: ReadiumReflowDiagnosticContext?,
            val previewRequestId: Long?,
        ) : ParsedCommand
        data class SupersedeSettingsPreviews(val requestId: Long) : ParsedCommand
        data class SettingsReflowGesture(val id: Long, val slider: String, val action: String, val value: Double) : ParsedCommand
        data class Toc(val id: String, val animated: Boolean) : ParsedCommand
        data class Search(val query: String) : ParsedCommand
        data object CancelSearch : ParsedCommand
        data object ClearSearch : ParsedCommand
        data class SearchResult(val id: String, val animated: Boolean) : ParsedCommand
        data class Decorations(val operation: Operation, val group: ReadiumDecorationGroup, val values: List<ReadiumDecorationSpec> = emptyList(), val id: String? = null) : ParsedCommand {
            enum class Operation { SET, UPSERT, REMOVE, CLEAR }
        }
        data object RequestSelection : ParsedCommand
        data object ClearSelection : ParsedCommand
        data class ResolveSelectionAction(val resolution: ReadiumSelectionActionResolution) : ParsedCommand
        data class ResolveAnnotationAction(val resolution: ReadiumAnnotationActionResolution) : ParsedCommand
    }

    private fun parseCommand(method: String, arguments: Any?): ParsedCommand = when (method) {
        ReadiumPlatformViewBridgeProtocol.GET_BRIDGE_INFO -> ParsedCommand.Info
        ReadiumPlatformViewBridgeProtocol.GET_SNAPSHOT -> ParsedCommand.Snapshot
        ReadiumPlatformViewBridgeProtocol.NEXT -> ParsedCommand.Navigation(ParsedCommand.Navigation.Kind.NEXT, animated = animated(arguments, false))
        ReadiumPlatformViewBridgeProtocol.PREVIOUS -> ParsedCommand.Navigation(ParsedCommand.Navigation.Kind.PREVIOUS, animated = animated(arguments, false))
        ReadiumPlatformViewBridgeProtocol.GO_TO_PROGRESSION -> {
            val map = bridgeMap(arguments)
            val owner = parseProgressOwner(map["progressOwner"])
            val originJson = bridgeString(map, "originLocatorJson", required = false)
            if (originJson != null && owner?.phase != ProgressNavigationOwner.Phase.FINAL)
                throw BridgeArgumentException("invalid_progress_origin_owner")
            val origin = originJson?.let { locatorParser(it).getOrElse { throw BridgeArgumentException("invalid_locator") } }
            val index = (map["originReadingOrderIndex"] as? Number)?.toInt()?.also {
                if (it < 0) throw BridgeArgumentException("invalid_origin_reading_order_index")
            }
            ParsedCommand.Navigation(
                ParsedCommand.Navigation.Kind.PROGRESSION,
                value = bridgeDouble(map, "progression"), locator = origin,
                animated = bridgeBoolean(map, "animated", false), progressOwner = owner,
                originReadingOrderIndex = index,
            )
        }
        ReadiumPlatformViewBridgeProtocol.OPEN_PROGRESS_SCRUB_SESSION,
        ReadiumPlatformViewBridgeProtocol.INVALIDATE_PROGRESS_SCRUB_SESSION -> {
            val map = bridgeMap(arguments)
            val sessionId = (map["sessionId"] as? Number)?.toLong()
                ?.takeIf { it > 0 } ?: throw BridgeArgumentException("invalid_progress_session_id")
            ParsedCommand.ProgressScrubSession(
                open = method == ReadiumPlatformViewBridgeProtocol.OPEN_PROGRESS_SCRUB_SESSION,
                sessionId = sessionId,
            )
        }
        ReadiumPlatformViewBridgeProtocol.RESERVE_PROGRESS_SCRUB_FINAL -> {
            val owner = parseProgressOwner(bridgeMap(arguments)["progressOwner"])
                ?.takeIf { it.phase == ProgressNavigationOwner.Phase.FINAL }
                ?: throw BridgeArgumentException("invalid_final_progress_owner")
            ParsedCommand.ProgressFinalReservation(owner)
        }
        ReadiumPlatformViewBridgeProtocol.GO_TO_LOCATOR -> {
            val map = bridgeMap(arguments)
            val json = bridgeString(map, "locatorJson")!!
            val locator = locatorParser(json).getOrElse { throw BridgeArgumentException("invalid_locator") }
            ParsedCommand.Navigation(ParsedCommand.Navigation.Kind.LOCATOR, locator = locator, animated = bridgeBoolean(map, "animated", false))
        }
        ReadiumPlatformViewBridgeProtocol.APPLY_PREFERENCES -> {
            val map = bridgeMap(arguments)
            ParsedCommand.Preferences(
                ReadiumBridgePreferencesMapper.parse(map["preferences"] ?: arguments).getOrElse { error -> throw (error as? BridgeArgumentException ?: BridgeArgumentException("invalid_preference_value")) },
                parseReflowDiagnosticContext(map["diagnosticContext"]),
                (map["previewRequestId"] as? Number)?.toLong()?.also {
                    if (it <= 0) throw BridgeArgumentException("invalid_preview_request_id")
                },
            )
        }
        ReadiumPlatformViewBridgeProtocol.SETTINGS_REFLOW_GESTURE -> {
            val map = bridgeMap(arguments)
            val id = (map["gestureId"] as? Number)?.toLong()?.takeIf { it > 0 }
                ?: throw BridgeArgumentException("invalid_gesture_id")
            val slider = bridgeString(map, "slider")!!
            val action = bridgeString(map, "action")!!
            val value = bridgeDouble(map, "value")
            if (slider !in setOf("fontSize", "fontWeight", "lineHeight", "margins", "pageSpacing") ||
                action !in setOf("begin", "end", "cancel") || !value.isFinite()) throw BridgeArgumentException("invalid_reflow_gesture")
            ParsedCommand.SettingsReflowGesture(id, slider, action, value)
        }
        ReadiumPlatformViewBridgeProtocol.SUPERSEDE_SETTINGS_PREVIEWS -> {
            val requestId = (bridgeMap(arguments)["requestId"] as? Number)?.toLong()
                ?.takeIf { it > 0 } ?: throw BridgeArgumentException("invalid_preview_request_id")
            ParsedCommand.SupersedeSettingsPreviews(requestId)
        }
        ReadiumPlatformViewBridgeProtocol.GO_TO_TOC_ENTRY -> {
            val map = bridgeMap(arguments)
            ParsedCommand.Toc(bridgeString(map, "entryId")!!.trim(), bridgeBoolean(map, "animated", true))
        }
        ReadiumPlatformViewBridgeProtocol.SEARCH -> {
            val map = bridgeMap(arguments)
            ParsedCommand.Search(bridgeString(map, "query")!!.trim())
        }
        ReadiumPlatformViewBridgeProtocol.CANCEL_SEARCH -> ParsedCommand.CancelSearch
        ReadiumPlatformViewBridgeProtocol.CLEAR_SEARCH -> ParsedCommand.ClearSearch
        ReadiumPlatformViewBridgeProtocol.GO_TO_SEARCH_RESULT -> {
            val map = bridgeMap(arguments)
            ParsedCommand.SearchResult(bridgeString(map, "resultId")!!.trim(), bridgeBoolean(map, "animated", false))
        }
        ReadiumPlatformViewBridgeProtocol.SET_DECORATIONS,
        ReadiumPlatformViewBridgeProtocol.UPSERT_DECORATION,
        ReadiumPlatformViewBridgeProtocol.REMOVE_DECORATION,
        ReadiumPlatformViewBridgeProtocol.CLEAR_DECORATIONS -> parseDecorations(method, arguments)
        ReadiumPlatformViewBridgeProtocol.REQUEST_CURRENT_SELECTION -> ParsedCommand.RequestSelection
        ReadiumPlatformViewBridgeProtocol.CLEAR_SELECTION -> ParsedCommand.ClearSelection
        ReadiumPlatformViewBridgeProtocol.RESOLVE_SELECTION_ACTION -> ParsedCommand.ResolveSelectionAction(parseSelectionActionResolution(arguments))
        ReadiumPlatformViewBridgeProtocol.RESOLVE_ANNOTATION_ACTION -> ParsedCommand.ResolveAnnotationAction(parseAnnotationActionResolution(arguments))
        else -> throw BridgeArgumentException("unknown_command")
    }

    private fun parseSelectionActionResolution(arguments: Any?): ReadiumSelectionActionResolution {
        val map = bridgeMap(arguments)
        val requestId = (map["requestId"] as? Number)?.toLong()
            ?.takeIf { it > 0 } ?: throw BridgeArgumentException("invalid_request_id")
        val sessionId = (map["selectionSessionId"] as? Number)?.toLong()
            ?.takeIf { it > 0 } ?: throw BridgeArgumentException("invalid_selection_session_id")
        val outcome = bridgeString(map, "outcome")!!.let { raw ->
            ReadiumSelectionActionOutcome.entries.firstOrNull { it.wireValue == raw }
                ?: throw BridgeArgumentException("invalid_selection_action_outcome")
        }
        val annotationId = bridgeString(map, "annotationId", required = false)?.takeIf { it.isNotBlank() }
        val errorCode = bridgeString(map, "errorCode", required = false)?.takeIf { it.isNotBlank() }
        return ReadiumSelectionActionResolution(requestId, sessionId, outcome, annotationId, errorCode)
    }

    private fun parseAnnotationActionResolution(arguments: Any?): ReadiumAnnotationActionResolution {
        val map = bridgeMap(arguments)
        val requestId = (map["requestId"] as? Number)?.toLong()
            ?.takeIf { it > 0 } ?: throw BridgeArgumentException("invalid_request_id")
        val outcome = bridgeString(map, "outcome")!!.let { raw ->
            ReadiumSelectionActionOutcome.entries.firstOrNull { it.wireValue == raw }
                ?: throw BridgeArgumentException("invalid_annotation_action_outcome")
        }
        val errorCode = bridgeString(map, "errorCode", required = false)?.takeIf { it.isNotBlank() }
        return ReadiumAnnotationActionResolution(requestId, outcome, errorCode)
    }

    private fun parseProgressOwner(value: Any?): ProgressNavigationOwner? {
        if (value == null) return null
        val map = bridgeMap(value)
        val sessionId = (map["sessionId"] as? Number)?.toLong()
            ?.takeIf { it > 0 } ?: throw BridgeArgumentException("invalid_progress_session_id")
        val requestId = (map["requestId"] as? Number)?.toLong()
            ?.takeIf { it > 0 } ?: throw BridgeArgumentException("invalid_progress_request_id")
        val phase = when (bridgeString(map, "phase")) {
            "preview" -> ProgressNavigationOwner.Phase.PREVIEW
            "final" -> ProgressNavigationOwner.Phase.FINAL
            else -> throw BridgeArgumentException("invalid_progress_phase")
        }
        return ProgressNavigationOwner(sessionId, requestId, phase)
    }

    private fun parseDecorations(method: String, arguments: Any?): ParsedCommand {
        val map = bridgeMap(arguments)
        val group = ReadiumBridgeDecorationMapper.parseGroup(map["group"]).getOrElse { throw BridgeArgumentException("invalid_decoration_group") }
        return when (method) {
            ReadiumPlatformViewBridgeProtocol.SET_DECORATIONS -> ParsedCommand.Decorations(ParsedCommand.Decorations.Operation.SET, group, values = ReadiumBridgeDecorationMapper.parseList(map["decorations"], locatorParser).getOrElse { error -> throw error.asBridgeArgument("invalid_decoration") })
            ReadiumPlatformViewBridgeProtocol.UPSERT_DECORATION -> ParsedCommand.Decorations(ParsedCommand.Decorations.Operation.UPSERT, group, values = ReadiumBridgeDecorationMapper.parseList(listOf(map["decoration"]), locatorParser).getOrElse { error -> throw error.asBridgeArgument("invalid_decoration") })
            ReadiumPlatformViewBridgeProtocol.REMOVE_DECORATION -> ParsedCommand.Decorations(ParsedCommand.Decorations.Operation.REMOVE, group, id = bridgeString(map, "id")!!.trim())
            else -> ParsedCommand.Decorations(ParsedCommand.Decorations.Operation.CLEAR, group)
        }
    }

    private fun animated(arguments: Any?, default: Boolean): Boolean = when (arguments) {
        null -> default
        is Map<*, *> -> bridgeBoolean(arguments, "animated", default)
        else -> throw BridgeArgumentException("invalid_argument_type")
    }

    private fun Throwable.asBridgeArgument(fallback: String): BridgeArgumentException =
        this as? BridgeArgumentException ?: BridgeArgumentException(fallback)

    private fun dispatch(command: ParsedCommand, result: OnceBridgeResult) {
        try {
            when (command) {
                ParsedCommand.Info -> result.success(ReadiumBridgeResultEnvelope.success(ReadiumPlatformViewBridgeSerializer.info(configuration)))
                ParsedCommand.Snapshot -> result.success(ReadiumBridgeResultEnvelope.success(ReadiumPlatformViewBridgeSerializer.snapshot(configuration.bridgeProtocolVersion, configuration.instanceId, nextSequence(), latestState, latestPublication, latestError, controller, configuration)))
                is ParsedCommand.Navigation -> dispatchNavigation(command, result)
                is ParsedCommand.ProgressScrubSession -> {
                    val accepted = if (command.open) controller.openProgressScrubSession(command.sessionId)
                    else controller.invalidateProgressScrubSession(command.sessionId)
                    result.success(ReadiumBridgeResultEnvelope.success(mapOf("status" to if (accepted) "accepted" else "stale")))
                }
                is ParsedCommand.ProgressFinalReservation -> {
                    val accepted = controller.reserveProgressScrubFinal(command.owner)
                    result.success(ReadiumBridgeResultEnvelope.success(mapOf("status" to if (accepted) "accepted" else "stale")))
                }
                is ParsedCommand.SupersedeSettingsPreviews -> {
                    val accepted = controller.supersedeSettingsPreviewsBefore(command.requestId)
                    result.success(ReadiumBridgeResultEnvelope.success(mapOf("status" to if (accepted) "accepted" else "stale")))
                }
                is ParsedCommand.SettingsReflowGesture -> controller.settingsReflowGesture(command.id, command.slider, command.action, command.value) { accepted ->
                    result.success(ReadiumBridgeResultEnvelope.success(mapOf("status" to if (accepted) "accepted" else "stale")))
                }
                is ParsedCommand.Preferences -> dispatchPreferences(command, result)
                is ParsedCommand.Toc -> result.success(ReadiumBridgeResultEnvelope.success(navigation(controller.goToTocEntry(command.id, command.animated))))
                is ParsedCommand.Search -> { controller.search(command.query); result.success(ReadiumBridgeResultEnvelope.success(mapOf("status" to "started", "query" to command.query))) }
                ParsedCommand.CancelSearch -> { controller.clearSearch(); result.success(ReadiumBridgeResultEnvelope.success(mapOf("status" to "cancelled"))) }
                ParsedCommand.ClearSearch -> { controller.clearSearch(); result.success(ReadiumBridgeResultEnvelope.success(mapOf("status" to "cleared"))) }
                is ParsedCommand.SearchResult -> result.success(ReadiumBridgeResultEnvelope.success(searchNavigation(controller.goToSearchResult(command.id, command.animated))))
                is ParsedCommand.Decorations -> dispatchDecorations(command, result)
                ParsedCommand.RequestSelection -> result.success(ReadiumBridgeResultEnvelope.success(selectionRequest(controller.requestCurrentSelection())))
                ParsedCommand.ClearSelection -> result.success(ReadiumBridgeResultEnvelope.success(selectionClear(controller.clearSelection())))
                is ParsedCommand.ResolveSelectionAction -> result.success(
                    ReadiumBridgeResultEnvelope.success(
                        mapOf("status" to resolveSelectionAction(command.resolution)),
                    ),
                )
                is ParsedCommand.ResolveAnnotationAction -> result.success(
                    ReadiumBridgeResultEnvelope.success(
                        mapOf("status" to resolveAnnotationAction(command.resolution)),
                    ),
                )
            }
        } catch (_: Throwable) {
            result.success(ReadiumBridgeResultEnvelope.failure("controller_failure"))
        }
    }

    private fun dispatchNavigation(command: ParsedCommand.Navigation, result: OnceBridgeResult) {
        when (command.kind) {
            ParsedCommand.Navigation.Kind.NEXT -> result.success(ReadiumBridgeResultEnvelope.success(navigation(controller.next(command.animated))))
            ParsedCommand.Navigation.Kind.PREVIOUS -> result.success(ReadiumBridgeResultEnvelope.success(navigation(controller.previous(command.animated))))
            ParsedCommand.Navigation.Kind.LOCATOR -> result.success(ReadiumBridgeResultEnvelope.success(navigation(controller.goTo(requireNotNull(command.locator), command.animated))))
            ParsedCommand.Navigation.Kind.PROGRESSION -> {
                register(result)
                val completion: (ReadiumPlatformViewNavigationResult) -> Unit = { value -> complete(result, ReadiumBridgeResultEnvelope.success(navigation(value))) }
                if (command.locator != null) controller.goToProgressLocator(command.locator,
                    requireNotNull(command.value), requireNotNull(command.progressOwner), command.originReadingOrderIndex, completion)
                else controller.goToProgression(requireNotNull(command.value), command.animated, command.progressOwner, completion)
            }
        }
    }

    private fun dispatchPreferences(command: ParsedCommand.Preferences, result: OnceBridgeResult) {
        register(result)
        val onComplete: (ReadiumPlatformViewPreferenceResult) -> Unit = { value ->
            complete(result, ReadiumBridgeResultEnvelope.success(preference(value)))
        }
        if (command.previewRequestId != null) {
            controller.applySettingsPreviewPayloadWithDiagnostics(
                command.value,
                configuration.isNightMode,
                command.diagnosticContext,
                command.previewRequestId,
                onComplete,
            )
        } else {
            controller.applyPreferencesPayloadWithDiagnostics(
                command.value,
                configuration.isNightMode,
                command.diagnosticContext,
                onComplete,
            )
        }
    }

    private fun parseReflowDiagnosticContext(value: Any?): ReadiumReflowDiagnosticContext? = runCatching {
        val map = value as? Map<*, *> ?: return null
        val gestureId = (map["gestureId"] as? Number)?.toLong()?.takeIf { it > 0 } ?: return null
        val applyId = (map["applyId"] as? Number)?.toLong()?.takeIf { it > 0 } ?: return null
        val slider = map["slider"] as? String ?: return null
        if (slider !in setOf("fontSize", "fontWeight", "lineHeight", "margins", "pageSpacing")) return null
        val normalizedValue = (map["normalizedValue"] as? Number)?.toDouble()
            ?.takeIf { it.isFinite() } ?: return null
        ReadiumReflowDiagnosticContext(gestureId, slider, applyId, normalizedValue)
    }.getOrNull()

    private fun dispatchDecorations(command: ParsedCommand.Decorations, result: OnceBridgeResult) {
        register(result)
        when (command.operation) {
            ParsedCommand.Decorations.Operation.SET -> controller.setDecorations(command.group, command.values) { value -> complete(result, ReadiumBridgeResultEnvelope.success(decoration(value))) }
            ParsedCommand.Decorations.Operation.UPSERT -> controller.upsertDecoration(command.group, command.values.single()) { value -> complete(result, ReadiumBridgeResultEnvelope.success(decoration(value))) }
            ParsedCommand.Decorations.Operation.REMOVE -> controller.removeDecoration(command.group, requireNotNull(command.id)) { value -> complete(result, ReadiumBridgeResultEnvelope.success(decoration(value))) }
            ParsedCommand.Decorations.Operation.CLEAR -> controller.clearDecorations(command.group) { value -> complete(result, ReadiumBridgeResultEnvelope.success(decoration(value))) }
        }
    }

    private fun register(result: OnceBridgeResult) {
        if (!result.isCompleted()) synchronized(pendingResults) { pendingResults += result }
    }

    private fun complete(result: OnceBridgeResult, value: Map<String, Any?>) {
        synchronized(pendingResults) { pendingResults.remove(result) }
        result.success(value)
    }

    private fun navigation(value: ReadiumPlatformViewNavigationResult): Map<String, Any?> = mapOf("status" to when (value) {
        ReadiumPlatformViewNavigationResult.Completed -> "completed"
        ReadiumPlatformViewNavigationResult.CompletedWithPublicationFailure -> "completed"
        ReadiumPlatformViewNavigationResult.RecoveredTimeout -> "recoveredTimeout"
        ReadiumPlatformViewNavigationResult.BoundaryReached -> "boundaryReached"
        ReadiumPlatformViewNavigationResult.NavigatorNotReady -> "notReady"
        ReadiumPlatformViewNavigationResult.InvalidLocator -> "invalidLocator"
        ReadiumPlatformViewNavigationResult.InvalidProgression -> "invalidProgression"
        ReadiumPlatformViewNavigationResult.SessionDisposed -> "disposed"
        ReadiumPlatformViewNavigationResult.Cancelled -> "cancelled"
        ReadiumPlatformViewNavigationResult.TocNotReady -> "tocNotReady"
        ReadiumPlatformViewNavigationResult.UnknownTocEntry -> "unknownTocEntry"
        ReadiumPlatformViewNavigationResult.Failed -> "failed"
    }) + if (value == ReadiumPlatformViewNavigationResult.CompletedWithPublicationFailure)
        mapOf("positionPublication" to "failed") else emptyMap()
    private fun searchNavigation(value: ReadiumPlatformViewSearchNavigationResult): Map<String, Any?> = mapOf("status" to when (value) {
        ReadiumPlatformViewSearchNavigationResult.Completed -> "completed"
        ReadiumPlatformViewSearchNavigationResult.NavigatorNotReady -> "notReady"
        ReadiumPlatformViewSearchNavigationResult.SessionDisposed -> "disposed"
        ReadiumPlatformViewSearchNavigationResult.UnknownResultId -> "unknownResultId"
        ReadiumPlatformViewSearchNavigationResult.ObsoleteResultId -> "obsoleteResultId"
        ReadiumPlatformViewSearchNavigationResult.Failed -> "failed"
    })
    private fun preference(value: ReadiumPlatformViewPreferenceResult): Map<String, Any?> = mapOf("status" to when (value) {
        ReadiumPlatformViewPreferenceResult.Applied -> "applied"
        ReadiumPlatformViewPreferenceResult.Unchanged -> "unchanged"
        ReadiumPlatformViewPreferenceResult.NavigatorNotReady -> "notReady"
        ReadiumPlatformViewPreferenceResult.SessionDisposed -> "disposed"
        ReadiumPlatformViewPreferenceResult.Cancelled -> "cancelled"
        ReadiumPlatformViewPreferenceResult.Failed -> "failed"
    })
    private fun decoration(value: ReadiumPlatformViewDecorationResult): Map<String, Any?> = mapOf("status" to when (value) {
        ReadiumPlatformViewDecorationResult.Applied -> "applied"
        ReadiumPlatformViewDecorationResult.Queued -> "queued"
        ReadiumPlatformViewDecorationResult.Unchanged -> "unchanged"
        ReadiumPlatformViewDecorationResult.Superseded -> "superseded"
        ReadiumPlatformViewDecorationResult.Failed -> "failed"
        ReadiumPlatformViewDecorationResult.NavigatorNotReady -> "notReady"
        ReadiumPlatformViewDecorationResult.SessionDisposed -> "disposed"
    })
    private fun selectionRequest(value: ReadiumSelectionRequestResult): Map<String, Any?> = mapOf("status" to when (value) {
        is ReadiumSelectionRequestResult.Updated -> "updated"
        ReadiumSelectionRequestResult.Empty -> "empty"
        ReadiumSelectionRequestResult.Started -> "started"
        ReadiumSelectionRequestResult.AlreadyInFlight -> "alreadyInFlight"
        ReadiumSelectionRequestResult.Clearing -> "clearing"
        ReadiumSelectionRequestResult.NotActive -> "notActive"
        ReadiumSelectionRequestResult.NavigatorNotReady -> "notReady"
        is ReadiumSelectionRequestResult.Failed -> "failed"
        ReadiumSelectionRequestResult.Stale -> "stale"
        ReadiumSelectionRequestResult.Disposed -> "disposed"
    })
    private fun selectionClear(value: ReadiumSelectionClearResult): Map<String, Any?> = mapOf("status" to when (value) {
        ReadiumSelectionClearResult.Started -> "started"
        ReadiumSelectionClearResult.AlreadyClearing -> "alreadyClearing"
        ReadiumSelectionClearResult.NotActive -> "notActive"
        ReadiumSelectionClearResult.NavigatorNotReady -> "notReady"
        is ReadiumSelectionClearResult.Failed -> "failed"
        ReadiumSelectionClearResult.Disposed -> "disposed"
    })
}

internal object ReadiumBridgeResultEnvelope {
    fun success(value: Any?): Map<String, Any?> = mapOf("ok" to true, "value" to value)
    fun failure(code: String): Map<String, Any?> = mapOf(
        "ok" to false,
        "error" to mapOf("code" to code, "messageKey" to code, "details" to null),
    )
}
