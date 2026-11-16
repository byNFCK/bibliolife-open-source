import 'dart:developer' as developer;

import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OfflineModeException implements Exception {
  const OfflineModeException(this.operation);
  final String operation;
}

abstract interface class NetworkAccessPolicy {
  bool get isOnlineAccessAllowed;
  void requireOnlineAccess(String operation);
}

final networkAccessPolicyProvider = Provider<NetworkAccessPolicy>(
  _RiverpodNetworkAccessPolicy.new,
);

class _RiverpodNetworkAccessPolicy implements NetworkAccessPolicy {
  _RiverpodNetworkAccessPolicy(this._ref);
  final Ref _ref;

  @override
  bool get isOnlineAccessAllowed => _ref.read(onlineAccessAllowedProvider);

  @override
  void requireOnlineAccess(String operation) {
    if (isOnlineAccessAllowed) return;
    assert(() {
      developer.log(
        'operation=$operation reason=offline_mode',
        name: 'NETWORK_ACCESS_BLOCKED',
      );
      return true;
    }());
    throw OfflineModeException(operation);
  }
}

/// Future remote repositories must use this boundary before any HTTP work.
class PolicyAwareRemoteGateway {
  const PolicyAwareRemoteGateway(this._policy);
  final NetworkAccessPolicy _policy;

  Future<T> run<T>(String operation, Future<T> Function() request) {
    _policy.requireOnlineAccess(operation);
    return request();
  }
}
