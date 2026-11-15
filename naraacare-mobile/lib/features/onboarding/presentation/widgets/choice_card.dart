import 'package:flutter/material.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// A selectable option row/card (activity levels, body types).
class ChoiceCard extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NcRadius.m),
        child: Container(
          padding: const EdgeInsets.all(NcSpace.cardPadding),
          decoration: BoxDecoration(
            color: selected ? nc.primarySurface : nc.inputFill,
            borderRadius: BorderRadius.circular(NcRadius.m),
            border: Border.all(
              color: selected ? nc.primary : nc.inputFill,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: nc.primary),
                const SizedBox(width: NcSpace.buttonGap),
              ],
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? nc.primary : nc.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
