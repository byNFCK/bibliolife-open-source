package app.bibliolife.reader.readium

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner

/** Focused JVM coverage for the native Flutter bridge boundary. */
@RunWith(RobolectricTestRunner::class)
class ReadiumPlatformViewBridgeTest {
    @Test fun `rollback bridge preserves canonical origin locator index and final ownership`() {
        val controller = FakeController()
        val bridge = core(controller)
        val origin = """{"href":"chapter.xhtml","type":"application/xhtml+xml","locations":{"progression":0.375,"totalProgression":0.2,"position":42,"cssSelector":"p:nth-child(8)"},"text":{"before":"prefix","highlight":"anchor","after":"suffix"}}"""
        val result = RecordingResult()
        bridge.onCommand(ReadiumPlatformViewBridgeProtocol.GO_TO_PROGRESSION,
            mapOf("progression" to .2, "originLocatorJson" to origin, "originReadingOrderIndex" to 3,
                "progressOwner" to mapOf("sessionId" to 7L, "requestId" to 1L, "phase" to "final")), result)
        assertEquals(1, controller.originNavigationCount)
        assertEquals(0, controller.progressionCount)
        assertEquals(.375, controller.lastOriginLocator?.locations?.progression)
        assertEquals(.2, controller.lastOriginLocator?.locations?.totalProgression)
        assertEquals(42, controller.lastOriginLocator?.locations?.position)
        assertEquals("p:nth-child(8)", controller.lastOriginLocator?.locations?.otherLocations?.get("cssSelector"))
        assertEquals("anchor", controller.lastOriginLocator?.text?.highlight)
        assertEquals(3, controller.lastOriginIndex)
        assertEquals(ProgressNavigationOwner.Phase.FINAL, controller.lastProgressOwner?.phase)
        assertEquals(1, result.values.size)
    }

