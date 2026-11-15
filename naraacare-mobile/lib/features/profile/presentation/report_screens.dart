import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/profile/data/profile_tab_api.dart';
import 'package:naraacare/features/profile/presentation/streak_screens.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/features/profile/profile_tab_providers.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_star_badge.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

String reportErrorMessage(AppLocalizations l10n, ApiError e) =>
    switch (e.code) {
      'REPORT_LIMIT_REACHED' => l10n.reportLimitReached,
      'REPORT_NO_DATA' => l10n.reportNoData,
      'REPORT_RANGE_INVALID' => l10n.reportRangeInvalid,
      'UPGRADE_REQUIRED' => l10n.reportNeedsStar,
      'CONSENT_REQUIRED' => l10n.reportNeedsAiConsent,
      _ => featureErrorMessage(l10n, e),
    };

String reportPeriod(BuildContext context, ReportJob job) {
  final f = DateFormat(
    'd MMM yyyy',
    Localizations.localeOf(context).toString(),
  );
  return AppLocalizations.of(context)
      .reportPeriod(f.format(job.from), f.format(job.to), job.days);
}

String reportTitle(AppLocalizations l10n, List<String> sections) {
  final names = [
    if (sections.contains('hydration')) l10n.hydrationLabel,
    if (sections.contains('nutrition')) l10n.nutritionLabel,
    if (sections.contains('sleep')) l10n.sleepLabel,
  ];
  return l10n.reportTitle(names.join(' & '));
}

/// Queues a report and opens its preview. One idempotency key per tap.
Future<void> _create(
  BuildContext context,
  WidgetRef ref, {
  required String type,
  required List<String> sections,
  DateTime? month,
  DateTime? from,
  DateTime? to,
}) async {
  final l10n = AppLocalizations.of(context);
  final api = ref.read(profileTabApiProvider);
  final key = const Uuid().v4();
  Future<String> send(List<String> s) => api.createReport(
    type: type,
    sections: s,
    month: month,
    from: from,
    to: to,
    idempotencyKey: s.length == sections.length ? key : const Uuid().v4(),
  );
  try {
    String id;
    try {
      id = await send(sections);
    } on ApiError catch (e) {
      // Insights need the AI consent: still make the report, without them.
      if (e.code != 'CONSENT_REQUIRED' || !sections.contains('insights')) {
        rethrow;
      }
      id = await send([...sections]..remove('insights'));
      if (context.mounted) {
        showNcToast(context, l10n.reportNeedsAiConsent, kind: NcToastKind.info);
      }
    }
    ref.invalidate(reportsProvider);
    if (context.mounted) unawaited(context.push(Routes.reportPreview(id)));
  } on ApiError catch (e) {
    if (context.mounted) {
      showNcToast(
        context,
        reportErrorMessage(l10n, e),
        kind: NcToastKind.error,
      );
    }
  }
}

/// Figma "Profile/ Streak/ Download Report" (STANDARD and STAR): monthly or
/// custom report, what is included, the STAR upsell, and recent reports.
class DownloadReportScreen extends ConsumerWidget {
  const new({super.key});

