import 'package:flutter/material.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// The metric card on an avatar (Figma "Water 2.1 L / 84 %", "Meal 1450
/// kcal"). Numbers come from the server; the app does no health maths
/// (doc 03 section 3). [pending] marks an entry not yet synced.
class NcAvatarCard extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
    this.caption,
    this.progress,
    this.pending = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? caption;

  /// 0..1 for the ring; null hides it.
  final double? progress;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: nc.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NcRadius.m),
        side: BorderSide(color: nc.inputFill),
      ),
      child: Padding(
        padding: const EdgeInsets.all(NcSpace.buttonGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: NcSize.iconSmall, color: nc.primary),
                const SizedBox(width: NcSpace.xs),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium,
                  ),
                ),
                if (pending) ...[
                  const SizedBox(width: NcSpace.xs),
                  Icon(
                    Icons.sync,
                    size: NcSize.iconSmall,
                    color: nc.textSecondary,
                  ),
                ],
                // The ring sits beside the label so the headline gets the
                // card's full width (narrow screens, long headlines).
                if (progress != null)
                  SizedBox.square(
                    dimension: NcSize.icon,
                    child: CircularProgressIndicator(
                      value: progress!.clamp(0, 1),
                      strokeWidth: 3,
                      backgroundColor: nc.inputFill,
                      color: nc.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: NcSpace.xs),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium?.copyWith(color: nc.primary),
            ),
            if (caption != null) Text(caption!, style: text.labelSmall),
          ],
        ),
      ),
    );
  }
}