    @Test fun `origin rollback rejects preview owner and invalid locator without approximate fallback`() {
        for ((locator, phase) in listOf(locatorJson() to "preview", "invalid json" to "final")) {
            val controller = FakeController()
            val result = RecordingResult()
            core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.GO_TO_PROGRESSION,
                mapOf("progression" to .2, "originLocatorJson" to locator,
                    "progressOwner" to mapOf("sessionId" to 7L, "requestId" to 1L, "phase" to phase)), result)
            assertEquals(0, controller.originNavigationCount)
            assertEquals(0, controller.progressionCount)
            assertEquals(1, result.values.size)
        }
    }

    @Test fun `gesture lifetime command preserves identity and rejects invalid lifecycle actions`() {
        val controller = FakeController()
        val bridge = core(controller)
        listOf("begin", "end", "cancel").forEach { action ->
            bridge.onCommand(ReadiumPlatformViewBridgeProtocol.SETTINGS_REFLOW_GESTURE,
                mapOf("gestureId" to 42L, "slider" to "fontSize", "action" to action, "value" to 1.5), RecordingResult())
        }
        assertEquals(listOf("42:fontSize:begin:1.5", "42:fontSize:end:1.5", "42:fontSize:cancel:1.5"), controller.gestureCommands)
        bridge.onCommand(ReadiumPlatformViewBridgeProtocol.SETTINGS_REFLOW_GESTURE,
            mapOf("gestureId" to 42L, "slider" to "fontSize", "action" to "unknown", "value" to 1.5), RecordingResult())
        assertEquals(3, controller.gestureCommands.size)
    }
    @Test fun `channel command name is deterministic`() {
        val names = ReadiumPlatformViewBridgeChannelNames.require("reader-1")
        assertEquals(names.command, ReadiumPlatformViewBridgeChannelNames.require("reader-1").command)
        assertTrue(names.command.endsWith("/commands"))
    }

    @Test fun `channel event name is deterministic`() {
        val names = ReadiumPlatformViewBridgeChannelNames.require("reader-1")
        assertEquals(names.events, ReadiumPlatformViewBridgeChannelNames.require("reader-1").events)
        assertTrue(names.events.endsWith("/events"))
    }

    @Test fun `different instance ids do not collide`() {
        assertFalse(ReadiumPlatformViewBridgeChannelNames.require("reader-1").command == ReadiumPlatformViewBridgeChannelNames.require("reader-2").command)
    }

    @Test fun `slash and control identity is encoded`() {
        val names = ReadiumPlatformViewBridgeChannelNames.require("reader/a\n1")
        assertFalse(names.command.contains("reader/a"))
        assertFalse(names.command.contains("\n"))
    }

    @Test fun `blank identity is rejected`() {
        val error = runCatching { ReadiumPlatformViewBridgeChannelNames.require(" ") }.exceptionOrNull()
        assertEquals("invalid_instance_id", error?.message)
    }

    @Test fun `very long identity is bounded`() {
        val error = runCatching { ReadiumPlatformViewBridgeChannelNames.require("x".repeat(513)) }.exceptionOrNull()
        assertEquals("instance_id_too_long", error?.message)
    }

    @Test fun `path is not exposed by channel name`() {
        val names = ReadiumPlatformViewBridgeChannelNames.require("C:\\books\\secret.epub")
        assertFalse(names.command.contains("secret.epub"))
        assertFalse(names.events.contains("C:"))
    }

    @Test fun `protocol version is centralized`() = assertEquals(1, ReadiumPlatformViewBridgeProtocol.VERSION)

    @Test fun `open configuration defaults protocol`() = assertEquals(
        ReadiumPlatformViewBridgeProtocol.VERSION,
        ReadiumPlatformViewOpenConfiguration.parse(config().toMap() - "bridgeProtocolVersion").getOrThrow().bridgeProtocolVersion,
    )

    @Test fun `unsupported protocol is deterministic`() {
        val error = ReadiumPlatformViewOpenConfiguration.parse(config().toMap() + ("bridgeProtocolVersion" to 99)).exceptionOrNull()
        assertEquals("unsupported_protocol", (error as ReadiumPlatformViewCreationException).failureCode)
    }

    @Test fun `malformed protocol type is rejected`() {
        val error = ReadiumPlatformViewOpenConfiguration.parse(config().toMap() + ("bridgeProtocolVersion" to "1")).exceptionOrNull()
        assertEquals("invalid_protocol", (error as ReadiumPlatformViewCreationException).failureCode)
    }

    @Test fun `locator mapper preserves nullable serialization`() = assertNull(ReadiumBridgeLocatorMapper.serialize(null))

    @Test fun `malformed locator fails`() = assertEquals(false, ReadiumBridgeLocatorMapper.parse("not json").isSuccess)

    @Test fun `preferences mapper preserves supported fields`() {
        val value = ReadiumBridgePreferencesMapper.parse(preferencesMap()).getOrThrow()
        assertEquals("dark", value.theme)
        assertEquals(1.2, value.fontSize, 0.0)
        assertEquals(false, value.publisherStyles)
    }

    @Test fun `preferences mapper rejects enum`() {
        val result = ReadiumBridgePreferencesMapper.parse(preferencesMap() + ("theme" to "comic"))
        assertEquals("invalid_preference_value", result.exceptionOrNull()?.message)
    }

    @Test fun `preferences mapper rejects nan`() {
        val result = ReadiumBridgePreferencesMapper.parse(preferencesMap() + ("fontSize" to Double.NaN))
        assertEquals("invalid_preference_value", result.exceptionOrNull()?.message)
    }

    @Test fun `decoration mapper accepts persistent group`() = assertEquals(
        ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS,
        ReadiumBridgeDecorationMapper.parseGroup("PERSISTENT_HIGHLIGHTS").getOrThrow(),
    )

    @Test fun `decoration mapper rejects unknown group`() = assertEquals(
        "invalid_decoration_group",
        ReadiumBridgeDecorationMapper.parseGroup("other").exceptionOrNull()?.message,
    )

    @Test fun `decoration mapper rejects malformed locator`() = assertEquals(
        "invalid_locator",
        ReadiumBridgeDecorationMapper.parseList(listOf(mapOf("id" to "a", "locatorJson" to "bad", "style" to styleMap()))).exceptionOrNull()?.message,
    )

    @Test fun `decoration mapper preserves stable id and style`() {
        val spec = ReadiumBridgeDecorationMapper.parseList(listOf(decorationMap()), locatorParser = { Result.success(testLocator()) }).getOrThrow().single()
        assertEquals("highlight-1", spec.id)
        assertTrue(spec.style is ReadiumDecorationStyle.Highlight)
    }

    @Test fun `info returns protocol and logical identity`() {
        val info = ReadiumPlatformViewBridgeSerializer.info(config())
        assertEquals(1, info["protocolVersion"])
        assertEquals("reader", info["instanceId"])
    }

    @Test fun `lifecycle serializer emits codec safe event`() {
        val event = ReadiumPlatformViewBridgeSerializer.stateEvent(1, "reader", 1, ReadiumPlatformViewReaderState.NavigatorReady)!!
        assertEquals("readerLifecycleChanged", event["type"])
        assertEquals(1L, event["sequence"])
    }

    @Test fun `diagnostic serializer uses separate event type and whitelisted payload`() {
        val event = ReadiumPlatformViewBridgeSerializer.stateEvent(
            1,
            "reader",
            2,
            ReadiumPlatformViewReaderState.Diagnostic(
                mapOf("kind" to "preference_terminal", "result" to "applied", "gestureId" to 9L),
            ),
        )!!
        assertEquals(ReadiumPlatformViewBridgeProtocol.READER_DIAGNOSTIC, event["type"])
        assertEquals(
            mapOf("kind" to "preference_terminal", "result" to "applied", "gestureId" to 9L),
            event["payload"],
        )
    }

    @Test fun `position event preserves exact progress owner`() {
        val owner = ProgressNavigationOwner(12, 4, ProgressNavigationOwner.Phase.FINAL)
        val event = ReadiumPlatformViewBridgeSerializer.stateEvent(
            1,
            "reader",
            2,
            ReadiumPlatformViewReaderState.PositionChanged(
                ReadiumPositionState(
                    Locator(
                        href = Url("chapter.xhtml")!!,
                        mediaType = MediaType.XHTML,
                        locations = Locator.Locations(progression = 0.25, position = 2),
                    ),
                    0.4,
                ),
                progressOwner = owner,
            ),
        )!!
        val payload = event["payload"] as Map<*, *>
        assertEquals(
            mapOf("sessionId" to 12L, "requestId" to 4L, "phase" to "final"),
            payload["progressOwner"],
        )
    }

    @Test fun `snapshot serializes retained publication as a map`() {
        val snapshot = ReadiumPlatformViewBridgeSerializer.snapshot(
            1,
            "reader",
            1,
            ReadiumPlatformViewReaderState.InitialLocatorRestored(false),
            ReadiumPlatformViewPublicationInfo("book", "The Time Machine"),
            null,
            FakeController(),
            config(),
        )

        val lifecycle = (snapshot["payload"] as Map<*, *>)["lifecycle"] as Map<*, *>
        assertEquals("ready", lifecycle["phase"])
        assertEquals(
            mapOf("bookId" to "book", "title" to "The Time Machine"),
            lifecycle["publication"],
        )
    }

    @Test fun `toc serializer preserves nested document order`() {
        val toc = ReadiumTocState.Ready(listOf(ReadiumTocEntry("a", "А", "a.xhtml", null, 0, listOf(ReadiumTocEntry("b", "Б", "b.xhtml", null, 1, emptyList())))))
        val event = ReadiumPlatformViewBridgeSerializer.stateEvent(1, "reader", 2, ReadiumPlatformViewReaderState.TocStateChanged(toc))!!
        val entries = ((event["payload"] as Map<*, *>) ["entries"] as List<*>)
        assertEquals("a", (entries[0] as Map<*, *>) ["id"])
        assertEquals("Б", (((entries[0] as Map<*, *>) ["children"] as List<*>)[0] as Map<*, *>) ["title"])
    }

    @Test fun `search serializer preserves before highlight after and unicode`() {
        val state = EpubSearchState.Results("слово", 4, listOf(EpubSearchResult("r", "a.xhtml", "Заголовок", "до", "слово", "після", 2, 0.2)), false, false)
        val event = ReadiumPlatformViewBridgeSerializer.stateEvent(1, "reader", 3, ReadiumPlatformViewReaderState.SearchStateChanged(state))!!
        val result = (((event["payload"] as Map<*, *>) ["results"] as List<*>).single() as Map<*, *>)
        assertEquals("слово", result["highlight"])
        assertEquals("до", result["before"])
        assertEquals("після", result["after"])
    }

    @Test fun `selection serializer contains only scalar rectangle fields`() {
        val selection = ReadiumSelectionState(ReadiumSelectionStatus.ACTIVE, 1, 2, 3, 4, ReadiumSelectionSnapshot(null, "текст", null, null, "a.xhtml", 0.1, 0.2, ReadiumSelectionRect(1f, 2f, 3f, 4f)), false, null)
        val event = ReadiumPlatformViewBridgeSerializer.stateEvent(1, "reader", 4, ReadiumPlatformViewReaderState.SelectionChanged(selection))!!
        val rect = ((((event["payload"] as Map<*, *>) ["selection"] as Map<*, *>) ["rect"] as Map<*, *>))
        assertEquals(1.0, rect["left"])
        assertEquals("текст", ((event["payload"] as Map<*, *>) ["selection"] as Map<*, *>) ["selectedText"])
    }

    @Test fun `decoration state serializer includes group and counts`() {
        val state = ReadiumReaderDecorationState(2, 1, 3, false, true, false, true)
        val value = ReadiumBridgeDecorationMapper.serialize(ReadiumDecorationGroup.SEARCH_RESULT, state)
        assertEquals("SEARCH_RESULT", value["group"])
        assertEquals(2, value["requestedCount"])
    }

    @Test fun `event hub fans out typed state to native and flutter`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator()
        val hub = ReadiumPlatformViewEventHub(coordinator)
        val native = RecordingListener()
        val flutter = RecordingListener()
        coordinator.bind(native)
        hub.bindFlutterListener(flutter)
        coordinator.emit(ReadiumPlatformViewReaderState.NavigatorReady)
        assertEquals(1, native.states.size)
        assertEquals(1, flutter.states.size)
    }

    @Test fun `diagnostic event is forwarded without replacing retained lifecycle state`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator()
        val existing = RecordingListener()
        val existingToken = coordinator.bind(existing)!!
        coordinator.emit(ReadiumPlatformViewReaderState.NavigatorReady)
        coordinator.emit(ReadiumPlatformViewReaderState.Diagnostic(mapOf("kind" to "preference_received")))
        assertEquals(2, existing.states.size)

        coordinator.unbind(existingToken)
        val late = RecordingListener()
        assertNotNull(coordinator.bind(late))
        assertEquals(listOf(ReadiumPlatformViewReaderState.NavigatorReady), late.states)
    }

    @Test fun `stale settings supersede control is rejected without replacing newer cutoff`() {
        val controller = FakeController()
        val core = core(controller)
        val newer = RecordingResult()
        core.onCommand(
            ReadiumPlatformViewBridgeProtocol.SUPERSEDE_SETTINGS_PREVIEWS,
            mapOf("requestId" to 9L),
            newer,
        )
        assertEquals("accepted", (((newer.values.single() as Map<*, *>) ["value"] as Map<*, *>) ["status"]))
        assertEquals(9L, controller.settingsPreviewCutoff)

        val stale = RecordingResult()
        core.onCommand(
            ReadiumPlatformViewBridgeProtocol.SUPERSEDE_SETTINGS_PREVIEWS,
            mapOf("requestId" to 8L),
            stale,
        )
        assertEquals("stale", (((stale.values.single() as Map<*, *>) ["value"] as Map<*, *>) ["status"]))
        assertEquals(9L, controller.settingsPreviewCutoff)
    }

    @Test fun `bridge info command delegates no session work`() {
        val controller = FakeController()
        val core = core(controller)
        val result = RecordingResult()
        core.onCommand(ReadiumPlatformViewBridgeProtocol.GET_BRIDGE_INFO, null, result)
        val value = result.values.single() as Map<*, *>
        assertEquals(true, value["ok"])
        assertEquals(0, controller.commandCount)
    }

    @Test fun `next command delegates exactly once`() {
        val controller = FakeController()
        val core = core(controller)
        val result = RecordingResult()
        core.onCommand(ReadiumPlatformViewBridgeProtocol.NEXT, null, result)
        assertEquals(1, controller.nextCount)
        assertEquals("completed", (((result.values.single() as Map<*, *>) ["value"] as Map<*, *>) ["status"]))
    }

    @Test fun `previous command delegates exactly once`() {
        val controller = FakeController()
        val core = core(controller)
        core.onCommand(ReadiumPlatformViewBridgeProtocol.PREVIOUS, null, RecordingResult())
        assertEquals(1, controller.previousCount)
    }

    @Test fun `nan progression is rejected before delegation`() {
        val controller = FakeController()
        val result = RecordingResult()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.GO_TO_PROGRESSION, mapOf("progression" to Double.NaN), result)
        assertEquals(0, controller.progressionCount)
        assertEquals("invalid_argument", (((result.values.single() as Map<*, *>) ["error"] as Map<*, *>) ["code"]))
    }

    @Test fun `infinite progression is rejected before delegation`() {
        val controller = FakeController()
        val result = RecordingResult()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.GO_TO_PROGRESSION, mapOf("progression" to Double.POSITIVE_INFINITY), result)
        assertEquals(0, controller.progressionCount)
    }

    @Test fun `out of range progression reaches typed session result`() {
        val controller = FakeController().apply { navigationResult = ReadiumPlatformViewNavigationResult.InvalidProgression }
        val result = RecordingResult()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.GO_TO_PROGRESSION, mapOf("progression" to 2.0), result)
        assertEquals(1, controller.progressionCount)
        assertEquals("invalidProgression", (((result.values.single() as Map<*, *>) ["value"] as Map<*, *>) ["status"]))
    }

    @Test fun `fractional progression is preserved without quantization`() {
        val controller = FakeController()
        core(controller).onCommand(
            ReadiumPlatformViewBridgeProtocol.GO_TO_PROGRESSION,
            mapOf("progression" to 0.76),
            RecordingResult(),
        )
        assertEquals(0.76, controller.lastProgression ?: -1.0, 0.0)
    }

    @Test fun `verified navigation publication error retains completed status with separate outcome`() {
        val controller = FakeController().apply { navigationResult = ReadiumPlatformViewNavigationResult.CompletedWithPublicationFailure }
        val result = RecordingResult()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.GO_TO_PROGRESSION, mapOf("progression" to .2765), result)
        val value = (result.values.single() as Map<*, *>)["value"] as Map<*, *>
        assertEquals("completed", value["status"])
        assertEquals("failed", value["positionPublication"])
    }

    @Test fun `recovered progress callback is explicitly unsuccessful`() {
        val controller = FakeController().apply { navigationResult = ReadiumPlatformViewNavigationResult.RecoveredTimeout }
        val result = RecordingResult()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.GO_TO_PROGRESSION, mapOf("progression" to .8), result)
        val value = (result.values.single() as Map<*, *>)["value"] as Map<*, *>
        assertEquals("recoveredTimeout", value["status"])
        assertFalse(ReadiumPlatformViewNavigationResult.RecoveredTimeout.accepted)
    }

    @Test fun `final owner reservation reaches native controller before seek`() {
        val controller = FakeController()
        val result = RecordingResult()
        val owner = mapOf("sessionId" to 3L, "requestId" to 9L, "phase" to "final")
        core(controller).onCommand(
            ReadiumPlatformViewBridgeProtocol.RESERVE_PROGRESS_SCRUB_FINAL,
            mapOf("progressOwner" to owner),
            result,
        )
        assertEquals(ProgressNavigationOwner(3, 9, ProgressNavigationOwner.Phase.FINAL), controller.reservedFinalOwner)
        assertEquals("accepted", (((result.values.single() as Map<*, *>) ["value"] as Map<*, *>) ["status"]))
    }

    @Test fun `preview owner reaches navigation command unchanged`() {
        val controller = FakeController()
        val owner = mapOf("sessionId" to 3L, "requestId" to 8L, "phase" to "preview")
        core(controller).onCommand(
            ReadiumPlatformViewBridgeProtocol.GO_TO_PROGRESSION,
            mapOf("progression" to 0.61, "progressOwner" to owner),
            RecordingResult(),
        )
        assertEquals(ProgressNavigationOwner(3, 8, ProgressNavigationOwner.Phase.PREVIEW), controller.lastProgressOwner)
    }

    @Test fun `malformed locator is rejected before delegation`() {
        val controller = FakeController()
        val result = RecordingResult()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.GO_TO_LOCATOR, mapOf("locatorJson" to "bad"), result)
        assertEquals(0, controller.locatorCount)
        assertEquals("invalid_locator", (((result.values.single() as Map<*, *>) ["error"] as Map<*, *>) ["code"]))
    }

    @Test fun `valid locator delegates once`() {
        val controller = FakeController()
        core(controller, locatorParser = { Result.success(testLocator()) }).onCommand(ReadiumPlatformViewBridgeProtocol.GO_TO_LOCATOR, mapOf("locatorJson" to locatorJson()), RecordingResult())
        assertEquals(1, controller.locatorCount)
    }

    @Test fun `preferences command delegates typed payload`() {
        val controller = FakeController()
        val result = RecordingResult()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.APPLY_PREFERENCES, mapOf("preferences" to preferencesMap()), result)
        assertEquals(1, controller.preferenceCount)
        assertEquals(1, controller.preferenceCount)
    }

    @Test fun `toc command delegates stable id only`() {
        val controller = FakeController()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.GO_TO_TOC_ENTRY, mapOf("entryId" to "toc-id"), RecordingResult())
        assertEquals("toc-id", controller.lastTocId)
    }

    @Test fun `search preserves trim only`() {
        val controller = FakeController()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.SEARCH, mapOf("query" to "  слово  "), RecordingResult())
        assertEquals("слово", controller.lastQuery)
    }

    @Test fun `cancel and clear search delegate`() {
        val controller = FakeController()
        val core = core(controller)
        core.onCommand(ReadiumPlatformViewBridgeProtocol.CANCEL_SEARCH, null, RecordingResult())
        core.onCommand(ReadiumPlatformViewBridgeProtocol.CLEAR_SEARCH, null, RecordingResult())
        assertEquals(2, controller.clearSearchCount)
    }

    @Test fun `search result delegates stable id`() {
        val controller = FakeController()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.GO_TO_SEARCH_RESULT, mapOf("resultId" to "result-1"), RecordingResult())
        assertEquals("result-1", controller.lastSearchResultId)
    }

    @Test fun `invalid decoration group does not delegate`() {
        val controller = FakeController()
        val result = RecordingResult()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.SET_DECORATIONS, mapOf("group" to "invalid", "decorations" to emptyList<Any>()), result)
        assertEquals(0, controller.decorationCount)
    }

    @Test fun `set decorations delegates one complete group snapshot`() {
        val controller = FakeController()
        core(controller, locatorParser = { Result.success(testLocator()) }).onCommand(ReadiumPlatformViewBridgeProtocol.SET_DECORATIONS, mapOf("group" to "PERSISTENT_HIGHLIGHTS", "decorations" to listOf(decorationMap())), RecordingResult())
        assertEquals(1, controller.decorationCount)
        assertEquals(ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS, controller.lastGroup)
    }

    @Test fun `remove decoration passes group and stable id`() {
        val controller = FakeController()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.REMOVE_DECORATION, mapOf("group" to "SEARCH_RESULT", "id" to "stable"), RecordingResult())
        assertEquals("stable", controller.lastDecorationId)
    }

    @Test fun `clear decoration passes one group`() {
        val controller = FakeController()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.CLEAR_DECORATIONS, mapOf("group" to "SEARCH_RESULT"), RecordingResult())
        assertEquals(ReadiumDecorationGroup.SEARCH_RESULT, controller.lastGroup)
    }

    @Test fun `unknown command returns controlled error`() {
        val result = RecordingResult()
        core(FakeController()).onCommand("unknown", null, result)
        assertEquals("unknown_command", (((result.values.single() as Map<*, *>) ["error"] as Map<*, *>) ["code"]))
    }

    @Test fun `stale instance command is rejected`() {
        val controller = FakeController()
        val result = RecordingResult()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.NEXT, mapOf("instanceId" to "other"), result)
        assertEquals(0, controller.nextCount)
        assertEquals("stale_instance", (((result.values.single() as Map<*, *>) ["error"] as Map<*, *>) ["code"]))
    }

    @Test fun `first listener receives snapshot immediately`() {
        val core = core(FakeController())
        val sink = RecordingSink()
        core.onListen(null, sink)
        assertEquals("snapshot", sink.events.single()["type"])
        assertEquals(1, sink.events.single()["protocolVersion"])
    }

    @Test fun `restoration diagnostics precede fatal error and the snapshot retains its details`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator()
        val core = core(FakeController(), coordinator)
        val sink = RecordingSink()
        core.onListen(null, sink)
        val restoration = ReadiumOpenDiagnostics.stage("restoration_terminal", "failed", "readium_initial_locator", mapOf(
            "kind" to "initial_locator_restoration",
            "openAttemptId" to 17L,
            "failureReason" to "viewport_locator_did_not_converge",
        ))
        val details = ReadiumOpenDiagnostics.stage("navigator_initialization", "failed", "android_readium_navigator", mapOf(
            "openAttemptId" to 17L,
            "initialLocatorRestoration" to restoration,
        ))
        val fatal = ReadiumPlatformViewError("initial_locator_restoration_failed", details)

        coordinator.emit(ReadiumPlatformViewReaderState.Diagnostic(restoration))
        coordinator.emitFatal(fatal)
        assertEquals(listOf("snapshot", "readerDiagnostic", "readerError"), sink.events.map { it["type"] })
        val error = sink.events.last()["payload"] as Map<*, *>
        assertEquals(details, error["details"])

        val reconnect = RecordingSink()
        core.onListen(null, reconnect)
        val snapshot = reconnect.events.single()["payload"] as Map<*, *>
        assertEquals(details, (snapshot["error"] as Map<*, *>)["details"])
    }

    @Test fun `open configuration carries diagnostic identity and locator source`() {
        val parsed = ReadiumPlatformViewOpenConfiguration.parse(config().toMap() + mapOf(
            "openAttemptId" to 17,
            "initialLocatorSource" to "saved_progress",
        )).getOrThrow()
        assertEquals(17L, parsed.openAttemptId)
        assertEquals("saved_progress", parsed.initialLocatorSource)
    }

    @Test fun `opening failure still carries details when the diagnostic send fails`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator()
        val core = core(FakeController(), coordinator)
        val delivered = mutableListOf<Map<String, Any?>>()
        core.onListen(null, object : ReadiumBridgeEventSink {
            override fun success(event: Map<String, Any?>) {
                if (event["type"] == "readerDiagnostic") error("diagnostic delivery failed")
                delivered.add(event)
            }
        })
        val details = ReadiumOpenDiagnostics.stage("navigator_initialization", "failed", "android_readium_navigator", mapOf(
            "openAttemptId" to 18L,
            "initialLocatorRestoration" to mapOf("failureReason" to "target_not_in_reading_order"),
        ))
        coordinator.emit(ReadiumPlatformViewReaderState.Diagnostic(details))
        coordinator.emitFatal(ReadiumPlatformViewError("initial_locator_restoration_failed", details))
        val error = delivered.single { it["type"] == "readerError" }["payload"] as Map<*, *>
        assertEquals(details, error["details"])
    }

    @Test fun `snapshot does not restart engine work`() {
        val controller = FakeController()
        val core = core(controller)
        core.onListen(null, RecordingSink())
        assertEquals(0, controller.commandCount)
        assertEquals(0, controller.searchCount)
        assertEquals(0, controller.tocLoadCount)
    }

    @Test fun `listener reconnect receives latest snapshot without work`() {
        val controller = FakeController()
        val core = core(controller)
        val first = RecordingSink()
        core.onListen(null, first)
        core.onCancel(null)
        val second = RecordingSink()
        core.onListen(null, second)
        assertEquals("snapshot", second.events.single()["type"])
        assertEquals(0, controller.searchCount)
    }

    @Test fun `cancel detaches only sink`() {
        val core = core(FakeController())
        val sink = RecordingSink()
        core.onListen(null, sink)
        core.onCancel(null)
        core.onCommand(ReadiumPlatformViewBridgeProtocol.NEXT, null, RecordingResult())
        assertEquals(1, sink.events.size)
    }

    @Test fun `event sequence continues across reconnect`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator()
        val controller = FakeController()
        val core = core(controller, coordinator)
        val first = RecordingSink()
        core.onListen(null, first)
        coordinator.emit(ReadiumPlatformViewReaderState.NavigatorReady)
        val firstLast = first.events.last()["sequence"] as Long
        core.onCancel(null)
        val second = RecordingSink()
        core.onListen(null, second)
        val snapshotSequence = second.events.single()["sequence"] as Long
        assertTrue(snapshotSequence > firstLast)
    }

    @Test fun `on cancel does not dispose bridge`() {
        val core = core(FakeController())
        core.onListen(null, RecordingSink())
        core.onCancel(null)
        val result = RecordingResult()
        core.onCommand(ReadiumPlatformViewBridgeProtocol.NEXT, null, result)
        assertEquals(true, (result.values.single() as Map<*, *>) ["ok"])
    }

    @Test fun `stale sink cancellation does not detach replacement`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator()
        val core = core(FakeController(), coordinator)
        val first = RecordingSink()
        val second = RecordingSink()
        core.onListen(mapOf("listenerGeneration" to 1L), first)
        core.onListen(mapOf("listenerGeneration" to 2L), second)
        core.onCancel(mapOf("listenerGeneration" to 1L))
        coordinator.emit(ReadiumPlatformViewReaderState.NavigatorReady)
        assertEquals(2, second.events.size)
    }

    @Test fun `disposal is idempotent`() {
        val core = core(FakeController())
        core.dispose()
        core.dispose()
        val result = RecordingResult()
        core.onCommand(ReadiumPlatformViewBridgeProtocol.NEXT, null, result)
        assertEquals("disposed", (((result.values.single() as Map<*, *>) ["error"] as Map<*, *>) ["code"]))
    }

    @Test fun `no event after disposal`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator()
        val core = core(FakeController(), coordinator)
        val sink = RecordingSink()
        core.onListen(null, sink)
        core.dispose()
        val count = sink.events.size
        coordinator.emit(ReadiumPlatformViewReaderState.NavigatorReady)
        assertEquals(count, sink.events.size)
    }

    @Test fun `duplicate async callback completes once`() {
        val controller = FakeController().apply { duplicatePreferenceCallback = true }
        val result = RecordingResult()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.APPLY_PREFERENCES, mapOf("preferences" to preferencesMap()), result)
        assertEquals(1, result.values.size)
    }

    @Test fun `controller exception maps typed error`() {
        val controller = FakeController().apply { throwOnNext = true }
        val result = RecordingResult()
        core(controller).onCommand(ReadiumPlatformViewBridgeProtocol.NEXT, null, result)
        assertEquals("controller_failure", (((result.values.single() as Map<*, *>) ["error"] as Map<*, *>) ["code"]))
    }

    @Test fun `state event has instance and monotonic sequence`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator()
        val core = core(FakeController(), coordinator)
        val sink = RecordingSink()
        core.onListen(null, sink)
        coordinator.emit(ReadiumPlatformViewReaderState.InitializationStarted)
        coordinator.emit(ReadiumPlatformViewReaderState.NavigatorReady)
        val sequences = sink.events.map { it["sequence"] as Long }
        assertTrue(sequences.zipWithNext().all { it.first < it.second })
        assertTrue(sink.events.all { it["instanceId"] == "reader" })
    }

    private fun core(controller: FakeController, coordinator: ReadiumPlatformViewHostListenerCoordinator = ReadiumPlatformViewHostListenerCoordinator(), locatorParser: (String) -> Result<Locator> = ReadiumBridgeLocatorMapper::parse) =
        ReadiumPlatformViewBridgeCore(
            configuration = config(),
            controller = controller,
            eventHub = ReadiumPlatformViewEventHub(coordinator),
            scope = CoroutineScope(Dispatchers.Unconfined),
            parseDispatcher = Dispatchers.Unconfined,
            mainDispatcher = Dispatchers.Unconfined,
            locatorParser = locatorParser,
        )

    private fun config() = ReadiumPlatformViewOpenConfiguration("reader", "book", "/book.epub", null, ReaderPreferencesPayload(), false, false)
    private fun locatorJson() = "{\"href\":\"chapter.xhtml\",\"type\":\"application/xhtml+xml\",\"locations\":{\"progression\":0.25,\"position\":2}}"
    private fun preferencesMap() = mapOf(
        "theme" to "dark",
        "fontFamily" to "serif",
        "fontSize" to 1.2,
        "fontWeight" to 1.1,
        "lineHeight" to 1.6,
        "pageMargins" to 1.0,
        "textAlignment" to "justify",
        "scroll" to true,
        "columns" to "two",
        "publisherStyles" to false,
    )
    private fun styleMap() = mapOf("type" to "highlight", "tint" to 0x00FF00, "active" to true)
    private fun decorationMap() = mapOf("id" to "highlight-1", "locatorJson" to locatorJson(), "style" to styleMap())
    private fun testLocator(): Locator {
        val unsafeField = Class.forName("sun.misc.Unsafe").getDeclaredField("theUnsafe").apply { isAccessible = true }
        val unsafe = unsafeField.get(null)
        val allocate = unsafe.javaClass.getMethod("allocateInstance", Class::class.java)
        return allocate.invoke(unsafe, Locator::class.java) as Locator
    }

    private class RecordingResult : ReadiumBridgeCommandResult {
        val values = mutableListOf<Any?>()
        override fun success(value: Any?) { values += value }
    }

    private class RecordingSink : ReadiumBridgeEventSink {
        val events = mutableListOf<Map<String, Any?>>()
        override fun success(event: Map<String, Any?>) { events += event }
    }

    private class RecordingListener : ReadiumPlatformViewHostListener {
        val states = mutableListOf<ReadiumPlatformViewReaderState>()
        override fun onStateChanged(state: ReadiumPlatformViewReaderState) { states += state }
    }

    private class FakeController : ReadiumPlatformViewController {
        var originNavigationCount = 0
        var lastOriginLocator: Locator? = null
        var lastOriginIndex: Int? = null
        override fun goToProgressLocator(locator: Locator, progression: Double, owner: ProgressNavigationOwner,
            readingOrderIndex: Int?, onComplete: (ReadiumPlatformViewNavigationResult) -> Unit) {
            originNavigationCount++; lastOriginLocator = locator; lastOriginIndex = readingOrderIndex
            lastProgressOwner = owner; onComplete(navigationResult)
        }
        var commandCount = 0
        var nextCount = 0
        var previousCount = 0
        var progressionCount = 0
        var lastProgression: Double? = null
        var lastProgressOwner: ProgressNavigationOwner? = null
        var reservedFinalOwner: ProgressNavigationOwner? = null
        var settingsPreviewCutoff = 0L
        var locatorCount = 0
        var preferenceCount = 0
        var tocLoadCount = 0
        var searchCount = 0
        var clearSearchCount = 0
        var decorationCount = 0
        var lastQuery: String? = null
        var lastTocId: String? = null
        var lastSearchResultId: String? = null
        var lastDecorationId: String? = null
        var lastGroup: ReadiumDecorationGroup? = null
        var lastPreferences: EpubPreferences? = null
        var navigationResult: ReadiumPlatformViewNavigationResult = ReadiumPlatformViewNavigationResult.Completed
        var duplicatePreferenceCallback = false
        var throwOnNext = false

        override val isNavigatorReady = true
        override fun selectionState() = ReadiumSelectionState(ReadiumSelectionStatus.INACTIVE, null, null, 0, 0, null, false, null)
        override fun onNativeSelectionSessionStarted(nativeSessionId: Long) = null
        override fun onNativeSelectionSessionEnded(nativeSessionId: Long) = false
        override fun requestCurrentSelection(onComplete: (ReadiumSelectionRequestResult) -> Unit, refreshAfterInFlight: Boolean) = ReadiumSelectionRequestResult.NotActive
        override fun clearSelection() = ReadiumSelectionClearResult.NotActive
        override fun onViewportEpochChanged(epoch: Long) = Unit
        override fun position() = null
        override fun preferences() = ReadiumPlatformViewPreferenceState(null, null, 0, false)
        override fun currentChapter() = ReadiumChapterState.Unknown
        override fun tocState() = ReadiumTocState.NotLoaded
        override fun searchState() = EpubSearchState.Idle
        override fun decorationState(group: ReadiumDecorationGroup) = ReadiumReaderDecorationState(0, 0, 0, false, true, false, false)
        override fun next(animated: Boolean): ReadiumPlatformViewNavigationResult { commandCount++; nextCount++; if (throwOnNext) error("boom"); return navigationResult }
        override fun previous(animated: Boolean) = navigationResult.also { commandCount++; previousCount++ }
        override fun goToProgression(progression: Double, animated: Boolean, onComplete: (ReadiumPlatformViewNavigationResult) -> Unit) { commandCount++; progressionCount++; lastProgression = progression; onComplete(navigationResult) }
        override fun goToProgression(progression: Double, animated: Boolean, progressOwner: ProgressNavigationOwner?, onComplete: (ReadiumPlatformViewNavigationResult) -> Unit) { lastProgressOwner = progressOwner; goToProgression(progression, animated, onComplete) }
        override fun openProgressScrubSession(sessionId: Long) = true
        override fun invalidateProgressScrubSession(sessionId: Long) = true
        override fun reserveProgressScrubFinal(owner: ProgressNavigationOwner): Boolean { reservedFinalOwner = owner; return true }
        override fun supersedeSettingsPreviewsBefore(requestId: Long): Boolean {
            if (requestId <= settingsPreviewCutoff) return false
            settingsPreviewCutoff = requestId
            return true
        }
        val gestureCommands = mutableListOf<String>()
        override fun settingsReflowGesture(id: Long, slider: String, action: String, value: Double, onComplete: (Boolean) -> Unit) {
            gestureCommands += "$id:$slider:$action:$value"
            onComplete(true)
        }
        override fun search(query: String) { commandCount++; searchCount++; lastQuery = query }
        override fun loadNextSearchPage() = Unit
        override fun retrySearch() = Unit
        override fun clearSearch() { commandCount++; clearSearchCount++ }
        override fun goToSearchResult(resultId: String, animated: Boolean): ReadiumPlatformViewSearchNavigationResult { commandCount++; lastSearchResultId = resultId; return ReadiumPlatformViewSearchNavigationResult.Completed }
        override fun setPersistentHighlights(decorations: List<ReadiumDecorationSpec>, onComplete: (ReadiumPlatformViewDecorationResult) -> Unit) = onComplete(ReadiumPlatformViewDecorationResult.Applied)
        override fun setSearchDecoration(locator: Locator, tint: Int, onComplete: (ReadiumPlatformViewDecorationResult) -> Unit) = onComplete(ReadiumPlatformViewDecorationResult.Applied)
        override fun clearSearchDecoration(onComplete: (ReadiumPlatformViewDecorationResult) -> Unit) = onComplete(ReadiumPlatformViewDecorationResult.Applied)
        override fun setDecorations(group: ReadiumDecorationGroup, decorations: List<ReadiumDecorationSpec>, onComplete: (ReadiumPlatformViewDecorationResult) -> Unit) { decorationCount++; lastGroup = group; onComplete(ReadiumPlatformViewDecorationResult.Applied) }
        override fun upsertDecoration(group: ReadiumDecorationGroup, decoration: ReadiumDecorationSpec, onComplete: (ReadiumPlatformViewDecorationResult) -> Unit) { decorationCount++; lastGroup = group; onComplete(ReadiumPlatformViewDecorationResult.Applied) }
        override fun removeDecoration(group: ReadiumDecorationGroup, id: String, onComplete: (ReadiumPlatformViewDecorationResult) -> Unit) { decorationCount++; lastGroup = group; lastDecorationId = id; onComplete(ReadiumPlatformViewDecorationResult.Applied) }
        override fun clearDecorations(group: ReadiumDecorationGroup, onComplete: (ReadiumPlatformViewDecorationResult) -> Unit) { decorationCount++; lastGroup = group; onComplete(ReadiumPlatformViewDecorationResult.Applied) }
        override fun applyPreferences(preferences: EpubPreferences, onComplete: (ReadiumPlatformViewPreferenceResult) -> Unit) { commandCount++; preferenceCount++; lastPreferences = preferences; onComplete(ReadiumPlatformViewPreferenceResult.Applied); if (duplicatePreferenceCallback) onComplete(ReadiumPlatformViewPreferenceResult.Applied) }
        override fun applyPreferencesPayload(preferences: ReaderPreferencesPayload, isNightMode: Boolean, onComplete: (ReadiumPlatformViewPreferenceResult) -> Unit) { commandCount++; preferenceCount++; onComplete(ReadiumPlatformViewPreferenceResult.Applied); if (duplicatePreferenceCallback) onComplete(ReadiumPlatformViewPreferenceResult.Applied) }
        override fun goTo(locator: Locator, animated: Boolean): ReadiumPlatformViewNavigationResult { commandCount++; locatorCount++; return navigationResult }
        override fun goToTocEntry(entryId: String, animated: Boolean): ReadiumPlatformViewNavigationResult { commandCount++; lastTocId = entryId; return navigationResult }
        override fun loadProgressTargets(onComplete: (Result<List<ProgressNavigationTarget>>) -> Unit) = onComplete(Result.success(emptyList()))
    }
}
