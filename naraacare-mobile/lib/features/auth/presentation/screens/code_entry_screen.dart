import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/auth_providers.dart';
import 'package:naraacare/features/auth/presentation/auth_args.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_otp_input.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';

enum CodePurpose {
  /// A4: verifies the new account; success signs the user in.
  verifyEmail,

  /// A8: the password reset code ("code", not "link", OQ-64); the code is
  /// checked by the API together with the new password (A9).
  resetPassword,
}

/// Six code boxes with paste/autofill, resend countdown, "New code sent"
/// toast, and the wrong-code / expired / locked states (Figma Email
/// Verification variants).
class CodeEntryScreen extends ConsumerStatefulWidget {
  const new({required this.purpose, required this.args, super.key});

  final CodePurpose purpose;
  final CodeArgs args;

  @override
  ConsumerState<CodeEntryScreen> createState() => _CodeEntryScreenState();
}

class _CodeEntryScreenState extends ConsumerState<CodeEntryScreen> {
  final _code = TextEditingController();
  late String _challengeId = widget.args.challengeId;
  Timer? _timer;
  int _wait = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCountdown(widget.args.resendAfterSeconds);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _wait = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _wait <= 1) {
        timer.cancel();
        if (mounted) setState(() => _wait = 0);
        return;
      }
      setState(() => _wait--);
    });
  }

  String get _countdown {
    final m = (_wait ~/ 60).toString().padLeft(2, '0');
    final s = (_wait % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final code = InputValidators.normalise(_code.text);
    if (InputValidators.otp(code) != null) {
      setState(() => _error = l10n.otpInvalid);
      return;
    }
    if (widget.purpose == CodePurpose.resetPassword) {
      await context.push(
        Routes.newPassword,
        extra: NewPasswordArgs(challengeId: _challengeId, code: code),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pair = await ref
          .read(authApiProvider)
          .verifyEmail(challengeId: _challengeId, code: code);
      // The router moves to A5 "Email Verified" (onboarding area).
      await ref
          .read(authControllerProvider)
          .signedIn(pair, verifiedEmail: true);
    } on ApiError catch (e) {
      _code.clear();
      if (mounted) setState(() => _error = featureErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final l10n = AppLocalizations.of(context);
    final api = ref.read(authApiProvider);
    setState(() => _error = null);
    try {
      if (widget.purpose == CodePurpose.verifyEmail) {
        _startCountdown(await api.resendCode(_challengeId));
      } else {
        // A new reset request issues a new challenge (and a new code).
        _challengeId = await api.forgotPassword(widget.args.email);
        _startCountdown(widget.args.resendAfterSeconds);
      }
      _code.clear();
      if (mounted) showNcToast(context, l10n.codeResent);
    } on ApiError catch (e) {
      if (e.retryAfterSeconds != null) _startCountdown(e.retryAfterSeconds!);
      if (mounted) setState(() => _error = featureErrorMessage(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final style = Theme.of(context).textTheme.bodySmall;
    final verify = widget.purpose == CodePurpose.verifyEmail;
    return AuthScaffold(
      title: verify ? l10n.verifyTitle : l10n.resetCodeTitle,
      subtitle: verify ? l10n.verifyBody : l10n.resetCodeBody,
      showBack: true,
      children: [
        Text(
          widget.args.email,
          textAlign: TextAlign.center,
          style: style?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: NcSpace.sectionGap),
        NcOtpInput(
          controller: _code,
          hasError: _error != null,
          enabled: !_busy,
          onCompleted: (_) => _submit(),
        ),
        const SizedBox(height: NcSpace.inputGap),
        FormErrorText(_error),
        const SizedBox(height: NcSpace.cardGap),
        NcButton(
          label: verify ? l10n.verifyButton : l10n.continueButton,
          loading: _busy,
          onPressed: _submit,
        ),
        const SizedBox(height: NcSpace.cardGap),
        if (!verify)
          Text(
            l10n.resetCodeSpamHint,
            textAlign: TextAlign.center,
            style: style?.copyWith(color: nc.textSecondary),
          ),
        if (_wait > 0)
          Text(
            l10n.resendIn(_countdown),
            textAlign: TextAlign.center,
            style: style?.copyWith(color: nc.textSecondary),
          )
        else
          AuthPromptLink(
            prompt: l10n.resendPrompt,
            action: l10n.resendCode,
            onTap: _resend,
          ),
      ],
    );
  }
}