  Future<void> _monthly(BuildContext context, WidgetRef ref, bool star) async {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    // Months from the one the account was created in, newest first (owner).
    final joined = ref.read(meProvider).value?.memberSince ?? now;
    // Year first, then month, from the account's first month (owner).
    final month = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true, // above the tab bar
      isScrollControlled: true,
      builder: (context) => _MonthPicker(
        first: DateTime(joined.year, joined.month),
        last: DateTime(now.year, now.month),
        locale: locale,
        title: l10n.chooseMonth,
        yearLabel: l10n.chooseYear,
        action: l10n.createReport,
      ),
    );
    if (month == null || !context.mounted) return;
    await _create(
      context,
      ref,
      type: 'monthly',
      month: month,
      sections: [
        'hydration',
        'nutrition',
        if (star) ...['sleep', 'insights'],
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final star = ref.watch(meProvider).value?.isStar ?? false;
    final recent = ref.watch(reportsProvider).value ?? const <ReportJob>[];
    final small = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: nc.textSecondary);
    Widget option(
      String title,
      String hint,
      VoidCallback? onTap, {
      bool badge = false,
    }) => ProfileCard(
      onTap: onTap,
      colour: onTap == null ? nc.inputFill : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: onTap == null ? nc.textSecondary : null,
                      ),
                    ),
                    if (badge) ...[
                      const SizedBox(width: NcSpace.inputGap),
                      const NcStarBadge(),
                    ],
                  ],
                ),
                Text(hint, style: small),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
    Widget included(String emoji, String label) => Padding(
      padding: const EdgeInsets.only(right: NcSpace.sectionGap),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: NcSpace.xs),
          Text(label, style: small),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.downloadReport)),
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          Text(l10n.createNewReport, style: small),
          const SizedBox(height: NcSpace.inputGap),
          option(
            l10n.monthlyReport,
            l10n.monthlyReportHint,
            () => _monthly(context, ref, star),
          ),
          const SizedBox(height: NcSpace.buttonGap),
          option(
            l10n.customReport,
            l10n.customReportHint,
            star ? () => context.push(Routes.customReport) : null,
            badge: !star,
          ),
          const SizedBox(height: NcSpace.sectionGap),
          Text(l10n.whatsIncluded, style: small),
          const SizedBox(height: NcSpace.buttonGap),
          Row(
            children: [
              included('💧', l10n.hydrationLabel),
              included('🍽', l10n.nutritionLabel),
              if (star) ...[
                included('😴', l10n.sleepLabel),
                included('📄', l10n.insightsLabel),
              ],
            ],
          ),
          if (!star) ...[
            const SizedBox(height: NcSpace.sectionGap),
            ProfileCard(
              colour: nc.star.withAlpha(24),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: nc.star),
                  const SizedBox(width: NcSpace.buttonGap),
                  Expanded(child: Text(l10n.reportUpsell)),
                  const SizedBox(width: NcSpace.inputGap),
                  OutlinedButton(
                    onPressed: () => context.push(Routes.subscriptions),
                    child: Text(l10n.upgradeButton),
                  ),
                ],
              ),
            ),
          ],
          if (recent.isNotEmpty) ...[
            const SizedBox(height: NcSpace.sectionGap),
            Text(l10n.yourReports, style: small),
            const SizedBox(height: NcSpace.inputGap),
            for (final job in recent.take(10))
              Padding(
                padding: const EdgeInsets.only(bottom: NcSpace.inputGap),
                child: ProfileCard(
                  onTap: job.status == 'expired'
                      ? null
                      : () => context.push(Routes.reportPreview(job.id)),
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined, color: nc.primary),
                      const SizedBox(width: NcSpace.buttonGap),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(reportTitle(l10n, job.sections)),
                            Text(reportPeriod(context, job), style: small),
                          ],
                        ),
                      ),
                      Text(_statusLabel(l10n, job), style: small),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

String _statusLabel(AppLocalizations l10n, ReportJob job) =>
    switch (job.status) {
      'ready' => l10n.reportReady,
      'failed' => l10n.reportFailed,
      'expired' => l10n.reportExpired,
      _ => l10n.reportPreparing,
    };

/// Figma "Customize Report" (STAR): quick ranges, from / to and sections.
class CustomizeReportScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<CustomizeReportScreen> createState() => _CustomizeState();
}

class _CustomizeState extends ConsumerState<CustomizeReportScreen> {
  DateTime? _from;
  DateTime? _to;
  final _sections = <String>{'hydration', 'nutrition'};
  bool _busy = false;

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  void _quick(int days, {bool year = false}) => setState(() {
    _to = _today;
    _from = year
        ? DateTime(_today.year)
        : _today.subtract(Duration(days: days - 1));
  });

