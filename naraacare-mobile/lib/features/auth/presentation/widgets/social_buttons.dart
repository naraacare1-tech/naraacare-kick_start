import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/auth_providers.dart';
import 'package:naraacare/features/auth/data/social_sign_in.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/shared/widgets/nc_bottom_sheet.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_error_banner.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';

enum _Provider { google, apple }

/// Google / Apple buttons (A3, A6) with the whole flow: provider sheet ->
/// API -> signed in. 409 LINK_REQUIRED asks for the existing account's
/// password (OQ-30); failures show the A11 banners. Cancelling is silent.
class SocialButtons extends ConsumerStatefulWidget {
  const new({required this.signUp, super.key});

  /// Sign-up copy ("Sign up with…") or sign-in copy.
  final bool signUp;

  @override
  ConsumerState<SocialButtons> createState() => _SocialButtonsState();
}

class _SocialButtonsState extends ConsumerState<SocialButtons> {
  _Provider? _busy;
  String? _error;

  Future<void> _run(_Provider provider) async {
    final l10n = AppLocalizations.of(context);
    final unavailable = provider == _Provider.apple
        ? l10n.appleUnavailable
        : l10n.googleUnavailable;
    setState(() {
      _busy = provider;
      _error = null;
    });
    final social = ref.read(socialSignInProvider);
    final api = ref.read(authApiProvider);
    try {
      final pair = switch (provider) {
        _Provider.google => await social.google().then(
          (c) => api.google(idToken: c.idToken, nonce: c.nonce),
        ),
        _Provider.apple => await social.apple().then(
          (c) => api.apple(
            identityToken: c.identityToken,
            authorizationCode: c.authorizationCode,
            nonce: c.nonce,
          ),
        ),
      };
      await ref.read(authControllerProvider).signedIn(pair);
    } on SocialSignInCancelled {
      // The user closed the sheet.
    } on SocialSignInFailed {
      _show(unavailable);
    } on ApiError catch (e) {
      final linkToken = e.details['link_token'];
      if (e.code == 'LINK_REQUIRED' && linkToken != null && mounted) {
        setState(() => _busy = null); // no spinner behind the sheet
        await _link(linkToken);
      } else {
        _show(e.isNetwork ? unavailable : l10n.socialError);
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _show(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _link(String linkToken) async {
    final l10n = AppLocalizations.of(context);
    final pair = await showNcBottomSheet<Map<String, dynamic>>(
      context: context,
      title: l10n.linkAccountTitle,
      builder: (context) => _LinkSheet(linkToken: linkToken),
    );
    if (pair != null) {
      await ref.read(authControllerProvider).signedIn(pair);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final social = ref.watch(socialSignInProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          NcErrorBanner(
            message: _error!,
            actionLabel: l10n.actionClose,
            onAction: () => setState(() => _error = null),
          ),
          const SizedBox(height: NcSpace.buttonGap),
        ],
        NcButton(
          label: widget.signUp
              ? l10n.continueWithGoogle
              : l10n.signInWithGoogle,
          icon: Icons.g_mobiledata,
          variant: NcButtonVariant.secondary,
          loading: _busy == _Provider.google,
          onPressed: _busy == null ? () => _run(_Provider.google) : null,
        ),
        if (social.appleAvailable) ...[
          const SizedBox(height: NcSpace.buttonGap),
          NcButton(
            label: widget.signUp
                ? l10n.continueWithApple
                : l10n.signInWithApple,
            icon: Icons.apple,
            variant: NcButtonVariant.secondary,
            loading: _busy == _Provider.apple,
            onPressed: _busy == null ? () => _run(_Provider.apple) : null,
          ),
        ],
      ],
    );
  }
}

/// Password prompt to link a Google/Apple sign-in to an existing account.
class _LinkSheet extends ConsumerStatefulWidget {
  const new({required this.linkToken});

  final String linkToken;

  @override
  ConsumerState<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends ConsumerState<_LinkSheet> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final l10n = AppLocalizations.of(context);
    try {
      final pair = await ref
          .read(authApiProvider)
          .link(linkToken: widget.linkToken, password: _password.text);
      if (mounted) Navigator.of(context).pop(pair);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = featureErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.linkAccountBody),
          const SizedBox(height: NcSpace.cardGap),
          NcTextField(
            controller: _password,
            validator: InputValidators.passwordLogin,
            maxLength: 128,
            label: l10n.passwordLabel,
            hint: l10n.passwordHint,
            secret: true,
            autofillHints: const [AutofillHints.password],
            serverError: _error,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: NcSpace.cardGap),
          NcButton(
            label: l10n.linkAccountButton,
            loading: _busy,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
