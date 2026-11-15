import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/errors/error_messages.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';

/// Fixed copy for the API codes the auth, onboarding and settings screens
/// handle (doc 04 error catalogue). Never contains what the user typed.
String featureErrorMessage(AppLocalizations l10n, ApiError error) =>
    switch (error.code) {
      'EMAIL_REGISTERED' => l10n.emailRegistered,
      'PASSWORD_WEAK' => l10n.passwordWeak,
      'PASSWORD_REUSED' => l10n.passwordReused,
      'INVALID_CREDENTIALS' => l10n.invalidCredentials,
      'ACCOUNT_LOCKED' => l10n.accountLocked(
        ((error.retryAfterSeconds ?? 60) / 60).ceil(),
      ),
      'EMAIL_NOT_VERIFIED' => l10n.emailNotVerified,
      'OTP_INVALID' =>
        error.attemptsLeft == null
            ? l10n.otpInvalid
            : l10n.otpInvalidAttempts(error.attemptsLeft!),
      'OTP_EXPIRED' => l10n.otpExpired,
      'OTP_LOCKED' => l10n.otpLocked,
      'GOAL_NOT_ALLOWED' => l10n.goalNotAllowed,
      'USERNAME_TAKEN' => l10n.usernameTaken,
      'USERNAME_CHANGE_TOO_SOON' => l10n.usernameTooSoon,
      'EDIT_WINDOW_CLOSED' => l10n.editWindowClosed,
      'SAVED_MEAL_LIMIT' => l10n.savedMealLimit,
      _ => ErrorMessages.api(l10n, error),
    };
