import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/care_circle/circle_providers.dart';
import 'package:naraacare/features/care_circle/data/circle_data.dart';
import 'package:naraacare/features/care_circle/presentation/circle_widgets.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/shared/widgets/nc_avatar_card.dart';
import 'package:naraacare/shared/widgets/nc_avatar_figure.dart';
import 'package:naraacare/shared/widgets/nc_star_badge.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';

enum _MemberAction { makeAdmin, removeAdmin, remove }

/// "Care Circle 7 / View Members" and "Settings / Manage Members": a
/// username filter, Admins, Invited (n) and Members. Admins get a menu per
/// person (make / remove admin, remove or cancel the invite).
class CircleMembersScreen extends ConsumerStatefulWidget {
  const new({required this.circleId, super.key, this.manage = false});

  final String circleId;
  final bool manage;

  @override
  ConsumerState<CircleMembersScreen> createState() => _MembersState();
}

class _MembersState extends ConsumerState<CircleMembersScreen> {
  String _filter = '';

  Future<void> _act(CircleMember m, _MemberAction action) async {
    final api = ref.read(circleApiProvider);
    final id = widget.circleId;
    final ok = await runSocial(context, () async {
      switch (action) {
        case _MemberAction.makeAdmin:
          await api.setRole(id, m.person.userId, admin: true);
        case _MemberAction.removeAdmin:
          await api.setRole(id, m.person.userId, admin: false);
        case _MemberAction.remove:
          await api.removeMember(id, m.person.userId);
      }
    });
    if (ok) {
      ref
        ..invalidate(circleMembersProvider(id))
        ..invalidate(circleDetailProvider(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final members = ref.watch(circleMembersProvider(widget.circleId));
    final detail = ref.watch(circleDetailProvider(widget.circleId)).value;
    final me = ref.watch(meProvider).value?.userId ?? '';
    final isAdmin = detail?.isAdmin ?? false;
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(
        title: Text(widget.manage ? l10n.manageMembers : l10n.allMembers),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: l10n.addMembers,
              icon: const Icon(Icons.person_add_alt),
              onPressed: () =>
                  context.push(Routes.circleAddMembers(widget.circleId)),
            ),
        ],
      ),
      body: members.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.circleNotFound)),
        data: (all) {
          final shown = [
            for (final m in all)
              if (_filter.isEmpty ||
                  (m.person.username ?? '').contains(_filter))
                m,
          ];
          final admins = [
            for (final m in shown)
              if (m.status == MemberStatus.active && m.isAdmin) m,
          ];
          final invited = [
            for (final m in shown)
              if (m.status == MemberStatus.invited) m,
          ];
          final regular = [
            for (final m in shown)
              if (m.status == MemberStatus.active && !m.isAdmin) m,
          ];
          Widget tile(CircleMember m) => _MemberTile(
            member: m,
            me: me,
            canManage: isAdmin && m.person.userId != me,
            onAction: (a) => _act(m, a),
            onTap: m.status == MemberStatus.active && m.person.userId != me
                ? () => context.push(
                    Routes.circleMember(widget.circleId, m.person.userId),
                  )
                : null,
          );
          return ListView(
            padding: EdgeInsets.all(nc.screenPadding),
            children: [
              NcTextField(
                hint: l10n.searchByUsername,
                prefixIcon: Icons.search,
                validator: InputValidators.usernameSearch,
                maxLength: 64,
                onChanged: (v) => setState(
                  () =>
                      _filter = InputValidators.normalise(v)
                          .replaceFirst('@', '')
                          .toLowerCase(),
                ),
              ),
              SectionHeader(l10n.admins),
              ...admins.map(tile),
              if (invited.isNotEmpty) ...[
                SectionHeader(l10n.invitedCount(invited.length)),
                ...invited.map(tile),
              ],
              SectionHeader(l10n.membersTitle),
              ...regular.map(tile),
            ],
          );
        },
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const new({
    required this.member,
    required this.me,
    required this.canManage,
    required this.onAction,
    this.onTap,
  });

