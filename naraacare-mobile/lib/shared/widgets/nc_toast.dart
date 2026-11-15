import 'package:flutter/material.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

enum NcToastKind { success, info, error }

/// Short confirmation ("New code sent successfully on your email"). Fixed
/// copy only.
void showNcToast(
  BuildContext context,
  String message, {
  NcToastKind kind = NcToastKind.success,
}) {
  final nc = context.nc;
  final (background, foreground, icon) = switch (kind) {
    NcToastKind.success => (
      nc.successSurface,
      nc.success,
      Icons.check_circle_outline,
    ),
    NcToastKind.info => (nc.primarySurface, nc.primary, Icons.info_outline),
    NcToastKind.error => (nc.errorSurface, nc.error, Icons.error_outline),
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: background,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NcRadius.s),
        ),
        content: Row(
          children: [
            Icon(icon, color: foreground, size: NcSize.iconSmall),
            const SizedBox(width: NcSpace.inputGap),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
}
