import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/care_circle/data/circle_data.dart'
    show AvatarType;
import 'package:naraacare/features/care_circle/presentation/avatar_share_sheet.dart';
import 'package:naraacare/features/nutrition/nutrition_providers.dart';
import 'package:naraacare/features/nutrition/presentation/widgets/nutrition_widgets.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/features/sleep/data/sleep_data.dart';
import 'package:naraacare/features/sleep/sleep_providers.dart';
import 'package:naraacare/shared/widgets/nc_avatar_card.dart';
import 'package:naraacare/shared/widgets/nc_avatar_figure.dart';
import 'package:naraacare/shared/widgets/nc_avatar_menu.dart';
import 'package:naraacare/shared/widgets/nc_bottom_sheet.dart';
import 'package:naraacare/shared/widgets/nc_star_badge.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';
import 'package:naraacare/shared/widgets/nc_wheel_picker.dart';

/// "7 h 30 m".
String hoursMinutes(AppLocalizations l10n, int minutes) =>
    l10n.hoursMinutes(minutes ~/ 60, minutes % 60);

String sleepLabel(AppLocalizations l10n, SleepLabel label) => switch (label) {
  SleepLabel.good => l10n.sleepGood,
  SleepLabel.fair => l10n.sleepFair,
  SleepLabel.low => l10n.sleepLow,
  SleepLabel.none => l10n.sleepNone,
};

String _time(BuildContext context, DateTime at) =>
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal()));

// ------------------------------------------------------------------ S1 card

/// The Sleep avatar page on Home (STAR): counted sleep, score and label (the
/// colour fill is the score); tap for Today's Sleep. The Log Sleep button
/// is on Home. STANDARD sees the blurred card "Unlock your Sleep Avatar",
/// which opens the upsell (the API refuses sleep for STANDARD anyway).
class SleepAvatarCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (!ref.watch(isStarProvider)) return const _LockedSleepCard();
    final summary = ref.watch(sleepSummaryProvider);
    final sex = ref.watch(meProvider).value?.profile.biologicalSex;
    final data = summary.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: data == null ? null : () => showTodaysSleep(context),
          child: NcAvatarStage(
            sex: sex,
            look: AvatarLook.neutral,
            fill: data == null ? 0 : (data.scorePct / 100).clamp(0, 1),
            onShare: () => showAvatarShareSheet(context, AvatarType.sleep),
            actions: [
              NcAvatarAction(
                icon: Icons.more_vert,
                tooltip: l10n.moreOptions,
                onPressed: () => showAvatarMenu(context, [
                  AvatarMenuItem(
                    icon: Icons.bedtime_outlined,
                    label: l10n.todaysSleep,
                    onTap: () => showTodaysSleep(context),
                  ),
                ]),
              ),
              NcAvatarAction(
                icon: Icons.info_outline,
                tooltip: l10n.sleepInfo,
                color: context.nc.star,
                onPressed: () => showSleepInfo(context),
              ),
            ],
            card: NcAvatarCard(
              label: l10n.avatarSleep,
              value: data == null
                  ? (summary.hasError ? l10n.sleepUnavailable : '…')
                  : data.countedMin == 0
                  ? l10n.sleepNotLogged
                  : hoursMinutes(l10n, data.countedMin),
              caption: data == null || data.countedMin == 0
                  ? null
                  : '${l10n.levelPct(data.scorePct)} · '
                        '${sleepLabel(l10n, data.label)}',
              icon: Icons.bedtime_outlined,
              progress: data == null ? 0 : (data.scorePct / 100).clamp(0, 1),
            ),
          ),
        ),
      ],
    );
  }
}

