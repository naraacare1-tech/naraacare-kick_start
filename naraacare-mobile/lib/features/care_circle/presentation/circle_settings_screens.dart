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
import 'package:naraacare/shared/widgets/nc_text_field.dart';

/// "Care Circle 9 / Settings": Manage Members, Add Members, Your Shared
/// Avatars, Notifications, Name & Picture (admins) and Leave (dialog; the
/// earliest-joined member becomes admin if the last admin leaves).
class CircleSettingsScreen extends ConsumerWidget {
  const new({required this.circleId, super.key});

  final String circleId;

  Future<void> _leave(BuildContext context, WidgetRef ref, String name) async {
    final l10n = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.leaveCircleTitle),
        content: Text(l10n.leaveCircleBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l10n.leave),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final ok = await runSocial(
      context,
      () => ref.read(circleApiProvider).leave(circleId),
      success: l10n.leftCircle(name),
    );
    if (ok && context.mounted) {
      ref.invalidate(circlesProvider);
      context.go(Routes.careCircle);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final detail = ref.watch(circleDetailProvider(circleId));
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.circleNotFound)),
        data: (c) => ListView(
          padding: EdgeInsets.all(nc.screenPadding),
          children: [
            Center(
              child: CircleBadge(
                name: c.name,
                wallpaper: c.wallpaper,
                size: 88,
              ),
            ),
            const SizedBox(height: NcSpace.inputGap),
            Center(child: Text(c.name, style: text.titleLarge)),
            Center(
              child: Text(
                l10n.membersCount(c.memberCount),
                style: text.bodySmall,
              ),
            ),
            const SizedBox(height: NcSpace.sectionGap),
            if (c.isAdmin) ...[
              _Item(
                icon: Icons.groups_outlined,
                label: l10n.manageMembers,
                onTap: () =>
                    context.push('${Routes.circleMembers(circleId)}?manage=1'),
              ),
              _Item(
                icon: Icons.person_add_alt,
                label: l10n.addMembers,
                onTap: () => context.push(Routes.circleAddMembers(circleId)),
              ),
              _Item(
                icon: Icons.image_outlined,
                label: l10n.namePicture,
                onTap: () => context.push(Routes.circleProfile(circleId)),
              ),
            ],
            _Item(
              icon: Icons.ios_share,
              label: l10n.yourSharedAvatars,
              onTap: () => context.push(Routes.circleShares(circleId)),
            ),
            _Item(
              icon: Icons.notifications_none,
              label: l10n.notificationsTitle,
              onTap: () =>
                  context.push(Routes.circleNotificationSettings(circleId)),
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.logout, color: nc.error),
              title: Text(
                l10n.leaveCircle(c.name),
                style: TextStyle(color: nc.error),
              ),
              onTap: () => _leave(context, ref, c.name),
            ),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const new({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

/// "Settings / Notification": the six per-circle switches.
class CircleNotificationSettingsScreen extends ConsumerStatefulWidget {
  const new({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<CircleNotificationSettingsScreen> createState() =>
      _PrefsState();
}

class _PrefsState extends ConsumerState<CircleNotificationSettingsScreen> {
  CirclePrefs? _prefs;

  Future<void> _set(String key, {required bool value}) async {
    final previous = _prefs!;
    final next = previous.copyWith(key, value: value);
    setState(() => _prefs = next);
    final ok = await runSocial(
      context,
      () => ref.read(circleApiProvider).setPrefs(widget.circleId, next),
    );
    if (!ok && mounted) setState(() => _prefs = previous);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final detail = ref.watch(circleDetailProvider(widget.circleId)).value;
    _prefs ??= detail?.prefs;
    final prefs = _prefs;
    (String, String) copy(String key) => switch (key) {
      'member_join_leave' => (l10n.prefJoinLeave, l10n.prefJoinLeaveBody),
      'circle_updates' => (l10n.prefCircleUpdates, l10n.prefCircleUpdatesBody),
      'goal_completions' => (l10n.prefGoals, l10n.prefGoalsBody),
      'avatar_updates' => (l10n.prefAvatarUpdates, l10n.prefAvatarUpdatesBody),
      'mentions' => (l10n.prefMentions, l10n.prefMentionsBody),
      _ => (l10n.prefNewMessages, l10n.prefNewMessagesBody),
    };
    Widget toggle(String key) {
      final (title, body) = copy(key);
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(body),
        value: prefs!.values[key] ?? false,
        onChanged: (v) => _set(key, value: v),
      );
    }

    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.notificationSettingsTitle)),
      body: prefs == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(nc.screenPadding),
              children: [
                SectionHeader(l10n.circleActivity),
                toggle('member_join_leave'),
                toggle('circle_updates'),
                SectionHeader(l10n.healthUpdates),
                toggle('goal_completions'),
                toggle('avatar_updates'),
                SectionHeader(l10n.chatSection),
                toggle('mentions'),
                toggle('new_messages'),
              ],
            ),
    );
  }
}

