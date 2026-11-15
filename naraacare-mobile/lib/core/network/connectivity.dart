import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Online/offline as a stream of booleans (drives the offline banner and the
/// outbox). "Online" means a network interface is up; requests can still fail,
/// which the sync engine treats as "try again later".
abstract interface class ConnectivityMonitor {
  Stream<bool> get onlineChanges;
  Future<bool> isOnline();
}

class PlatformConnectivity implements ConnectivityMonitor {
  new([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _online(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Stream<bool> get onlineChanges =>
      _connectivity.onConnectivityChanged.map(_online).distinct();

  @override
  Future<bool> isOnline() async =>
      _online(await _connectivity.checkConnectivity());
}