class _LockedSleepCard extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final sex = ref.watch(meProvider).value?.profile.biologicalSex;
    return InkWell(
      borderRadius: BorderRadius.circular(NcRadius.m),
      onTap: () => showStarUpsell(context),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: NcAvatarStage(
              sex: sex,
              look: AvatarLook.neutral,
              card: NcAvatarCard(
                label: l10n.avatarSleep,
                value: hoursMinutes(l10n, 450),
                icon: Icons.bedtime_outlined,
                progress: 0.9,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NcStarBadge(),
              const SizedBox(height: NcSpace.xs),
              Text(
                l10n.unlockSleepAvatar,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: nc.star),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ S2 today

/// "Today's Sleep": entries, total against the goal, score and label, the
/// buffers explanation (OQ-23) and the editable goal (PUT /me/sleep-goal).
Future<void> showTodaysSleep(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showNcBottomSheet<void>(
    context: context,
    title: l10n.todaysSleep,
    builder: (context) => const _TodaysSleep(),
  );
}

class _TodaysSleep extends ConsumerWidget {
  const new();

  static final List<int> _goals = [for (var m = 240; m <= 720; m += 15) m];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final s = ref.watch(sleepSummaryProvider).value;
    if (s == null) return const Center(child: CircularProgressIndicator());
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.countedMin == 0
              ? l10n.sleepNotLogged
              : l10n.sleepOfGoal(
                  hoursMinutes(l10n, s.countedMin),
                  hoursMinutes(l10n, s.goalMin),
                ),
          style: text.titleLarge,
        ),
        if (s.countedMin > 0)
          Text(
            '${l10n.levelPct(s.scorePct)} · ${sleepLabel(l10n, s.label)}',
            style: text.titleSmall?.copyWith(color: nc.primary),
          ),
        const SizedBox(height: NcSpace.cardGap),
        for (final e in s.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bedtime_outlined),
            title: Text(
              '${_time(context, e.sleepStart)} – ${_time(context, e.wakeTime)}',
            ),
            subtitle: Text(
              [
                hoursMinutes(l10n, e.countedMin),
                if (e.wakings.isNotEmpty) l10n.nightWakings(e.wakings.length),
              ].join(' · '),
            ),
            trailing: e.editable
                ? IconButton(
                    tooltip: l10n.editEntry,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () {
                      Navigator.of(context).pop();
                      unawaited(context.push(Routes.updateSleep, extra: e));
                    },
                  )
                : null,
          ),
        const SizedBox(height: NcSpace.inputGap),
        Text(
          l10n.sleepBuffersExplain(
            s.onsetBufferMin,
            s.wakeBufferMin,
            s.wakingBufferMin,
          ),
          style: text.bodySmall?.copyWith(color: nc.textSecondary),
        ),
        const SizedBox(height: NcSpace.cardGap),
        Text(l10n.sleepGoal, style: text.titleSmall),
        NcWheelPicker<int>(
          values: _goals,
          selected: _goals.reduce(
            (a, b) => (a - s.goalMin).abs() <= (b - s.goalMin).abs() ? a : b,
          ),
          labelOf: (m) => hoursMinutes(l10n, m),
          onChanged: (m) async {
            try {
              await ref.read(sleepApiProvider).setGoal(m);
              ref.invalidate(sleepSummaryProvider);
            } on ApiError catch (e) {
              if (context.mounted) {
                showNcToast(
                  context,
                  featureErrorMessage(l10n, e),
                  kind: NcToastKind.error,
                );
              }
            }
          },
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ S3 update

/// "Update Sleep": sleep and wake times on wheels (no typing), night wakings
/// with "Add night waking"; editing one of the last 2 entries (If-Match).
class UpdateSleepScreen extends ConsumerStatefulWidget {
  const new({super.key, this.entry});

  final SleepEntry? entry;

  @override
  ConsumerState<UpdateSleepScreen> createState() => _UpdateSleepScreenState();
}

class _UpdateSleepScreenState extends ConsumerState<UpdateSleepScreen> {
  static const _maxWakings = 10;
  late DateTime _start;
  late DateTime _wake;
  late List<NightWaking> _wakings;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    final now = DateTime.now();
    final today7 = DateTime(now.year, now.month, now.day, 7);
    _wake = e?.wakeTime.toLocal() ?? (now.isBefore(today7) ? now : today7);
    _start =
        e?.sleepStart.toLocal() ?? _wake.subtract(const Duration(hours: 8));
    _wakings = [...?e?.wakings];
  }

  String? _problem(AppLocalizations l10n) {
    if (!_wake.isAfter(_start)) return l10n.sleepWakeAfterStart;
    if (_wake.difference(_start) > const Duration(hours: 16)) {
      return l10n.sleepTooLong;
    }
    if (_wake.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return l10n.sleepInFuture;
    }
    var previous = _start;
    for (final w in _wakings) {
      if (!w.backAsleepAt.isAfter(w.wokeAt) ||
          w.wokeAt.isBefore(previous) ||
          w.backAsleepAt.isAfter(_wake)) {
        return l10n.sleepWakingsInvalid;
      }
      previous = w.backAsleepAt;
    }
    return null;
  }

  Future<DateTime?> _pick(DateTime initial) => showModalBottomSheet<DateTime>(
    context: context,
    builder: (context) {
      var picked = initial;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 216,
              child: CupertinoDatePicker(
                initialDateTime: initial,
                minimumDate: DateTime.now().subtract(const Duration(days: 8)),
                maximumDate: DateTime.now().add(const Duration(minutes: 5)),
                onDateTimeChanged: (v) => picked = v,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(picked),
              child: Text(AppLocalizations.of(context).continueButton),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final problem = _problem(l10n);
    if (problem != null) {
      showNcToast(context, problem, kind: NcToastKind.error);
      return;
    }
    setState(() => _busy = true);
    try {
      final e = widget.entry;
      var queued = false;
      if (e == null) {
        queued = await ref
            .read(sleepRepositoryProvider)
            .logEntry(sleepStart: _start, wakeTime: _wake, wakings: _wakings);
      } else {
        final api = ref.read(sleepApiProvider);
        await api.updateEntry(
          e.entryId,
          e.version,
          api.entryBody(sleepStart: _start, wakeTime: _wake, wakings: _wakings),
        );
      }
      if (!mounted) return;
      ref.invalidate(sleepSummaryProvider);
      showNcToast(context, queued ? l10n.savedOffline : l10n.sleepSaved);
      context.pop();
    } on ApiError catch (err) {
      if (!mounted) return;
      if (err.code == 'UPGRADE_REQUIRED') {
        unawaited(showStarUpsell(context));
      } else {
        showNcToast(context, switch (err.code) {
          'SLEEP_OVERLAP' => l10n.sleepOverlap,
          'VERSION_CONFLICT' => l10n.changedElsewhere,
          _ => featureErrorMessage(l10n, err),
        }, kind: NcToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(SleepEntry e) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(sleepApiProvider).deleteEntry(e.entryId, e.version);
      if (!mounted) return;
      ref.invalidate(sleepSummaryProvider);
      showNcToast(context, l10n.entryDeleted);
      context.pop();
    } on ApiError catch (err) {
      if (mounted) {
        showNcToast(
          context,
          featureErrorMessage(l10n, err),
          kind: NcToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    Widget timeRow(String label, DateTime value, ValueChanged<DateTime> set) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          trailing: Text(_time(context, value), style: text.titleMedium),
          onTap: () async {
            final picked = await _pick(value);
            if (picked != null) setState(() => set(picked));
          },
        );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.updateSleep)),
      backgroundColor: nc.surface,
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          timeRow(l10n.sleepStartLabel, _start, (v) => _start = v),
          timeRow(l10n.wakeTimeLabel, _wake, (v) => _wake = v),
          const SizedBox(height: NcSpace.cardGap),
          Text(l10n.nightWakingsTitle, style: text.titleSmall),
          for (var i = 0; i < _wakings.length; i++)
            Row(
              children: [
                Expanded(
                  child: timeRow(
                    l10n.wokeAtLabel,
                    _wakings[i].wokeAt.toLocal(),
                    (v) => _wakings[i] = NightWaking(
                      wokeAt: v,
                      backAsleepAt: _wakings[i].backAsleepAt,
                    ),
                  ),
                ),
                const SizedBox(width: NcSpace.inputGap),
                Expanded(
                  child: timeRow(
                    l10n.backAsleepLabel,
                    _wakings[i].backAsleepAt.toLocal(),
                    (v) => _wakings[i] = NightWaking(
                      wokeAt: _wakings[i].wokeAt,
                      backAsleepAt: v,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.removeItem,
                  icon: Icon(Icons.close, color: nc.error),
                  onPressed: () => setState(() => _wakings.removeAt(i)),
                ),
              ],
            ),
          if (_wakings.length < _maxWakings)
            TextButton.icon(
              onPressed: () => setState(() {
                final from = _wakings.isEmpty
                    ? _start.add(_wake.difference(_start) ~/ 2)
                    : _wakings.last.backAsleepAt.add(
                        const Duration(minutes: 30),
                      );
                _wakings.add(
                  NightWaking(
                    wokeAt: from,
                    backAsleepAt: from.add(const Duration(minutes: 15)),
                  ),
                );
              }),
              icon: const Icon(Icons.add),
              label: Text(l10n.addNightWaking),
            ),
          const SizedBox(height: NcSpace.sectionGap),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(l10n.saveSleep),
          ),
          if (widget.entry != null) ...[
            const SizedBox(height: NcSpace.inputGap),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: nc.error),
              onPressed: _busy ? null : () => _delete(widget.entry!),
              child: Text(l10n.deleteEntry),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ S4 info

/// Sleep "Information", with the counting rules of OQ-23 (buffers).
Future<void> showSleepInfo(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showNcBottomSheet<void>(
    context: context,
    title: l10n.sleepInfo,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.sleepInfoHowTitle, style: text.titleSmall),
          const SizedBox(height: NcSpace.xs),
          Text(l10n.sleepInfoHowBody),
          const SizedBox(height: NcSpace.cardGap),
          Text(l10n.sleepInfoGoalTitle, style: text.titleSmall),
          const SizedBox(height: NcSpace.xs),
          Text(l10n.sleepInfoGoalBody),
          const SizedBox(height: NcSpace.cardGap),
          Text(l10n.infoNoteTitle, style: text.titleSmall),
          const SizedBox(height: NcSpace.xs),
          Text(l10n.sleepInfoNoteBody),
        ],
      );
    },
  );
}
