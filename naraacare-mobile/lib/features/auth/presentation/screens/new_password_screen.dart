import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/auth_providers.dart';
import 'package:naraacare/features/auth/presentation/auth_args.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:naraacare/features/auth/presentation/widgets/password_rules.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_status_screen.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';

/// A9 Set New Password with the live rules checklist. The code from A8 is
/// checked here by the API; a wrong or expired code sends the user back.
class NewPasswordScreen extends ConsumerStatefulWidget {
  const new({required this.args, super.key});

  final NewPasswordArgs args;

  @override
  ConsumerState<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends ConsumerState<NewPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authApiProvider)
          .resetPassword(
            challengeId: widget.args.challengeId,
            code: widget.args.code,
            newPassword: _password.text,
            confirmPassword: _confirm.text,
          );
      if (mounted) context.go(Routes.passwordChanged);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = featureErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthScaffold(
      title: l10n.newPasswordTitle,
      subtitle: l10n.newPasswordBody,
      showBack: true,
      children: [
        AutofillGroup(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NcTextField(
                  controller: _password,
                  validator: InputValidators.password,
                  maxLength: 128,
                  label: l10n.newPasswordLabel,
                  hint: l10n.newPasswordHint,
                  secret: true,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: NcSpace.cardGap),
                NcTextField(
                  controller: _confirm,
                  validator: InputValidators.confirmPassword(
                    () => _password.text,
                  ),
                  maxLength: 128,
                  label: l10n.confirmPasswordLabel,
                  hint: l10n.confirmNewPasswordHint,
                  secret: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: NcSpace.cardGap),
        PasswordRules(password: _password.text),
        const SizedBox(height: NcSpace.sectionGap),
        FormErrorText(_error),
        NcButton(
          label: l10n.resetPasswordButton,
          loading: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// A10 Password Changed.
class PasswordChangedScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NcStatusScreen(
      title: l10n.passwordChangedTitle,
      body: l10n.passwordChangedBody,
      actionLabel: l10n.backToSignIn,
      onAction: () => context.go(Routes.signIn),
    );
  }
}
