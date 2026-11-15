import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/care_circle/circle_providers.dart';
import 'package:naraacare/features/care_circle/data/circle_data.dart';
import 'package:naraacare/features/care_circle/presentation/circle_widgets.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';

/// Share an avatar inside NaraaCare only (owner 2026-11-08): pick any of
/// your Care Circles (a card in Recent Updates) and connections (an in-app
/// notification). Nothing leaves the app; the server builds the card from
/// today's values, so only the avatar and the chosen ids are sent.
Future<void> showAvatarShareSheet(BuildContext context, AvatarType avatar) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true, // above the tab bar
      isScrollControlled: true,
      builder: (context) => _AvatarShareSheet(avatar: avatar),
    );

/// The server's limits (social.pr_share_avatar).
const _maxCircles = 10;
const _maxPeople = 20;

class _AvatarShareSheet extends ConsumerStatefulWidget {
  const new({required this.avatar});

  final AvatarType avatar;

  @override
  ConsumerState<_AvatarShareSheet> createState() => _State();
}

class _State extends ConsumerState<_AvatarShareSheet> {
  final _circles = <String>{};
  final _people = <String>{};
  bool _busy = false;

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final ok = await runSocial(
      context,
      () => ref
          .read(circleApiProvider)
          .shareAvatar(widget.avatar, circleIds: _circles, userIds: _people),
      success: l10n.avatarShared,
    );
    if (!mounted) return;
    if (ok) {
      for (final id in _circles) {
        ref.invalidate(circleFeedProvider(id));
      }
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final circles = ref.watch(circlesProvider);
    final connections = ref.watch(connectionsProvider);
    final people = [
      for (final c in connections.value ?? const <Connection>[])
        if (c.state == ConnectionStatus.connected) c.person,
    ];
    final loading = circles.isLoading || connections.isLoading;
    final none =
        !loading && (circles.value ?? const []).isEmpty && people.isEmpty;

    Widget tick({
      required bool on,
      required bool allowed,
      required ValueChanged<bool> onChanged,
      required Widget leading,
      required String title,
      String? subtitle,
    }) => CheckboxListTile(
      value: on,
      onChanged: on || allowed ? (v) => onChanged(v ?? false) : null,
      secondary: leading,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null ? null : Text(subtitle),
      contentPadding: EdgeInsets.zero,
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
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
              Text(
                l10n.shareAvatarTitle(avatarLabel(l10n, widget.avatar)),
                style: text.titleLarge,
              ),
              const SizedBox(height: NcSpace.xs),
              Text(
                l10n.shareAvatarHint,
                style: text.bodySmall?.copyWith(color: nc.textSecondary),
              ),
              const SizedBox(height: NcSpace.inputGap),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(NcSpace.sectionGap),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (none)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: NcSpace.sectionGap,
                  ),
                  child: Text(
                    l10n.shareAvatarNobody,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: nc.textSecondary),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if ((circles.value ?? const []).isNotEmpty)
                        SectionHeader(l10n.shareToCircles),
                      for (final c in circles.value ?? const <CircleSummary>[])
                        tick(
                          on: _circles.contains(c.id),
                          allowed: _circles.length < _maxCircles,
                          onChanged: (v) => setState(
                            () =>
                                v ? _circles.add(c.id) : _circles.remove(c.id),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: nc.primarySurface,
                            child: Icon(
                              Icons.groups_outlined,
                              color: nc.primary,
                            ),
                          ),
                          title: c.name,
                          subtitle: l10n.membersCount(c.memberCount),
                        ),
                      if (people.isNotEmpty)
                        SectionHeader(l10n.shareToConnections),
                      for (final p in people)
                        tick(
                          on: _people.contains(p.userId),
                          allowed: _people.length < _maxPeople,
                          onChanged: (v) => setState(
                            () => v
                                ? _people.add(p.userId)
                                : _people.remove(p.userId),
                          ),
                          leading: PersonAvatar(person: p, size: 40),
                          title: p.displayName ?? p.handle,
                          subtitle: p.displayName == null ? null : p.handle,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: NcSpace.cardGap),
              NcButton(
                label: l10n.shareSend,
                loading: _busy,
                onPressed: _busy || (_circles.isEmpty && _people.isEmpty)
                    ? null
                    : _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
