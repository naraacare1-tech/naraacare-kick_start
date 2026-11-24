import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/auth_providers.dart';
import 'package:naraacare/features/auth/presentation/auth_args.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:naraacare/features/auth/presentation/widgets/social_buttons.dart';
import 'package:naraacare/features/legal/legal_document_screen.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';

/// A3 Sign Up: email, password, confirm, terms (no Full Name, OQ-65), then
/// the 6-digit email code (A4). States from Figma: password hidden/shown,
/// email already registered, password mismatch, terms required.
class SignUpScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _terms = false;
  bool _termsError = false;
  bool _busy = false;
  String? _emailError;
  String? _formError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _form.currentState!.validate();
    setState(() => _termsError = !_terms);
    if (!valid || !_terms) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _emailError = null;
      _formError = null;
    });
    final api = ref.read(authApiProvider);
    final email = InputValidators.normalise(_email.text);
    try {
      final policies = await api.policyVersions();
      final challenge = await api.signUp(
        email: email,
        password: _password.text,
        confirmPassword: _confirm.text,
        policies: policies,
      );
      if (!mounted) return;
      await context.push(
        Routes.verifyEmail,
        extra: CodeArgs(
          challengeId: challenge.challengeId,
          email: email,
          resendAfterSeconds: challenge.resendAfterSeconds,
        ),
      );
    } on ApiError catch (e) {
      final message = featureErrorMessage(l10n, e);
      setState(() {
        if (e.code == 'EMAIL_REGISTERED') {
          _emailError = message;
        } else {
          _formError = message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthScaffold(
      title: l10n.signUpTitle,
      subtitle: l10n.signUpSubtitle,
      children: [
        AutofillGroup(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NcTextField(
                  controller: _email,
                  validator: InputValidators.email,
                  maxLength: 254,
                  label: l10n.emailLabel,
                  hint: l10n.emailHint,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  serverError: _emailError,
                  onChanged: (_) {
                    if (_emailError != null) {
                      setState(() => _emailError = null);
                    }
                  },
                ),
                const SizedBox(height: NcSpace.cardGap),
                NcTextField(
                  controller: _password,
                  validator: InputValidators.password,
                  maxLength: 128,
                  label: l10n.passwordLabel,
                  hint: l10n.passwordCreateHint,
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
                  hint: l10n.confirmPasswordHint,
                  secret: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: NcSpace.cardGap),
                _TermsCheckbox(
                  value: _terms,
                  error: _termsError ? l10n.termsRequired : null,
                  onChanged: (v) => setState(() {
                    _terms = v;
                    if (v) _termsError = false;
                  }),
                  onTerms: () =>
                      showLegalDocument(context, LegalDocument.terms),
                  onPrivacy: () =>
                      showLegalDocument(context, LegalDocument.privacy),
                ),
                const SizedBox(height: NcSpace.cardGap),
                FormErrorText(_formError),
                NcButton(
                  label: l10n.signUpButton,
                  loading: _busy,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
        AuthPromptLink(
          prompt: l10n.haveAccountPrompt,
          action: l10n.signInLink,
          onTap: () => context.pushReplacement(Routes.signIn),
        ),
        const OrDivider(),
        const SocialButtons(signUp: true),
      ],
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  const new({
    required this.value,
    required this.error,
    required this.onChanged,
    required this.onTerms,
    required this.onPrivacy,
  });

  final bool value;
  final String? error;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final style = Theme.of(context).textTheme.bodySmall;
    final link = style?.copyWith(
      color: nc.primary,
      fontWeight: FontWeight.w600,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              isError: error != null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: NcSpace.buttonGap),
                child: Text.rich(
                  TextSpan(
                    style: style,
                    children: [
                      TextSpan(text: l10n.termsAgreePrefix),
                      TextSpan(
                        text: l10n.termsLink,
                        style: link,
                        recognizer: TapGestureRecognizer()..onTap = onTerms,
                      ),
                      TextSpan(text: l10n.termsAnd),
                      TextSpan(
                        text: l10n.privacyLink,
                        style: link,
                        recognizer: TapGestureRecognizer()..onTap = onPrivacy,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (error != null)
          Text(error!, style: style?.copyWith(color: nc.error)),
      ],
    );
  }
}
