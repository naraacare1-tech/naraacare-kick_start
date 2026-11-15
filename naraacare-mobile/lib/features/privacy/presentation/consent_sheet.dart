import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/config/providers.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/data/auth_api.dart';
import 'package:naraacare/shared/widgets/legal_links.dart';
import 'package:naraacare/shared/widgets/nc_bottom_sheet.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';

/// Consent before onboarding completes (doc 07 SEC-7.1): terms, privacy and
/// health data are required; AI processing is optional and off by default.
/// Returns the decisions for POST /me/onboarding/complete, or null when the
/// sheet is closed.
Future<List<Map<String, Object?>>?> showConsentSheet(
  BuildContext context,
  PolicyVersions policies,
) => showNcBottomSheet<List<Map<String, Object?>>>(
  context: context,
  title: AppLocalizations.of(context).consentTitle,
  builder: (context) => _ConsentSheet(policies: policies),
);

class _ConsentSheet extends ConsumerStatefulWidget {
  const new({required this.policies});

  final PolicyVersions policies;

  @override
  ConsumerState<_ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends ConsumerState<_ConsentSheet> {
  bool _terms = false;
  bool _privacy = false;
  bool _health = false;
  bool _ai = false;

  bool get _ready => _terms && _privacy && _health;

  void _agree() {
    // Health and AI consents follow the privacy policy version.
    final privacy = widget.policies.privacy;
    Navigator.of(context).pop([
      {
        'purpose': 'terms',
        'policy_version': widget.policies.terms,
        'granted': true,
      },
      {'purpose': 'privacy', 'policy_version': privacy, 'granted': true},
      {'purpose': 'health_data', 'policy_version': privacy, 'granted': true},
      {'purpose': 'ai_processing', 'policy_version': privacy, 'granted': _ai},
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final config = ref.watch(appConfigProvider);
    Widget row(
      String label,
      ValueChanged<bool> onChanged, {
      required bool value,
      bool required = true,
      VoidCallback? onOpen,
    }) => CheckboxListTile(
      value: value,
      onChanged: (v) => setState(() => onChanged(v ?? false)),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      subtitle: required
          ? Text(
              l10n.consentRequired,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: nc.textSecondary),
            )
          : null,
      secondary: onOpen == null
          ? null
          : IconButton(icon: const Icon(Icons.open_in_new), onPressed: onOpen),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(
          l10n.consentTerms,
          (v) => _terms = v,
          value: _terms,
          onOpen: () => openLegalLink(context, config.termsUrl),
        ),
        row(
          l10n.consentPrivacy,
          (v) => _privacy = v,
          value: _privacy,
          onOpen: () => openLegalLink(context, config.privacyUrl),
        ),
        row(l10n.consentHealth, (v) => _health = v, value: _health),
        row(l10n.consentAi, (v) => _ai = v, value: _ai, required: false),
        const SizedBox(height: NcSpace.cardGap),
        NcButton(label: l10n.consentAgree, onPressed: _ready ? _agree : null),
      ],
    );
  }
}
