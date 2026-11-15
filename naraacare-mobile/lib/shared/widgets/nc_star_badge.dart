import 'package:flutter/material.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// The STAR plan badge (profile header, locked features).
class NcStarBadge extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: nc.star,
        borderRadius: BorderRadius.circular(NcRadius.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NcSpace.inputGap,
          vertical: NcSpace.xs,
        ),
        child: Text(
          AppLocalizations.of(context).starBadge,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: nc.surface, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
