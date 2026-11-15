import 'package:flutter/material.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// Empty list / no data yet, with an optional call to action.
class NcEmptyState extends StatelessWidget {
  const new({
    required this.title,
    super.key,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.all(nc.screenPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: NcSize.icon * 2, color: nc.textSecondary),
          const SizedBox(height: NcSpace.cardGap),
          Text(title, style: text.titleLarge, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: NcSpace.inputGap),
            Text(message!, style: text.bodySmall, textAlign: TextAlign.center),
          ],
          if (action != null) ...[
            const SizedBox(height: NcSpace.sectionGap),
            action!,
          ],
        ],
      ),
    );
  }
}
