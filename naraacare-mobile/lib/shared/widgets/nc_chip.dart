import 'package:flutter/material.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// Selectable chip (presets like "+250 ml", activities, conditions).
class NcChip extends StatelessWidget {
  const new({
    required this.label,
    required this.onTap,
    super.key,
    this.selected = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? nc.primarySurface : nc.surface,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? nc.primary : nc.inputFill),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NcSpace.buttonGap,
              vertical: NcSpace.inputGap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: NcSize.iconSmall, color: nc.primary),
                  const SizedBox(width: NcSpace.xs),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: selected ? nc.primary : nc.textBody),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
