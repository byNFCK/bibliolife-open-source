package app.bibliolife.reader.readium

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.util.Log
import android.view.View
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.FragmentManager
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.lang.ref.WeakReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.continuous.BiblioLifeOpenTimingDiagnostics
import java.util.concurrent.atomic.AtomicLong

/** Stable public contract for the one native Readium PlatformView registration. */
internal object ReadiumPlatformViewContract {
    const val VIEW_TYPE = "app.bibliolife.reader.readium/reader_host"
}

internal class ReadiumPlatformViewCreationException(
    val failureCode: String,
) : IllegalStateException(failureCode)

/** The only lifecycle state owned by a PlatformView; it never owns a reader session. */
internal enum class ReadiumPlatformViewOwnerState {
    CREATED,
    ATTACHED,
    DETACHED,
    DISPOSED,
}

/**
 * Pure owner state for a reusable host. Host detach is reversible; only dispose is final.
 * The activity generation is metadata used to reject stale lifecycle work after reattach.
 */
internal class ReadiumPlatformViewOwnerCoordinator(
    val instanceId: String,
    val flutterViewId: Int,
    val hostContainerId: Int,
    val activityGeneration: Long,
) {
    init {
        require(instanceId.isNotBlank()) { "Readium PlatformView requires an instance ID" }
        require(hostContainerId > 0) { "Readium PlatformView requires a positive host ID" }
        require(activityGeneration >= 0) { "Readium PlatformView requires a valid activity generation" }
    }

    var state: ReadiumPlatformViewOwnerState = ReadiumPlatformViewOwnerState.CREATED
        private set

    fun acceptsActivityGeneration(generation: Long): Boolean =
        state != ReadiumPlatformViewOwnerState.DISPOSED && generation == activityGeneration

    fun onHostAttached(): Boolean {
        if (state == ReadiumPlatformViewOwnerState.DISPOSED ||
            state == ReadiumPlatformViewOwnerState.ATTACHED
        ) return false
        state = ReadiumPlatformViewOwnerState.ATTACHED
        return true
    }

    fun onHostDetached(): Boolean {
        if (state == ReadiumPlatformViewOwnerState.DISPOSED ||
            state == ReadiumPlatformViewOwnerState.DETACHED ||
            state == ReadiumPlatformViewOwnerState.CREATED
        ) return false
        state = ReadiumPlatformViewOwnerState.DETACHED
        return true
    }

    fun dispose(): Boolean {
        if (state == ReadiumPlatformViewOwnerState.DISPOSED) return false
        state = ReadiumPlatformViewOwnerState.DISPOSED
        return true
    }
}

/** Dependencies are resolved by the current Activity; a PlatformView does not retain Activity. */
internal data class ReadiumPlatformViewDependencies(
    val applicationContext: Context,
    val fragmentManager: FragmentManager,
    val classLoader: ClassLoader,
    val activityGeneration: Long,
) {
    companion object {
        fun from(
            activity: FragmentActivity,
            activityGeneration: Long,
        ) =
            ReadiumPlatformViewDependencies(
                applicationContext = activity.applicationContext,
                fragmentManager = activity.supportFragmentManager,
                classLoader = activity.classLoader,
                activityGeneration = activityGeneration,
            )
    }
}

internal enum class ReadiumActivityDependencyStatus {
    ATTACHED_COMPATIBLE,
    ATTACHED_INCOMPATIBLE,
    DETACHED,
}

/** Pure lifecycle bookkeeping used by the ActivityAware provider and JVM tests. */
internal class ReadiumActivityDependencyLifecycle {
    var status: ReadiumActivityDependencyStatus = ReadiumActivityDependencyStatus.DETACHED
        private set
    var generation: Long = 0
        private set

    fun attach(compatible: Boolean): Long {
        generation++
        status = if (compatible) {
            ReadiumActivityDependencyStatus.ATTACHED_COMPATIBLE
        } else {
            ReadiumActivityDependencyStatus.ATTACHED_INCOMPATIBLE
        }
        return generation
    }

    fun detach(): Long {
        generation++
        status = ReadiumActivityDependencyStatus.DETACHED
        return generation
    }

