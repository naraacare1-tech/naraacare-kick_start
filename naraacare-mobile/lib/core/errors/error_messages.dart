import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/security/input_validators.dart';

/// User-facing text for validation and API errors. Messages are fixed copy:
/// they never contain the rejected input (doc 07 section 4.3). Screens add
/// copy for the codes they handle themselves (e.g. OTP_INVALID in S07).
abstract final class ErrorMessages {
  static String validation(AppLocalizations l10n, ValidationError error) =>
      switch (error) {
        ValidationError.required => l10n.validationRequired,
        ValidationError.unsafe => l10n.validationUnsafe,
        ValidationError.format => l10n.validationFormat,
        ValidationError.tooShort => l10n.validationTooShort,
        ValidationError.tooLong => l10n.validationTooLong,
        ValidationError.mismatch => l10n.validationMismatch,
        ValidationError.weakPassword => l10n.validationWeakPassword,
        ValidationError.outOfRange => l10n.validationOutOfRange,
      };

  static String api(AppLocalizations l10n, ApiError error) =>
      switch (error.code) {
        ApiError.network => l10n.errorNetwork,
        ApiError.timeout => l10n.errorTimeout,
        ApiError.certificate => l10n.errorCertificate,
        ApiError.rateLimited => l10n.errorRateLimited,
        ApiError.unauthenticated ||
        ApiError.tokenExpired => l10n.errorSessionExpired,
        ApiError.upgradeRequired => l10n.errorUpgradeRequired,
        ApiError.versionConflict => l10n.errorConflict,
        'VALIDATION_FAILED' => l10n.validationUnsafe,
        _ => l10n.errorGeneric,
      };
}
