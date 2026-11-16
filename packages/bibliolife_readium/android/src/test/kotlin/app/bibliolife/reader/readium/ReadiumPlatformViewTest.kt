package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import io.flutter.plugin.platform.PlatformView

/** Pure JVM contract coverage for the Block 2B PlatformView boundary. */
class ReadiumPlatformViewTest {
    // Activity/provider lifecycle: every attach/detach advances the generation.
    @Test fun `dependency lifecycle starts detached`() {
        val lifecycle = ReadiumActivityDependencyLifecycle()
        assertEquals(ReadiumActivityDependencyStatus.DETACHED, lifecycle.status)
        assertEquals(0L, lifecycle.generation)
    }

    @Test fun `compatible attach is observable`() {
        val lifecycle = ReadiumActivityDependencyLifecycle()
        assertEquals(1L, lifecycle.attach(true))
        assertEquals(ReadiumActivityDependencyStatus.ATTACHED_COMPATIBLE, lifecycle.status)
    }

    @Test fun `incompatible attach is observable`() {
        val lifecycle = ReadiumActivityDependencyLifecycle()
        lifecycle.attach(false)
        assertEquals(ReadiumActivityDependencyStatus.ATTACHED_INCOMPATIBLE, lifecycle.status)
    }

    @Test fun `detach clears compatible state`() {
        val lifecycle = ReadiumActivityDependencyLifecycle()
        lifecycle.attach(true)
        lifecycle.detach()
        assertEquals(ReadiumActivityDependencyStatus.DETACHED, lifecycle.status)
    }

    @Test fun `config detach advances generation`() {
        val lifecycle = ReadiumActivityDependencyLifecycle()
        lifecycle.attach(true)
        assertEquals(2L, lifecycle.detach())
    }

    @Test fun `reattach receives a new generation`() {
        val lifecycle = ReadiumActivityDependencyLifecycle()
        lifecycle.attach(true)
        lifecycle.detach()
        assertEquals(3L, lifecycle.attach(true))
    }

    @Test fun `compatible generation validates`() {
        val lifecycle = ReadiumActivityDependencyLifecycle()
        val generation = lifecycle.attach(true)
        assertTrue(lifecycle.isCurrentCompatible(generation))
    }

    @Test fun `stale generation is rejected`() {
        val lifecycle = ReadiumActivityDependencyLifecycle()
        val generation = lifecycle.attach(true)
        lifecycle.detach()
        assertFalse(lifecycle.isCurrentCompatible(generation))
    }

    @Test fun `incompatible generation is rejected`() {
        val lifecycle = ReadiumActivityDependencyLifecycle()
        val generation = lifecycle.attach(false)
        assertFalse(lifecycle.isCurrentCompatible(generation))
    }

    @Test fun `detached generation is rejected`() {
        val lifecycle = ReadiumActivityDependencyLifecycle()
        lifecycle.attach(true)
        val generation = lifecycle.detach()
        assertFalse(lifecycle.isCurrentCompatible(generation))
    }

    @Test fun `repeated detach remains detached`() {
        val lifecycle = ReadiumActivityDependencyLifecycle()
        lifecycle.detach()
        lifecycle.detach()
        assertEquals(ReadiumActivityDependencyStatus.DETACHED, lifecycle.status)
    }

    @Test fun `provider begins without dependencies`() {
        assertEquals(null, ReadiumActivityDependencyProvider().currentDependencies())
    }

    @Test fun `provider exposes detached status`() {
        assertEquals(ReadiumActivityDependencyStatus.DETACHED, ReadiumActivityDependencyProvider().status)
    }

    @Test fun `provider detach invalidates old generation`() {
        val lifecycle = ReadiumActivityDependencyLifecycle()
        val old = lifecycle.attach(true)
        lifecycle.detach()
        assertFalse(lifecycle.isCurrentCompatible(old))
    }

    // Owner lifecycle: temporary host detach is not disposal and disposal is exactly once.
    @Test fun `owner starts created`() {
        assertEquals(ReadiumPlatformViewOwnerState.CREATED, owner().state)
    }

    @Test fun `owner preserves identity metadata`() {
        val owner = owner()
        assertEquals("reader-1", owner.instanceId)
        assertEquals(9, owner.flutterViewId)
        assertEquals(3210, owner.hostContainerId)
    }

