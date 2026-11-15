import 'package:flutter/material.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// Inline error banner (e.g. "Unable to connect to Apple...", A11) with an
/// optional retry. [message] is fixed copy, never text from the server.
class NcErrorBanner extends StatelessWidget {
  const new({
    required this.message,
    super.key,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: nc.errorSurface,
          borderRadius: BorderRadius.circular(NcRadius.s),
          border: Border.all(color: nc.error),
        ),
        child: Padding(
          padding: const EdgeInsets.all(NcSpace.buttonGap),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: nc.error, size: NcSize.icon),
              const SizedBox(width: NcSpace.inputGap),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: nc.error),
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ),
        ),
      ),
    );
  }
}
