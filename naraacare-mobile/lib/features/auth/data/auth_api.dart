import 'package:naraacare/core/network/api_client.dart';
import 'package:naraacare/core/security/secure_storage.dart';

/// A one-time-code challenge (sign-up verification or password reset).
typedef Challenge = ({String challengeId, int resendAfterSeconds});

/// Policy versions the user accepts at sign-up (GET /reference/policies).
typedef PolicyVersions = ({String terms, String privacy});

/// The S05 auth endpoints (doc 04 section 2.1). Values are sent exactly as
/// validated by the screens; tokens never leave this layer except into the
/// auth controller (secure storage).
class AuthApi {
  const new(this.api, this.storage);

  final ApiClient api;
  final SecureStorage storage;

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body, {
    bool withInstallation = false,
  }) async {
    final payload = {
      ...body,
      if (withInstallation) 'installation_id': await storage.installationId(),
    };
    final response = await api.post(
      path,
      body: payload,
      options: ApiClient.public,
    );
    return response! as Map<String, dynamic>;
  }

  Future<PolicyVersions> policyVersions() async {
    final body = (await api.get('reference/policies'))! as Map<String, dynamic>;
    String version(String type) =>
        ((body['policies'] as List).cast<Map<String, dynamic>>().firstWhere(
              (p) => p['type'] == type,
            )['version'])
            as String;
    return (terms: version('terms'), privacy: version('privacy'));
  }

  Future<Challenge> signUp({
    required String email,
    required String password,
    required String confirmPassword,
    required PolicyVersions policies,
  }) async {
    final body = await _post('auth/signup', {
      'email': email,
      'password': password,
      'confirm_password': confirmPassword,
      'accept_terms': true,
      'policy_versions': {'terms': policies.terms, 'privacy': policies.privacy},
    }, withInstallation: true);
    return (
      challengeId: body['challenge_id'] as String,
      resendAfterSeconds: body['resend_after_s'] as int,
    );
  }

  /// Returns a TokenPair body.
  Future<Map<String, dynamic>> verifyEmail({
    required String challengeId,
    required String code,
  }) => _post('auth/otp/verify', {
    'challenge_id': challengeId,
    'code': code,
  }, withInstallation: true);

  /// Seconds until the next resend is allowed.
  Future<int> resendCode(String challengeId) async {
    final body = await _post('auth/otp/resend', {'challenge_id': challengeId});
    return body['resend_after_s'] as int;
  }

  Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
  }) => _post('auth/login', {
    'email': email,
    'password': password,
  }, withInstallation: true);

  Future<Map<String, dynamic>> google({
    required String idToken,
    required String nonce,
  }) => _post('auth/oauth/google', {
    'id_token': idToken,
    'nonce': nonce,
  }, withInstallation: true);

  Future<Map<String, dynamic>> apple({
    required String identityToken,
    required String? authorizationCode,
    required String nonce,
  }) => _post('auth/oauth/apple', {
    'identity_token': identityToken,
    'authorization_code': ?authorizationCode,
    'nonce': nonce,
  }, withInstallation: true);

  /// After 409 LINK_REQUIRED: proves the existing account with its password.
  Future<Map<String, dynamic>> link({
    required String linkToken,
    required String password,
  }) => _post('auth/oauth/link', {
    'link_token': linkToken,
    'password': password,
  }, withInstallation: true);

  /// Always answers the same whether or not the email exists (no account
  /// enumeration); the returned challenge is used with the emailed code.
  Future<String> forgotPassword(String email) async {
    final body = await _post('auth/password/forgot', {'email': email});
    return body['challenge_id'] as String;
  }

  Future<void> resetPassword({
    required String challengeId,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) => api.post(
    'auth/password/reset',
    body: {
      'challenge_id': challengeId,
      'code': code,
      'new_password': newPassword,
      'confirm_password': confirmPassword,
    },
    options: ApiClient.public,
  );

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) => api.post(
    'auth/password/change',
    body: {
      'current_password': currentPassword,
      'new_password': newPassword,
      'confirm_password': confirmPassword,
    },
  );
}
