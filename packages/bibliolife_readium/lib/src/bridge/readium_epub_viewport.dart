import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'readium_bridge_client.dart';
import 'readium_bridge_constants.dart';
import 'readium_bridge_models.dart';
import 'readium_epub_controller.dart';

typedef ReadiumEpubPlatformViewBuilder =
    Widget Function(
      BuildContext context,
      ReadiumEpubOpenConfiguration configuration,
      ValueChanged<int> onPlatformViewCreated,
    );

enum ReadiumAndroidCompositionBackend { hcpp, legacyHybridComposition }

enum ReadiumHcppSupportCheck { supported, unsupported, error }

@immutable
final class ReadiumAndroidCompositionResolution {
  const ReadiumAndroidCompositionResolution({
    required this.backend,
    required this.supportCheck,
  });

  final ReadiumAndroidCompositionBackend backend;
  final ReadiumHcppSupportCheck supportCheck;

  String get backendLabel => switch (backend) {
    ReadiumAndroidCompositionBackend.hcpp => 'hcpp',
    ReadiumAndroidCompositionBackend.legacyHybridComposition => 'legacy_hc',
  };

  String get supportCheckLabel => switch (supportCheck) {
    ReadiumHcppSupportCheck.supported => 'true',
    ReadiumHcppSupportCheck.unsupported => 'false',
    ReadiumHcppSupportCheck.error => 'error',
  };

  String get controllerLabel => switch (backend) {
    ReadiumAndroidCompositionBackend.hcpp => 'HybridAndroidViewController',
    ReadiumAndroidCompositionBackend.legacyHybridComposition =>
      'ExpensiveAndroidViewController',
  };
}

typedef ReadiumHcppSupportProbe = Future<bool> Function();

/// Resolves and memoizes only the engine capability, never a view controller.
final class ReadiumAndroidCompositionResolver {
  ReadiumAndroidCompositionResolver({ReadiumHcppSupportProbe? supportProbe})
    : _supportProbe =
          supportProbe ?? HybridAndroidViewController.checkIfSupported;

  final ReadiumHcppSupportProbe _supportProbe;
  Future<ReadiumAndroidCompositionResolution>? _resolution;

  Future<ReadiumAndroidCompositionResolution> resolve() =>
      _resolution ??= _resolve();

  Future<ReadiumAndroidCompositionResolution> _resolve() async {
    try {
      final supported = await _supportProbe();
      return ReadiumAndroidCompositionResolution(
        backend: supported
            ? ReadiumAndroidCompositionBackend.hcpp
            : ReadiumAndroidCompositionBackend.legacyHybridComposition,
        supportCheck: supported
            ? ReadiumHcppSupportCheck.supported
            : ReadiumHcppSupportCheck.unsupported,
      );
    } on Object {
      return const ReadiumAndroidCompositionResolution(
        backend: ReadiumAndroidCompositionBackend.legacyHybridComposition,
        supportCheck: ReadiumHcppSupportCheck.error,
      );
    }
  }
}

/// Debug summary bridge for the active Readium viewport.
abstract final class ReadiumAndroidCompositionDiagnostics {
  static Object? _owner;
  static String _activeBackendLabel = 'unresolved';

  static String get activeBackendLabel => _activeBackendLabel;

  static void activate(Object owner, String backendLabel) {
    _owner = owner;
    _activeBackendLabel = backendLabel;
  }

  static void clear(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _activeBackendLabel = 'unresolved';
  }
}

const _readiumPerformanceLogsEnabled = bool.fromEnvironment(
  'BIBLIOLIFE_READER_PERF_LOGS',
  defaultValue: false,
);

final ReadiumAndroidCompositionResolver _defaultCompositionResolver =
    ReadiumAndroidCompositionResolver();

final class ReadiumEpubViewport extends StatefulWidget {
  const ReadiumEpubViewport({
    required this.configuration,
    this.controller,
    this.onControllerReady,
    this.onStateChanged,
    this.onContentTap,
    this.onError,
    this.onPlatformViewCreationError,
    this.clientFactory,
    this.instanceIdFactory,
    this.platformViewBuilder,
    this.compositionResolver,
    super.key,
  });

  final ReadiumEpubOpenConfiguration configuration;
  final ReadiumEpubController? controller;
  final ValueChanged<ReadiumEpubController>? onControllerReady;
  final ValueChanged<ReadiumEpubControllerState>? onStateChanged;
  final ValueChanged<ReadiumContentTapEvent>? onContentTap;
  final ValueChanged<ReadiumBridgeError>? onError;
  final ValueChanged<Object>? onPlatformViewCreationError;
  final ReadiumBridgeClientFactory? clientFactory;
  final ReadiumInstanceIdFactory? instanceIdFactory;
  @visibleForTesting
  final ReadiumEpubPlatformViewBuilder? platformViewBuilder;
  @visibleForTesting
  final ReadiumAndroidCompositionResolver? compositionResolver;

