package app.bibliolife.reader.readium

import androidx.fragment.app.FragmentActivity
import java.io.File
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.publication.*
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class ProgressPositionPublicationOutcomeTest {
    @Test fun `published and deduped both acknowledge success without duplicate event or failure`() {
        val fixture = Fixture()
        try {
            fixture.emit()
            assertEquals(listOf("published"), fixture.outcomes())
            assertEquals(1, fixture.positionEvents)
            assertEquals(1, fixture.completions)
            fixture.emit()
            assertEquals(listOf("published", "deduped"), fixture.outcomes())
            assertEquals(1, fixture.positionEvents)
            assertEquals(2, fixture.completions)
        } finally { fixture.close() }
    }

    @Test fun `rejected canonical publication never acknowledges success`() {
        val fixture = Fixture(continuous = true)
        try {
            // No current continuous context/rendition: canonical publication is rejected.
            fixture.emit()
            assertEquals(listOf("failed"), fixture.outcomes())
            assertEquals(0, fixture.positionEvents)
            assertEquals(0, fixture.completions)
        } finally { fixture.close() }
    }

    @Test fun `delivery exception produces failure without a prior published result`() {
        val fixture = Fixture(failDelivery = true)
        try {
            fixture.emit()
            assertEquals(listOf("failed"), fixture.outcomes())
            assertEquals(0, fixture.completions)
        } finally { fixture.close() }
    }

    private class Fixture(continuous: Boolean = false, failDelivery: Boolean = false) {
        val activity = Robolectric.buildActivity(FragmentActivity::class.java).setup()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val fields = mutableListOf<Map<String, Any?>>()
        var positionEvents = 0
        var completions = 0
        val owner = ProgressNavigationOwner(1, 1, ProgressNavigationOwner.Phase.PREVIEW)
        val session = ReadiumReaderSession(
            context = activity.get(), fragmentManager = activity.get().supportFragmentManager,
            scope = scope, classLoader = javaClass.classLoader!!, file = File("unused.epub"),
            initialLocatorJson = null, initialPreferences = EpubPreferences(),
            initialPreferencesAreAuthoritative = false,
            navigatorConfiguration = EpubNavigatorFragment.Configuration(),
            renditionBackend = if (continuous) ReadiumEpubRenditionBackend.CONTINUOUS_EXPERIMENTAL else ReadiumEpubRenditionBackend.LEGACY,
            listener = object : ReadiumReaderSession.Listener {
                override fun onStateChanged(state: ReadiumReaderSession.State) {
                    if (state is ReadiumReaderSession.State.Diagnostic) fields += state.fields
                    if (state is ReadiumReaderSession.State.PositionChanged) {
                        if (failDelivery) error("delivery failed")
                        positionEvents++
                    }
                }
                override fun onNavigatorReady(publication: Publication, navigator: EpubNavigatorFragment) = Unit
                override fun onFatalError(error: ReadiumReaderSession.Error) = Unit
            },
        )
        init {
            session.openProgressScrubSession(1)
            val field = ReadiumReaderSession::class.java.getDeclaredField("progressScrubOwnership").apply { isAccessible = true }
            assertTrue((field.get(session) as ProgressScrubOwnership).reserve(owner))
        }
        val position = ReadiumPositionState(
            Locator(href = Url("chapter.xhtml")!!, mediaType = MediaType.XHTML,
                locations = Locator.Locations(progression = .5, totalProgression = .5)), .5,
        )
        fun emit() {
            val before = completions
            try {
                val method = ReadiumReaderSession::class.java.declaredMethods.single { it.name == "emitPosition" }
                method.isAccessible = true
                method.invoke(session, position, null, null, false, null, null, null, owner,
                    { completions++; Unit })
            } catch (_: java.lang.reflect.InvocationTargetException) {
                // Same failure classification as the continuous locator caller.
            } finally {
                if (before == completions) fields += mapOf("kind" to "progress_position_publication", "result" to "failed")
            }
        }
        fun outcomes() = fields.filter { it["kind"] == "progress_position_publication" }.map { it["result"] }
        fun close() { scope.cancel(); activity.pause().stop().destroy() }
    }
}