  Future<void> _pick({required bool from}) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2026),
      lastDate: _today,
      initialDate: (from ? _from : _to) ?? _today,
    );
    if (picked != null) setState(() => from ? _from = picked : _to = picked);
  }

  bool get _valid =>
      _from != null &&
      _to != null &&
      !_from!.isAfter(_to!) &&
      _to!.difference(_from!).inDays <= 365 &&
      _sections.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final fmt = DateFormat(
      'd MMM yyyy',
      Localizations.localeOf(context).toString(),
    );
    Widget dateField(String label, DateTime? value, {required bool from}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: NcSpace.buttonGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: NcSpace.xs),
              InkWell(
                borderRadius: BorderRadius.circular(NcRadius.m),
                onTap: () => _pick(from: from),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(
                    value == null
                        ? (from ? l10n.enterStartDate : l10n.enterEndDate)
                        : fmt.format(value),
                    style: TextStyle(
                      color: value == null ? nc.textSecondary : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
    Widget section(String key, String emoji, String label) => CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: _sections.contains(key),
      onChanged: (v) => setState(
        () => (v ?? false) ? _sections.add(key) : _sections.remove(key),
      ),
      title: Text('$emoji  $label'),
    );
    final quick = [
      (l10n.last7Days, () => _quick(7)),
      (l10n.last30Days, () => _quick(30)),
      (l10n.last3Months, () => _quick(91)),
      (l10n.last6Months, () => _quick(182)),
      (l10n.thisYear, () => _quick(0, year: true)),
    ];
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.customizeReport)),
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          Text(
            l10n.selectDateRange,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: NcSpace.inputGap),
          Wrap(
            spacing: NcSpace.inputGap,
            runSpacing: NcSpace.inputGap,
            children: [
              for (final (label, onTap) in quick)
                ActionChip(label: Text(label), onPressed: onTap),
            ],
          ),
          const SizedBox(height: NcSpace.cardGap),
          dateField(l10n.fromLabel, _from, from: true),
          dateField(l10n.toLabel, _to, from: false),
          if (_from != null && _to != null && !_valid && _sections.isNotEmpty)
            Text(l10n.reportRangeInvalid, style: TextStyle(color: nc.error)),
          const SizedBox(height: NcSpace.cardGap),
          Text(
            l10n.whatToInclude,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          section('hydration', '💧', l10n.hydrationLabel),
          section('nutrition', '🍽', l10n.nutritionLabel),
          section('sleep', '😴', l10n.sleepLabel),
          const SizedBox(height: NcSpace.sectionGap),
          NcButton(
            label: l10n.generateReport,
            loading: _busy,
            onPressed: !_valid
                ? null
                : () async {
                    setState(() => _busy = true);
                    await _create(
                      context,
                      ref,
                      type: 'custom',
                      from: _from,
                      to: _to,
                      sections: [..._sections, 'insights'],
                    );
                    if (mounted) setState(() => _busy = false);
                  },
          ),
        ],
      ),
    );
  }
}

const _downloads = MethodChannel('naraacare/downloads');

/// Copies a downloaded report into the phone's Downloads/NaraaCare folder
/// (Android 10+, MainActivity.savePdf). False on iOS (the app's folder is
/// visible in the Files app instead), older Android or any error: the
/// report stays in the app and Share still works.
Future<bool> saveToDownloads(File file) async {
  if (!Platform.isAndroid) return false;
  try {
    return await _downloads.invokeMethod<bool>('savePdf', {
          'path': file.path,
          'name': p.basename(file.path),
        }) ??
        false;
  } on PlatformException {
    return false;
  }
}

/// Downloads a ready report into the app's folder (if not there yet).
Future<File?> _download(
  BuildContext context,
  WidgetRef ref,
  ReportJob job,
) async {
  final l10n = AppLocalizations.of(context);
  try {
    return await ref.read(profileTabApiProvider).downloadReport(job);
  } on ApiError catch (e) {
    if (context.mounted) {
      showNcToast(
        context,
        reportErrorMessage(l10n, e),
        kind: NcToastKind.error,
      );
    }
  } on FileSystemException {
    if (context.mounted) {
      showNcToast(context, l10n.reportSaveFailed, kind: NcToastKind.error);
    }
  }
  return null;
}

Future<void> shareReport(BuildContext context, File file, String title) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      subject: title,
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