/// "Settings / Name & Picture": wallpaper and circle name (admins).
class CircleProfileScreen extends ConsumerStatefulWidget {
  const new({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<CircleProfileScreen> createState() => _ProfileState();
}

class _ProfileState extends ConsumerState<CircleProfileScreen> {
  final _form = GlobalKey<FormState>();
  TextEditingController? _name;
  String? _wallpaper;
  bool _busy = false;

  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  Future<void> _save(CircleDetail c) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    final name = InputValidators.normalise(_name!.text);
    setState(() => _busy = true);
    final ok = await runSocial(
      context,
      () => ref
          .read(circleApiProvider)
          .updateCircle(
            widget.circleId,
            name: name == c.name ? null : name,
            wallpaper: _wallpaper == c.wallpaper ? null : _wallpaper,
          ),
      success: l10n.saved,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref
        ..invalidate(circleDetailProvider(widget.circleId))
        ..invalidate(circlesProvider);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final c = ref.watch(circleDetailProvider(widget.circleId)).value;
    if (c == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _name ??= TextEditingController(text: c.name);
    _wallpaper ??= c.wallpaper ?? 'default';
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.namePicture)),
      body: Form(
        key: _form,
        child: ListView(
          padding: EdgeInsets.all(nc.screenPadding),
          children: [
            Center(
              child: CircleBadge(
                name: _name!.text,
                wallpaper: _wallpaper,
                size: 96,
              ),
            ),
            SectionHeader(l10n.selectWallpaper),
            Wrap(
              spacing: NcSpace.buttonGap,
              children: [
                for (final code in wallpaperCodes)
                  GestureDetector(
                    onTap: () => setState(() => _wallpaper = code),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 2,
                          color: code == _wallpaper
                              ? nc.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: CircleBadge(name: '', wallpaper: code, size: 52),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: NcSpace.sectionGap),
            NcTextField(
              controller: _name,
              label: l10n.circleName,
              validator: InputValidators.shortText(max: 50),
              maxLength: 50,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: NcSpace.sectionGap),
            FilledButton(
              onPressed: _busy ? null : () => _save(c),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Care Circle 8 / Notifications": goal completions, joins and leaves,
/// mentions and admin changes for this circle (logs go to Recent Updates,
/// not here). Opening the screen marks them read.
class CircleNotificationsScreen extends ConsumerStatefulWidget {
  const new({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<CircleNotificationsScreen> createState() =>
      _NotificationsState();
}

class _NotificationsState extends ConsumerState<CircleNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(
      ref
          .read(circleApiProvider)
          .markNotificationsRead(circleId: widget.circleId)
          .catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final list = ref.watch(circleNotificationsProvider(widget.circleId));
    final members =
        ref.watch(circleMembersProvider(widget.circleId)).value ?? const [];
    final names = {for (final m in members) m.person.userId: m.person.handle};
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.notificationsTitle)),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.circleNotFound)),
        data: (items) => items.isEmpty
            ? Center(child: Text(l10n.noNotificationsYet))
            : ListView(
                padding: EdgeInsets.all(nc.screenPadding),
                children: [
                  for (final n in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: nc.primarySurface,
                        child: Icon(
                          n.template == 'circle_mention'
                              ? Icons.forum_outlined
                              : Icons.notifications_none,
                          color: nc.primary,
                        ),
                      ),
                      title: Text(notificationText(l10n, n, names)),
                      subtitle: Text(timeAgo(l10n, n.at)),
                      trailing: n.read
                          ? null
                          : Icon(Icons.circle, size: 10, color: nc.primary),
                    ),
                ],
              ),
      ),
    );
  }
}