    fun isCurrentCompatible(expectedGeneration: Long): Boolean =
        status == ReadiumActivityDependencyStatus.ATTACHED_COMPATIBLE &&
            generation == expectedGeneration
}

/**
 * ActivityAware dependency access. Only a weak reference is retained, and it is cleared on
 * every detach path so an obsolete Activity cannot be kept by the plugin.
 */
internal class ReadiumActivityDependencyProvider {
    private val lifecycle = ReadiumActivityDependencyLifecycle()
    private var activityReference: WeakReference<FragmentActivity>? = null

    val status: ReadiumActivityDependencyStatus
        get() = lifecycle.status

    val generation: Long
        get() = lifecycle.generation

    fun attach(activity: Activity): ReadiumActivityDependencyStatus {
        val fragmentActivity = activity as? FragmentActivity
        activityReference = fragmentActivity?.let(::WeakReference)
        lifecycle.attach(fragmentActivity != null)
        return lifecycle.status
    }

    fun detachForConfigChanges() {
        activityReference = null
        lifecycle.detach()
    }

    fun detach() {
        activityReference = null
        lifecycle.detach()
    }

    fun currentDependencies(): ReadiumPlatformViewDependencies? {
        val activity = activityReference?.get() ?: return null
        if (!lifecycle.isCurrentCompatible(generation)) return null
        return ReadiumPlatformViewDependencies.from(activity, generation)
    }
}

/** Pure factory decisions keep malformed Dart payloads and stale Activity state testable. */
internal class ReadiumPlatformViewFactoryPolicy(
    private val dependencyProvider: ReadiumActivityDependencyProvider,
) {
    fun parseOpenConfiguration(value: Any?): ReadiumPlatformViewOpenConfiguration =
        ReadiumPlatformViewOpenConfiguration.parse(value).getOrElse { error ->
            throw error as? ReadiumPlatformViewCreationException
                ?: ReadiumPlatformViewCreationException("invalid_open_configuration")
        }

    fun requireDependencies(): ReadiumPlatformViewDependencies =
        dependencyProvider.currentDependencies()
            ?: throw ReadiumPlatformViewCreationException("activity_unavailable")
}

/** Real Flutter factory. It has no fallback view and fails with a stable, controlled code. */
internal class ReadiumPlatformViewFactory(
    private val dependencyProvider: ReadiumActivityDependencyProvider,
    private val transportFactory: ReadiumFlutterBridgeTransportFactory,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val policy = ReadiumPlatformViewFactoryPolicy(dependencyProvider)
        val configuration = policy.parseOpenConfiguration(args)
        BiblioLifeOpenTimingDiagnostics.claim(configuration.bookId)
        val channelNames = runCatching {
            ReadiumPlatformViewBridgeChannelNames.require(configuration.instanceId)
        }.getOrElse { throw ReadiumPlatformViewCreationException("invalid_channel_identity") }
        val transport = transportFactory.create(channelNames)
        val dependencies = policy.requireDependencies()
        return ReadiumPlatformView(context, viewId, configuration, dependencies, bridgeTransport = transport)
    }
}

/**
 * Production PlatformView wrapper around the exact reusable native host instance.
 * It owns the one reusable Readium session and exposes only typed host/controller ports;
 * publication, navigator and reader chrome stay behind those ports.
 */
