import 'package:flutter/material.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/shared/widgets/nc_bottom_sheet.dart';

/// One entry of an avatar page's "more" (⋮) menu.
class AvatarMenuItem {
  const new({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// The ⋮ menu of a Home avatar page (Figma H1): a sheet with the page's
/// secondary actions. The sheet closes before the action runs.
Future<void> showAvatarMenu(BuildContext context, List<AvatarMenuItem> items) {
  final l10n = AppLocalizations.of(context);
  return showNcBottomSheet<void>(
    context: context,
    title: l10n.moreOptions,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in items)
          ListTile(
            leading: Icon(item.icon),
            title: Text(item.label),
            onTap: () {
              Navigator.of(sheet).pop();
              item.onTap();
            },
          ),
      ],
    ),
  );
}
