import 'dart:io';

import 'package:dio/dio.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// A policy whose new major version the user has not accepted yet.
class PolicyUpdate {
  const new({
    required this.docType,
    required this.currentVersion,
    required this.url,
    this.acceptedVersion,
  });

  /// terms | privacy
  final String docType;
  final String currentVersion;
  final String? acceptedVersion;
  final String url;
}

/// A data export request (doc 04 section 2.13).
class ExportJob {
  const new({
    required this.id,
    required this.status,
    required this.requestedAt,
    this.expiresAt,
    this.sizeBytes,
  });

  factory fromJson(Map<String, dynamic> json) => ExportJob(
    id: json['export_id'] as String,
    status: json['status'] as String,
    requestedAt: DateTime.parse(json['requested_at'] as String),
    expiresAt: json['expires_at'] == null
        ? null
        : DateTime.parse(json['expires_at'] as String),
    sizeBytes: (json['size_bytes'] as num?)?.toInt(),
  );

  final String id;

  /// queued | running | ready | failed | expired
  final String status;
  final DateTime requestedAt;
  final DateTime? expiresAt;
  final int? sizeBytes;

  bool get ready => status == 'ready';
  bool get pending => status == 'queued' || status == 'running';
}

/// GET /privacy/status, read at launch.
class PrivacyStatus {
  const new({required this.policyUpdates, this.deletionAt, this.latestExport});

  factory fromJson(Map<String, dynamic> json) {
    final deletion = json['deletion'] as Map<String, dynamic>?;
    final export = json['latest_export'] as Map<String, dynamic>?;
    return PrivacyStatus(
      deletionAt: deletion == null
          ? null
          : DateTime.parse(deletion['scheduled_for'] as String),
      policyUpdates: [
        for (final r
            in (json['reconsent'] as List? ?? const [])
                .cast<Map<String, dynamic>>())
          PolicyUpdate(
            docType: r['doc_type'] as String,
            currentVersion: r['current_version'] as String,
            acceptedVersion: r['accepted_version'] as String?,
            url: r['url'] as String,
          ),
      ],
      latestExport: export == null ? null : ExportJob.fromJson(export),
    );
  }

  /// When the account will be erased (a deletion is scheduled).
  final DateTime? deletionAt;
  final List<PolicyUpdate> policyUpdates;
  final ExportJob? latestExport;
}

class ConsentState {
  const new({
    required this.purpose,
    required this.granted,
    required this.policyVersion,
    required this.recordedAt,
  });

  final String purpose;
  final bool granted;
  final String policyVersion;
  final DateTime recordedAt;
}

/// Proof of identity before an export or deletion: the password, or a code
/// emailed by [PrivacyApi.startReauth].
class ReauthProof {
  const new password(String this.password) : challengeId = null, code = null;
  const new code({required String this.challengeId, required String this.code})
    : password = null;

  final String? password;
  final String? challengeId;
  final String? code;

  Map<String, Object?> toJson() => {
    'password': ?password,
    'challenge_id': ?challengeId,
    'code': ?code,
  };
}

/// Privacy calls (doc 04 section 2.13, doc 07 SEC-7). The user is the
/// token's subject; ids come from the server.
class PrivacyApi {
  const new(this.api);

  final ApiClient api;
  static const _uuid = Uuid();

  Future<PrivacyStatus> status() async => PrivacyStatus.fromJson(
    (await api.get('privacy/status'))! as Map<String, dynamic>,
  );

  Future<List<ConsentState>> consents() async => [
    for (final c
        in (((await api.get('privacy/consents'))!
                    as Map<String, dynamic>)['consents']
                as List)
            .cast<Map<String, dynamic>>())
      ConsentState(
        purpose: c['purpose'] as String,
        granted: c['granted'] as bool,
        policyVersion: c['policy_version'] as String,
        recordedAt: DateTime.parse(c['recorded_at'] as String),
      ),
  ];

  /// Appends a decision (a withdrawal is `granted: false`, never an edit).
  Future<void> recordConsent({
    required String purpose,
    required String policyVersion,
    required bool granted,
  }) => api.post(
    'privacy/consents',
    body: {
      'purpose': purpose,
      'policy_version': policyVersion,
      'granted': granted,
    },
  );

  /// Emails a 6-digit code; returns the challenge id.
  Future<String> startReauth() async =>
      ((await api.post('privacy/reauth'))!
              as Map<String, dynamic>)['challenge_id']
          as String;

  Future<String> requestExport(ReauthProof proof) async =>
      ((await api.post(
                'privacy/exports',
                body: proof.toJson(),
                options: Options(headers: {'Idempotency-Key': _uuid.v4()}),
              ))!
              as Map<String, dynamic>)['export_id']
          as String;

  Future<ExportJob> export(String id) async => ExportJob.fromJson(
    (await api.get('privacy/exports/$id'))! as Map<String, dynamic>,
  );

  /// Saves a ready export in the app's private folder (wiped on sign-out).
  /// Always our own API path, so the token only goes to our server.
  Future<File> downloadExport(ExportJob job) async {
    final Response<List<int>> response;
    try {
      response = await api.dio.get<List<int>>(
        'privacy/exports/${job.id}/file',
        options: Options(responseType: ResponseType.bytes),
      );
    } on DioException catch (e) {
      throw ApiClient.toApiError(e);
    }
    final dir = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'exports'),
    );
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'NaraaCare-data-export.zip'));
    await file.writeAsBytes(response.data!, flush: true);
    return file;
  }

  /// Returns when the account will be erased.
  Future<DateTime> requestDeletion(ReauthProof proof) async => DateTime.parse(
    ((await api.post('privacy/deletion-request', body: proof.toJson()))!
            as Map<String, dynamic>)['scheduled_for']
        as String,
  );

  Future<void> cancelDeletion() => api.delete('privacy/deletion-request');
}
