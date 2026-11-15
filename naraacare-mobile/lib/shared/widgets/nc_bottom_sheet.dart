import 'package:flutter/material.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// Slide-in bottom sheet with a title and a close (x) button (Figma sheets:
/// Add Intake, Profile Username, Today's Nutrition).
Future<T?> showNcBottomSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
}) {
  final nc = context.nc;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: nc.surface,
    barrierColor: nc.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(NcRadius.xl)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        left: nc.screenPadding,
        right: nc.screenPadding,
        bottom: MediaQuery.viewInsetsOf(context).bottom + NcSpace.cardPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: AppLocalizations.of(context).actionClose,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: NcSize.buttonHeight),
            ],
          ),
          const SizedBox(height: NcSpace.cardGap),
          Builder(builder: builder),
        ],
      ),
    ),
  );
}
