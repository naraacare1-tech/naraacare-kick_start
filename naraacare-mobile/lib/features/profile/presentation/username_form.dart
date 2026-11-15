import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/shared/widgets/nc_bottom_sheet.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';

/// Username entry with a debounced availability check (H2, C2, ST3).
/// Lower-case letters, digits, `.` and `_` only (formatter + validator);
/// the API re-checks and enforces the once-per-90-days rule.
class UsernameForm extends ConsumerStatefulWidget {
  const new({
    required this.onSaved,
    super.key,
    this.initial,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String? initial;
  final VoidCallback onSaved;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  ConsumerState<UsernameForm> createState() => _UsernameFormState();
}

class _UsernameFormState extends ConsumerState<UsernameForm> {
  final _form = GlobalKey<FormState>();
  late final _username = TextEditingController(text: widget.initial);
  Timer? _debounce;
  bool? _available;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _username.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    setState(() {
      _available = null;
      _error = null;
    });
    if (InputValidators.username(value) != null) return;
    _debounce = Timer(const Duration(milliseconds: 500), () => _check(value));
  }

  Future<void> _check(String value) async {
    try {
      final available = await ref
          .read(profileApiProvider)
          .usernameAvailable(value);
      if (mounted && _username.text == value) {
        setState(() => _available = available);
      }
    } on ApiError {
      // Availability is a hint only; saving re-checks.
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(profileApiProvider)
          .setUsername(InputValidators.normalise(_username.text));
      ref.invalidate(meProvider);
      widget.onSaved();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = featureErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final hint = switch (_available) {
      true => (l10n.usernameAvailable, nc.success),
      false => (l10n.usernameTaken, nc.error),
      null => null,
    };
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NcTextField(
            controller: _username,
            validator: InputValidators.username,
            maxLength: 30,
            label: l10n.usernameLabel,
            hint: l10n.usernameHint,
            prefixIcon: Icons.alternate_email,
            inputFormatters: NcTextField.username,
            autofillHints: const [AutofillHints.newUsername],
            serverError: _error,
            onChanged: _changed,
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: NcSpace.xs),
              child: Text(
                hint.$1,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: hint.$2),
              ),
            ),
          const SizedBox(height: NcSpace.inputGap),
          Text(
            l10n.usernameRule,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: nc.textSecondary),
          ),
          const SizedBox(height: NcSpace.sectionGap),
          NcButton(
            label: l10n.saveButton,
            loading: _busy,
            onPressed: _available == false ? null : _save,
          ),
          if (widget.secondaryLabel != null) ...[
            const SizedBox(height: NcSpace.inputGap),
            NcButton(
              label: widget.secondaryLabel!,
              variant: NcButtonVariant.ghost,
              onPressed: widget.onSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

/// H2 / C2 "Create your NaraaCare username" sheet; true when saved.
Future<bool> showUsernameSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final saved = await showNcBottomSheet<bool>(
    context: context,
    title: l10n.usernameSheetTitle,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.usernameSheetBody),
        const SizedBox(height: NcSpace.cardGap),
        UsernameForm(
          onSaved: () => Navigator.of(context).pop(true),
          secondaryLabel: l10n.setUpLater,
          onSecondary: () => Navigator.of(context).pop(false),
        ),
      ],
    ),
  );
  return saved ?? false;
}
