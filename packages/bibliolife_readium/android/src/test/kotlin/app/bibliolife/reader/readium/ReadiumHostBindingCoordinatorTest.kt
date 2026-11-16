package app.bibliolife.reader.readium

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadiumHostBindingCoordinatorTest {
    @Test fun `first binding succeeds`() {
        val coordinator = coordinator()
        assertNotNull(coordinator.bind(RecordingBinding()))
        assertEquals(ReadiumHostAttachmentState.BOUND, coordinator.state)
    }

    @Test fun `duplicate identical binding is idempotent`() {
        val coordinator = coordinator()
        val binding = RecordingBinding()
        val first = coordinator.bind(binding)
        val duplicate = coordinator.bind(binding)
        assertNotNull(first)
        assertEquals(first, duplicate)
        assertEquals(ReadiumHostAttachmentState.BOUND, coordinator.state)
    }

    @Test fun `second active owner is rejected`() {
        val coordinator = coordinator()
        assertNotNull(coordinator.bind(RecordingBinding()))
        assertNull(coordinator.bind(RecordingBinding()))
    }

    @Test fun `attach is forwarded once`() {
        val coordinator = coordinator()
        val binding = RecordingBinding()
        coordinator.bind(binding)
        coordinator.onAttached()
        coordinator.onAttached()
        assertEquals(1, binding.attached)
        assertEquals(ReadiumHostAttachmentState.ATTACHED, coordinator.state)
    }

    @Test fun `binding after attach receives the current attach once`() {
        val coordinator = coordinator()
        coordinator.onAttached()
        val binding = RecordingBinding()
        coordinator.bind(binding)
        assertEquals(1, binding.attached)
    }

    @Test fun `layout is forwarded only with valid bounds`() {
        val coordinator = coordinator()
        val binding = RecordingBinding()
        coordinator.bind(binding)
        coordinator.onAttached()
        coordinator.onLaidOut(0, 10)
        coordinator.onLaidOut(100, 200)
        assertEquals(listOf(100 to 200), binding.layouts)
    }

    @Test fun `detach is forwarded once and is not disposal`() {
        val coordinator = coordinator()
        val binding = RecordingBinding()
        coordinator.bind(binding)
        coordinator.onAttached()
        coordinator.onDetached()
        coordinator.onDetached()
        assertEquals(1, binding.detached)
        assertEquals(0, binding.disposed)
        assertEquals(ReadiumHostAttachmentState.DETACHED, coordinator.state)
    }

    @Test fun `reattach after temporary detach is safe`() {
        val coordinator = coordinator()
        val binding = RecordingBinding()
        coordinator.bind(binding)
        coordinator.onAttached()
        coordinator.onDetached()
        coordinator.onAttached()
        assertEquals(2, binding.attached)
        assertEquals(1, binding.detached)
    }

    @Test fun `dispose is forwarded once`() {
        val coordinator = coordinator()
        val binding = RecordingBinding()
        coordinator.bind(binding)
        coordinator.dispose()
        coordinator.dispose()
        assertEquals(1, binding.disposed)
        assertEquals(ReadiumHostAttachmentState.DISPOSED, coordinator.state)
    }

    @Test fun `events after dispose are ignored`() {
        val coordinator = coordinator()
        val binding = RecordingBinding()
        coordinator.bind(binding)
        coordinator.dispose()
        coordinator.onAttached()
        coordinator.onLaidOut(100, 200)
        coordinator.onDetached()
        assertEquals(0, binding.attached)
        assertEquals(0, binding.detached)
        assertEquals(emptyList<Pair<Int, Int>>(), binding.layouts)
    }

    @Test fun `rebind after permanent disposal is rejected`() {
        val coordinator = coordinator()
        coordinator.dispose()
        assertNull(coordinator.bind(RecordingBinding()))
    }

    @Test fun `stale token cannot unbind a rebound owner`() {
        val coordinator = coordinator()
        val firstBinding = RecordingBinding()
        val firstToken = requireNotNull(coordinator.bind(firstBinding))
        assertTrue(coordinator.unbind(firstToken))
        val secondBinding = RecordingBinding()
        val secondToken = requireNotNull(coordinator.bind(secondBinding))
        assertFalse(coordinator.unbind(firstToken))
        assertEquals(ReadiumHostAttachmentState.BOUND, coordinator.state)
        assertTrue(coordinator.unbind(secondToken))
    }

    @Test fun `unbind while attached detaches without disposing`() {
        val coordinator = coordinator()
        val binding = RecordingBinding()
        val token = requireNotNull(coordinator.bind(binding))
        coordinator.onAttached()
        assertTrue(coordinator.unbind(token))
        assertEquals(1, binding.detached)
        assertEquals(0, binding.disposed)
        assertEquals(ReadiumHostAttachmentState.UNBOUND, coordinator.state)
    }

    @Test fun `container ID remains stable through lifecycle`() {
        var idReads = 0
        val coordinator = ReadiumHostBindingCoordinator {
            idReads++
            4321
        }
        val binding = RecordingBinding()
        coordinator.bind(binding)
        coordinator.onAttached()
        coordinator.onLaidOut(100, 200)
        coordinator.onDetached()
        assertEquals(4321, binding.attachedContainerIds.single())
        assertEquals(4321, binding.layoutContainerIds.single())
        assertTrue(idReads >= 2)
    }

    @Test fun `invalid container ID cannot be bound`() {
        val coordinator = ReadiumHostBindingCoordinator { 0 }
        assertNull(coordinator.bind(RecordingBinding()))
        assertEquals(ReadiumHostAttachmentState.UNBOUND, coordinator.state)
    }

    @Test fun `existing XML ID is preserved`() {
        assertEquals(1234, stableReadiumHostContainerId(1234) { error("must not generate") })
    }

    @Test fun `missing ID gets one generated stable ID`() {
        var generated = 0
        val id = stableReadiumHostContainerId(0) { generated++; 5678 }
        assertEquals(5678, id)
        assertEquals(1, generated)
    }

    @Test fun `negative ID gets one generated stable ID`() {
        assertEquals(6789, stableReadiumHostContainerId(-1) { 6789 })
    }

    @Test fun `layout received before binding is replayed once`() {
        val coordinator = coordinator()
        coordinator.onAttached()
        coordinator.onLaidOut(640, 480)
        val binding = RecordingBinding()
        coordinator.bind(binding)
        assertEquals(listOf(640 to 480), binding.layouts)
    }

    @Test fun `layout is reset across detach`() {
        val coordinator = coordinator()
        val binding = RecordingBinding()
        coordinator.bind(binding)
        coordinator.onAttached()
        coordinator.onLaidOut(640, 480)
        coordinator.onDetached()
        coordinator.onAttached()
        assertEquals(listOf(640 to 480), binding.layouts)
    }

    @Test fun `binding coordinator has no session side effects`() {
        val coordinator = coordinator()
        val binding = RecordingBinding()
        coordinator.bind(binding)
        coordinator.onAttached()
        assertEquals(0, binding.sessionStarts)
        assertEquals(0, binding.publicationOpens)
        assertEquals(0, binding.navigatorCreates)
    }

    private fun coordinator() = ReadiumHostBindingCoordinator { 3210 }

    private class RecordingBinding : ReadiumReaderHostBinding {
        var attached = 0
        var detached = 0
        var disposed = 0
        var sessionStarts = 0
        var publicationOpens = 0
        var navigatorCreates = 0
        val attachedContainerIds = mutableListOf<Int>()
        val layoutContainerIds = mutableListOf<Int>()
        val layouts = mutableListOf<Pair<Int, Int>>()

        override fun onHostAttached(containerId: Int) {
            attached++
            attachedContainerIds += containerId
        }

        override fun onHostLaidOut(containerId: Int, width: Int, height: Int) {
            layoutContainerIds += containerId
            layouts += width to height
        }

        override fun onHostDetached() {
            detached++
        }

        override fun onHostDisposed() {
            disposed++
        }
    }
}
