import 'package:flutter/material.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/shared/widgets/nc_bottom_sheet.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';

/// "Unlock STAR" upsell, shown when the API answers 403 UPGRADE_REQUIRED or a
/// STAR-only control is tapped. [onUpgrade] opens My Subscriptions (S11).
Future<void> showNcUpsellSheet(
  BuildContext context, {
  required VoidCallback onUpgrade,
}) {
  final l10n = AppLocalizations.of(context);
  return showNcBottomSheet<void>(
    context: context,
    title: l10n.upsellTitle,
    builder: (context) {
      final nc = context.nc;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.auto_awesome, color: nc.star, size: NcSize.icon * 2),
          const SizedBox(height: NcSpace.cardGap),
          Text(
            l10n.upsellBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: NcSpace.sectionGap),
          NcButton(label: l10n.upsellTitle, onPressed: onUpgrade),
        ],
      );
    },
  );
}
