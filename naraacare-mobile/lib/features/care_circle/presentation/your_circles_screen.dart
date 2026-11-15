import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/guards.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/care_circle/circle_providers.dart';
import 'package:naraacare/features/care_circle/data/circle_data.dart';
import 'package:naraacare/features/care_circle/presentation/circle_widgets.dart';
import 'package:naraacare/features/care_circle/presentation/create_circle_screens.dart';
import 'package:naraacare/features/profile/presentation/username_form.dart';
import 'package:naraacare/features/profile/profile_providers.dart';

/// "Your Circles" (Figma Care Circle / Care Circle 1): open invites, the
/// circles with member count, updates today and unread messages, and the
/// + button. Without a username the + opens the username sheet first.
class YourCirclesScreen extends ConsumerWidget {
  const new({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final me = ref.read(meProvider).value;
    if (!hasUsername(me?.username)) {
      final saved = await showUsernameSheet(context);
      if (!saved || !context.mounted) return;
    }
    if (!context.mounted) return;
    // A fresh draft for each new circle (outside any build).
    ref.read(circleDraftProvider.notifier).start();
    unawaited(context.push(Routes.createCircle));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final circles = ref.watch(circlesProvider);
    final invites = ref.watch(circleInvitesProvider).value ?? const [];
    // Keep the socket open on this tab so unread counts stay current.
    ref.listen(realtimeEventsProvider, (_, _) {
      ref
        ..invalidate(circlesProvider)
        ..invalidate(circleInvitesProvider);
    });
    return Scaffold(
      backgroundColor: nc.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(circlesProvider)
              ..invalidate(circleInvitesProvider);
            await ref.read(circlesProvider.future);
          },
          child: ListView(
            padding: EdgeInsets.all(nc.screenPadding),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.yourCircles,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.connections,
                    icon: const Icon(Icons.people_outline),
                    onPressed: () => context.push(Routes.connections),
                  ),
                  IconButton(
                    tooltip: l10n.createCircle,
                    icon: Icon(Icons.add_circle_outline, color: nc.primary),
                    onPressed: () => _create(context, ref),
                  ),
                ],
              ),
              if (invites.isNotEmpty) ...[
                SectionHeader(l10n.invitesHeader),
                for (final i in invites) _InviteTile(invite: i),
              ],
              const SizedBox(height: NcSpace.cardGap),
              ...circles.when(
                loading: () => const [
                  Center(child: CircularProgressIndicator()),
                ],
                error: (_, _) => [Center(child: Text(l10n.circlesUnavailable))],
                data: (items) => [
                  for (final c in items) _CircleTile(circle: c),
                  const SizedBox(height: NcSpace.cardGap),
                  _CreateTip(onTap: () => _create(context, ref)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleTile extends StatelessWidget {
  const new({required this.circle});

  final CircleSummary circle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final updates = circle.updatesToday == 0
        ? l10n.noNewUpdates
        : l10n.updatesToday(circle.updatesToday);
    return Card(
      elevation: 0,
      color: nc.surface,
      margin: const EdgeInsets.only(bottom: NcSpace.buttonGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NcRadius.l),
        side: BorderSide(color: nc.inputFill),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NcSpace.cardPadding,
          vertical: NcSpace.inputGap,
        ),
        leading: CircleBadge(name: circle.name, wallpaper: circle.wallpaper),
        title: Text(circle.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${l10n.membersCount(circle.memberCount)} · $updates'),
        trailing: circle.unread == 0
            ? const Icon(Icons.chevron_right)
            : Badge(
                label: Text('${circle.unread}'),
                backgroundColor: nc.primary,
              ),
        onTap: () => context.push(Routes.circle(circle.id)),
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  const new({required this.invite});

  final CircleInvite invite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    return Card(
      elevation: 0,
      color: nc.primarySurface,
      margin: const EdgeInsets.only(bottom: NcSpace.buttonGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NcRadius.l),
      ),
      child: ListTile(
        leading: CircleBadge(name: invite.name, wallpaper: invite.wallpaper),
        title: Text(invite.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          invite.inviter == null
              ? l10n.invitedToJoin
              : l10n.invitedBy(invite.inviter!),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.circleInviteDetail(invite.circleId)),
      ),
    );
  }
}

/// "Create a Care Circle — Invite friends and family to share avatars and
/// support each other" (Figma Info Tip).
class _CreateTip extends StatelessWidget {
  const new({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(NcRadius.l),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(NcSpace.cardPadding),
        decoration: BoxDecoration(
          color: nc.primarySurface,
          borderRadius: BorderRadius.circular(NcRadius.l),
        ),
        child: Row(
          children: [
            Icon(Icons.diversity_1_outlined, color: nc.primary, size: 40),
            const SizedBox(width: NcSpace.buttonGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.createCircleTitle, style: text.titleSmall),
                  Text(
                    l10n.createCircleTip,
                    style: text.bodySmall?.copyWith(color: nc.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