  final CircleMember member;
  final String me;
  final bool canManage;
  final ValueChanged<_MemberAction> onAction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = member.person;
    final subtitle = switch (member.status) {
      MemberStatus.invited => l10n.invited,
      _ when member.isAdmin => l10n.circleAdmin,
      _ when member.joinedAt != null => l10n.joinedDaysAgo(
        DateTime.now().difference(member.joinedAt!).inDays,
      ),
      _ => null,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: PersonAvatar(person: p),
      title: Text(p.userId == me ? '${p.handle} (${l10n.you})' : p.handle),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: onTap,
      trailing: canManage
          ? PopupMenuButton<_MemberAction>(
              tooltip: l10n.moreOptions,
              onSelected: onAction,
              itemBuilder: (_) => [
                if (member.status == MemberStatus.active && member.isAdmin)
                  PopupMenuItem(
                    value: _MemberAction.removeAdmin,
                    child: Text(l10n.removeAdmin),
                  )
                else if (member.status == MemberStatus.active)
                  PopupMenuItem(
                    value: _MemberAction.makeAdmin,
                    child: Text(l10n.makeAdmin),
                  ),
                PopupMenuItem(
                  value: _MemberAction.remove,
                  child: Text(
                    member.status == MemberStatus.invited
                        ? l10n.cancelInvite
                        : l10n.removeFromCircle,
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

/// "Member avatar": a member's avatars as the caller may see them; each
/// page shows today's values for shared avatars, "Not shared", or the STAR
/// note for sleep (sleep is visible only when both people are STAR).
class MemberAvatarScreen extends ConsumerStatefulWidget {
  const new({required this.circleId, required this.userId, super.key});

  final String circleId;
  final String userId;

  @override
  ConsumerState<MemberAvatarScreen> createState() => _MemberAvatarState();
}

class _MemberAvatarState extends ConsumerState<MemberAvatarScreen> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final avatars = ref.watch(
      memberAvatarsProvider((widget.circleId, widget.userId)),
    );
    final member = ref
        .watch(circleMembersProvider(widget.circleId))
        .value
        ?.where((m) => m.person.userId == widget.userId)
        .firstOrNull;
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(member?.person.handle ?? '')),
      body: avatars.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.circleNotFound)),
        data: (items) => Column(
          children: [
            Expanded(
              child: PageView(
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final a in items)
                    // The avatar fills the page down to the dots (no empty
                    // space below it), as on Home.
                    LayoutBuilder(
                      builder: (context, box) => NcAvatarStageHeight(
                        height: (box.maxHeight - 2 * nc.screenPadding).clamp(
                          320,
                          double.infinity,
                        ),
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(nc.screenPadding),
                          child: _MemberAvatarPage(avatar: a),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < items.length; i++)
                  Container(
                    margin: const EdgeInsets.all(NcSpace.xs),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page ? nc.primary : nc.inputFill,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: NcSpace.cardGap),
          ],
        ),
      ),
    );
  }
}

class _MemberAvatarPage extends StatelessWidget {
  const new({required this.avatar});

  final MemberAvatar avatar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final s = avatar.state;
    final look = switch (avatar.type) {
      AvatarType.hydration => AvatarLook.water,
      AvatarType.nutrition => AvatarLook.food,
      AvatarType.sleep => AvatarLook.neutral,
    };
    final pct = (s['pct'] ?? s['score_pct']) as num?;
    final (value, caption) = switch (avatar.type) {
      AvatarType.hydration => (
        l10n.litresValue(((s['consumed_ml'] as num?) ?? 0) / 1000),
        l10n.ofGoalLitres(((s['goal_ml'] as num?) ?? 0) / 1000),
      ),
      AvatarType.nutrition => (
        l10n.kcalValueShort(((s['kcal'] as num?) ?? 0).toInt()),
        s['allowance_kcal'] == null
            ? null
            : l10n.ofGoalKcal((s['allowance_kcal'] as num).toInt()),
      ),
      AvatarType.sleep => (
        l10n.hoursMinutes(
          ((s['counted_min'] as num?) ?? 0).toInt() ~/ 60,
          ((s['counted_min'] as num?) ?? 0).toInt() % 60,
        ),
        null,
      ),
    };
    if (avatar.visibility != AvatarVisibility.shared) {
      return SizedBox(
        height: NcAvatarStageHeight.of(context) ?? NcAvatarStage.height,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                avatarEmoji(avatar.type),
                style: const TextStyle(fontSize: 40),
              ),
              const SizedBox(height: NcSpace.inputGap),
              if (avatar.visibility == AvatarVisibility.requiresStar) ...[
                const NcStarBadge(),
                const SizedBox(height: NcSpace.xs),
                Text(l10n.sleepStarOnly, textAlign: TextAlign.center),
              ] else
                Text(
                  l10n.notSharedAvatar(avatarLabel(l10n, avatar.type)),
                  style: TextStyle(color: nc.textSecondary),
                ),
            ],
          ),
        ),
      );
    }
    return NcAvatarStage(
      sex: null,
      look: look,
      fill: pct == null ? null : (pct / 100).clamp(0, 1).toDouble(),
      card: NcAvatarCard(
        label: avatarLabel(l10n, avatar.type),
        value: value,
        caption: caption,
        icon: switch (avatar.type) {
          AvatarType.hydration => Icons.water_drop_outlined,
          AvatarType.nutrition => Icons.restaurant_outlined,
          AvatarType.sleep => Icons.bedtime_outlined,
        },
        progress: pct == null ? null : (pct / 100).clamp(0, 1).toDouble(),
      ),
    );
  }
}
