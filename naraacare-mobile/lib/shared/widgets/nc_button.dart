import 'package:flutter/material.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

enum NcButtonVariant { primary, secondary, ghost }

/// Primary / secondary / ghost button (Figma foundations): full width,
/// 56 high, pill shaped; disabled while [onPressed] is null and showing a
/// spinner while [loading] (which also blocks double submits).
class NcButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    super.key,
    this.variant = NcButtonVariant.primary,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final NcButtonVariant variant;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final action = loading ? null : onPressed;
    final content = loading
        ? SizedBox.square(
            dimension: NcSize.icon,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: variant == NcButtonVariant.primary
                  ? nc.surface
                  : nc.primary,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              if (icon != null) ...[
                const SizedBox(width: NcSpace.inputGap),
                Icon(icon, size: NcSize.iconSmall),
              ],
            ],
          );
    const size = Size.fromHeight(NcSize.buttonHeight);
    return switch (variant) {
      NcButtonVariant.primary => FilledButton(
        onPressed: action,
        child: content,
      ),
      NcButtonVariant.secondary => OutlinedButton(
        onPressed: action,
        style: OutlinedButton.styleFrom(
          minimumSize: size,
          shape: const StadiumBorder(),
          foregroundColor: nc.textPrimary,
          side: BorderSide(color: nc.inputFill, width: 2),
        ),
        child: content,
      ),
      NcButtonVariant.ghost => TextButton(
        onPressed: action,
        style: TextButton.styleFrom(
          minimumSize: size,
          foregroundColor: nc.primary,
        ),
        child: content,
      ),
    };
  }
}
