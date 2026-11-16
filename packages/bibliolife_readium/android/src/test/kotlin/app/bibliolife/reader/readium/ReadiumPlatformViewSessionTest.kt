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

/** Block 2C JVM coverage for the typed session boundary and ownership seams. */
class ReadiumPlatformViewSessionTest {
    @Test fun `config round trips required identity`() {
        val config = config()
        val parsed = ReadiumPlatformViewOpenConfiguration.parse(config.toMap()).getOrThrow()
        assertEquals(config, parsed)
    }

    @Test fun `config preserves optional locator`() = assertEquals("{locator}", ReadiumPlatformViewOpenConfiguration.parse(config().toMap()).getOrThrow().initialLocatorJson)
    @Test fun `config preserves authoritative preferences`() = assertTrue(ReadiumPlatformViewOpenConfiguration.parse(config().toMap()).getOrThrow().initialPreferencesAreAuthoritative)
    @Test fun `config preserves night mode`() = assertTrue(ReadiumPlatformViewOpenConfiguration.parse(config().toMap()).getOrThrow().isNightMode)
    @Test fun `config trims instance id`() = assertEquals("reader", ReadiumPlatformViewOpenConfiguration.parse(config(instanceId = " reader ").toMap()).getOrThrow().instanceId)
    @Test fun `config trims book id`() = assertEquals("book", ReadiumPlatformViewOpenConfiguration.parse(config(bookId = " book ").toMap()).getOrThrow().bookId)
    @Test fun `config trims file path`() = assertEquals("/tmp/book.epub", ReadiumPlatformViewOpenConfiguration.parse(config(localFilePath = " /tmp/book.epub ").toMap()).getOrThrow().localFilePath)
    @Test fun `config rejects null payload`() = assertCode("invalid_open_configuration") { ReadiumPlatformViewOpenConfiguration.parse(null).getOrThrow() }
    @Test fun `config rejects scalar payload`() = assertCode("invalid_open_configuration") { ReadiumPlatformViewOpenConfiguration.parse("book").getOrThrow() }
    @Test fun `config rejects list payload`() = assertCode("invalid_open_configuration") { ReadiumPlatformViewOpenConfiguration.parse(listOf("book")).getOrThrow() }
    @Test fun `config rejects missing instance id`() = assertCode("missing_instance_id") { ReadiumPlatformViewOpenConfiguration.parse(mapOf("bookId" to "b", "localFilePath" to "/b")).getOrThrow() }
    @Test fun `config rejects numeric instance id`() = assertCode("missing_instance_id") { ReadiumPlatformViewOpenConfiguration.parse(mapOf("instanceId" to 1, "bookId" to "b", "localFilePath" to "/b")).getOrThrow() }
    @Test fun `config rejects blank instance id`() = assertCode("invalid_instance_id") { ReadiumPlatformViewOpenConfiguration.parse(config(instanceId = " ").toMap()).getOrThrow() }
    @Test fun `config rejects missing book id`() = assertCode("missing_book_id") { ReadiumPlatformViewOpenConfiguration.parse(mapOf("instanceId" to "r", "localFilePath" to "/b")).getOrThrow() }
    @Test fun `config rejects blank book id`() = assertCode("missing_book_id") { ReadiumPlatformViewOpenConfiguration.parse(config(bookId = " ").toMap()).getOrThrow() }
    @Test fun `config rejects missing file path`() = assertCode("missing_file_path") { ReadiumPlatformViewOpenConfiguration.parse(mapOf("instanceId" to "r", "bookId" to "b")).getOrThrow() }
    @Test fun `config rejects blank file path`() = assertCode("missing_file_path") { ReadiumPlatformViewOpenConfiguration.parse(config(localFilePath = " ").toMap()).getOrThrow() }
    @Test fun `config accepts absent optional locator`() = assertNull(ReadiumPlatformViewOpenConfiguration.parse(config().toMap() - "initialLocatorJson").getOrThrow().initialLocatorJson)
    @Test fun `config ignores unknown codec fields`() = assertEquals("book", ReadiumPlatformViewOpenConfiguration.parse(config().toMap() + ("future" to 7)).getOrThrow().bookId)
    @Test fun `config defaults malformed preference payload`() = assertEquals(ReaderPreferencesPayload(), ReadiumPlatformViewOpenConfiguration.parse(config().toMap() + ("initialPreferences" to 7)).getOrThrow().initialPreferences)
    @Test fun `config defaults absent authoritative flag`() = assertFalse(ReadiumPlatformViewOpenConfiguration.parse(config().toMap() - "initialPreferencesAreAuthoritative").getOrThrow().initialPreferencesAreAuthoritative)
    @Test fun `config defaults absent night flag`() = assertFalse(ReadiumPlatformViewOpenConfiguration.parse(config().toMap() - "isNightMode").getOrThrow().isNightMode)
    @Test fun `config validates direct value`() = assertEquals("missing_book_id", config(bookId = " ").validate()?.failureCode)
    @Test fun `config toMap contains instance id`() = assertEquals("reader", config().toMap()["instanceId"])
    @Test fun `config toMap contains book id`() = assertEquals("book", config().toMap()["bookId"])
    @Test fun `config toMap contains local path`() = assertEquals("/book.epub", config().toMap()["localFilePath"])
    @Test fun `config toMap contains preference map`() = assertTrue(config().toMap()["initialPreferences"] is Map<*, *>)
    @Test fun `config is immutable data value`() = assertEquals(config(), config())