/// Figma "Report Preview": the period and sections while the PDF is built
/// (polled every 2 s, every 10 s after a minute with a "taking longer"
/// note), then Download Report / Share report.
class ReportPreviewScreen extends ConsumerStatefulWidget {
  const new({required this.reportId, super.key});

  final String reportId;

  @override
  ConsumerState<ReportPreviewScreen> createState() => _PreviewState();
}

class _PreviewState extends ConsumerState<ReportPreviewScreen> {
  ReportJob? _job;
  Timer? _poll;
  final _waiting = Stopwatch()..start();
  bool _busy = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final job = await ref.read(profileTabApiProvider).report(widget.reportId);
      if (!mounted) return;
      setState(() {
        _job = job;
        _error = false;
      });
      if (job.pending) {
        // Every 2 s at first, then every 10 s once it is slow.
        _poll = Timer(
          Duration(seconds: _slow ? 10 : 2),
          () => unawaited(_load()),
        );
      } else {
        ref.invalidate(reportsProvider);
      }
    } on ApiError {
      if (mounted) setState(() => _error = true);
    }
  }

  bool get _slow => _waiting.elapsed > const Duration(minutes: 1);

  Future<void> _save({required bool share}) async {
    final job = _job!;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final file = await _download(context, ref, job);
    if (!mounted) return;
    setState(() => _busy = false);
    if (file == null) return;
    if (share) {
      await shareReport(context, file, reportTitle(l10n, job.sections));
    } else {
      final inDownloads = await saveToDownloads(file);
      if (!mounted) return;
      unawaited(
        context.push(Routes.reportDownloaded(job.id, inDownloads: inDownloads)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final job = _job;
    final small = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: nc.textSecondary);
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.reportPreview)),
      body: job == null
          ? Center(
              child: _error
                  ? TextButton(onPressed: _load, child: Text(l10n.retry))
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: EdgeInsets.all(nc.screenPadding),
              children: [
                ProfileCard(
                  colour: nc.inputFill,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.reportSummary,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(reportPeriod(context, job), style: small),
                      const SizedBox(height: NcSpace.buttonGap),
                      Wrap(
                        spacing: NcSpace.inputGap,
                        children: [
                          for (final s in job.sections)
                            Chip(
                              avatar: Icon(
                                Icons.circle,
                                size: 8,
                                color: nc.primary,
                              ),
                              label: Text(switch (s) {
                                'hydration' => l10n.hydrationLabel,
                                'nutrition' => l10n.nutritionLabel,
                                'sleep' => l10n.sleepLabel,
                                _ => l10n.insightsLabel,
                              }),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: NcSpace.cardGap),
                ProfileCard(
                  colour: nc.primarySurface,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: nc.primary),
                      const SizedBox(width: NcSpace.buttonGap),
                      Expanded(child: Text(l10n.reportIncludes)),
                    ],
                  ),
                ),
                const SizedBox(height: NcSpace.sectionGap),
                if (job.pending) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: NcSpace.inputGap),
                  Text(
                    _slow ? l10n.reportSlow : l10n.reportPreparingLong,
                    textAlign: TextAlign.center,
                  ),
                ] else if (!job.ready)
                  Text(
                    job.status == 'expired'
                        ? l10n.reportExpired
                        : l10n.reportFailedLong,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: nc.error),
                  )
                else ...[
                  NcButton(
                    label: l10n.downloadReport,
                    loading: _busy,
                    onPressed: () => _save(share: false),
                  ),
                  const SizedBox(height: NcSpace.inputGap),
                  Builder(
                    builder: (context) => TextButton(
                      onPressed: _busy ? null : () => _save(share: true),
                      child: Text(l10n.shareReport),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Figma "Download Report Final page": saved confirmation with the file
/// card; Share opens the system share sheet.
class ReportDownloadedScreen extends ConsumerWidget {
  const new({required this.reportId, super.key, this.inDownloads = false});

  final String reportId;

  /// The copy is in the phone's Downloads/NaraaCare folder.
  final bool inDownloads;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final job = ref
        .watch(reportsProvider)
        .value
        ?.where((j) => j.id == reportId)
        .firstOrNull;
    final size = job?.sizeBytes;
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(),
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          const SizedBox(height: NcSpace.sectionGap),
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: nc.successSurface,
              ),
              child: Icon(Icons.verified_outlined, size: 56, color: nc.success),
            ),
          ),
          const SizedBox(height: NcSpace.sectionGap),
          Text(
            l10n.reportDownloaded,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            inDownloads
                ? l10n.reportSavedDownloads
                : Platform.isIOS
                ? l10n.reportSavedFiles
                : l10n.reportSavedBody,
            textAlign: TextAlign.center,
            style: TextStyle(color: nc.textSecondary),
          ),
          const SizedBox(height: NcSpace.sectionGap),
          if (job != null)
            ProfileCard(
              child: Row(
                children: [
                  Icon(Icons.description_outlined, color: nc.primary),
                  const SizedBox(width: NcSpace.buttonGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reportTitle(l10n, job.sections),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(reportPeriod(context, job)),
                        if (size != null)
                          Text(
                            l10n.reportSize((size / 1024).toStringAsFixed(0)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: NcSpace.sectionGap),
          if (job != null)
            Builder(
              builder: (context) => NcButton(
                label: l10n.shareReport,
                icon: Icons.share_outlined,
                onPressed: () async {
                  final file = await _download(context, ref, job);
                  if (file != null && context.mounted) {
                    await shareReport(
                      context,
                      file,
                      reportTitle(l10n, job.sections),
                    );
                  }
                },
              ),
            ),
          const SizedBox(height: NcSpace.inputGap),
          NcButton(
            label: l10n.done,
            variant: NcButtonVariant.ghost,
            onPressed: () => context.go(Routes.streak),
          ),
        ],
      ),
    );
  }
}

/// Year chips, then a 3 x 4 grid of months; months outside [first]..[last]
/// are disabled. Pops the chosen month (first day) or nothing.
class _MonthPicker extends StatefulWidget {
  const new({
    required this.first,
    required this.last,
    required this.locale,
    required this.title,
    required this.yearLabel,
    required this.action,
  });

  final DateTime first;
  final DateTime last;
  final String locale;
  final String title;
  final String yearLabel;
  final String action;

  @override
  State<_MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  late int _year = widget.last.year;
  int? _month;

  bool _allowed(int year, int month) {
    final m = DateTime(year, month);
    return !m.isBefore(widget.first) && !m.isAfter(widget.last);
  }

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final years = [
      for (var y = widget.last.year; y >= widget.first.year; y--) y,
    ];
    final names = DateFormat.MMM(widget.locale);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          nc.screenPadding,
          0,
          nc.screenPadding,
          nc.screenPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.yearLabel, style: text.titleMedium),
            const SizedBox(height: NcSpace.inputGap),
            Wrap(
              spacing: NcSpace.inputGap,
              runSpacing: NcSpace.inputGap,
              children: [
                for (final y in years)
                  ChoiceChip(
                    label: Text('$y'),
                    selected: y == _year,
                    onSelected: (_) => setState(() {
                      _year = y;
                      _month = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: NcSpace.cardGap),
            Text(widget.title, style: text.titleMedium),
            const SizedBox(height: NcSpace.inputGap),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: NcSpace.inputGap,
              crossAxisSpacing: NcSpace.inputGap,
              childAspectRatio: 2,
              children: [
                for (var m = 1; m <= 12; m++)
                  ChoiceChip(
                    label: SizedBox(
                      width: double.infinity,
                      child: Text(
                        names.format(DateTime(_year, m)),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    showCheckmark: false,
                    selected: m == _month,
                    onSelected: _allowed(_year, m)
                        ? (_) => setState(() => _month = m)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: NcSpace.cardGap),
            NcButton(
              label: widget.action,
              onPressed: _month == null
                  ? null
                  : () => Navigator.of(context).pop(DateTime(_year, _month!)),
            ),
          ],
        ),
      ),
    );
  }
}