internal class ReadiumPlatformView(
    context: Context,
    viewId: Int,
    configuration: ReadiumPlatformViewOpenConfiguration,
    dependencies: ReadiumPlatformViewDependencies,
    hostContainerId: Int? = null,
    private val sessionFactory: ReadiumReaderSessionFactory = ProductionReadiumReaderSessionFactory,
    private val bridgeTransport: ReadiumBridgeTransport? = null,
) : PlatformView {
    private val diagnosticInstanceId = configuration.instanceId
    private val hostView = hostContainerId?.let { ReadiumReaderHostView(context, it) }
        ?: ReadiumReaderHostView(context)
    private val ownerCoordinator = ReadiumPlatformViewOwnerCoordinator(
        instanceId = configuration.instanceId,
        flutterViewId = viewId,
        hostContainerId = hostView.fragmentContainerId,
        activityGeneration = dependencies.activityGeneration,
    )
    private val sessionScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var platformDisposed = false
    private lateinit var session: ReadiumReaderSession
    private lateinit var sessionOwner: ReadiumPlatformViewSessionOwner<ReadiumReaderSession>
    private val listenerCoordinator = ReadiumPlatformViewHostListenerCoordinator()
    private val controllerImpl = ReadiumPlatformViewControllerImpl(
        sessionProvider = { if (::session.isInitialized && !platformDisposed) session else null },
        scope = sessionScope,
        isDisposed = { platformDisposed },
    )
    private var navigatorHost: ReadiumPlatformViewNavigatorHost? = null
    private var decorationActivationListener: ReadiumPlatformViewDecorationActivationListener? = null
    private var persistentHighlightActivationListener: ReadiumPersistentHighlightActivationListener? = null
    private var bindingToken: ReadiumHostBindingToken? = null
    private val eventHub = ReadiumPlatformViewEventHub(listenerCoordinator)
    private val annotationActionHost = ReadiumAnnotationActionHost(
        instanceId = configuration.instanceId,
        emit = { eventHub.emitInteraction(ReadiumReaderInteraction.AnnotationActionRequested(it)) },
    )
    private val interactionIds = AtomicLong(0)
    private val contentTapCoordinator = ReadiumContentTapCoordinator(interactionIds)
    private lateinit var highlightToolbar: ReaderHighlightToolbarPresenter
    private val contentTapInputListener by lazy {
        ReadiumContentTapInputListener(
            coordinator = contentTapCoordinator,
            viewportGeneration = { controllerImpl.selectionState().viewportEpoch },
            isHostActive = { !platformDisposed && ownerCoordinator.state != ReadiumPlatformViewOwnerState.DISPOSED },
            // Legacy attaches this listener only after navigator readiness;
            // continuous invokes it only after its live-resource validation.
            isNavigatorActive = { !platformDisposed && ownerCoordinator.state != ReadiumPlatformViewOwnerState.DISPOSED },
            isInteractionBlocked = highlightToolbar::isVisible,
            onBlockedTap = { highlightToolbar.dismissEditToolbar("outside_tap") },
            isSelectionActive = { controllerImpl.selectionState().sessionActive },
            emit = eventHub::emitInteraction,
        )
    }
    private lateinit var resolvedSelectionToolbarAdapter: ReadiumResolvedSelectionToolbarAdapter
    private val selectionResolutionHost = ReadiumNativeSelectionResolutionHost(
        beginSession = controllerImpl::onNativeSelectionSessionStarted,
        activeNativeSessionId = { controllerImpl.selectionState().nativeSessionId },
        post = hostView::post,
        requestSelection = controllerImpl::requestCurrentSelection,
        trace = ::diagnoseHighlightMenu,
    )
    private val selectionPresentationHost = ReadiumSelectionPresentationHost(
        instanceId = configuration.instanceId,
        selectionProvider = { controllerImpl.selectionState() },
        emitSelectionAction = { request ->
            eventHub.emitInteraction(ReadiumReaderInteraction.SelectionActionRequested(request))
        },
        onSelectionSessionStarted = selectionResolutionHost::onNativeSelectionSessionStarted,
        onSelectionSessionEnded = { sessionId ->
            selectionResolutionHost.onNativeSelectionSessionEnded(sessionId)
            controllerImpl.onNativeSelectionSessionEnded(sessionId)
            highlightToolbar.dismissCreateToolbar("selection_cleared")
        },
        onActionModeCreated = { visibleItemCount ->
            diagnoseHighlightMenu("action_mode=created visible_items=$visibleItemCount")
        },
        onActionModePrepared = { visibleItemCount ->
            diagnoseHighlightMenu("action_mode=prepared visible_items=$visibleItemCount")
            selectionResolutionHost.refreshActiveSelection()
        },
        onActionModeDestroyed = {
            diagnoseHighlightMenu("action_mode=destroyed")
        },
        onSelectionHandlesPreparing = { sessionId ->
            if (controllerImpl.selectionState().nativeSessionId == sessionId) {
                highlightToolbar.hideCreateToolbarContentForCustomDrag()
            }
        },
    )
    private val bridgeCore = ReadiumPlatformViewBridgeCore(
        configuration = configuration,
        controller = controllerImpl,
        eventHub = eventHub,
        scope = sessionScope,
        transport = bridgeTransport,
        resolveSelectionAction = selectionPresentationHost::resolve,
        resolveAnnotationAction = annotationActionHost::resolve,
    )

    init {
        configuration.validate()?.let { throw it }
        require(dependencies.activityGeneration >= 0) { "Readium PlatformView requires an activity generation" }
        highlightToolbar = ReaderHighlightToolbarPresenter(
            context = hostView.context,
            rootProvider = ::resolveActiveReaderRoot,
            onCopyCreateSelection = {
                resolveSelectionForToolbarAction("copy") { selection ->
                    hostView.context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(
                        ClipData.newPlainText("highlight", selection.selectedText),
                    )
                }
            },
            onCreate = { color ->
                resolveSelectionForToolbarAction("highlight") { selection ->
                    if (
                        selectionPresentationHost.emitFloatingMenuAction(
                            ReadiumSelectionAction.HIGHLIGHT,
                            color,
                            selection,
                        )
                    ) {
                        highlightToolbar.dismissCreateToolbar("highlight_requested")
                    }
                }
            },
            onDelete = annotationActionHost::requestDelete,
            onRecolor = annotationActionHost::requestRecolor,
        )
        resolvedSelectionToolbarAdapter = ReadiumResolvedSelectionToolbarAdapter(
            viewportProvider = {
                val root = resolveActiveReaderRoot() ?: return@ReadiumResolvedSelectionToolbarAdapter null
                diagnoseHighlightMenu(
                    "HIGHLIGHT_FLOAT_ROOT attached=${root.isAttachedToWindow} token=${root.windowToken != null} " +
                        "size=${root.width}x${root.height}",
                )
                ReadiumSelectionRect(0f, 0f, root.width.toFloat(), root.height.toFloat())
            },
            showCreate = { rect, selectedText ->
                highlightToolbar.showCreate(rect.toRectF(), validSelection = true, selectedText = selectedText)
            },
            // Selection lifecycle owns CREATE only. A late INACTIVE callback
            // must not dismiss an existing-highlight EDIT popup.
            hide = highlightToolbar::dismissCreateToolbar,
            trace = ::diagnoseHighlightMenu,
        )
        sessionOwner = ReadiumPlatformViewSessionOwner(
            factory = {
                sessionFactory.create(
                    dependencies = dependencies,
                    configuration = configuration,
                    navigatorConfiguration = selectionPresentationHost.createNavigatorConfiguration(),
                    scope = sessionScope,
                    listener = createSessionListener(configuration),
                    diagnosticInstanceId = diagnosticInstanceId,
                )
            },
            initialize = { active -> active.initialize(ownerCoordinator.hostContainerId, hostView.nativeRenditionHost()) },
            disposeSession = { active, retain -> active.dispose(retain) },
        )
        listenerCoordinator.emit(ReadiumPlatformViewReaderState.Diagnostic(
            ReadiumOpenDiagnostics.stage("native_session", "started", "android_reader_session"),
        ))
        session = requireNotNull(sessionOwner.createOnce())
        listenerCoordinator.emit(ReadiumPlatformViewReaderState.Diagnostic(
            ReadiumOpenDiagnostics.stage("native_session", "success", "android_reader_session", mapOf("nativeSessionCreated" to true)),
        ))
        BiblioLifeOpenTimingDiagnostics.lifecycle("SESSION_CREATE", instanceId = diagnosticInstanceId, sessionId = diagnosticInstanceId)
        BiblioLifeOpenTimingDiagnostics.lifecycle("PLATFORM_VIEW_CREATE", instanceId = diagnosticInstanceId, sessionId = diagnosticInstanceId, generation = ownerCoordinator.activityGeneration)
        bindingToken = hostView.bind(object : ReadiumReaderHostBinding {
            override fun onHostAttached(containerId: Int) {
                if (containerId == ownerCoordinator.hostContainerId && ownerCoordinator.onHostAttached()) {
                    sessionOwner.initializeOnce()
                }
                session?.updateNativeRenditionHost(hostView.nativeRenditionHost())
            }

            override fun onHostDetached() {
                session.detachNativeRenditionHost(hostView.nativeRenditionHost().generation)
                ownerCoordinator.onHostDetached()
            }
        }) ?: throw ReadiumPlatformViewCreationException("host_binding_unavailable")
        listenerCoordinator.emit(ReadiumPlatformViewReaderState.Diagnostic(
            ReadiumOpenDiagnostics.stage("platform_view", "success", "android_platform_view"),
        ))
    }

    fun controller(): ReadiumPlatformViewController = controllerImpl

    fun bindHostListener(listener: ReadiumPlatformViewHostListener): ReadiumPlatformViewHostListenerToken? =
        listenerCoordinator.bind(listener)

    fun unbindHostListener(token: ReadiumPlatformViewHostListenerToken): Boolean =
        listenerCoordinator.unbind(token)

    override fun getView(): View = hostView

    fun dispose(retainPublicationForRestoredNavigator: Boolean = false) {
        if (platformDisposed) return
        val diagnosticGeneration = ownerCoordinator.activityGeneration
        BiblioLifeOpenTimingDiagnostics.lifecycle("PLATFORM_VIEW_DISPOSE_BEGIN", instanceId = diagnosticInstanceId, sessionId = diagnosticInstanceId, generation = diagnosticGeneration)
        highlightToolbar.detach()
        annotationActionHost.dispose()
        contentTapCoordinator.dispose()
        selectionPresentationHost.dispose()
        listenerCoordinator.emit(ReadiumPlatformViewReaderState.Disposed)
        bridgeCore.dispose()
        platformDisposed = true
        listenerCoordinator.dispose()
        decorationActivationListener?.dispose()
        decorationActivationListener = null
        persistentHighlightActivationListener?.dispose()
        persistentHighlightActivationListener = null
        navigatorHost?.dispose()
        navigatorHost = null
        bindingToken = null
        hostView.disposeHostBinding()
        if (::sessionOwner.isInitialized) {
            BiblioLifeOpenTimingDiagnostics.lifecycle("SESSION_DISPOSE_BEGIN", instanceId = diagnosticInstanceId, sessionId = diagnosticInstanceId)
            sessionOwner.disposeOnce(retainPublicationForRestoredNavigator)
            BiblioLifeOpenTimingDiagnostics.lifecycle("SESSION_DISPOSE_END", instanceId = diagnosticInstanceId, sessionId = diagnosticInstanceId)
        }
        sessionScope.cancel()
        ownerCoordinator.dispose()
        BiblioLifeOpenTimingDiagnostics.lifecycle("PLATFORM_VIEW_DISPOSE_END", instanceId = diagnosticInstanceId, sessionId = diagnosticInstanceId, generation = diagnosticGeneration)
    }

    override fun dispose() {
        dispose(retainPublicationForRestoredNavigator = false)
    }

    private fun resolveSelectionForToolbarAction(
        action: String,
        onResolved: (ReadiumSelectionSnapshot) -> Unit,
    ) {
        diagnoseHighlightMenu("READIUM_SELECTION_ACTION_REFRESH action=$action")
        controllerImpl.requestCurrentSelection(
            { result ->
                val selection = (result as? ReadiumSelectionRequestResult.Updated)?.selection
                diagnoseHighlightMenu(
                    "READIUM_SELECTION_ACTION_RESOLVED action=$action hasSelection=${selection != null}",
                )
                if (selection != null) onResolved(selection)
            },
            refreshAfterInFlight = true,
        )
    }

    private fun createSessionListener(
        configuration: ReadiumPlatformViewOpenConfiguration,
    ) = object : ReadiumReaderSession.Listener {
        override fun onContinuousContentTap(): Boolean = contentTapInputListener.onContinuousContentTap()

        override fun onContinuousPersistentHighlightActivated(
            decorationId: String,
            group: String,
            rect: android.graphics.RectF,
            tint: Int?,
            selectedText: String,
        ): Boolean {
            val activation = ReadiumExistingHighlightActivationResolver.resolve(
                group = group,
                decorationId = decorationId,
                tint = tint,
                selectedText = selectedText,
            ) ?: return false
            diagnoseHighlightMenu("HIGHLIGHT_FLOAT_ACTIVATION mode=existing geometry=true")
            highlightToolbar.showEdit(
                id = activation.id,
                color = activation.color,
                selectedText = activation.selectedText,
                anchor = rect,
            )
            return true
        }

        override fun onStateChanged(state: ReadiumReaderSession.State) {
            if (platformDisposed) return
            when (state) {
                ReadiumReaderSession.State.InitializationStarted ->
                    listenerCoordinator.emit(ReadiumPlatformViewReaderState.InitializationStarted)
                is ReadiumReaderSession.State.PublicationOpened -> listenerCoordinator.emit(
                    ReadiumPlatformViewReaderState.PublicationOpened(
                        ReadiumPlatformViewPublicationInfo(configuration.bookId, publicationTitle(state.publication, configuration)),
                    ),
                )
                ReadiumReaderSession.State.ContinuousRenditionPending -> Unit
                ReadiumReaderSession.State.ContinuousRenditionAttached -> Unit
                is ReadiumReaderSession.State.NavigatorAttached -> listenerCoordinator.emit(
                    ReadiumPlatformViewReaderState.NavigatorAttached(state.reusedRestoredFragment),
                )
                ReadiumReaderSession.State.NavigatorReady -> listenerCoordinator.emit(ReadiumPlatformViewReaderState.NavigatorReady)
                is ReadiumReaderSession.State.InitialLocatorRestored -> listenerCoordinator.emit(
                    ReadiumPlatformViewReaderState.InitialLocatorRestored(state.navigated),
                )
                is ReadiumReaderSession.State.PositionChanged -> listenerCoordinator.emit(
                    ReadiumPlatformViewReaderState.PositionChanged(state.position, state.liveManual, state.progressOwner),
                )
                is ReadiumReaderSession.State.ManualScrollActivityChanged -> listenerCoordinator.emit(
                    ReadiumPlatformViewReaderState.ManualScrollActivityChanged(state.active),
                )
                is ReadiumReaderSession.State.NavigationStarted -> {
                    highlightToolbar.dismiss("page_changed")
                    listenerCoordinator.emit(
                        ReadiumPlatformViewReaderState.NavigationStarted(
                            state.command,
                            state.generation,
                            state.progressOwner,
                        ),
                    )
                }
                is ReadiumReaderSession.State.NavigationCompleted -> listenerCoordinator.emit(
                    ReadiumPlatformViewReaderState.NavigationCompleted(state.command, state.generation),
                )
                is ReadiumReaderSession.State.NavigationFailed -> listenerCoordinator.emit(
                    ReadiumPlatformViewReaderState.NavigationFailed(state.command, state.error.toPlatformError()),
                )
                is ReadiumReaderSession.State.PreferencesRequested -> listenerCoordinator.emit(
                    ReadiumPlatformViewReaderState.PreferencesRequested(state.preferences.toPlatformState()),
                )
                is ReadiumReaderSession.State.PreferencesApplied -> listenerCoordinator.emit(
                    ReadiumPlatformViewReaderState.PreferencesApplied(state.preferences.toPlatformState(), state.initial),
                )
                is ReadiumReaderSession.State.PreferencesFailed -> listenerCoordinator.emit(
                    ReadiumPlatformViewReaderState.PreferencesFailed(state.preferences.toPlatformState(), state.error.toPlatformError()),
                )
                is ReadiumReaderSession.State.Diagnostic -> listenerCoordinator.emit(
                    ReadiumPlatformViewReaderState.Diagnostic(state.fields),
                )
                is ReadiumReaderSession.State.TocStateChanged -> listenerCoordinator.emit(
                    ReadiumPlatformViewReaderState.TocStateChanged(state.toc),
                )
                is ReadiumReaderSession.State.CurrentChapterChanged -> listenerCoordinator.emit(
                    ReadiumPlatformViewReaderState.CurrentChapterChanged(state.chapter),
                )
                is ReadiumReaderSession.State.SearchStateChanged -> listenerCoordinator.emit(
                    ReadiumPlatformViewReaderState.SearchStateChanged(state.search),
                )
                is ReadiumReaderSession.State.SelectionChanged -> {
                    listenerCoordinator.emit(ReadiumPlatformViewReaderState.SelectionChanged(state.selection))
                    resolvedSelectionToolbarAdapter.onSelectionStateChanged(state.selection)
                }
                is ReadiumReaderSession.State.DecorationsChanged -> listenerCoordinator.emit(
                    ReadiumPlatformViewReaderState.DecorationsChanged(state.group, state.decorations.toPlatformState()),
                )
                ReadiumReaderSession.State.Disposed -> listenerCoordinator.emit(ReadiumPlatformViewReaderState.Disposed)
            }
        }

        override fun onNavigatorReady(
            publication: org.readium.r2.shared.publication.Publication,
            navigator: EpubNavigatorFragment,
        ) {
            if (platformDisposed) return
            val host = ReadiumPlatformViewNavigatorHost(navigator)
            decorationActivationListener?.dispose()
            persistentHighlightActivationListener?.dispose()
            navigatorHost?.dispose()
            navigatorHost = host
            val activationListener = ReadiumPlatformViewDecorationActivationListener(
                instanceId = configuration.instanceId,
                interactionIds = interactionIds,
                emit = { eventHub.emitInteraction(ReadiumReaderInteraction.DecorationActivated(it)) },
            )
            val highlightActivationListener = ReadiumPersistentHighlightActivationListener(
                showEdit = { id, color, selectedText, anchor ->
                    diagnoseHighlightMenu(
                        "HIGHLIGHT_FLOAT_ACTIVATION mode=existing geometry=${anchor != null}",
                    )
                    if (controllerImpl.selectionState().sessionActive) {
                        diagnoseHighlightMenu("HIGHLIGHT_FLOAT_EXISTING_CLEAR_ACTIVE_SELECTION")
                        controllerImpl.clearSelection()
                    }
                    highlightToolbar.showEdit(id, color, selectedText, anchor)
                },
            )
            host.addDecorationListener(
                ReadiumDecorationGroup.PERSISTENT_HIGHLIGHTS.nativeName,
                highlightActivationListener,
            )
            host.addDecorationListener(ReadiumDecorationGroup.SEARCH_RESULT.nativeName, activationListener)
            decorationActivationListener = activationListener
            persistentHighlightActivationListener = highlightActivationListener
            host.addInputListener(contentTapInputListener)
            val info = ReadiumPlatformViewPublicationInfo(
                bookId = configuration.bookId,
                title = publicationTitle(publication, configuration),
            )
            listenerCoordinator.emitNavigatorReady(info, host)
        }

        override fun onResolvedNativeSelection(selection: ReadiumSelectionState) {
            if (!platformDisposed) resolvedSelectionToolbarAdapter.onResolvedSelection(selection)
        }

        override fun onPositionChanged(position: ReadiumPositionState) {
            // PositionChanged is transported through the typed state stream above.
        }

        override fun onFatalError(error: ReadiumReaderSession.Error) = onFatalError(error, null)

        override fun onFatalError(error: ReadiumReaderSession.Error, openFailure: Map<String, Any?>?) {
            if (!platformDisposed) listenerCoordinator.emitFatal(ReadiumPlatformViewError(error.code, openFailure))
        }

        override fun onRecoverableError(error: ReadiumReaderSession.Error) {
            if (!platformDisposed) listenerCoordinator.emitRecoverable(error.toPlatformError())
        }
    }

    /** The PlatformView host owns both the fragment and the window token used by the popup. */
    private fun resolveActiveReaderRoot(): View? = hostView.takeIf {
        !platformDisposed && ownerCoordinator.state != ReadiumPlatformViewOwnerState.DISPOSED
    }

    private fun diagnoseHighlightMenu(message: String) {
        if (BuildConfig.DEBUG || Log.isLoggable("BiblioLifeReadium", Log.DEBUG)) {
            Log.d("BiblioLifeReadium", "HIGHLIGHT_TOOLBAR $message")
        }
    }

    private fun publicationTitle(
        publication: org.readium.r2.shared.publication.Publication,
        configuration: ReadiumPlatformViewOpenConfiguration,
    ): String = publication.metadata.title?.trim()?.takeIf { it.isNotEmpty() }
        ?: java.io.File(configuration.localFilePath).nameWithoutExtension.trim().takeIf { it.isNotEmpty() }
        ?: configuration.bookId
}