    @Test fun `owner factory creates once`() {
        var created = 0
        val owner = fakeOwner({ created++; FakeSession() })
        assertNotNull(owner.createOnce()); assertNotNull(owner.createOnce()); assertEquals(1, created)
    }
    @Test fun `owner returns same session`() {
        val owner = fakeOwner(); assertSame(owner.createOnce(), owner.createOnce())
    }
    @Test fun `owner initializes once`() {
        var initialized = 0
        val owner = fakeOwner(initialize = { initialized++ })
        owner.initializeOnce(); owner.initializeOnce(); assertEquals(1, initialized)
    }
    @Test fun `owner initializes created session`() {
        var seen: FakeSession? = null
        val owner = fakeOwner(initialize = { seen = it }); owner.initializeOnce(); assertNotNull(seen)
    }
    @Test fun `owner disposal calls callback once`() {
        var disposed = 0
        val owner = fakeOwner(dispose = { _, _ -> disposed++ }); owner.createOnce(); owner.disposeOnce(); owner.disposeOnce(); assertEquals(1, disposed)
    }
    @Test fun `owner forwards retain flag`() {
        var retain = false
        val owner = fakeOwner(dispose = { _, value -> retain = value }); owner.createOnce(); owner.disposeOnce(true); assertTrue(retain)
    }
    @Test fun `owner disposal before create is harmless`() {
        val owner = fakeOwner(); owner.disposeOnce(); assertFalse(owner.hasSession())
    }
    @Test fun `owner refuses create after disposal`() {
        val owner = fakeOwner(); owner.disposeOnce(); assertNull(owner.createOnce())
    }
    @Test fun `owner refuses initialize after disposal`() {
        var initialized = 0
        val owner = fakeOwner(initialize = { initialized++ }); owner.disposeOnce(); owner.initializeOnce(); assertEquals(0, initialized)
    }
    @Test fun `owner marks disposed`() {
        val owner = fakeOwner(); assertFalse(owner.isDisposed()); owner.disposeOnce(); assertTrue(owner.isDisposed())
    }
    @Test fun `owner retains session until disposal`() {
        val owner = fakeOwner(); owner.createOnce(); assertTrue(owner.hasSession()); owner.disposeOnce(); assertFalse(owner.hasSession())
    }
    @Test fun `owner creates after initialize request`() {
        val owner = fakeOwner(); owner.initializeOnce(); assertTrue(owner.hasSession())
    }
    @Test fun `owner initialize callback receives only session`() {
        var count = 0
        val owner = fakeOwner(initialize = { count++ }); owner.initializeOnce(); assertEquals(1, count)
    }
    @Test fun `owner repeated disposal keeps disposed state`() {
        val owner = fakeOwner(); owner.disposeOnce(); owner.disposeOnce(true); assertTrue(owner.isDisposed())
    }
    @Test fun `owner disposal callback receives false by default`() {
        var retain = true
        val owner = fakeOwner(dispose = { _, value -> retain = value }); owner.createOnce(); owner.disposeOnce(); assertFalse(retain)
    }
    @Test fun `route reopen creates a fresh owner and fresh session`() {
        val firstOwner = fakeOwner()
        firstOwner.initializeOnce()
        val firstSession = firstOwner.createOnce()
        firstOwner.disposeOnce()

        val reopenedOwner = fakeOwner()
        reopenedOwner.initializeOnce()
        val reopenedSession = reopenedOwner.createOnce()

        assertTrue(firstOwner.isDisposed())
        assertFalse(reopenedOwner.isDisposed())
        assertFalse(firstSession === reopenedSession)
        assertTrue(reopenedOwner.hasSession())
    }

