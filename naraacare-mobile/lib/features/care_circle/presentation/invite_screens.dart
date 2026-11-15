import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/guards.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/care_circle/circle_providers.dart';
import 'package:naraacare/features/care_circle/presentation/circle_widgets.dart';
import 'package:naraacare/features/profile/presentation/username_form.dart';
import 'package:naraacare/features/profile/profile_providers.dart';

/// "Invite to join circle": "You are invited to join" + the circle name,
/// invited by,
/// member count; Accept (choose shares next), Decline, Maybe Later.
class CircleInviteScreen extends ConsumerWidget {
  const new({required this.circleId, super.key});

  final String circleId;

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref, {
    required bool later,
  }) async {
    final ok = await runSocial(
      context,
      () => ref.read(circleApiProvider).declineInvite(circleId, later: later),
    );
    if (ok && context.mounted) {
      ref.invalidate(circleInvitesProvider);
      context.go(Routes.careCircle);
    }
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    if (!hasUsername(ref.read(meProvider).value?.username)) {
      final saved = await showUsernameSheet(context);
      if (!saved || !context.mounted) return;
    }
    unawaited(context.push(Routes.circleInviteAccept(circleId)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final invite = ref
        .watch(circleInvitesProvider)
        .value
        ?.where((i) => i.circleId == circleId)
        .firstOrNull;
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(),
      body: SafeArea(
        child: invite == null
            ? Center(
                child: ref.watch(circleInvitesProvider).isLoading
                    ? const CircularProgressIndicator()
                    : Text(l10n.inviteNotFound),
              )
            : Padding(
                padding: EdgeInsets.all(nc.screenPadding),
                child: Column(
                  children: [
                    const Spacer(),
                    CircleBadge(
                      name: invite.name,
                      wallpaper: invite.wallpaper,
                      size: 96,
                    ),
                    const SizedBox(height: NcSpace.cardGap),
                    Text(
                      l10n.invitedToJoin,
                      style: text.bodyMedium?.copyWith(color: nc.textSecondary),
                    ),
                    Text(
                      invite.name,
                      style: text.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    if (invite.inviter != null)
                      Text(l10n.invitedBy(invite.inviter!)),
                    const SizedBox(height: NcSpace.inputGap),
                    Text(l10n.membersCount(invite.memberCount)),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => _accept(context, ref),
                        child: Text(l10n.accept),
                      ),
                    ),
                    const SizedBox(height: NcSpace.inputGap),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                _respond(context, ref, later: false),
                            child: Text(l10n.decline),
                          ),
                        ),
                        const SizedBox(width: NcSpace.inputGap),
                        Expanded(
                          child: TextButton(
                            onPressed: () =>
                                _respond(context, ref, later: true),
                            child: Text(l10n.maybeLater),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// `/circle/<token>` (invite link, validated by DeepLinkValidator): turns
/// the link into an invite on the server, then shows it. Already a member:
/// opens the circle. Expired / unknown: a message.
class CircleLinkScreen extends ConsumerStatefulWidget {
  const new({required this.token, super.key});

  final String token;

  @override
  ConsumerState<CircleLinkScreen> createState() => _CircleLinkState();
}

class _CircleLinkState extends ConsumerState<CircleLinkScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_resolve()));
  }

  Future<void> _resolve() async {
    final l10n = AppLocalizations.of(context);
    try {
      final invite = await ref
          .read(circleApiProvider)
          .resolveInviteLink(widget.token);
      if (!mounted) return;
      ref.invalidate(circleInvitesProvider);
      context.go(Routes.careCircle);
      unawaited(context.push(Routes.circleInviteDetail(invite.circleId)));
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = socialErrorMessage(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(NcSpace.sectionGap),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: () => context.go(Routes.careCircle),
                      child: Text(l10n.backToCircles),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
