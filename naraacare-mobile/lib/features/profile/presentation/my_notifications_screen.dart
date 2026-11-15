import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/care_circle/circle_providers.dart';
import 'package:naraacare/features/care_circle/data/circle_data.dart';
import 'package:naraacare/features/care_circle/presentation/circle_widgets.dart';
import 'package:naraacare/features/profile/presentation/streak_screens.dart';
import 'package:naraacare/features/profile/profile_tab_providers.dart';

/// In-app routes a notification may open. Only these fixed shapes are
/// accepted (the server writes the link, but the app still treats it as
/// untrusted input, doc 07 SEC-5.8); anything else opens nothing.
String? notificationRoute(InAppNotification n) {
  final report = RegExp(r'^[0-9a-f-]{36}$');
  final id = n.params['report_id'];
  return switch (n.template) {
    'streak_milestone' => Routes.streak,
    'report_ready' when id is String && report.hasMatch(id) =>
      Routes.reportPreview(id),
    'report_failed' => Routes.reports,
    'connection_request' || 'connection_accepted' => Routes.connections,
    _ when n.circleId != null && report.hasMatch(n.circleId!) => Routes.circle(
      n.circleId!,
    ),
    _ => null,
  };
}

/// Figma "Profile/ Notifications": every notification of the user (personal
/// and circles), Today / Earlier, unread dots. Opening the screen marks them
/// read; tapping one opens its screen.
class MyNotificationsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<MyNotificationsScreen> createState() => _State();
}

class _State extends ConsumerState<MyNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(
      ref
          .read(circleApiProvider)
          .markNotificationsRead()
          .catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final list = ref.watch(myNotificationsProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.notificationsTitle)),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.loadFailed)),
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(l10n.noNotificationsYet));
          }
          final recent = [
            for (final n in items)
              if (!n.at.toLocal().isBefore(today)) n,
          ];
          final earlier = [
            for (final n in items)
              if (n.at.toLocal().isBefore(today)) n,
          ];
          Widget header(String t) => Padding(
            padding: const EdgeInsets.only(
              top: NcSpace.cardGap,
              bottom: NcSpace.inputGap,
            ),
            child: Text(
              t,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: nc.textSecondary),
            ),
          );
          return RefreshIndicator(
            onRefresh: () => ref.refresh(myNotificationsProvider.future),
            child: ListView(
              padding: EdgeInsets.all(nc.screenPadding),
              children: [
                if (recent.isNotEmpty) header(l10n.todayHeader),
                for (final n in recent) _Tile(n: n),
                if (earlier.isNotEmpty) header(l10n.earlierHeader),
                for (final n in earlier) _Tile(n: n),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const new({required this.n});

  final InAppNotification n;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final route = notificationRoute(n);
    final (icon, colour) = switch (n.template) {
      'streak_milestone' => (
        Icons.local_fire_department,
        const Color(0xFFF59E0B),
      ),
      'report_ready' ||
      'report_failed' => (Icons.description_outlined, nc.primary),
      'connection_request' ||
      'connection_accepted' => (Icons.person_add_alt, nc.primary),
      'circle_mention' ||
      'circle_message' => (Icons.forum_outlined, nc.primary),
      'circle_goal_completed' => (Icons.emoji_events_outlined, nc.success),
      'avatar_shared' ||
      'circle_avatar_shared' => (Icons.share_outlined, nc.primary),
      _ => (Icons.notifications_none, nc.primary),
    };
    final text = switch (n.template) {
      'streak_milestone' => l10n.notifStreak(
        (n.params['days'] as num?)?.toInt() ?? 0,
      ),
      'report_ready' => l10n.notifReportReady,
      'report_failed' => l10n.notifReportFailed,
      _ => notificationText(l10n, n, const {}),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: NcSpace.inputGap),
      child: ProfileCard(
        onTap: route == null ? null : () => context.push(route),
        child: Row(
          children: [
            Icon(icon, color: colour),
            const SizedBox(width: NcSpace.buttonGap),
            Expanded(child: Text(text)),
            const SizedBox(width: NcSpace.inputGap),
            Text(
              timeAgo(l10n, n.at),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: nc.textSecondary),
            ),
            if (!n.read) ...[
              const SizedBox(width: NcSpace.xs),
              Icon(Icons.circle, size: 8, color: nc.primary),
            ],
          ],
        ),
      ),
    );
  }
}
