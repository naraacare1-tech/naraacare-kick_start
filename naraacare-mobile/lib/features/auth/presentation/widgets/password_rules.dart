import 'package:flutter/material.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// Live checklist under a new password (A9, OQ-29): 8+ characters, one
/// uppercase letter, one number. The validator enforces the same rules.
class PasswordRules extends StatelessWidget {
  const new({required this.password, super.key});

  final String password;

  static final _upper = RegExp(r'\p{Lu}', unicode: true);
  static final _digit = RegExp(r'\p{Nd}', unicode: true);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rules = [
      (l10n.ruleLength, password.length >= 8),
      (l10n.ruleUppercase, _upper.hasMatch(password)),
      (l10n.ruleNumber, _digit.hasMatch(password)),
    ];
    final nc = context.nc;
    final style = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.passwordRulesTitle, style: style),
        const SizedBox(height: NcSpace.xs),
        for (final (label, met) in rules)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NcSpace.xs / 2),
            child: Row(
              children: [
                Icon(
                  met ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: NcSize.iconSmall,
                  color: met ? nc.success : nc.textSecondary,
                ),
                const SizedBox(width: NcSpace.inputGap),
                Text(
                  label,
                  style: style?.copyWith(
                    color: met ? nc.success : nc.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
