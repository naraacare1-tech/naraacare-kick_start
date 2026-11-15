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
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';

/// A7 Forgot Password. The API answers the same for unknown emails, so the
/// Figma "No account found with this email" state is not shown (no account
/// enumeration, doc 07); the next screen's copy says "if an account exists".
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final email = InputValidators.normalise(_email.text);
    try {
      final challenge = await ref.read(authApiProvider).forgotPassword(email);
      if (!mounted) return;
      await context.push(
        Routes.resetCode,
        extra: CodeArgs(challengeId: challenge, email: email),
      );
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
      title: l10n.forgotTitle,
      subtitle: l10n.forgotBody,
      showBack: true,
      children: [
        Form(
          key: _form,
          child: NcTextField(
            controller: _email,
            validator: InputValidators.email,
            maxLength: 254,
            label: l10n.emailLabel,
            hint: l10n.emailHint,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            serverError: _error,
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(height: NcSpace.sectionGap),
        NcButton(
          label: l10n.resetPasswordButton,
          loading: _busy,
          onPressed: _submit,
        ),
        const SizedBox(height: NcSpace.buttonGap),
        NcButton(
          label: l10n.backToSignIn,
          variant: NcButtonVariant.ghost,
          onPressed: () => context.go(Routes.signIn),
        ),
      ],
    );
  }
}