    @Test fun `owner attach transitions`() {
        val owner = owner()
        assertTrue(owner.onHostAttached())
        assertEquals(ReadiumPlatformViewOwnerState.ATTACHED, owner.state)
    }

    @Test fun `owner duplicate attach is ignored`() {
        val owner = owner()
        owner.onHostAttached()
        assertFalse(owner.onHostAttached())
    }

    @Test fun `owner detach transitions`() {
        val owner = owner()
        owner.onHostAttached()
        assertTrue(owner.onHostDetached())
        assertEquals(ReadiumPlatformViewOwnerState.DETACHED, owner.state)
    }

    @Test fun `owner detach before attach is ignored`() {
        assertFalse(owner().onHostDetached())
    }

    @Test fun `owner reattach after temporary detach`() {
        val owner = owner()
        owner.onHostAttached()
        owner.onHostDetached()
        assertTrue(owner.onHostAttached())
    }

    @Test fun `owner dispose transitions`() {
        val owner = owner()
        assertTrue(owner.dispose())
        assertEquals(ReadiumPlatformViewOwnerState.DISPOSED, owner.state)
    }

    @Test fun `owner dispose is idempotent`() {
        val owner = owner()
        owner.dispose()
        assertFalse(owner.dispose())
    }

    @Test fun `owner ignores attach after dispose`() {
        val owner = owner()
        owner.dispose()
        assertFalse(owner.onHostAttached())
    }

    @Test fun `owner ignores detach after dispose`() {
        val owner = owner()
        owner.dispose()
        assertFalse(owner.onHostDetached())
    }

    @Test fun `owner accepts matching activity generation`() {
        val owner = owner(generation = 4)
        assertTrue(owner.acceptsActivityGeneration(4))
    }

    @Test fun `owner rejects stale activity generation`() {
        val owner = owner(generation = 4)
        assertFalse(owner.acceptsActivityGeneration(3))
    }

    @Test fun `disposed owner rejects matching generation`() {
        val owner = owner(generation = 4)
        owner.dispose()
        assertFalse(owner.acceptsActivityGeneration(4))
    }

    @Test fun `owner can dispose from attached`() {
        val owner = owner()
        owner.onHostAttached()
        assertTrue(owner.dispose())
    }

    @Test fun `owner can dispose from detached`() {
        val owner = owner()
        owner.onHostAttached()
        owner.onHostDetached()
        assertTrue(owner.dispose())
    }

    @Test fun `independent owners dispose separately`() {
        val first = owner()
        val second = owner(generation = 2)
        first.dispose()
        assertEquals(ReadiumPlatformViewOwnerState.CREATED, second.state)
    }

    @Test fun `owner never creates a session`() {
        val owner = owner()
        owner.onHostAttached()
        assertEquals(ReadiumPlatformViewOwnerState.ATTACHED, owner.state)
    }

    @Test fun `owner keeps host id stable`() {
        val owner = owner()
        owner.onHostAttached()
        owner.onHostDetached()
        assertEquals(3210, owner.hostContainerId)
    }

    @Test fun `owner keeps instance id stable`() {
        val owner = owner()
        owner.onHostAttached()
        owner.dispose()
        assertEquals("reader-1", owner.instanceId)
    }

    // Integration/factory policy: only the complete open payload reaches production.
    @Test fun `factory policy parses the typed open configuration`() {
        val policy = ReadiumPlatformViewFactoryPolicy(ReadiumActivityDependencyProvider())
        assertEquals("reader-1", policy.parseOpenConfiguration(openConfiguration()).instanceId)
    }

    @Test fun `factory policy rejects malformed open payload`() = assertCode("invalid_open_configuration") {
        ReadiumPlatformViewFactoryPolicy(ReadiumActivityDependencyProvider()).parseOpenConfiguration(42)
    }

    @Test fun `factory policy rejects missing id`() = assertCode("missing_instance_id") {
        ReadiumPlatformViewFactoryPolicy(ReadiumActivityDependencyProvider()).parseOpenConfiguration(
            openConfiguration().minus("instanceId"),
        )
    }

