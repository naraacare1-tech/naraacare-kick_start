import 'package:flutter/material.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/care_circle/data/circle_data.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';

/// Wallpapers seeded in ref.wallpaper (art pending design): drawn as
/// gradients until the assets arrive.
const wallpaperCodes = ['default', 'sunrise', 'ocean', 'forest'];

List<Color> wallpaperColors(String? code) => switch (code) {
  'sunrise' => const [Color(0xFFFFC37A), Color(0xFFFF7E8A)],
  'ocean' => const [Color(0xFF7FD3FF), Color(0xFF2F80ED)],
  'forest' => const [Color(0xFFA8E6A1), Color(0xFF2E9E6B)],
  _ => const [Color(0xFFDCEFFC), Color(0xFF8CCBF5)],
};

/// The round circle picture (wallpaper + first letter of the name).
class CircleBadge extends StatelessWidget {
  const new({
    required this.name,
    required this.wallpaper,
    super.key,
    this.size = 48,
  });

  final String name;
  final String? wallpaper;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: wallpaperColors(wallpaper),
      ),
    ),
    child: Text(
      name.isEmpty ? '?' : name.characters.first.toUpperCase(),
      style: TextStyle(
        fontSize: size * 0.4,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
  );
}

/// A person's round picture: their initial (no photos in the MVP).
class PersonAvatar extends StatelessWidget {
  const new({required this.person, super.key, this.size = 44});

  final PersonCard person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: nc.inputFill,
      child: Text(
        person.initial,
        style: TextStyle(
          fontSize: size * 0.4,
          color: nc.textBody,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// "TODAY", "MEMBERS" style section header.
class SectionHeader extends StatelessWidget {
  const new(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: NcSpace.cardGap,
      bottom: NcSpace.inputGap,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: context.nc.textSecondary),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

String avatarLabel(AppLocalizations l10n, AvatarType type) => switch (type) {
  AvatarType.hydration => l10n.avatarWater,
  AvatarType.nutrition => l10n.avatarFood,
  AvatarType.sleep => l10n.avatarSleep,
};

String avatarEmoji(AvatarType type) => switch (type) {
  AvatarType.hydration => '💧',
  AvatarType.nutrition => '🍽',
  AvatarType.sleep => '😴',
};

/// "1h ago", "Yesterday", or the date.
String timeAgo(AppLocalizations l10n, DateTime at, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(at.toLocal());
  if (diff.inMinutes < 1) return l10n.justNow;
  if (diff.inHours < 1) return l10n.minutesAgo(diff.inMinutes);
  if (diff.inDays < 1) return l10n.hoursAgo(diff.inHours);
  if (diff.inDays < 2) return l10n.yesterday;
  return l10n.daysAgo(diff.inDays);
}

/// One Recent Updates line, e.g. "@priya updated nutrition." + "Meal logged".
(String, String?) feedText(AppLocalizations l10n, FeedEvent e, String me) {
  final who = e.actor.userId == me ? l10n.you : e.actor.handle;
  final avatar = e.avatar == null ? '' : avatarLabel(l10n, e.avatar!);
  return switch (e.type) {
    'goal_completed' => (l10n.feedGoalCompleted(who, avatar), null),
    'joined' => (l10n.feedJoined(who), null),
    'left' => (l10n.feedLeft(who), null),
    // An avatar card shared into this circle (V029): today's progress.
    'shared' => (
      l10n.feedShared(who, avatar),
      switch (e.summary['pct'] ?? e.summary['score_pct']) {
        final num pct => l10n.sharedProgress(pct.round()),
        _ => null,
      },
    ),
    _ => (
      l10n.feedUpdated(who, avatar),
      switch (e.avatar) {
        AvatarType.hydration when e.summary['volume_ml'] is num => l10n.mlValue(
          (e.summary['volume_ml'] as num).toInt(),
        ),
        AvatarType.nutrition => l10n.mealLogged,
        AvatarType.sleep when e.summary['counted_min'] is num =>
          l10n.hoursMinutes(
            (e.summary['counted_min'] as num).toInt() ~/ 60,
            (e.summary['counted_min'] as num).toInt() % 60,
          ),
        _ => null,
      },
    ),
  };
}

/// Text for an in-app notification. Params hold ids only; [names] maps a
/// user id to the handle the app already knows (circle members).
String notificationText(
  AppLocalizations l10n,
  InAppNotification n,
  Map<String, String> names,
) {
  final username = n.params['username'];
  final who =
      names[n.params['user_id']] ??
      (username is String ? '@$username' : l10n.someone);
  final avatar = switch (n.params['avatar_type']) {
    'hydration' => l10n.avatarWater,
    'nutrition' => l10n.avatarFood,
    'sleep' => l10n.avatarSleep,
    _ => '',
  };
  final pct = n.params['pct'] ?? n.params['score_pct'];
  return switch (n.template) {
    'avatar_shared' => [
      l10n.notifAvatarShared(who, avatar),
      if (pct is num) l10n.sharedProgress(pct.round()),
    ].join(' '),
    'circle_avatar_shared' => l10n.notifCircleAvatarShared(who, avatar),
    'circle_mention' => l10n.notifMention(who),
    'circle_message' => l10n.notifMessage,
    'circle_member_joined' => l10n.notifJoined(who),
    'circle_member_left' => l10n.notifLeft(who),
    'circle_goal_completed' => l10n.notifGoal(who),
    'circle_invite' => l10n.notifInvite,
    'circle_admin_granted' => l10n.notifAdmin,
    'circle_removed' => l10n.notifRemoved,
    'circle_deleted' => l10n.notifDeleted,
    'connection_request' => l10n.notifConnectionRequest,
    'connection_accepted' => l10n.notifConnectionAccepted,
    _ => l10n.notifGeneric,
  };
}

/// Messages for the social error codes (doc 04 section 1.1, S12).
String socialErrorMessage(AppLocalizations l10n, ApiError e) =>
    switch (e.code) {
      'USERNAME_REQUIRED' => l10n.usernameRequired,
      'ADMIN_REQUIRED' => l10n.adminRequired,
      'CIRCLE_FULL' => l10n.circleFull,
      'LAST_ADMIN' => l10n.lastAdmin,
      'INVITE_LINK_EXPIRED' => l10n.inviteLinkExpired,
      'INVITE_LINK_LIMIT' => l10n.inviteLinkLimit,
      'SHARES_INVALID' => l10n.sharesInvalid,
      'MENTION_INVALID' => l10n.mentionInvalid,
      'TOO_MANY_MENTIONS' => l10n.tooManyMentions,
      'QUERY_TOO_SHORT' => l10n.queryTooShort,
      'NOT_FOUND' => l10n.circleNotFound,
      _ => featureErrorMessage(l10n, e),
    };

/// Runs a social call; shows the error as a toast and returns false on
/// failure, true on success.
Future<bool> runSocial(
  BuildContext context,
  Future<void> Function() call, {
  String? success,
}) async {
  final l10n = AppLocalizations.of(context);
  try {
    await call();
    if (success != null && context.mounted) showNcToast(context, success);
    return true;
  } on ApiError catch (e) {
    if (context.mounted) {
      showNcToast(
        context,
        socialErrorMessage(l10n, e),
        kind: NcToastKind.error,
      );
    }
    return false;
  }
}
