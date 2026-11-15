import 'package:flutter/material.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';

/// Full-screen success/progress state: Email Verified (A5), Password
/// Changed (A10), Generating / Saved Details (O7).
class NcStatusScreen extends StatelessWidget {
  const new({
    required this.title,
    super.key,
    this.body,
    this.actionLabel,
    this.onAction,
    this.busy = false,
  });

  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Shows a progress indicator instead of the success badge.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: nc.surface,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(nc.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: busy
                    ? SizedBox.square(
                        dimension: NcSize.icon * 3,
                        child: CircularProgressIndicator(color: nc.primary),
                      )
                    : CircleAvatar(
                        radius: NcSize.icon * 2,
                        backgroundColor: nc.successSurface,
                        child: Icon(
                          Icons.verified,
                          size: NcSize.icon * 2,
                          color: nc.success,
                        ),
                      ),
              ),
              const SizedBox(height: NcSpace.sectionGap),
              Text(
                title,
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
              if (body != null) ...[
                const SizedBox(height: NcSpace.inputGap),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: NcSize.onboardingTextMaxWidth,
                    ),
                    child: Text(
                      body!,
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: nc.textSecondary),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (actionLabel != null)
                NcButton(label: actionLabel!, onPressed: onAction),
            ],
          ),
        ),
      ),
    );
  }
}
