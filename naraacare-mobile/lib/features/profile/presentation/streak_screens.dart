import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/profile/data/profile_tab_api.dart';
import 'package:naraacare/features/profile/profile_tab_providers.dart';

const _fire = Color(0xFFF59E0B);

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// A white rounded card used across the Profile tab screens.
class ProfileCard extends StatelessWidget {
  const new({required this.child, super.key, this.onTap, this.colour});

  final Widget child;
  final VoidCallback? onTap;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    return Material(
      color: colour ?? nc.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NcRadius.l),
        side: BorderSide(color: colour == null ? nc.inputFill : colour!),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(NcSpace.cardPadding),
          child: child,
        ),
      ),
    );
  }
}

/// Figma "Profile/ Streak" and "Profile/ Streak/ Break": the current streak,
/// this week's days, the rule (or the Streak Broken message) and the way to
/// Download report. Tapping the week opens the calendar.
class ActiveStreakScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final streak = ref.watch(streakProvider(null));
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(
        title: Text(l10n.activeStreak),
        actions: [
          IconButton(
            tooltip: l10n.streakCalendar,
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => context.push(Routes.streakCalendar),
          ),
        ],
      ),
      body: streak.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Retry(onRetry: () => ref.invalidate(streakProvider)),
        data: (s) => RefreshIndicator(
          onRefresh: () => ref.refresh(streakProvider(null).future),
          child: ListView(
            padding: EdgeInsets.all(nc.screenPadding),
            children: [
              const SizedBox(height: NcSpace.cardGap),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (s.brokenYesterday ? nc.error : _fire).withAlpha(36),
                    border: Border.all(
                      color: s.brokenYesterday ? nc.error : _fire,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.local_fire_department,
                    size: 56,
                    color: s.brokenYesterday ? nc.error : _fire,
                  ),
                ),
              ),
              const SizedBox(height: NcSpace.cardGap),
              Text(
                s.current.toString().padLeft(2, '0'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                l10n.activeStreak,
                textAlign: TextAlign.center,
                style: TextStyle(color: nc.textSecondary),
              ),
              const SizedBox(height: NcSpace.sectionGap),
              ProfileCard(
                onTap: () => context.push(Routes.streakCalendar),
                child: _WeekStrip(streak: s),
              ),
              const SizedBox(height: NcSpace.cardGap),
              if (s.brokenYesterday)
                ProfileCard(
                  colour: nc.errorSurface,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: nc.error),
                      const SizedBox(width: NcSpace.buttonGap),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.streakBrokenTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: NcSpace.xs),
                            Text(l10n.streakBrokenBody),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                ProfileCard(
                  colour: nc.primarySurface,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: nc.primary),
                      const SizedBox(width: NcSpace.buttonGap),
                      Expanded(child: Text(l10n.streakRule)),
                    ],
                  ),
                ),
              const SizedBox(height: NcSpace.sectionGap),
              // Nothing logged yet: no report to download (owner).
              ProfileCard(
                onTap: s.longest == 0
                    ? null
                    : () => context.push(Routes.reports),
                colour: s.longest == 0 ? nc.inputFill : null,
                child: Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      color: s.longest == 0 ? nc.textSecondary : nc.primary,
                    ),
                    const SizedBox(width: NcSpace.buttonGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.downloadReport,
                            style: TextStyle(
                              color: s.longest == 0
                                  ? nc.textSecondary
                                  : nc.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            s.longest == 0
                                ? l10n.reportNoData
                                : l10n.downloadReportHint,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: nc.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (s.longest > 0) const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// This week (Monday to Sunday): a check for an active day, a cross for the
/// day the streak broke, an empty ring otherwise.
class _WeekStrip extends StatelessWidget {
  const new({required this.streak});

  final StreakInfo streak;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final today = _day(streak.today);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final letters = DateFormat.E(Localizations.localeOf(context).toString());
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          Builder(
            builder: (context) {
              final day = monday.add(Duration(days: i));
              final active = streak.lastSevenDays[day] ?? false;
              final broken =
                  streak.brokenYesterday &&
                  day == today.subtract(const Duration(days: 1));
              return Column(
                children: [
                  Text(
                    letters.format(day).substring(0, 1),
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: nc.textSecondary),
                  ),
                  const SizedBox(height: NcSpace.inputGap),
                  Icon(
                    active
                        ? Icons.verified_outlined
                        : broken
                        ? Icons.cancel_outlined
                        : Icons.circle_outlined,
                    color: active
                        ? nc.success
                        : broken
                        ? nc.error
                        : nc.primaryDisabled,
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// Figma "Profile/ Streak" (calendar): one month with active days, the
/// current and longest streak, and the legend.
class StreakCalendarScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<StreakCalendarScreen> createState() => _CalendarState();
}

class _CalendarState extends ConsumerState<StreakCalendarScreen> {
  DateTime? _month;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final locale = Localizations.localeOf(context).toString();
    final streak = ref.watch(streakProvider(_month));
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.activeStreak)),
      body: streak.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Retry(onRetry: () => ref.invalidate(streakProvider)),
        data: (s) {
          final today = _day(s.today);
          final month = _month ?? DateTime(today.year, today.month);
          final first = DateTime(month.year, month.month);
          final days = DateUtils.getDaysInMonth(month.year, month.month);
          final lead = first.weekday % 7; // Sunday first, as in the Figma
          final canNext = DateTime(
            month.year,
            month.month + 1,
          ).isBefore(today.add(const Duration(days: 1)));
          final canPrev = DateTime(
            month.year,
            month.month - 1,
          ).isAfter(DateTime(2025, 12, 31));
          return ListView(
            padding: EdgeInsets.all(nc.screenPadding),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat.yMMMM(locale).format(month),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.previousMonth,
                    icon: const Icon(Icons.chevron_left),
                    onPressed: canPrev
                        ? () => setState(
                            () =>
                                _month = DateTime(month.year, month.month - 1),
                          )
                        : null,
                  ),
                  IconButton(
                    tooltip: l10n.nextMonth,
                    icon: const Icon(Icons.chevron_right),
                    onPressed: canNext
                        ? () => setState(
                            () =>
                                _month = DateTime(month.year, month.month + 1),
                          )
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: NcSpace.inputGap),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: NcSpace.xs,
                crossAxisSpacing: NcSpace.xs,
                children: [
                  for (var i = 0; i < 7; i++)
                    Center(
                      child: Text(
                        DateFormat.E(locale)
                            .format(DateTime(2026, 11, 1 + i))
                            .toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: nc.textSecondary),
                      ),
                    ),
                  for (var i = 0; i < lead; i++) const SizedBox.shrink(),
                  for (var d = 1; d <= days; d++)
                    _DayCell(
                      day: DateTime(month.year, month.month, d),
                      today: today,
                      active:
                          s.activeDays[DateTime(month.year, month.month, d)] ??
                          false,
                      broken:
                          s.brokenYesterday &&
                          DateTime(month.year, month.month, d) ==
                              today.subtract(const Duration(days: 1)),
                    ),
                ],
              ),
              const SizedBox(height: NcSpace.sectionGap),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      value: l10n.streakDays(s.current),
                      label: l10n.activeStreak,
                    ),
                  ),
                  const SizedBox(width: NcSpace.buttonGap),
                  Expanded(
                    child: _Stat(
                      value: l10n.streakDays(s.longest),
                      label: l10n.longestStreak,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NcSpace.sectionGap),
              _Legend(colour: nc.success, filled: true, label: l10n.activeDay),
              const SizedBox(height: NcSpace.inputGap),
              _Legend(
                colour: nc.primaryDisabled,
                filled: false,
                label: l10n.noData,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const new({
    required this.day,
    required this.today,
    required this.active,
    required this.broken,
  });

  final DateTime day;
  final DateTime today;
  final bool active;
  final bool broken;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final isToday = day == today;
    final fill = active
        ? nc.success
        : broken
        ? nc.error
        : isToday
        ? nc.primary.withAlpha(110)
        : null;
    return Center(
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
        child: Text(
          '${day.day}',
          style: TextStyle(
            color: fill == null
                ? (day.isAfter(today) ? nc.textSecondary : nc.textPrimary)
                : nc.surface,
            fontWeight: fill == null ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const new({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => ProfileCard(
    child: Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.nc.textSecondary),
        ),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  const new({required this.colour, required this.filled, required this.label});

  final Color colour;
  final bool filled;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? colour : null,
          border: Border.all(color: colour),
        ),
      ),
      const SizedBox(width: NcSpace.inputGap),
      Text(label, style: TextStyle(color: filled ? colour : null)),
    ],
  );
}

class _Retry extends StatelessWidget {
  const new({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.loadFailed),
          TextButton(onPressed: onRetry, child: Text(l10n.retry)),
        ],
      ),
    );
  }
}
