import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/auth_providers.dart';
import 'package:naraacare/features/auth/presentation/auth_args.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:naraacare/features/auth/presentation/widgets/social_buttons.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';

/// A6 Sign In. Wrong email or password gives one generic message (no
/// account enumeration); a lockout shows the wait; an unverified account
/// goes to the code screen with the fresh code the API just sent.
class SignInScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
      final pair = await ref
          .read(authApiProvider)
          .signIn(email: email, password: _password.text);
      await ref.read(authControllerProvider).signedIn(pair);
    } on ApiError catch (e) {
      final challenge = e.details['challenge_id'];
      if (e.code == 'EMAIL_NOT_VERIFIED' && challenge != null && mounted) {
        await context.push(
          Routes.verifyEmail,
          extra: CodeArgs(challengeId: challenge, email: email),
        );
        return;
      }
      _password.clear();
      if (mounted) setState(() => _error = featureErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthScaffold(
      title: l10n.signInTitle,
      subtitle: l10n.signInSubtitle,
      children: [
        AutofillGroup(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FormErrorText(_error),
                NcTextField(
                  controller: _email,
                  validator: InputValidators.email,
                  maxLength: 254,
                  label: l10n.emailLabel,
                  hint: l10n.emailHint,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: NcSpace.cardGap),
                NcTextField(
                  controller: _password,
                  validator: InputValidators.passwordLogin,
                  maxLength: 128,
                  label: l10n.passwordLabel,
                  hint: l10n.passwordHint,
                  secret: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.push(Routes.forgotPassword),
                    child: Text(l10n.forgotPasswordLink),
                  ),
                ),
                NcButton(
                  label: l10n.signInButton,
                  loading: _busy,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
        const OrDivider(),
        const SocialButtons(signUp: false),
        AuthPromptLink(
          prompt: l10n.noAccountPrompt,
          action: l10n.createAccountLink,
          onTap: () => context.pushReplacement(Routes.signUp),
        ),
      ],
    );
  }
}
