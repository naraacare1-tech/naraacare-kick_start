import 'package:flutter/material.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// Shown above every screen while offline; logging keeps working through
/// the outbox.
class NcOfflineBanner extends StatelessWidget {
  const new({required this.offline, super.key});

  final bool offline;

  @override
  Widget build(BuildContext context) {
    if (!offline) return const SizedBox.shrink();
    final nc = context.nc;
    return Material(
      color: nc.textPrimary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NcSpace.cardPadding,
            vertical: NcSpace.inputGap,
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_off, color: nc.surface, size: NcSize.iconSmall),
              const SizedBox(width: NcSpace.inputGap),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).offlineBanner,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: nc.surface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
