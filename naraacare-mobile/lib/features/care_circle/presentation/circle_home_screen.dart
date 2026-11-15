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
import 'package:naraacare/features/profile/profile_providers.dart';

/// "Care Circle 5 / Home page": header (picture, name, members, bell, gear),
/// the members strip, the Circle Chat card and Recent Updates. Realtime
/// events for this circle refresh it; a 404 (removed / left) goes back.
class CircleHomeScreen extends ConsumerWidget {
  const new({required this.circleId, super.key});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final detail = ref.watch(circleDetailProvider(circleId));
    ref.listen(realtimeEventsProvider, (_, next) {
      final e = next.value;
      if (e == null || e.circleId != circleId || e.type == 'typing') return;
      ref
        ..invalidate(circleDetailProvider(circleId))
        ..invalidate(circleFeedProvider(circleId));
    });
    return Scaffold(
      backgroundColor: nc.surface,
      body: SafeArea(
        child: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _Gone(message: l10n.circleNotFound),
          data: (c) => RefreshIndicator(
            onRefresh: () async {
              ref
                ..invalidate(circleDetailProvider(circleId))
                ..invalidate(circleFeedProvider(circleId));
              await ref.read(circleDetailProvider(circleId).future);
            },
            child: ListView(
              padding: EdgeInsets.all(nc.screenPadding),
              children: [
                _Header(circle: c),
                const SizedBox(height: NcSpace.cardGap),
                _MembersStrip(circle: c),
                const SizedBox(height: NcSpace.cardGap),
                _ChatCard(circle: c),
                const SizedBox(height: NcSpace.cardGap),
                _RecentUpdates(circleId: circleId),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Gone extends StatelessWidget {
  const new({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        TextButton(
          onPressed: () => context.go(Routes.careCircle),
          child: Text(AppLocalizations.of(context).backToCircles),
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const new({required this.circle});

  final CircleDetail circle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        const BackButton(),
        CircleBadge(name: circle.name, wallpaper: circle.wallpaper),
        const SizedBox(width: NcSpace.buttonGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                circle.name,
                style: text.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                l10n.membersCount(circle.memberCount),
                style: text.bodySmall,
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: l10n.notificationsTitle,
          icon: const Icon(Icons.notifications_none),
          onPressed: () => context.push(Routes.circleNotifications(circle.id)),
        ),
        IconButton.filledTonal(
          tooltip: l10n.settingsTitle,
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.push(Routes.circleSettings(circle.id)),
        ),
      ],
    );
  }
}

class _MembersStrip extends ConsumerWidget {
  const new({required this.circle});

  final CircleDetail circle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final me = ref.watch(meProvider).value?.userId;
    final shown = circle.members.take(5).toList();
    final more = circle.memberCount - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.membersTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: () => context.push(Routes.circleMembers(circle.id)),
              child: Text(l10n.viewMembers),
            ),
          ],
        ),
        SizedBox(
          height: 76,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final m in shown)
                _Person(
                  avatar: PersonAvatar(person: m.person),
                  label: m.person.userId == me ? l10n.you : m.person.handle,
                  onTap: m.person.userId == me
                      ? null
                      : () => context.push(
                          Routes.circleMember(circle.id, m.person.userId),
                        ),
                ),
              _Person(
                avatar: CircleAvatar(
                  radius: 22,
                  backgroundColor: nc.primarySurface,
                  child: Text(
                    more > 0 ? '+$more' : '+',
                    style: TextStyle(color: nc.primary),
                  ),
                ),
                label: more > 0 ? l10n.more : l10n.invite,
                onTap: () => context.push(
                  more > 0
                      ? Routes.circleMembers(circle.id)
                      : Routes.circleAddMembers(circle.id),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Person extends StatelessWidget {
  const new({required this.avatar, required this.label, this.onTap});

  final Widget avatar;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(NcRadius.m),
    child: SizedBox(
      width: 64,
      child: Column(
        children: [
          avatar,
          const SizedBox(height: NcSpace.xs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    ),
  );
}

class _ChatCard extends StatelessWidget {
  const new({required this.circle});

  final CircleDetail circle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final last = circle.lastMessage;
    final sender = circle.members
        .where((m) => m.person.userId == last?.senderId)
        .map((m) => m.person.handle)
        .firstOrNull;
    return InkWell(
      borderRadius: BorderRadius.circular(NcRadius.l),
      onTap: () => context.push(Routes.circleChat(circle.id)),
      child: Container(
        padding: const EdgeInsets.all(NcSpace.cardPadding),
        decoration: BoxDecoration(
          color: nc.primarySurface,
          borderRadius: BorderRadius.circular(NcRadius.l),
          border: Border.all(color: nc.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: nc.surface,
              child: Icon(Icons.forum_outlined, color: nc.primary),
            ),
            const SizedBox(width: NcSpace.buttonGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.circleChat, style: text.titleMedium),
                  Text(
                    last == null
                        ? l10n.noMessagesYet
                        : last.body == null
                        ? l10n.messageDeleted
                        : '${sender ?? l10n.someone}: ${last.body}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _RecentUpdates extends ConsumerWidget {
  const new({required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final feed = ref.watch(circleFeedProvider(circleId)).value ?? const [];
    final me = ref.watch(meProvider).value?.userId ?? '';
    return Card(
      elevation: 0,
      color: nc.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NcRadius.l),
        side: BorderSide(color: nc.inputFill),
      ),
      child: Padding(
        padding: const EdgeInsets.all(NcSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.recentUpdates,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (feed.length > 3)
                  TextButton(
                    onPressed: () => context.push(Routes.circleFeed(circleId)),
                    child: Text(l10n.viewAll),
                  ),
              ],
            ),
            if (feed.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: NcSpace.cardGap),
                child: Text(
                  l10n.noUpdatesYet,
                  style: TextStyle(color: nc.textSecondary),
                ),
              ),
            for (final e in feed.take(3)) FeedTile(event: e, me: me),
          ],
        ),
      ),
    );
  }
}

class FeedTile extends StatelessWidget {
  const new({required this.event, required this.me, super.key});

  final FeedEvent event;
  final String me;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (title, detail) = feedText(l10n, event, me);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: PersonAvatar(person: event.actor),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: detail == null ? null : Text(detail),
      trailing: Text(
        timeAgo(l10n, event.at),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

/// All Recent Updates of a circle (View All).
class CircleFeedScreen extends ConsumerWidget {
  const new({required this.circleId, super.key});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final feed = ref.watch(circleFeedProvider(circleId));
    final me = ref.watch(meProvider).value?.userId ?? '';
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.recentUpdates)),
      body: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.circleNotFound)),
        data: (items) => items.isEmpty
            ? Center(child: Text(l10n.noUpdatesYet))
            : ListView(
                padding: EdgeInsets.all(nc.screenPadding),
                children: [for (final e in items) FeedTile(event: e, me: me)],
              ),
      ),
    );
  }
}