  @override
  State<ReadiumEpubViewport> createState() => _ReadiumEpubViewportState();
}

class _ReadiumEpubViewportState extends State<ReadiumEpubViewport> {
  late ReadiumEpubOpenConfiguration _effectiveConfiguration;
  late ReadiumEpubController _controller;
  late bool _ownsController;
  int _viewGeneration = 0;
  bool _platformCreated = false;
  bool _readyNotified = false;
  bool _bridgeStartScheduled = false;
  bool _bridgeStartRequested = false;
  StreamSubscription<ReadiumReaderInteractionEvent>? _interactionSubscription;
  ReadiumBridgeError? _creationError;
  String? _registeredInstanceId;
  ReadiumAndroidCompositionResolution? _compositionResolution;
  final Object _compositionDiagnosticsOwner = Object();
  int _compositionResolutionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _initializeController();
    _attachInteractionListener();
    _prepareCompositionBackend();
  }

  @override
  void didUpdateWidget(covariant ReadiumEpubViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _setCreationError(
        const ReadiumBridgeError(
          code: 'controller_changed_requires_new_viewport',
        ),
      );
      return;
    }
    if (oldWidget.onContentTap != widget.onContentTap) {
      _detachInteractionListener();
      _attachInteractionListener();
    }
    if (oldWidget.configuration != widget.configuration) {
      if (_ownsController) {
        _controller.listenable.removeListener(_handleStateChanged);
        _detachInteractionListener();
        _unregisterInstanceId();
        unawaited(_controller.dispose());
        _initializeController(rebuild: true);
        _attachInteractionListener();
        if (_compositionResolution != null) _scheduleBridgeStart();
      } else {
        _setCreationError(
          const ReadiumBridgeError(
            code: 'configuration_changed_requires_new_viewport',
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _compositionResolutionGeneration++;
    ReadiumAndroidCompositionDiagnostics.clear(_compositionDiagnosticsOwner);
    _controller.listenable.removeListener(_handleStateChanged);
    _detachInteractionListener();
    _unregisterInstanceId();
    if (_ownsController) unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _creationError;
    if (error != null) {
      return const SizedBox.expand();
    }
    final compositionResolution = _compositionResolution;
    if (compositionResolution == null) {
      return const SizedBox.expand(
        key: ValueKey<String>('readium-composition-resolving'),
      );
    }
    final child =
        widget.platformViewBuilder?.call(
          context,
          _effectiveConfiguration,
          _onPlatformViewCreated,
        ) ??
        _buildProductionPlatformView(context, compositionResolution.backend);
    return KeyedSubtree(key: ValueKey<int>(_viewGeneration), child: child);
  }

  void _initializeController({bool rebuild = false}) {
    final supplied = widget.controller;
    final suppliedId = supplied?.instanceId;
    final requestedId = widget.configuration.instanceId?.trim();
    if (suppliedId != null &&
        requestedId != null &&
        suppliedId != requestedId) {
      _effectiveConfiguration = widget.configuration.withInstanceId(
        requestedId,
      );
      _ownsController = false;
      _controller = supplied!;
      _creationError = const ReadiumBridgeError(
        code: 'controller_instance_mismatch',
      );
      return;
    }
    final instanceId =
        (requestedId ??
                suppliedId ??
                (widget.instanceIdFactory ?? _defaultViewportInstanceId)())
            .trim();
    if (instanceId.isEmpty) {
      final fallbackId = _defaultViewportInstanceId();
      _effectiveConfiguration = widget.configuration.withInstanceId(fallbackId);
      _ownsController = supplied == null;
      _controller =
          supplied ??
          ReadiumEpubController(
            configuration: _effectiveConfiguration,
            clientFactory: widget.clientFactory,
          );
      _creationError = const ReadiumBridgeError(code: 'invalid_instance_id');
      return;
    }
    _effectiveConfiguration = widget.configuration.withInstanceId(instanceId);
    _ownsController = supplied == null;
    _controller =
        supplied ??
        ReadiumEpubController(
          configuration: _effectiveConfiguration,
          clientFactory: widget.clientFactory,
        );
    if (!_activeViewportInstanceIds.add(instanceId)) {
      _creationError = const ReadiumBridgeError(code: 'duplicate_instance_id');
      return;
    }
    _registeredInstanceId = instanceId;
    _creationError = null;
    _platformCreated = false;
    _readyNotified = false;
    _bridgeStartScheduled = false;
    _bridgeStartRequested = false;
    if (rebuild) _viewGeneration++;
    _controller.listenable.addListener(_handleStateChanged);
  }

  void _handleStateChanged() {
    if (!mounted) return;
    widget.onStateChanged?.call(_controller.state);
  }

  void _attachInteractionListener() {
    if (widget.onContentTap == null) return;
    _interactionSubscription = _controller.interactions.listen((event) {
      if (!mounted || event is! ReadiumContentTapEvent) return;
      widget.onContentTap?.call(event);
    });
  }

  void _detachInteractionListener() {
    final subscription = _interactionSubscription;
    _interactionSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _onPlatformViewCreated(int id) {
    if (_platformCreated || _creationError != null) return;
    _platformCreated = true;
    if (!_readyNotified) {
      _readyNotified = true;
      widget.onControllerReady?.call(_controller);
    }
    // The native channels are registered as part of PlatformView creation.
    // Attach immediately on the authoritative callback; the frame fallback
    // below exists only for Android devices that omit that callback.
    _startBridge();
  }

  void _scheduleBridgeStart() {
    if (_bridgeStartScheduled || _creationError != null) return;
    _bridgeStartScheduled = true;
    // A065 does not consistently deliver the Dart creation callback. Keep a
    // fixed frame-only fallback instead of a timer, then attach exactly once.
    void scheduleFrameBoundary(int remaining) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (remaining == 0) {
          _startBridge();
          return;
        }
        scheduleFrameBoundary(remaining - 1);
        WidgetsBinding.instance.scheduleFrame();
      });
    }

    scheduleFrameBoundary(5);
  }

  void _startBridge() {
    if (!mounted || _bridgeStartRequested || _creationError != null) return;
    _bridgeStartRequested = true;
    unawaited(
      _controller.start().catchError((Object error) {
        if (error is ReadiumBridgeException) {
          _setCreationError(error.error);
        } else {
          _setCreationError(
            const ReadiumBridgeError(
              code: 'transport_unavailable',
              fatal: true,
            ),
          );
        }
      }),
    );
  }

  void _prepareCompositionBackend() {
    // Injected builders are a host-test seam and never create an Android view.
    // Tests exercising selection inject a resolver explicitly.
    if (widget.platformViewBuilder != null &&
        widget.compositionResolver == null) {
      _compositionResolution = const ReadiumAndroidCompositionResolution(
        backend: ReadiumAndroidCompositionBackend.legacyHybridComposition,
        supportCheck: ReadiumHcppSupportCheck.unsupported,
      );
      _scheduleBridgeStart();
      return;
    }
    final generation = ++_compositionResolutionGeneration;
    final resolver = widget.compositionResolver ?? _defaultCompositionResolver;
    unawaited(
      resolver.resolve().then((resolution) {
        if (!mounted || generation != _compositionResolutionGeneration) return;
        ReadiumAndroidCompositionDiagnostics.activate(
          _compositionDiagnosticsOwner,
          resolution.backendLabel,
        );
        if (_readiumPerformanceLogsEnabled) {
          debugPrint(
            'READIUM_PLATFORMVIEW_COMPOSITION requested=hcpp '
            'resolved=${resolution.backendLabel} '
            'supportCheck=${resolution.supportCheckLabel} '
            'controller=${resolution.controllerLabel}',
          );
        }
        setState(() => _compositionResolution = resolution);
        _scheduleBridgeStart();
      }),
    );
  }

  Widget _buildProductionPlatformView(
    BuildContext context,
    ReadiumAndroidCompositionBackend backend,
  ) => PlatformViewLink(
    viewType: ReadiumBridgeConstants.viewType,
    surfaceFactory: (context, controller) => AndroidViewSurface(
      controller: controller as AndroidViewController,
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      hitTestBehavior: PlatformViewHitTestBehavior.opaque,
    ),
    onCreatePlatformView: (params) {
      final AndroidViewController controller = switch (backend) {
        ReadiumAndroidCompositionBackend.hcpp =>
          PlatformViewsService.initHybridAndroidView(
            id: params.id,
            viewType: params.viewType,
            layoutDirection: Directionality.of(context),
            creationParams: _effectiveConfiguration.toMap(),
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          ),
        ReadiumAndroidCompositionBackend.legacyHybridComposition =>
          PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: params.viewType,
            layoutDirection: Directionality.of(context),
            creationParams: _effectiveConfiguration.toMap(),
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          ),
      };
      controller.addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
      final onCreationError = widget.onPlatformViewCreationError;
      final creation = controller.create();
      if (onCreationError != null) {
        unawaited(
          creation.then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {
              onCreationError(error);
              Error.throwWithStackTrace(error, stack);
            },
          ),
        );
      }
      return controller;
    },
  );

  void _setCreationError(ReadiumBridgeError error) {
    if (!mounted) return;
    widget.onError?.call(error);
    setState(() => _creationError = error);
  }

  void _unregisterInstanceId() {
    final id = _registeredInstanceId;
    if (id == null) return;
    _activeViewportInstanceIds.remove(id);
    _registeredInstanceId = null;
  }
}

final Set<String> _activeViewportInstanceIds = <String>{};
int _viewportCounter = 0;

String _defaultViewportInstanceId() {
  _viewportCounter++;
  return 'dart-viewport-${DateTime.now().microsecondsSinceEpoch}-$_viewportCounter';
}
