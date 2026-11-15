import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// `/invite/<code>` (App Link / Universal Link, validated by the router):
/// keeps the code until the friend has signed up; Home then sends it to
/// POST /referrals/attribute, and the server decides whether it counts.
class InviteScreen extends ConsumerStatefulWidget {
  const new({required this.code, super.key});

  final String code;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(secureStorageProvider).setPendingReferralCode(widget.code),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    return Scaffold(
      backgroundColor: nc.surface,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(nc.screenPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.card_giftcard,
                color: nc.primary,
                size: NcSize.icon * 3,
              ),
              const SizedBox(height: NcSpace.cardGap),
              Text(
                l10n.invitedTitle,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: NcSpace.inputGap),
              Text(l10n.invitedBody, textAlign: TextAlign.center),
              const SizedBox(height: NcSpace.sectionGap),
              FilledButton(
                onPressed: () => context.go(Routes.home),
                child: Text(l10n.continueButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
