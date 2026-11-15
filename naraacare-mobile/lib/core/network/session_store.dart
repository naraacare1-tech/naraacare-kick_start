import 'dart:async';

import 'package:naraacare/core/security/secure_storage.dart';
import 'package:naraacare/core/utils/clock.dart';

/// Holds the current tokens (in memory and in secure storage) and tells the
/// rest of the app when the session ends.
class SessionStore {
  new(this._storage, {this.clock = const SystemClock()});

  final SecureStorage _storage;
  final Clock clock;
  final _ended = StreamController<void>.broadcast();
  StoredTokens? _tokens;
  bool _loaded = false;

  /// Fires when the session is over (refresh refused, logout, reset).
  Stream<void> get sessionEnded => _ended.stream;

  Future<StoredTokens?> tokens() async {
    if (!_loaded) {
      _tokens = await _storage.readTokens();
      _loaded = true;
    }
    return _tokens;
  }

  Future<void> save({
    required String accessToken,
    required String refreshToken,
    required int accessExpiresInSeconds,
  }) async {
    _tokens = StoredTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessExpiresAt: clock.now().add(
        Duration(seconds: accessExpiresInSeconds),
      ),
    );
    _loaded = true;
    await _storage.writeTokens(_tokens!);
  }

  Future<void> clear({bool notify = true}) async {
    _tokens = null;
    _loaded = true;
    await _storage.clearTokens();
    if (notify) _ended.add(null);
  }

  Future<void> dispose() => _ended.close();
}
