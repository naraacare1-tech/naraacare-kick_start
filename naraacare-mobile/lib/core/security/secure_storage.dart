import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Abstraction over the platform keystore so tests can use
/// [MemoryKeyValueStore].
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Keychain (iOS, `first_unlock_this_device`: never in backups, never on
/// another device) / Android Keystore-backed storage (doc 07 SEC-5.1).
class PlatformKeyValueStore implements KeyValueStore {
  const new([
    this._storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Session tokens with their expiry.
class StoredTokens {
  const new({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
}

/// Everything secret the app keeps on the device: tokens, the local database
/// key and the installation id. Never SharedPreferences or files.
class SecureStorage {
  const new(this._store);

  final KeyValueStore _store;

  static const _accessToken = 'auth.access_token';
  static const _refreshToken = 'auth.refresh_token';
  static const _accessExpiresAt = 'auth.access_expires_at';
  static const _databaseKey = 'db.key';
  static const _installationId = 'device.installation_id';
  static const _introSeen = 'app.intro_seen';
  static const _pendingReferral = 'referral.pending_code';

  Future<StoredTokens?> readTokens() async {
    final access = await _store.read(_accessToken);
    final refresh = await _store.read(_refreshToken);
    final expires = await _store.read(_accessExpiresAt);
    if (access == null || refresh == null || expires == null) return null;
    final at = DateTime.tryParse(expires);
    if (at == null) return null;
    return StoredTokens(
      accessToken: access,
      refreshToken: refresh,
      accessExpiresAt: at,
    );
  }

  Future<void> writeTokens(StoredTokens tokens) async {
    await _store.write(_accessToken, tokens.accessToken);
    await _store.write(_refreshToken, tokens.refreshToken);
    await _store.write(
      _accessExpiresAt,
      tokens.accessExpiresAt.toUtc().toIso8601String(),
    );
  }

  Future<void> clearTokens() async {
    await _store.delete(_accessToken);
    await _store.delete(_refreshToken);
    await _store.delete(_accessExpiresAt);
  }

  /// A random 256-bit key for SQLCipher, created on first use. Losing it (app
  /// reinstall) only loses the local cache: the server holds the data.
  Future<String> databaseKey() async {
    final existing = await _store.read(_databaseKey);
    if (existing != null) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = base64Url.encode(bytes);
    await _store.write(_databaseKey, key);
    return key;
  }

  Future<void> deleteDatabaseKey() => _store.delete(_databaseKey);

  /// Random per-installation id (UUIDv7); sent at sign-in so refresh tokens
  /// only work on this installation (doc 04 section 2.1).
  Future<String> installationId() async {
    final existing = await _store.read(_installationId);
    if (existing != null) return existing;
    final id = const Uuid().v7();
    await _store.write(_installationId, id);
    return id;
  }

  Future<bool> introSeen() => readFlag(_introSeen);

  Future<void> markIntroSeen() => writeFlag(_introSeen, value: true);

  /// Referral code from an invite link, kept until it is sent to the API
  /// after sign-up (S11). Validated before it is stored.
  Future<String?> pendingReferralCode() => _store.read(_pendingReferral);

  Future<void> setPendingReferralCode(String code) =>
      _store.write(_pendingReferral, code);

  Future<void> clearPendingReferralCode() => _store.delete(_pendingReferral);

  /// Small non-secret app flags kept with the session (cleared on reinstall
  /// together with the tokens, unlike SharedPreferences on Android).
  Future<bool> readFlag(String key) async => await _store.read(key) == 'true';

  Future<void> writeFlag(String key, {required bool value}) =>
      _store.write(key, '$value');
}