    @Test fun `listener coordinator starts unbound`() { assertNotNull(ReadiumPlatformViewHostListenerCoordinator().bind(RecordingListener())) }
    @Test fun `listener coordinator binds one listener`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator(); assertNotNull(coordinator.bind(RecordingListener()))
    }
    @Test fun `listener coordinator rejects second listener`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator(); coordinator.bind(RecordingListener()); assertNull(coordinator.bind(RecordingListener()))
    }
    @Test fun `listener coordinator emits state`() {
        val listener = RecordingListener(); val coordinator = ReadiumPlatformViewHostListenerCoordinator(); coordinator.bind(listener); coordinator.emit(ReadiumPlatformViewReaderState.InitializationStarted); assertEquals(1, listener.states.size)
    }
    @Test fun `listener coordinator stores latest state`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator(); coordinator.emit(ReadiumPlatformViewReaderState.NavigatorReady); val listener = RecordingListener(); coordinator.bind(listener); assertEquals(ReadiumPlatformViewReaderState.NavigatorReady, listener.states.single())
    }
    @Test fun `listener coordinator replays newest state only`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator(); coordinator.emit(ReadiumPlatformViewReaderState.InitializationStarted); coordinator.emit(ReadiumPlatformViewReaderState.NavigatorReady); val listener = RecordingListener(); coordinator.bind(listener); assertEquals(1, listener.states.size)
    }
    @Test fun `listener coordinator rejects stale token`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator(); val token = coordinator.bind(RecordingListener())!!; coordinator.unbind(token); assertFalse(coordinator.unbind(token))
    }
    @Test fun `listener coordinator unbinds current token`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator(); val token = coordinator.bind(RecordingListener())!!; assertTrue(coordinator.unbind(token))
    }
    @Test fun `listener coordinator accepts rebind after unbind`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator(); val first = coordinator.bind(RecordingListener())!!; coordinator.unbind(first); assertNotNull(coordinator.bind(RecordingListener()))
    }
    @Test fun `listener coordinator old token cannot remove rebound listener`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator(); val first = coordinator.bind(RecordingListener())!!; coordinator.unbind(first); coordinator.bind(RecordingListener()); assertFalse(coordinator.unbind(first))
    }
    @Test fun `listener coordinator unbound listener stops receiving`() {
        val listener = RecordingListener(); val coordinator = ReadiumPlatformViewHostListenerCoordinator(); val token = coordinator.bind(listener)!!; coordinator.unbind(token); coordinator.emit(ReadiumPlatformViewReaderState.NavigatorReady); assertTrue(listener.states.isEmpty())
    }
    @Test fun `listener coordinator disposed rejects bind`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator(); coordinator.dispose(); assertNull(coordinator.bind(RecordingListener()))
    }
    @Test fun `listener coordinator disposed rejects unbind`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator(); val token = coordinator.bind(RecordingListener())!!; coordinator.dispose(); assertFalse(coordinator.unbind(token))
    }
    @Test fun `listener coordinator disposed stops state`() {
        val listener = RecordingListener(); val coordinator = ReadiumPlatformViewHostListenerCoordinator(); coordinator.bind(listener); coordinator.dispose(); coordinator.emit(ReadiumPlatformViewReaderState.NavigatorReady); assertTrue(listener.states.isEmpty())
    }
    @Test fun `listener coordinator fatal reaches listener`() {
        val listener = RecordingListener(); val coordinator = ReadiumPlatformViewHostListenerCoordinator(); coordinator.bind(listener); coordinator.emitFatal(ReadiumPlatformViewError("session_disposed")); assertEquals("session_disposed", listener.fatal?.code)
    }
    @Test fun `listener coordinator recoverable reaches listener`() {
        val listener = RecordingListener(); val coordinator = ReadiumPlatformViewHostListenerCoordinator(); coordinator.bind(listener); coordinator.emitRecoverable(ReadiumPlatformViewError("session_disposed")); assertEquals("session_disposed", listener.recoverable?.code)
    }
    @Test fun `listener coordinator fatal is dropped after disposal`() {
        val listener = RecordingListener(); val coordinator = ReadiumPlatformViewHostListenerCoordinator(); coordinator.bind(listener); coordinator.dispose(); coordinator.emitFatal(ReadiumPlatformViewError("session_disposed")); assertNull(listener.fatal)
    }
    @Test fun `listener coordinator recoverable is dropped after disposal`() {
        val listener = RecordingListener(); val coordinator = ReadiumPlatformViewHostListenerCoordinator(); coordinator.bind(listener); coordinator.dispose(); coordinator.emitRecoverable(ReadiumPlatformViewError("session_disposed")); assertNull(listener.recoverable)
    }
    @Test fun `listener coordinator token generations advance`() {
        val coordinator = ReadiumPlatformViewHostListenerCoordinator(); val first = coordinator.bind(RecordingListener())!!; coordinator.unbind(first); val second = coordinator.bind(RecordingListener())!!; assertTrue(second.generation > first.generation)
    }

    @Test fun `controller reports disposed selection`() = assertEquals(ReadiumSelectionStatus.DISPOSED, controller().selectionState().status)
    @Test fun `controller reports navigator unavailable after disposal`() = assertFalse(controller().isNavigatorReady)
    @Test fun `controller returns disposed navigation`() = assertEquals(ReadiumPlatformViewNavigationResult.SessionDisposed, controller().goToTocEntry("entry"))
    @Test fun `controller returns disposed search navigation`() = assertEquals(ReadiumPlatformViewSearchNavigationResult.SessionDisposed, controller().goToSearchResult("result"))
    @Test fun `controller returns disposed clear selection`() = assertEquals(ReadiumSelectionClearResult.Disposed, controller().clearSelection())
    @Test fun `controller returns stale selection request`() = assertEquals(ReadiumSelectionRequestResult.Stale, controller().requestCurrentSelection())
    @Test fun `controller returns no position`() = assertNull(controller().position())
    @Test fun `controller returns empty preferences`() = assertEquals(0L, controller().preferences().generation)
    @Test fun `controller returns unloaded toc`() = assertEquals(ReadiumTocState.NotLoaded, controller().tocState())
    @Test fun `controller forwards no-op search safely`() { val value = controller(); value.search("q"); value.loadNextSearchPage(); value.retrySearch(); value.clearSearch() }
    @Test fun `controller returns disposed decoration`() {
        var result: ReadiumPlatformViewDecorationResult? = null; controller().clearSearchDecoration { result = it }; assertEquals(ReadiumPlatformViewDecorationResult.SessionDisposed, result)
    }
    @Test fun `controller returns disposed preference`() {
        var result: ReadiumPlatformViewPreferenceResult? = null; controller().applyPreferences(org.readium.r2.navigator.epub.EpubPreferences()) { result = it }; assertEquals(ReadiumPlatformViewPreferenceResult.SessionDisposed, result)
    }
    @Test fun `position preservation failure remains an explicit native failure`() = assertEquals(
        ReadiumPlatformViewPreferenceResult.Failed,
        ReadiumReaderSession.PreferenceResult.PositionPreservationFailed("semantic_restore_failed").toPlatformResult(),
    )
    @Test fun `initial viewport readiness failure remains a terminal native error`() = assertEquals(
        "initial_viewport_readiness_failed",
        ReadiumReaderSession.Error.InitialViewportReadinessFailed("readiness_timeout").toPlatformError().code,
    )
    @Test fun `controller progress reports missing session`() {
        var result: Result<List<ProgressNavigationTarget>>? = null; controller().loadProgressTargets { result = it }; assertTrue(result?.isFailure == true)
    }
    @Test fun `controller accepts viewport command after disposal`() { controller().onViewportEpochChanged(4) }
    @Test fun `controller accepts native selection end after disposal`() = assertFalse(controller().onNativeSelectionSessionEnded(4))
    @Test fun `controller native selection start after disposal is null`() = assertNull(controller().onNativeSelectionSessionStarted(4))
    @Test fun `controller persistent decoration reports disposed`() {
        var result: ReadiumPlatformViewDecorationResult? = null; controller().setPersistentHighlights(emptyList()) { result = it }; assertEquals(ReadiumPlatformViewDecorationResult.SessionDisposed, result)
    }
    private fun config(
        instanceId: String = "reader",
        bookId: String = "book",
        localFilePath: String = "/book.epub",
    ) = ReadiumPlatformViewOpenConfiguration(
        instanceId = instanceId,
        bookId = bookId,
        localFilePath = localFilePath,
        initialLocatorJson = "{locator}",
        initialPreferences = ReaderPreferencesPayload(theme = "dark", fontSize = 1.1),
        initialPreferencesAreAuthoritative = true,
        isNightMode = true,
    )

    private fun controller() = ReadiumPlatformViewControllerImpl(
        sessionProvider = { null },
        scope = CoroutineScope(Dispatchers.Unconfined),
        isDisposed = { true },
    )

    private fun fakeOwner(
        factory: () -> FakeSession = { FakeSession() },
        initialize: (FakeSession) -> Unit = {},
        dispose: (FakeSession, Boolean) -> Unit = { _, _ -> },
    ) = ReadiumPlatformViewSessionOwner(factory, initialize, dispose)

    private class FakeSession

    private class RecordingListener : ReadiumPlatformViewHostListener {
        val states = mutableListOf<ReadiumPlatformViewReaderState>()
        var fatal: ReadiumPlatformViewError? = null
        var recoverable: ReadiumPlatformViewError? = null
        override fun onStateChanged(state: ReadiumPlatformViewReaderState) { states += state }
        override fun onFatalError(error: ReadiumPlatformViewError) { fatal = error }
        override fun onRecoverableError(error: ReadiumPlatformViewError) { recoverable = error }
    }

    private fun assertCode(expected: String, block: () -> Unit) {
        val error = runCatching(block).exceptionOrNull()
        assertTrue(error is ReadiumPlatformViewCreationException)
        assertEquals(expected, (error as ReadiumPlatformViewCreationException).failureCode)
    }
}
