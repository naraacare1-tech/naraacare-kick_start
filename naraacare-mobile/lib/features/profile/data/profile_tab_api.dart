import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// GET /me/streak (doc 04 section 2.7).
class StreakInfo {
  const new({
    required this.current,
    required this.longest,
    required this.brokenYesterday,
    required this.today,
    required this.activeDays,
    required this.lastSevenDays,
  });

  factory fromJson(Map<String, dynamic> json) {
    DateTime day(Object? v) => DateTime.parse(v! as String);
    Map<DateTime, bool> days(Object? list) => {
      for (final d in (list as List? ?? const []).cast<Map<String, dynamic>>())
        day(d['date']): d['active'] as bool,
    };
    return StreakInfo(
      current: json['current'] as int,
      longest: json['longest'] as int,
      brokenYesterday: json['broken_yesterday'] as bool? ?? false,
      today: day(json['today']),
      activeDays: days(json['days']),
      lastSevenDays: days(json['last_7_days']),
    );
  }

  final int current;
  final int longest;
  final bool brokenYesterday;
  final DateTime today;

  /// Days of the requested month up to today -> active.
  final Map<DateTime, bool> activeDays;

  /// Today and the 6 days before it -> active (the week strip).
  final Map<DateTime, bool> lastSevenDays;
}

/// A PDF report job (doc 04 section 2.11).
class ReportJob {
  const new({
    required this.id,
    required this.type,
    required this.from,
    required this.to,
    required this.sections,
    required this.status,
    this.sizeBytes,
    this.expiresAt,
  });

  factory fromJson(Map<String, dynamic> json) => ReportJob(
    id: json['report_id'] as String,
    type: json['type'] as String,
    from: DateTime.parse(json['from'] as String),
    to: DateTime.parse(json['to'] as String),
    sections: (json['sections'] as List).cast<String>(),
    status: json['status'] as String,
    sizeBytes: json['size_bytes'] as int?,
    expiresAt: json['expires_at'] == null
        ? null
        : DateTime.parse(json['expires_at'] as String),
  );

  final String id;

  /// monthly | custom
  final String type;
  final DateTime from;
  final DateTime to;

  /// hydration | nutrition | sleep | insights
  final List<String> sections;

  /// queued | running | ready | failed | expired
  final String status;
  final int? sizeBytes;
  final DateTime? expiresAt;

  bool get ready => status == 'ready';
  bool get pending => status == 'queued' || status == 'running';
  int get days => to.difference(from).inDays + 1;
}

class Faq {
  const new({required this.id, required this.question, required this.answer});

  final String id;
  final String question;
  final String answer;
}

class SupportContact {
  const new({
    required this.email,
    this.emailResponse,
    this.phone,
    this.phoneHours,
    this.phoneRequiresStar = false,
  });

  final String email;
  final String? emailResponse;
  final String? phone;
  final String? phoneHours;
  final bool phoneRequiresStar;
}

/// A screenshot picked for Report a problem. The server checks, re-encodes
/// and strips it; the app only reads the bytes the picker returned.
class Screenshot {
  const new({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// Streak, reports and Help & Support calls (doc 04 sections 2.7, 2.11,
/// 2.13). The user is the token's subject; ids come from the server.
class ProfileTabApi {
  const new(this.api);

  final ApiClient api;
  static const _uuid = Uuid();

  Future<StreakInfo> streak({DateTime? month}) async => StreakInfo.fromJson(
    (await api.get(
          'me/streak',
          query: {
            if (month != null)
              'month':
                  '${month.year.toString().padLeft(4, '0')}-'
                  '${month.month.toString().padLeft(2, '0')}',
          },
        ))!
        as Map<String, dynamic>,
  );

  // ---------------------------------------------------------- reports
  /// Queues a report. The idempotency key is made once per tap, so a retry
  /// after a lost response returns the same job instead of a second one.
  Future<String> createReport({
    required String type,
    required List<String> sections,
    DateTime? month,
    DateTime? from,
    DateTime? to,
    String? idempotencyKey,
  }) async {
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    final json =
        (await api.post(
              'reports',
              body: {
                'type': type,
                'sections': sections,
                if (month != null) 'month': day(month).substring(0, 7),
                if (from != null) 'from': day(from),
                if (to != null) 'to': day(to),
              },
              options: Options(
                headers: {'Idempotency-Key': idempotencyKey ?? _uuid.v4()},
              ),
            ))!
            as Map<String, dynamic>;
    return json['report_id'] as String;
  }

  Future<ReportJob> report(String id) async => ReportJob.fromJson(
    (await api.get('reports/$id'))! as Map<String, dynamic>,
  );

  Future<List<ReportJob>> reports() async => [
    for (final j
        in (((await api.get('reports'))! as Map<String, dynamic>)['items']
                as List)
            .cast<Map<String, dynamic>>())
      ReportJob.fromJson(j),
  ];

  /// Downloads a ready report into the app's documents folder (private to the
  /// app) and returns the file. Always our own API path, never a URL from
  /// elsewhere, so the sign-in token only goes to our server.
  Future<File> downloadReport(ReportJob job) async {
    final Response<List<int>> response;
    try {
      response = await api.dio.get<List<int>>(
        'reports/${job.id}/file',
        options: Options(responseType: ResponseType.bytes),
      );
    } on DioException catch (e) {
      throw ApiClient.toApiError(e);
    }
    final dir = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'reports'),
    );
    await dir.create(recursive: true);
    String day(DateTime d) =>
        d.toIso8601String().substring(0, 10).replaceAll('-', '');
    final file = File(
      p.join(dir.path, 'NaraaCare-report-${day(job.from)}-${day(job.to)}.pdf'),
    );
    await file.writeAsBytes(response.data!, flush: true);
    return file;
  }

  // ---------------------------------------------------------- support
  Future<(List<Faq>, SupportContact)> faqs({String? query}) async {
    final json =
        (await api.get('support/faqs', query: {'q': ?query}))!
            as Map<String, dynamic>;
    final contact = json['contact'] as Map<String, dynamic>;
    return (
      [
        for (final f in (json['items'] as List).cast<Map<String, dynamic>>())
          Faq(
            id: f['id'] as String,
            question: f['question'] as String,
            answer: f['answer'] as String,
          ),
      ],
      SupportContact(
        email: contact['email'] as String,
        emailResponse: contact['email_response'] as String?,
        phone: contact['phone'] as String?,
        phoneHours: contact['phone_hours'] as String?,
        phoneRequiresStar: (contact['phone_requires_star'] as bool?) ?? false,
      ),
    );
  }

  Future<String> reportProblem({
    required String category,
    required String description,
    Screenshot? screenshot,
  }) async {
    final form = FormData.fromMap({
      'category': category,
      'description': description,
      if (screenshot != null)
        'screenshot': MultipartFile.fromBytes(
          screenshot.bytes,
          filename: screenshot.name,
        ),
    });
    final json =
        (await api.post('support/tickets', body: form))!
            as Map<String, dynamic>;
    return json['ticket_ref'] as String;
  }

  Future<void> requestFeature({
    required String title,
    required String benefit,
  }) => api.post(
    'support/feature-requests',
    body: {'title': title, 'benefit': benefit},
  );
}