    @Test fun `factory policy rejects blank id`() = assertCode("invalid_instance_id") {
        ReadiumPlatformViewFactoryPolicy(ReadiumActivityDependencyProvider()).parseOpenConfiguration(
            openConfiguration() + ("instanceId" to ""),
        )
    }

    @Test fun `factory policy reports unavailable activity`() = assertCode("activity_unavailable") {
        ReadiumPlatformViewFactoryPolicy(ReadiumActivityDependencyProvider()).requireDependencies()
    }

    @Test fun `factory has no fallback policy`() {
        assertCode("activity_unavailable") {
            ReadiumPlatformViewFactoryPolicy(ReadiumActivityDependencyProvider()).requireDependencies()
        }
    }

    @Test fun `platform dependencies carry activity generation`() {
        // The runtime holder is intentionally composed only from current FragmentActivity data.
        assertTrue(ReadiumPlatformViewDependencies::class.java.declaredFields.any { it.name == "activityGeneration" })
    }

    @Test fun `provider uses weak activity storage`() {
        assertTrue(ReadiumActivityDependencyProvider::class.java.declaredFields.any { it.type == java.lang.ref.WeakReference::class.java })
    }

    @Test fun `platform view exposes only host view contract`() {
        assertTrue(PlatformView::class.java.methods.any { it.name == "getView" })
    }

    @Test fun `platform view contract has no publication owner`() {
        assertFalse(ReadiumPlatformView::class.java.declaredFields.any { it.name.contains("publication", true) })
    }

    @Test fun `platform view contract has no navigator owner`() {
        assertFalse(ReadiumPlatformView::class.java.declaredFields.any { it.name == "navigator" })
    }

    @Test fun `platform view contract owns the session lifecycle`() {
        assertTrue(ReadiumPlatformView::class.java.declaredFields.any { it.name == "sessionOwner" })
    }

    @Test fun `factory is a platform view factory`() {
        assertTrue(io.flutter.plugin.platform.PlatformViewFactory::class.java.isAssignableFrom(ReadiumPlatformViewFactory::class.java))
    }

    @Test fun `creation exception is controlled`() {
        val exception = runCatching {
            ReadiumPlatformViewFactoryPolicy(ReadiumActivityDependencyProvider())
                .parseOpenConfiguration(emptyMap<String, Any?>())
        }.exceptionOrNull()
        assertTrue(exception is ReadiumPlatformViewCreationException)
    }

    @Test fun `creation exception does not expose paths`() {
        val exception = runCatching {
            ReadiumPlatformViewFactoryPolicy(ReadiumActivityDependencyProvider())
                .parseOpenConfiguration(emptyMap<String, Any?>())
        }.exceptionOrNull()
        assertFalse(exception?.message.orEmpty().contains("/"))
    }

    @Test fun `activity generation is monotonic`() {
        val lifecycle = ReadiumActivityDependencyLifecycle()
        val first = lifecycle.attach(true)
        val second = lifecycle.detach()
        assertTrue(second > first)
    }

    @Test fun `factory policy remains pure when provider detached`() {
        val provider = ReadiumActivityDependencyProvider()
        val policy = ReadiumPlatformViewFactoryPolicy(provider)
        assertEquals("reader-1", policy.parseOpenConfiguration(openConfiguration()).instanceId)
        assertCode("activity_unavailable") { policy.requireDependencies() }
    }

    private fun openConfiguration() = ReadiumPlatformViewOpenConfiguration(
        instanceId = "reader-1",
        bookId = "book-1",
        localFilePath = "book.epub",
        initialLocatorJson = null,
        initialPreferences = ReaderPreferencesPayload(),
        initialPreferencesAreAuthoritative = true,
        isNightMode = false,
    ).toMap()

    private fun owner(generation: Long = 1) = ReadiumPlatformViewOwnerCoordinator(
        instanceId = "reader-1",
        flutterViewId = 9,
        hostContainerId = 3210,
        activityGeneration = generation,
    )

    private fun assertCode(expected: String, block: () -> Unit) {
        try {
            block()
            fail("expected $expected")
        } catch (error: ReadiumPlatformViewCreationException) {
            assertEquals(expected, error.failureCode)
        }
    }
}
