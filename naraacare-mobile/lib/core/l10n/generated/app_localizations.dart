import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'NaraaCare'**
  String get appName;

  /// No description provided for @validationRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required.'**
  String get validationRequired;

  /// No description provided for @validationUnsafe.
  ///
  /// In en, this message translates to:
  /// **'Please use letters, numbers and basic punctuation only.'**
  String get validationUnsafe;

  /// No description provided for @validationFormat.
  ///
  /// In en, this message translates to:
  /// **'This doesn\'t look right. Please check and try again.'**
  String get validationFormat;

  /// No description provided for @validationTooShort.
  ///
  /// In en, this message translates to:
  /// **'This is too short.'**
  String get validationTooShort;

  /// No description provided for @validationTooLong.
  ///
  /// In en, this message translates to:
  /// **'This is too long.'**
  String get validationTooLong;

  /// No description provided for @validationMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get validationMismatch;

  /// No description provided for @validationWeakPassword.
  ///
  /// In en, this message translates to:
  /// **'Use at least 8 characters with one uppercase letter and one number.'**
  String get validationWeakPassword;

  /// No description provided for @validationOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'This value is outside the allowed range.'**
  String get validationOutOfRange;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'No internet connection. We\'ll try again when you\'re back online.'**
  String get errorNetwork;

  /// No description provided for @errorTimeout.
  ///
  /// In en, this message translates to:
  /// **'This is taking too long. Please try again.'**
  String get errorTimeout;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// No description provided for @errorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a moment and try again.'**
  String get errorRateLimited;

  /// No description provided for @errorSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get errorSessionExpired;

  /// No description provided for @errorUpgradeRequired.
  ///
  /// In en, this message translates to:
  /// **'This feature is available with STAR.'**
  String get errorUpgradeRequired;

  /// No description provided for @errorCertificate.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t verify a secure connection. Please check your network.'**
  String get errorCertificate;

  /// No description provided for @errorConflict.
  ///
  /// In en, this message translates to:
  /// **'This entry was changed on another device.'**
  String get errorConflict;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Changes will sync when you\'re back online.'**
  String get offlineBanner;

  /// No description provided for @rootedWarning.
  ///
  /// In en, this message translates to:
  /// **'This device appears to be rooted or jailbroken. Your data may be less secure.'**
  String get rootedWarning;

  /// No description provided for @biometricReason.
  ///
  /// In en, this message translates to:
  /// **'Unlock NaraaCare'**
  String get biometricReason;

  /// No description provided for @biometricUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get biometricUnlock;

  /// No description provided for @tabHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get tabHome;

  /// No description provided for @tabCareCircle.
  ///
  /// In en, this message translates to:
  /// **'Care Circle'**
  String get tabCareCircle;

  /// No description provided for @tabRinAi.
  ///
  /// In en, this message translates to:
  /// **'Rin AI'**
  String get tabRinAi;

  /// No description provided for @tabProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get tabProfile;

  /// No description provided for @starBadge.
  ///
  /// In en, this message translates to:
  /// **'STAR'**
  String get starBadge;

  /// No description provided for @upsellTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock STAR'**
  String get upsellTitle;

  /// No description provided for @upsellBody.
  ///
  /// In en, this message translates to:
  /// **'Get detailed insights and more features with the STAR plan.'**
  String get upsellBody;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @pendingSync.
  ///
  /// In en, this message translates to:
  /// **'Waiting to sync'**
  String get pendingSync;

  /// No description provided for @introSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get introSkip;

  /// No description provided for @introNext.
  ///
  /// In en, this message translates to:
  /// **'Next →'**
  String get introNext;

  /// No description provided for @introGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get introGetStarted;

  /// No description provided for @intro1Title.
  ///
  /// In en, this message translates to:
  /// **'Meet your health avatars'**
  String get intro1Title;

  /// No description provided for @intro1Body.
  ///
  /// In en, this message translates to:
  /// **'Three avatars for water, food and sleep. They fill up through the day as you reach your goals.'**
  String get intro1Body;

  /// No description provided for @intro2Title.
  ///
  /// In en, this message translates to:
  /// **'Goals made for your body'**
  String get intro2Title;

  /// No description provided for @intro2Body.
  ///
  /// In en, this message translates to:
  /// **'Tell us about yourself once. We work out your daily water and calorie goals, then adjust them for hot days and workouts.'**
  String get intro2Body;

  /// No description provided for @intro3Title.
  ///
  /// In en, this message translates to:
  /// **'Care for each other'**
  String get intro3Title;

  /// No description provided for @intro3Body.
  ///
  /// In en, this message translates to:
  /// **'Share your avatars with family and friends in a Care Circle, cheer each other on, and ask Rin AI when you need help.'**
  String get intro3Body;

  /// No description provided for @introStep.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String introStep(int current, int total);

  /// No description provided for @introWater.
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get introWater;

  /// No description provided for @introWaterValue.
  ///
  /// In en, this message translates to:
  /// **'2.1 L'**
  String get introWaterValue;

  /// No description provided for @introWaterCaption.
  ///
  /// In en, this message translates to:
  /// **'of 3.5 L goal'**
  String get introWaterCaption;

  /// No description provided for @introMeal.
  ///
  /// In en, this message translates to:
  /// **'Meal'**
  String get introMeal;

  /// No description provided for @introMealValue.
  ///
  /// In en, this message translates to:
  /// **'1,454'**
  String get introMealValue;

  /// No description provided for @introMealCaption.
  ///
  /// In en, this message translates to:
  /// **'kcal today'**
  String get introMealCaption;

  /// No description provided for @introSleep.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get introSleep;

  /// No description provided for @introSleepValue.
  ///
  /// In en, this message translates to:
  /// **'7h 4m'**
  String get introSleepValue;

  /// No description provided for @introSleepCaption.
  ///
  /// In en, this message translates to:
  /// **'Good sleep'**
  String get introSleepCaption;

  /// No description provided for @introFromProfile.
  ///
  /// In en, this message translates to:
  /// **'FROM YOUR PROFILE'**
  String get introFromProfile;

  /// No description provided for @introTagFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get introTagFemale;

  /// No description provided for @introTagAge.
  ///
  /// In en, this message translates to:
  /// **'28 yrs'**
  String get introTagAge;

  /// No description provided for @introTagHeight.
  ///
  /// In en, this message translates to:
  /// **'5 ft 5 in'**
  String get introTagHeight;

  /// No description provided for @introTagBody.
  ///
  /// In en, this message translates to:
  /// **'Mesomorph'**
  String get introTagBody;

  /// No description provided for @introTagActivity.
  ///
  /// In en, this message translates to:
  /// **'Moderately active'**
  String get introTagActivity;

  /// No description provided for @introDailyWater.
  ///
  /// In en, this message translates to:
  /// **'Daily water goal'**
  String get introDailyWater;

  /// No description provided for @introDailyWaterValue.
  ///
  /// In en, this message translates to:
  /// **'3.7 L'**
  String get introDailyWaterValue;

  /// No description provided for @introDailyCalories.
  ///
  /// In en, this message translates to:
  /// **'Daily calorie goal'**
  String get introDailyCalories;

  /// No description provided for @introDailyCaloriesValue.
  ///
  /// In en, this message translates to:
  /// **'2,374 kcal'**
  String get introDailyCaloriesValue;

  /// No description provided for @introCircleNotice.
  ///
  /// In en, this message translates to:
  /// **'Family circle · 1h ago'**
  String get introCircleNotice;

  /// No description provided for @introCircleNoticeValue.
  ///
  /// In en, this message translates to:
  /// **'@priya hit her water goal'**
  String get introCircleNoticeValue;

  /// No description provided for @introStreak.
  ///
  /// In en, this message translates to:
  /// **'Active streak'**
  String get introStreak;

  /// No description provided for @introStreakValue.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get introStreakValue;

  /// No description provided for @introRin.
  ///
  /// In en, this message translates to:
  /// **'Rin AI'**
  String get introRin;

  /// No description provided for @introRinBody.
  ///
  /// In en, this message translates to:
  /// **'Add about 30 g protein at dinner for a balanced day.'**
  String get introRinBody;

  /// No description provided for @welcomeTagline.
  ///
  /// In en, this message translates to:
  /// **'Glow when you\'re well.\nKnow when they\'re not'**
  String get welcomeTagline;

  /// No description provided for @welcomeGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get welcomeGetStarted;

  /// No description provided for @haveAccountPrompt.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get haveAccountPrompt;

  /// No description provided for @signInLink.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signInLink;

  /// No description provided for @noAccountPrompt.
  ///
  /// In en, this message translates to:
  /// **'New here?'**
  String get noAccountPrompt;

  /// No description provided for @createAccountLink.
  ///
  /// In en, this message translates to:
  /// **'Create an Account'**
  String get createAccountLink;

  /// No description provided for @signUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get signUpTitle;

  /// No description provided for @signUpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start your journey to a healthier you'**
  String get signUpSubtitle;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @emailHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get emailHint;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @passwordCreateHint.
  ///
  /// In en, this message translates to:
  /// **'Create a password'**
  String get passwordCreateHint;

  /// No description provided for @passwordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get passwordHint;

  /// No description provided for @confirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPasswordLabel;

  /// No description provided for @confirmPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Re-enter your password'**
  String get confirmPasswordHint;

  /// No description provided for @termsAgreePrefix.
  ///
  /// In en, this message translates to:
  /// **'I agree to the '**
  String get termsAgreePrefix;

  /// No description provided for @termsLink.
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions'**
  String get termsLink;

  /// No description provided for @termsAnd.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get termsAnd;

  /// No description provided for @privacyLink.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyLink;

  /// No description provided for @termsRequired.
  ///
  /// In en, this message translates to:
  /// **'Please accept the Terms & Conditions and Privacy Policy.'**
  String get termsRequired;

  /// No description provided for @signUpButton.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUpButton;

  /// No description provided for @orDivider.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get orDivider;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign up with Google'**
  String get continueWithGoogle;

  /// No description provided for @continueWithApple.
  ///
  /// In en, this message translates to:
  /// **'Sign up with Apple'**
  String get continueWithApple;

  /// No description provided for @emailRegistered.
  ///
  /// In en, this message translates to:
  /// **'This email is already registered. Try Signing In instead.'**
  String get emailRegistered;

  /// No description provided for @passwordWeak.
  ///
  /// In en, this message translates to:
  /// **'This password is too common or too weak. Please choose another.'**
  String get passwordWeak;

  /// No description provided for @socialError.
  ///
  /// In en, this message translates to:
  /// **'It looks like there was an error signing into your account. Please try again.'**
  String get socialError;

  /// No description provided for @appleUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unable to connect to Apple. Please check your internet connection and try again.'**
  String get appleUnavailable;

  /// No description provided for @googleUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unable to connect to Google. Please check your internet connection and try again.'**
  String get googleUnavailable;

  /// No description provided for @linkAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Link your account'**
  String get linkAccountTitle;

  /// No description provided for @linkAccountBody.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists. Enter its password to link your sign-in.'**
  String get linkAccountBody;

  /// No description provided for @linkAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Link and sign in'**
  String get linkAccountButton;

  /// No description provided for @verifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get verifyTitle;

  /// No description provided for @verifyBody.
  ///
  /// In en, this message translates to:
  /// **'We sent a verification code to your email. Enter the 6-digit code below.'**
  String get verifyBody;

  /// No description provided for @verifyButton.
  ///
  /// In en, this message translates to:
  /// **'Verify Email'**
  String get verifyButton;

  /// No description provided for @resendPrompt.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t receive the code?'**
  String get resendPrompt;

  /// No description provided for @resendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend Code.'**
  String get resendCode;

  /// No description provided for @resendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend available in {time}'**
  String resendIn(String time);

  /// No description provided for @codeResent.
  ///
  /// In en, this message translates to:
  /// **'New code sent successfully on your email'**
  String get codeResent;

  /// No description provided for @otpInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid verification code. Please try again'**
  String get otpInvalid;

  /// No description provided for @otpInvalidAttempts.
  ///
  /// In en, this message translates to:
  /// **'Invalid verification code. {count, plural, =1{1 attempt left.} other{{count} attempts left.}}'**
  String otpInvalidAttempts(int count);

  /// No description provided for @otpExpired.
  ///
  /// In en, this message translates to:
  /// **'This code has expired. Request a new code.'**
  String get otpExpired;

  /// No description provided for @otpLocked.
  ///
  /// In en, this message translates to:
  /// **'Too many wrong codes. Request a new code.'**
  String get otpLocked;

  /// No description provided for @emailVerifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Email Verified'**
  String get emailVerifiedTitle;

  /// No description provided for @emailVerifiedBody.
  ///
  /// In en, this message translates to:
  /// **'Your account is now ready to use. Just one more step.'**
  String get emailVerifiedBody;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get signInTitle;

  /// No description provided for @signInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign In to Continue'**
  String get signInSubtitle;

  /// No description provided for @forgotPasswordLink.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPasswordLink;

  /// No description provided for @signInButton.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signInButton;

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// No description provided for @signInWithApple.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Apple'**
  String get signInWithApple;

  /// No description provided for @invalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password. Please try again.'**
  String get invalidCredentials;

  /// No description provided for @accountLocked.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in {minutes, plural, =1{1 minute} other{{minutes} minutes}}.'**
  String accountLocked(int minutes);

  /// No description provided for @emailNotVerified.
  ///
  /// In en, this message translates to:
  /// **'Please verify your email first. We\'ve sent you a new code.'**
  String get emailNotVerified;

  /// No description provided for @forgotTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password'**
  String get forgotTitle;

  /// No description provided for @forgotBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the email linked to your account and we\'ll send you a code to reset your password.'**
  String get forgotBody;

  /// No description provided for @resetPasswordButton.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPasswordButton;

  /// No description provided for @backToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Back to Sign In'**
  String get backToSignIn;

  /// No description provided for @resetCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Check Your Email'**
  String get resetCodeTitle;

  /// No description provided for @resetCodeBody.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for this email, we\'ve sent a 6-digit code. Enter it below to continue.'**
  String get resetCodeBody;

  /// No description provided for @resetCodeSpamHint.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t receive the email? Check your spam folder or try another email.'**
  String get resetCodeSpamHint;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @newPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Set New Password'**
  String get newPasswordTitle;

  /// No description provided for @newPasswordBody.
  ///
  /// In en, this message translates to:
  /// **'Your new password must be different from previously used passwords.'**
  String get newPasswordBody;

  /// No description provided for @newPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPasswordLabel;

  /// No description provided for @newPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter new password'**
  String get newPasswordHint;

  /// No description provided for @confirmNewPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Re-enter new password'**
  String get confirmNewPasswordHint;

  /// No description provided for @passwordRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Password must contain:'**
  String get passwordRulesTitle;

  /// No description provided for @ruleLength.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get ruleLength;

  /// No description provided for @ruleUppercase.
  ///
  /// In en, this message translates to:
  /// **'One uppercase letter'**
  String get ruleUppercase;

  /// No description provided for @ruleNumber.
  ///
  /// In en, this message translates to:
  /// **'One number'**
  String get ruleNumber;

  /// No description provided for @passwordReused.
  ///
  /// In en, this message translates to:
  /// **'Please choose a password you haven\'t used before.'**
  String get passwordReused;

  /// No description provided for @passwordChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'Password Changed'**
  String get passwordChangedTitle;

  /// No description provided for @passwordChangedBody.
  ///
  /// In en, this message translates to:
  /// **'Your password has been successfully updated. You can now sign in with your new credentials.'**
  String get passwordChangedBody;

  /// No description provided for @onboardingIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Let\'s build your healthy avatar'**
  String get onboardingIntroTitle;

  /// No description provided for @onboardingIntroBody.
  ///
  /// In en, this message translates to:
  /// **'NaraaCare uses your details to map food and water directly to your body.'**
  String get onboardingIntroBody;

  /// No description provided for @onboardingIntroButton.
  ///
  /// In en, this message translates to:
  /// **'Build my avatar'**
  String get onboardingIntroButton;

  /// No description provided for @stepOf.
  ///
  /// In en, this message translates to:
  /// **'{step}/{total}'**
  String stepOf(int step, int total);

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get goBack;

  /// No description provided for @nextButton.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get nextButton;

  /// No description provided for @whyItMatters.
  ///
  /// In en, this message translates to:
  /// **'Why it matters?'**
  String get whyItMatters;

  /// No description provided for @step1Title.
  ///
  /// In en, this message translates to:
  /// **'Choose your gender'**
  String get step1Title;

  /// No description provided for @step1Why.
  ///
  /// In en, this message translates to:
  /// **'Bodies need different amounts of energy and water.'**
  String get step1Why;

  /// No description provided for @sexFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get sexFemale;

  /// No description provided for @sexMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get sexMale;

  /// No description provided for @fullNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullNameLabel;

  /// No description provided for @fullNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your full name'**
  String get fullNameHint;

  /// No description provided for @step2Title.
  ///
  /// In en, this message translates to:
  /// **'How tall are you?'**
  String get step2Title;

  /// No description provided for @step2Why.
  ///
  /// In en, this message translates to:
  /// **'Helps calculate your BMI & nutrition.'**
  String get step2Why;

  /// No description provided for @unitCm.
  ///
  /// In en, this message translates to:
  /// **'cm'**
  String get unitCm;

  /// No description provided for @unitFtIn.
  ///
  /// In en, this message translates to:
  /// **'ft/in'**
  String get unitFtIn;

  /// No description provided for @unitKg.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get unitKg;

  /// No description provided for @unitLb.
  ///
  /// In en, this message translates to:
  /// **'lb'**
  String get unitLb;

  /// No description provided for @feetInches.
  ///
  /// In en, this message translates to:
  /// **'{feet}’{inches}”'**
  String feetInches(int feet, int inches);

  /// No description provided for @step3Title.
  ///
  /// In en, this message translates to:
  /// **'What\'s your current weight?'**
  String get step3Title;

  /// No description provided for @step3Why.
  ///
  /// In en, this message translates to:
  /// **'We don\'t show anyone, not your family, not us. Your weight helps us estimate hydration needs and personalize your daily targets.'**
  String get step3Why;

  /// No description provided for @weightHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your weight'**
  String get weightHint;

  /// No description provided for @goalLabel.
  ///
  /// In en, this message translates to:
  /// **'Your goal'**
  String get goalLabel;

  /// No description provided for @goalHint.
  ///
  /// In en, this message translates to:
  /// **'Select your goal'**
  String get goalHint;

  /// No description provided for @step4Title.
  ///
  /// In en, this message translates to:
  /// **'What\'s your target weight?'**
  String get step4Title;

  /// No description provided for @step4Why.
  ///
  /// In en, this message translates to:
  /// **'Your target helps us support you in this journey.'**
  String get step4Why;

  /// No description provided for @targetHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your target weight'**
  String get targetHint;

  /// No description provided for @healthyRange.
  ///
  /// In en, this message translates to:
  /// **'This target falls within the healthy BMI range {min}-{max} kg for your height.'**
  String healthyRange(int min, int max);

  /// No description provided for @outsideRange.
  ///
  /// In en, this message translates to:
  /// **'You\'re outside the recommended BMI range {min}-{max} kg.'**
  String outsideRange(int min, int max);

  /// No description provided for @conditionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Any medical conditions or allergies?'**
  String get conditionsLabel;

  /// No description provided for @conditionsHint.
  ///
  /// In en, this message translates to:
  /// **'Search conditions'**
  String get conditionsHint;

  /// No description provided for @conditionsNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get conditionsNone;

  /// No description provided for @step5Title.
  ///
  /// In en, this message translates to:
  /// **'How old are you?'**
  String get step5Title;

  /// No description provided for @step5Why.
  ///
  /// In en, this message translates to:
  /// **'Organ function changes with age. Helps personalize hydration & nutrition for you.'**
  String get step5Why;

  /// No description provided for @ageHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your age'**
  String get ageHint;

  /// No description provided for @activityLabel.
  ///
  /// In en, this message translates to:
  /// **'How active are you?'**
  String get activityLabel;

  /// No description provided for @step6Title.
  ///
  /// In en, this message translates to:
  /// **'Choose your body type'**
  String get step6Title;

  /// No description provided for @step6Why.
  ///
  /// In en, this message translates to:
  /// **'It gives us a better understanding of your metabolic needs. Select what best represents you from the 3 types.'**
  String get step6Why;

  /// No description provided for @bodyTypeChosen.
  ///
  /// In en, this message translates to:
  /// **'You chose {name}.'**
  String bodyTypeChosen(String name);

  /// No description provided for @resultTitle.
  ///
  /// In en, this message translates to:
  /// **'Your avatar is ready'**
  String get resultTitle;

  /// No description provided for @resultName.
  ///
  /// In en, this message translates to:
  /// **'Name:'**
  String get resultName;

  /// No description provided for @resultHeight.
  ///
  /// In en, this message translates to:
  /// **'Height:'**
  String get resultHeight;

  /// No description provided for @resultWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight:'**
  String get resultWeight;

  /// No description provided for @resultAge.
  ///
  /// In en, this message translates to:
  /// **'Age:'**
  String get resultAge;

  /// No description provided for @resultGoal.
  ///
  /// In en, this message translates to:
  /// **'Goal:'**
  String get resultGoal;

  /// No description provided for @resultTarget.
  ///
  /// In en, this message translates to:
  /// **'Target weight:'**
  String get resultTarget;

  /// No description provided for @resultActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity:'**
  String get resultActivity;

  /// No description provided for @resultConditions.
  ///
  /// In en, this message translates to:
  /// **'Allergy:'**
  String get resultConditions;

  /// No description provided for @resultBodyType.
  ///
  /// In en, this message translates to:
  /// **'Body type:'**
  String get resultBodyType;

  /// No description provided for @resultCalories.
  ///
  /// In en, this message translates to:
  /// **'Daily calories:'**
  String get resultCalories;

  /// No description provided for @resultWater.
  ///
  /// In en, this message translates to:
  /// **'Daily water:'**
  String get resultWater;

  /// No description provided for @kcalValue.
  ///
  /// In en, this message translates to:
  /// **'{value} kcal'**
  String kcalValue(int value);

  /// No description provided for @mlValue.
  ///
  /// In en, this message translates to:
  /// **'{value} mL'**
  String mlValue(int value);

  /// No description provided for @editDetails.
  ///
  /// In en, this message translates to:
  /// **'Edit Details'**
  String get editDetails;

  /// No description provided for @saveAvatar.
  ///
  /// In en, this message translates to:
  /// **'Save my avatar'**
  String get saveAvatar;

  /// No description provided for @generatingTitle.
  ///
  /// In en, this message translates to:
  /// **'Generating your health profile…'**
  String get generatingTitle;

  /// No description provided for @savedTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved Details'**
  String get savedTitle;

  /// No description provided for @savedBody.
  ///
  /// In en, this message translates to:
  /// **'Redirecting in a moment...'**
  String get savedBody;

  /// No description provided for @goalNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This goal is not available for your current weight. Please choose another.'**
  String get goalNotAllowed;

  /// No description provided for @consentTitle.
  ///
  /// In en, this message translates to:
  /// **'Before we start'**
  String get consentTitle;

  /// No description provided for @consentTerms.
  ///
  /// In en, this message translates to:
  /// **'I accept the Terms & Conditions'**
  String get consentTerms;

  /// No description provided for @consentPrivacy.
  ///
  /// In en, this message translates to:
  /// **'I accept the Privacy Policy'**
  String get consentPrivacy;

  /// No description provided for @consentHealth.
  ///
  /// In en, this message translates to:
  /// **'I agree that NaraaCare processes my health data to give me targets and tracking'**
  String get consentHealth;

  /// No description provided for @consentAi.
  ///
  /// In en, this message translates to:
  /// **'Allow Rin AI to process my messages (optional)'**
  String get consentAi;

  /// No description provided for @consentRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get consentRequired;

  /// No description provided for @consentAgree.
  ///
  /// In en, this message translates to:
  /// **'Agree and continue'**
  String get consentAgree;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good Morning'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good Afternoon'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good Evening'**
  String get greetingEvening;

  /// No description provided for @greetingName.
  ///
  /// In en, this message translates to:
  /// **'{greeting}, {name}'**
  String greetingName(String greeting, String name);

  /// No description provided for @avatarWater.
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get avatarWater;

  /// No description provided for @avatarFood.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get avatarFood;

  /// No description provided for @avatarSleep.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get avatarSleep;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @usernameSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your NaraaCare username'**
  String get usernameSheetTitle;

  /// No description provided for @usernameSheetBody.
  ///
  /// In en, this message translates to:
  /// **'Your username helps people find and connect with you.'**
  String get usernameSheetBody;

  /// No description provided for @usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// No description provided for @usernameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. priya.s'**
  String get usernameHint;

  /// No description provided for @usernameAvailable.
  ///
  /// In en, this message translates to:
  /// **'Username available'**
  String get usernameAvailable;

  /// No description provided for @usernameTaken.
  ///
  /// In en, this message translates to:
  /// **'Username is already taken'**
  String get usernameTaken;

  /// No description provided for @usernameTooSoon.
  ///
  /// In en, this message translates to:
  /// **'You can change your username once every 3 months.'**
  String get usernameTooSoon;

  /// No description provided for @usernameRule.
  ///
  /// In en, this message translates to:
  /// **'Your username should be unique and can include letters, special characters and numbers. You can change your username once every 3 months.'**
  String get usernameRule;

  /// No description provided for @setUpLater.
  ///
  /// In en, this message translates to:
  /// **'Set up later'**
  String get setUpLater;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsProfileSection.
  ///
  /// In en, this message translates to:
  /// **'PROFILE'**
  String get settingsProfileSection;

  /// No description provided for @settingsSubscriptionSection.
  ///
  /// In en, this message translates to:
  /// **'SUBSCRIPTIONS & PAYMENTS'**
  String get settingsSubscriptionSection;

  /// No description provided for @settingsSupportSection.
  ///
  /// In en, this message translates to:
  /// **'SUPPORT & LEGAL'**
  String get settingsSupportSection;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @notificationsReminders.
  ///
  /// In en, this message translates to:
  /// **'Notifications & Reminders'**
  String get notificationsReminders;

  /// No description provided for @mySubscriptions.
  ///
  /// In en, this message translates to:
  /// **'My Subscriptions'**
  String get mySubscriptions;

  /// No description provided for @referFriend.
  ///
  /// In en, this message translates to:
  /// **'Refer a Friend'**
  String get referFriend;

  /// No description provided for @termsTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms and Conditions'**
  String get termsTitle;

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyTitle;

  /// No description provided for @licensesTitle.
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get licensesTitle;

  /// No description provided for @helpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpSupport;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logOut;

  /// No description provided for @logOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Do you want to log out of NaraaCare on this device?'**
  String get logOutConfirm;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get profileSaved;

  /// No description provided for @bmiLabel.
  ///
  /// In en, this message translates to:
  /// **'BMI'**
  String get bmiLabel;

  /// No description provided for @ageLabel.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get ageLabel;

  /// No description provided for @heightLabel.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get heightLabel;

  /// No description provided for @weightLabel.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get weightLabel;

  /// No description provided for @targetWeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Target weight'**
  String get targetWeightLabel;

  /// No description provided for @bodyTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Body type'**
  String get bodyTypeLabel;

  /// No description provided for @sexLabel.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get sexLabel;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @currentPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get currentPasswordLabel;

  /// No description provided for @currentPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter current password'**
  String get currentPasswordHint;

  /// No description provided for @passwordUpdated.
  ///
  /// In en, this message translates to:
  /// **'Password updated'**
  String get passwordUpdated;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// No description provided for @usernameSaved.
  ///
  /// In en, this message translates to:
  /// **'Username updated'**
  String get usernameSaved;

  /// No description provided for @linkOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the page. Please try again later.'**
  String get linkOpenFailed;

  /// No description provided for @kcalValueShort.
  ///
  /// In en, this message translates to:
  /// **'{value} kcal'**
  String kcalValueShort(int value);

  /// No description provided for @ofGoalKcal.
  ///
  /// In en, this message translates to:
  /// **'of {goal} kcal'**
  String ofGoalKcal(int goal);

  /// No description provided for @addMealButton.
  ///
  /// In en, this message translates to:
  /// **'Meal'**
  String get addMealButton;

  /// No description provided for @nutritionInfo.
  ///
  /// In en, this message translates to:
  /// **'About your calorie goal'**
  String get nutritionInfo;

  /// No description provided for @todaysNutrition.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Nutrition'**
  String get todaysNutrition;

  /// No description provided for @basedOnLoggedMeals.
  ///
  /// In en, this message translates to:
  /// **'Based on today\'s logged meals'**
  String get basedOnLoggedMeals;

  /// No description provided for @tierFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get tierFree;

  /// No description provided for @tierIncluded.
  ///
  /// In en, this message translates to:
  /// **'Included'**
  String get tierIncluded;

  /// No description provided for @caloriesOfGoal.
  ///
  /// In en, this message translates to:
  /// **'Calories ({eaten} / {goal} kcal)'**
  String caloriesOfGoal(int eaten, int goal);

  /// No description provided for @lastUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'Last updated • {time}'**
  String lastUpdatedAt(String time);

  /// No description provided for @unlockStarNutrients.
  ///
  /// In en, this message translates to:
  /// **'Get detailed insights on 10+ nutrients with STAR plan.'**
  String get unlockStarNutrients;

  /// No description provided for @lockedNutrients.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more nutrient with STAR} other{{count} more nutrients with STAR}}'**
  String lockedNutrients(int count);

  /// No description provided for @allNutrientsUnlocked.
  ///
  /// In en, this message translates to:
  /// **'All nutritional values unlocked'**
  String get allNutrientsUnlocked;

  /// No description provided for @nutrientUnknown.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get nutrientUnknown;

  /// No description provided for @nutritionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Nutrition isn\'t available right now.'**
  String get nutritionUnavailable;

  /// No description provided for @pendingMeals.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 meal is waiting to sync} other{{count} meals are waiting to sync}}'**
  String pendingMeals(int count);

  /// No description provided for @avatarEmpty.
  ///
  /// In en, this message translates to:
  /// **'Let\'s get started!'**
  String get avatarEmpty;

  /// No description provided for @avatarFueling.
  ///
  /// In en, this message translates to:
  /// **'Fueling up'**
  String get avatarFueling;

  /// No description provided for @avatarEnergized.
  ///
  /// In en, this message translates to:
  /// **'Energized'**
  String get avatarEnergized;

  /// No description provided for @avatarGoalMet.
  ///
  /// In en, this message translates to:
  /// **'Goal met'**
  String get avatarGoalMet;

  /// No description provided for @avatarOverfilled.
  ///
  /// In en, this message translates to:
  /// **'Over your goal'**
  String get avatarOverfilled;

  /// No description provided for @addMealTitle.
  ///
  /// In en, this message translates to:
  /// **'Nutrition Update'**
  String get addMealTitle;

  /// No description provided for @searchFoodHint.
  ///
  /// In en, this message translates to:
  /// **'Search here'**
  String get searchFoodHint;

  /// No description provided for @searchFoodOrBarcodeHint.
  ///
  /// In en, this message translates to:
  /// **'Enter product name or barcode number'**
  String get searchFoodOrBarcodeHint;

  /// No description provided for @recentChips.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recentChips;

  /// No description provided for @addItemsCount.
  ///
  /// In en, this message translates to:
  /// **'Add Items({count})'**
  String addItemsCount(int count);

  /// No description provided for @saveMealButton.
  ///
  /// In en, this message translates to:
  /// **'Save Meal'**
  String get saveMealButton;

  /// No description provided for @updateMealButton.
  ///
  /// In en, this message translates to:
  /// **'Update Meal'**
  String get updateMealButton;

  /// No description provided for @viewNutritionSummary.
  ///
  /// In en, this message translates to:
  /// **'View Nutrition Summary'**
  String get viewNutritionSummary;

  /// No description provided for @nutritionSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Nutrition Summary'**
  String get nutritionSummaryTitle;

  /// No description provided for @addToMeal.
  ///
  /// In en, this message translates to:
  /// **'Add to Meal'**
  String get addToMeal;

  /// No description provided for @noFoodsFound.
  ///
  /// In en, this message translates to:
  /// **'No foods found. Try another name.'**
  String get noFoodsFound;

  /// No description provided for @emptyMeal.
  ///
  /// In en, this message translates to:
  /// **'Search for a food to start your meal.'**
  String get emptyMeal;

  /// No description provided for @maxMealItems.
  ///
  /// In en, this message translates to:
  /// **'A meal can have up to 30 items.'**
  String get maxMealItems;

  /// No description provided for @quantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantityLabel;

  /// No description provided for @unitLabel.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get unitLabel;

  /// No description provided for @removeItem.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeItem;

  /// No description provided for @increaseQuantity.
  ///
  /// In en, this message translates to:
  /// **'Increase'**
  String get increaseQuantity;

  /// No description provided for @decreaseQuantity.
  ///
  /// In en, this message translates to:
  /// **'Decrease'**
  String get decreaseQuantity;

  /// No description provided for @voiceLogging.
  ///
  /// In en, this message translates to:
  /// **'Log by voice'**
  String get voiceLogging;

  /// No description provided for @barcodeLogging.
  ///
  /// In en, this message translates to:
  /// **'Scan a barcode'**
  String get barcodeLogging;

  /// No description provided for @mealTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Meal'**
  String get mealTypeLabel;

  /// No description provided for @mealTypeBreakfast.
  ///
  /// In en, this message translates to:
  /// **'Breakfast'**
  String get mealTypeBreakfast;

  /// No description provided for @mealTypeLunch.
  ///
  /// In en, this message translates to:
  /// **'Lunch'**
  String get mealTypeLunch;

  /// No description provided for @mealTypeSnack.
  ///
  /// In en, this message translates to:
  /// **'Snack'**
  String get mealTypeSnack;

  /// No description provided for @mealTypeDinner.
  ///
  /// In en, this message translates to:
  /// **'Dinner'**
  String get mealTypeDinner;

  /// No description provided for @alsoSaveFavourite.
  ///
  /// In en, this message translates to:
  /// **'Also add to Saved Meals'**
  String get alsoSaveFavourite;

  /// No description provided for @savedMealNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Saved meal name'**
  String get savedMealNameLabel;

  /// No description provided for @savedMealNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Dal Chawal'**
  String get savedMealNameHint;

  /// No description provided for @mealSaved.
  ///
  /// In en, this message translates to:
  /// **'Meal saved'**
  String get mealSaved;

  /// No description provided for @mealQueued.
  ///
  /// In en, this message translates to:
  /// **'Saved offline. It will sync when you\'re back online.'**
  String get mealQueued;

  /// No description provided for @savedMealLimit.
  ///
  /// In en, this message translates to:
  /// **'You have saved the maximum of 50 meals. Remove one first.'**
  String get savedMealLimit;

  /// No description provided for @limitTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily meal limit reached'**
  String get limitTitle;

  /// No description provided for @limitBodyStandard.
  ///
  /// In en, this message translates to:
  /// **'You\'ve logged {limit} meals today, the most on the free plan. STAR lets you log up to 8 meals a day.'**
  String limitBodyStandard(int limit);

  /// No description provided for @limitBodyStar.
  ///
  /// In en, this message translates to:
  /// **'You\'ve logged {limit} meals today. You can log more tomorrow.'**
  String limitBodyStar(int limit);

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @recentUpdates.
  ///
  /// In en, this message translates to:
  /// **'Recent Updates'**
  String get recentUpdates;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAll;

  /// No description provided for @savedMealsTab.
  ///
  /// In en, this message translates to:
  /// **'Saved Meals'**
  String get savedMealsTab;

  /// No description provided for @lastTwoUpdates.
  ///
  /// In en, this message translates to:
  /// **'Last 2 Updates'**
  String get lastTwoUpdates;

  /// No description provided for @otherEntry.
  ///
  /// In en, this message translates to:
  /// **'Other entry'**
  String get otherEntry;

  /// No description provided for @onlyLastTwoEditable.
  ///
  /// In en, this message translates to:
  /// **'Only last 2 entries can be updated'**
  String get onlyLastTwoEditable;

  /// No description provided for @editYourEntry.
  ///
  /// In en, this message translates to:
  /// **'Edit your entry'**
  String get editYourEntry;

  /// No description provided for @noRecentMeals.
  ///
  /// In en, this message translates to:
  /// **'No meals logged yet.'**
  String get noRecentMeals;

  /// No description provided for @noSavedMeals.
  ///
  /// In en, this message translates to:
  /// **'No saved meals yet. Turn on \"Also add to Saved Meals\" when you save a meal.'**
  String get noSavedMeals;

  /// No description provided for @useSavedMeal.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get useSavedMeal;

  /// No description provided for @deleteEntry.
  ///
  /// In en, this message translates to:
  /// **'Delete entry'**
  String get deleteEntry;

  /// No description provided for @deleteEntryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this meal? This cannot be undone.'**
  String get deleteEntryConfirm;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @entryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Entry updated'**
  String get entryUpdated;

  /// No description provided for @entryDeleted.
  ///
  /// In en, this message translates to:
  /// **'Entry deleted'**
  String get entryDeleted;

  /// No description provided for @editWindowClosed.
  ///
  /// In en, this message translates to:
  /// **'This entry can no longer be edited.'**
  String get editWindowClosed;

  /// No description provided for @syncingLabel.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get syncingLabel;

  /// No description provided for @mealItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String mealItemsCount(int count);

  /// No description provided for @voiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Nutrition Update'**
  String get voiceTitle;

  /// No description provided for @voiceListening.
  ///
  /// In en, this message translates to:
  /// **'Listening for ingredients…'**
  String get voiceListening;

  /// No description provided for @voiceTrySaying.
  ///
  /// In en, this message translates to:
  /// **'Try saying: \"2 roti and 1 katori dal\"'**
  String get voiceTrySaying;

  /// No description provided for @voiceTranscriptLabel.
  ///
  /// In en, this message translates to:
  /// **'What you said'**
  String get voiceTranscriptLabel;

  /// No description provided for @voiceTranscriptHint.
  ///
  /// In en, this message translates to:
  /// **'Your meal in words'**
  String get voiceTranscriptHint;

  /// No description provided for @voiceStart.
  ///
  /// In en, this message translates to:
  /// **'Tap to speak'**
  String get voiceStart;

  /// No description provided for @voiceStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get voiceStop;

  /// No description provided for @voiceFindFoods.
  ///
  /// In en, this message translates to:
  /// **'Find foods'**
  String get voiceFindFoods;

  /// No description provided for @voiceUnmatched.
  ///
  /// In en, this message translates to:
  /// **'Not found: {items}'**
  String voiceUnmatched(String items);

  /// No description provided for @voiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition isn\'t available on this device. You can type instead.'**
  String get voiceUnavailable;

  /// No description provided for @voiceDidNotHear.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t hear you. Check the microphone and try again, or type instead.'**
  String get voiceDidNotHear;

  /// No description provided for @voiceNothingFound.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t match any foods. Try again or search by name.'**
  String get voiceNothingFound;

  /// No description provided for @checkBeforeSaving.
  ///
  /// In en, this message translates to:
  /// **'Check the items before saving.'**
  String get checkBeforeSaving;

  /// No description provided for @barcodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get barcodeTitle;

  /// No description provided for @barcodePermission.
  ///
  /// In en, this message translates to:
  /// **'Allow camera access to scan barcodes, or type the number below.'**
  String get barcodePermission;

  /// No description provided for @barcodeManualLabel.
  ///
  /// In en, this message translates to:
  /// **'Barcode number'**
  String get barcodeManualLabel;

  /// No description provided for @barcodeManualHint.
  ///
  /// In en, this message translates to:
  /// **'8 to 14 digits'**
  String get barcodeManualHint;

  /// No description provided for @barcodeLookup.
  ///
  /// In en, this message translates to:
  /// **'Look up'**
  String get barcodeLookup;

  /// No description provided for @barcodeNotFound.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find this product. Try searching by name.'**
  String get barcodeNotFound;

  /// No description provided for @barcodeNotLoggable.
  ///
  /// In en, this message translates to:
  /// **'This product\'s nutrition data is incomplete. Try searching by name.'**
  String get barcodeNotLoggable;

  /// No description provided for @scanAnother.
  ///
  /// In en, this message translates to:
  /// **'Scan Another'**
  String get scanAnother;

  /// No description provided for @per100g.
  ///
  /// In en, this message translates to:
  /// **'Per 100 g'**
  String get per100g;

  /// No description provided for @servingSize.
  ///
  /// In en, this message translates to:
  /// **'Serving: {grams} g'**
  String servingSize(String grams);

  /// No description provided for @searchByName.
  ///
  /// In en, this message translates to:
  /// **'Search by name'**
  String get searchByName;

  /// No description provided for @openFoodFactsCredit.
  ///
  /// In en, this message translates to:
  /// **'Product data: Open Food Facts (ODbL)'**
  String get openFoodFactsCredit;

  /// No description provided for @macroSplit.
  ///
  /// In en, this message translates to:
  /// **'Carbs {carbs}% · Protein {protein}% · Fat {fat}%'**
  String macroSplit(int carbs, int protein, int fat);

  /// No description provided for @mealBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Meal breakdown'**
  String get mealBreakdown;

  /// No description provided for @infoGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'How your calorie goal is set'**
  String get infoGoalTitle;

  /// No description provided for @infoGoalBody.
  ///
  /// In en, this message translates to:
  /// **'NaraaCare works out your daily calorie goal from the details you gave us: the energy your body burns at rest (from your gender, height, weight and age), plus your normal daily movement, adjusted for your goal. It never goes below 1,200 kcal a day for women or 1,500 kcal for men; if that happens, we\'ll tell you.'**
  String get infoGoalBody;

  /// No description provided for @infoTodayGoal.
  ///
  /// In en, this message translates to:
  /// **'Today\'s goal: {kcal} kcal'**
  String infoTodayGoal(int kcal);

  /// No description provided for @infoWorkoutsTitle.
  ///
  /// In en, this message translates to:
  /// **'Workouts give you more to eat'**
  String get infoWorkoutsTitle;

  /// No description provided for @infoWorkoutsBody.
  ///
  /// In en, this message translates to:
  /// **'When you log a workout, the calories you burn are added to today\'s goal. For example, if your goal is 1,800 kcal and a run burns 400 kcal, you can eat 2,200 kcal today and stay on track.'**
  String get infoWorkoutsBody;

  /// No description provided for @infoNutrientsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your daily nutrients'**
  String get infoNutrientsTitle;

  /// No description provided for @infoNutrientsBody.
  ///
  /// In en, this message translates to:
  /// **'Your calories are split into a balanced mix: 55% carbohydrates, 25% fat and 20% protein. STANDARD shows 6 nutrients: calories, protein, carbohydrates, fat, dietary fibre and total sugar. STAR adds 11 more.'**
  String get infoNutrientsBody;

  /// No description provided for @infoTargets.
  ///
  /// In en, this message translates to:
  /// **'Today\'s targets: carbs {carbs} g, fat {fat} g, protein {protein} g'**
  String infoTargets(int carbs, int fat, int protein);

  /// No description provided for @infoLoggingTitle.
  ///
  /// In en, this message translates to:
  /// **'Logging your meals'**
  String get infoLoggingTitle;

  /// No description provided for @infoLoggingBody.
  ///
  /// In en, this message translates to:
  /// **'Search for a food, pick the amount and unit (katori, piece, cup, glass, tsp, tbsp) and add it to your meal. Add more items, then tap Save Meal. Use Recent and Saved Meals to log favourites quickly. Voice and barcode logging are part of STAR. You can change or delete your last 2 entries.'**
  String get infoLoggingBody;

  /// No description provided for @infoNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Please note'**
  String get infoNoteTitle;

  /// No description provided for @infoNoteBody.
  ///
  /// In en, this message translates to:
  /// **'Nutrition values are estimates and real foods vary. This isn\'t medical or dietary advice. If you have a medical condition, are pregnant, or follow a diet set by your doctor, follow their advice.'**
  String get infoNoteBody;

  /// No description provided for @hydrationEmpty.
  ///
  /// In en, this message translates to:
  /// **'Let\'s get started!'**
  String get hydrationEmpty;

  /// No description provided for @hydrationProgress.
  ///
  /// In en, this message translates to:
  /// **'{intake} L of {goal} L goal'**
  String hydrationProgress(String intake, String goal);

  /// No description provided for @hydrationGoalCompleted.
  ///
  /// In en, this message translates to:
  /// **'Goal Completed'**
  String get hydrationGoalCompleted;

  /// No description provided for @hydrationAboveGoal.
  ///
  /// In en, this message translates to:
  /// **'Above Goal · {intake} L'**
  String hydrationAboveGoal(String intake);

  /// No description provided for @hydrationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Hydration isn\'t available right now.'**
  String get hydrationUnavailable;

  /// No description provided for @bandWell.
  ///
  /// In en, this message translates to:
  /// **'Well hydrated'**
  String get bandWell;

  /// No description provided for @bandDrinkSoon.
  ///
  /// In en, this message translates to:
  /// **'Drink soon'**
  String get bandDrinkSoon;

  /// No description provided for @bandLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get bandLow;

  /// No description provided for @bandCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical, drink now'**
  String get bandCritical;

  /// No description provided for @goalPct.
  ///
  /// In en, this message translates to:
  /// **'{value} % of today\'s goal'**
  String goalPct(int value);

  /// No description provided for @levelPct.
  ///
  /// In en, this message translates to:
  /// **'{value} %'**
  String levelPct(int value);

  /// No description provided for @leftToDrink.
  ///
  /// In en, this message translates to:
  /// **'{litres} L left to drink today'**
  String leftToDrink(String litres);

  /// No description provided for @dayEndingSoon.
  ///
  /// In en, this message translates to:
  /// **'Your day is ending soon. There\'s still time to reach your goal.'**
  String get dayEndingSoon;

  /// No description provided for @overhydrationCaution.
  ///
  /// In en, this message translates to:
  /// **'That\'s a lot of fluid today. Drinking far more than you need can be harmful.'**
  String get overhydrationCaution;

  /// No description provided for @temperatureNotUpdated.
  ///
  /// In en, this message translates to:
  /// **'Temperature not updated today: we\'re using 25 °C.'**
  String get temperatureNotUpdated;

  /// No description provided for @swipeHint.
  ///
  /// In en, this message translates to:
  /// **'Swipe up to add 100 ml of water, swipe down to remove 100 ml'**
  String get swipeHint;

  /// No description provided for @swipeAdded.
  ///
  /// In en, this message translates to:
  /// **'{ml} ml of water added'**
  String swipeAdded(int ml);

  /// No description provided for @swipeRemoved.
  ///
  /// In en, this message translates to:
  /// **'{ml} ml of water removed'**
  String swipeRemoved(int ml);

  /// No description provided for @waterBelowZero.
  ///
  /// In en, this message translates to:
  /// **'Today\'s water can\'t go below zero.'**
  String get waterBelowZero;

  /// No description provided for @addWaterButton.
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get addWaterButton;

  /// No description provided for @temperatureActivity.
  ///
  /// In en, this message translates to:
  /// **'Temperature & Activity'**
  String get temperatureActivity;

  /// No description provided for @hydrationInfo.
  ///
  /// In en, this message translates to:
  /// **'About your water goal'**
  String get hydrationInfo;

  /// No description provided for @todaysHydration.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Hydration'**
  String get todaysHydration;

  /// No description provided for @tankLevel.
  ///
  /// In en, this message translates to:
  /// **'Hydration level'**
  String get tankLevel;

  /// No description provided for @dailyGoal.
  ///
  /// In en, this message translates to:
  /// **'Daily goal'**
  String get dailyGoal;

  /// No description provided for @drinksToday.
  ///
  /// In en, this message translates to:
  /// **'Drinks today'**
  String get drinksToday;

  /// No description provided for @waterFromFood.
  ///
  /// In en, this message translates to:
  /// **'Water from food'**
  String get waterFromFood;

  /// No description provided for @workoutSweat.
  ///
  /// In en, this message translates to:
  /// **'Lost in workouts'**
  String get workoutSweat;

  /// No description provided for @temperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get temperature;

  /// No description provided for @leftToDrinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Left to drink'**
  String get leftToDrinkLabel;

  /// No description provided for @addIntakeTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a drink'**
  String get addIntakeTitle;

  /// No description provided for @waterTab.
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get waterTab;

  /// No description provided for @otherDrinksTab.
  ///
  /// In en, this message translates to:
  /// **'Other drinks'**
  String get otherDrinksTab;

  /// No description provided for @searchDrinkHint.
  ///
  /// In en, this message translates to:
  /// **'Search drinks'**
  String get searchDrinkHint;

  /// No description provided for @customDrink.
  ///
  /// In en, this message translates to:
  /// **'Custom drink'**
  String get customDrink;

  /// No description provided for @amountMl.
  ///
  /// In en, this message translates to:
  /// **'Amount (ml)'**
  String get amountMl;

  /// No description provided for @addIntakeButton.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addIntakeButton;

  /// No description provided for @intakeAdded.
  ///
  /// In en, this message translates to:
  /// **'Drink added'**
  String get intakeAdded;

  /// No description provided for @savedOffline.
  ///
  /// In en, this message translates to:
  /// **'Saved. It will sync when you\'re back online.'**
  String get savedOffline;

  /// No description provided for @customDrinkName.
  ///
  /// In en, this message translates to:
  /// **'Drink name'**
  String get customDrinkName;

  /// No description provided for @customDrinkHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Banana Shake'**
  String get customDrinkHint;

  /// No description provided for @estimateFactor.
  ///
  /// In en, this message translates to:
  /// **'Estimate hydration'**
  String get estimateFactor;

  /// No description provided for @estimateFromAi.
  ///
  /// In en, this message translates to:
  /// **'Estimated by Rin AI. Adjust it if you know better.'**
  String get estimateFromAi;

  /// No description provided for @estimateDefault.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t estimate this drink, so we start at 85 %. Adjust it if you know better.'**
  String get estimateDefault;

  /// No description provided for @estimateNoConsent.
  ///
  /// In en, this message translates to:
  /// **'AI estimates need your AI consent (Privacy settings). We start at 85 %; adjust it if you know better.'**
  String get estimateNoConsent;

  /// No description provided for @factorPct.
  ///
  /// In en, this message translates to:
  /// **'{value} %'**
  String factorPct(int value);

  /// No description provided for @factorExplain.
  ///
  /// In en, this message translates to:
  /// **'{value} % of this drink counts as water'**
  String factorExplain(int value);

  /// No description provided for @saveCustomDrink.
  ///
  /// In en, this message translates to:
  /// **'Save drink'**
  String get saveCustomDrink;

  /// No description provided for @noDrinksYet.
  ///
  /// In en, this message translates to:
  /// **'No drinks logged today yet.'**
  String get noDrinksYet;

  /// No description provided for @swipeDownEntry.
  ///
  /// In en, this message translates to:
  /// **'Water removed · {ml} ml'**
  String swipeDownEntry(int ml);

  /// No description provided for @editEntry.
  ///
  /// In en, this message translates to:
  /// **'Edit your entry'**
  String get editEntry;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @changedElsewhere.
  ///
  /// In en, this message translates to:
  /// **'This entry was changed on another device. We\'ve loaded the latest version.'**
  String get changedElsewhere;

  /// No description provided for @temperatureActivityUpsell.
  ///
  /// In en, this message translates to:
  /// **'Set today\'s temperature and log workouts so your water goal follows your day. Part of STAR.'**
  String get temperatureActivityUpsell;

  /// No description provided for @saveTemperature.
  ///
  /// In en, this message translates to:
  /// **'Save temperature'**
  String get saveTemperature;

  /// No description provided for @temperatureSaved.
  ///
  /// In en, this message translates to:
  /// **'Temperature set to {value}'**
  String temperatureSaved(String value);

  /// No description provided for @activity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// No description provided for @minutesValue.
  ///
  /// In en, this message translates to:
  /// **'{value} min'**
  String minutesValue(int value);

  /// No description provided for @customMinutes.
  ///
  /// In en, this message translates to:
  /// **'Other duration (minutes)'**
  String get customMinutes;

  /// No description provided for @saveWorkout.
  ///
  /// In en, this message translates to:
  /// **'Save workout'**
  String get saveWorkout;

  /// No description provided for @workoutSaved.
  ///
  /// In en, this message translates to:
  /// **'Workout saved'**
  String get workoutSaved;

  /// No description provided for @workoutWalking.
  ///
  /// In en, this message translates to:
  /// **'Walking'**
  String get workoutWalking;

  /// No description provided for @workoutGym.
  ///
  /// In en, this message translates to:
  /// **'Gym'**
  String get workoutGym;

  /// No description provided for @workoutCycling.
  ///
  /// In en, this message translates to:
  /// **'Cycling'**
  String get workoutCycling;

  /// No description provided for @workoutSwimming.
  ///
  /// In en, this message translates to:
  /// **'Swimming'**
  String get workoutSwimming;

  /// No description provided for @workoutRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get workoutRunning;

  /// No description provided for @workoutTrekking.
  ///
  /// In en, this message translates to:
  /// **'Trekking'**
  String get workoutTrekking;

  /// No description provided for @hydrationInfoGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'Your daily water goal'**
  String get hydrationInfoGoalTitle;

  /// No description provided for @hydrationInfoGoalBody.
  ///
  /// In en, this message translates to:
  /// **'Your goal comes from your body (sex, height, weight, age, body type) and how active you are, using the Yamada 2022 water turnover model. With STAR it also follows the temperature and your workouts.'**
  String get hydrationInfoGoalBody;

  /// No description provided for @hydrationInfoTankTitle.
  ///
  /// In en, this message translates to:
  /// **'Your water avatar'**
  String get hydrationInfoTankTitle;

  /// No description provided for @hydrationInfoTankBody.
  ///
  /// In en, this message translates to:
  /// **'The avatar shows how full your body\'s water reserve is right now. It drains through the day and fills when you drink. Meals add a little water too.'**
  String get hydrationInfoTankBody;

  /// No description provided for @hydrationInfoLoggingTitle.
  ///
  /// In en, this message translates to:
  /// **'Logging drinks'**
  String get hydrationInfoLoggingTitle;

  /// No description provided for @hydrationInfoLoggingBody.
  ///
  /// In en, this message translates to:
  /// **'Swipe up on the water card to add 100 ml of water, or swipe down to remove 100 ml. Tap Water to add other amounts and drinks. You can change or delete your last 2 entries.'**
  String get hydrationInfoLoggingBody;

  /// No description provided for @hydrationInfoNoteBody.
  ///
  /// In en, this message translates to:
  /// **'Water needs are estimates and vary from person to person. This isn\'t medical advice. If your doctor has limited how much you should drink, follow their advice.'**
  String get hydrationInfoNoteBody;

  /// No description provided for @notificationsExplainerTitle.
  ///
  /// In en, this message translates to:
  /// **'Stay on track with reminders'**
  String get notificationsExplainerTitle;

  /// No description provided for @notificationsExplainerBody.
  ///
  /// In en, this message translates to:
  /// **'NaraaCare can remind you to drink water, log meals and wind down for sleep. Reminders never show your health numbers on the lock screen, and you can change them any time.'**
  String get notificationsExplainerBody;

  /// No description provided for @allowNotifications.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications'**
  String get allowNotifications;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @pushUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Notifications are off for NaraaCare. Turn them on in your phone\'s settings to get reminders. Your settings are saved.'**
  String get pushUnavailable;

  /// No description provided for @reminderWaterTitle.
  ///
  /// In en, this message translates to:
  /// **'Time for some water'**
  String get reminderWaterTitle;

  /// No description provided for @reminderWaterBody.
  ///
  /// In en, this message translates to:
  /// **'A few sips keep your avatar happy.'**
  String get reminderWaterBody;

  /// No description provided for @reminderMealTitle.
  ///
  /// In en, this message translates to:
  /// **'Log your meal'**
  String get reminderMealTitle;

  /// No description provided for @reminderMealBody.
  ///
  /// In en, this message translates to:
  /// **'Add what you ate to keep your day on track.'**
  String get reminderMealBody;

  /// No description provided for @reminderSleepTitle.
  ///
  /// In en, this message translates to:
  /// **'Wind down'**
  String get reminderSleepTitle;

  /// No description provided for @reminderSleepBody.
  ///
  /// In en, this message translates to:
  /// **'Getting ready for bed? Log your sleep in the morning.'**
  String get reminderSleepBody;

  /// No description provided for @reminderCheckinTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily check-in'**
  String get reminderCheckinTitle;

  /// No description provided for @reminderCheckinBody.
  ///
  /// In en, this message translates to:
  /// **'Take a moment to check in with your avatars.'**
  String get reminderCheckinBody;

  /// No description provided for @reminderProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep your profile current'**
  String get reminderProfileTitle;

  /// No description provided for @reminderProfileBody.
  ///
  /// In en, this message translates to:
  /// **'Review your health profile for accurate goals.'**
  String get reminderProfileBody;

  /// No description provided for @remindersSection.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get remindersSection;

  /// No description provided for @notificationTypesSection.
  ///
  /// In en, this message translates to:
  /// **'Notify me about'**
  String get notificationTypesSection;

  /// No description provided for @settingsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Settings aren\'t available right now.'**
  String get settingsUnavailable;

  /// No description provided for @everyMinutes.
  ///
  /// In en, this message translates to:
  /// **'Every {value} minutes while you\'re awake'**
  String everyMinutes(int value);

  /// No description provided for @addTime.
  ///
  /// In en, this message translates to:
  /// **'Add time'**
  String get addTime;

  /// No description provided for @quietHoursNote.
  ///
  /// In en, this message translates to:
  /// **'No reminders between 22:30 and 07:00.'**
  String get quietHoursNote;

  /// No description provided for @prefGoalCompletions.
  ///
  /// In en, this message translates to:
  /// **'Goal completions'**
  String get prefGoalCompletions;

  /// No description provided for @prefStreakMilestones.
  ///
  /// In en, this message translates to:
  /// **'Streak milestones'**
  String get prefStreakMilestones;

  /// No description provided for @prefHealthInsights.
  ///
  /// In en, this message translates to:
  /// **'Health insights'**
  String get prefHealthInsights;

  /// No description provided for @prefHydrationReminders.
  ///
  /// In en, this message translates to:
  /// **'Hydration reminders'**
  String get prefHydrationReminders;

  /// No description provided for @prefNutritionReminders.
  ///
  /// In en, this message translates to:
  /// **'Meal reminders'**
  String get prefNutritionReminders;

  /// No description provided for @prefSleepReminders.
  ///
  /// In en, this message translates to:
  /// **'Sleep reminders'**
  String get prefSleepReminders;

  /// No description provided for @prefDailyCheckin.
  ///
  /// In en, this message translates to:
  /// **'Daily check-in'**
  String get prefDailyCheckin;

  /// No description provided for @prefHealthProfile.
  ///
  /// In en, this message translates to:
  /// **'Health profile reminders'**
  String get prefHealthProfile;

  /// No description provided for @prefConnectionRequests.
  ///
  /// In en, this message translates to:
  /// **'Connection requests'**
  String get prefConnectionRequests;

  /// No description provided for @prefConnectionActivity.
  ///
  /// In en, this message translates to:
  /// **'Connection activity'**
  String get prefConnectionActivity;

  /// No description provided for @prefReportsReady.
  ///
  /// In en, this message translates to:
  /// **'Reports ready'**
  String get prefReportsReady;

  /// No description provided for @prefSubscriptionPayments.
  ///
  /// In en, this message translates to:
  /// **'Subscription and payments'**
  String get prefSubscriptionPayments;

  /// No description provided for @hoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} m'**
  String hoursMinutes(int hours, int minutes);

  /// No description provided for @sleepGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get sleepGood;

  /// No description provided for @sleepFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get sleepFair;

  /// No description provided for @sleepLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get sleepLow;

  /// No description provided for @sleepNone.
  ///
  /// In en, this message translates to:
  /// **'Not logged'**
  String get sleepNone;

  /// No description provided for @sleepNotLogged.
  ///
  /// In en, this message translates to:
  /// **'No sleep logged yet'**
  String get sleepNotLogged;

  /// No description provided for @sleepUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Sleep isn\'t available right now.'**
  String get sleepUnavailable;

  /// No description provided for @sleepButton.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get sleepButton;

  /// No description provided for @sleepInfo.
  ///
  /// In en, this message translates to:
  /// **'About your sleep score'**
  String get sleepInfo;

  /// No description provided for @unlockSleepAvatar.
  ///
  /// In en, this message translates to:
  /// **'Unlock your Sleep Avatar'**
  String get unlockSleepAvatar;

  /// No description provided for @todaysSleep.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Sleep'**
  String get todaysSleep;

  /// No description provided for @sleepOfGoal.
  ///
  /// In en, this message translates to:
  /// **'{achieved} of {goal}'**
  String sleepOfGoal(String achieved, String goal);

  /// No description provided for @nightWakings.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 night waking} other{{count} night wakings}}'**
  String nightWakings(int count);

  /// No description provided for @sleepBuffersExplain.
  ///
  /// In en, this message translates to:
  /// **'We don\'t count the first {onset} minutes after you go to bed (falling asleep) or the last {wake} minutes before you wake. Each night waking also removes {waking} extra minutes.'**
  String sleepBuffersExplain(int onset, int wake, int waking);

  /// No description provided for @sleepGoal.
  ///
  /// In en, this message translates to:
  /// **'Your sleep goal'**
  String get sleepGoal;

  /// No description provided for @updateSleep.
  ///
  /// In en, this message translates to:
  /// **'Update Sleep'**
  String get updateSleep;

  /// No description provided for @sleepStartLabel.
  ///
  /// In en, this message translates to:
  /// **'Went to bed'**
  String get sleepStartLabel;

  /// No description provided for @wakeTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Woke up'**
  String get wakeTimeLabel;

  /// No description provided for @nightWakingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Night wakings'**
  String get nightWakingsTitle;

  /// No description provided for @wokeAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Woke at'**
  String get wokeAtLabel;

  /// No description provided for @backAsleepLabel.
  ///
  /// In en, this message translates to:
  /// **'Back asleep'**
  String get backAsleepLabel;

  /// No description provided for @addNightWaking.
  ///
  /// In en, this message translates to:
  /// **'Add night waking'**
  String get addNightWaking;

  /// No description provided for @saveSleep.
  ///
  /// In en, this message translates to:
  /// **'Save sleep'**
  String get saveSleep;

  /// No description provided for @sleepSaved.
  ///
  /// In en, this message translates to:
  /// **'Sleep saved'**
  String get sleepSaved;

  /// No description provided for @badgeSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get badgeSaved;

  /// No description provided for @badgeSyncsLater.
  ///
  /// In en, this message translates to:
  /// **'Syncs when online'**
  String get badgeSyncsLater;

  /// No description provided for @sleepWakeAfterStart.
  ///
  /// In en, this message translates to:
  /// **'Wake-up time must be after bedtime.'**
  String get sleepWakeAfterStart;

  /// No description provided for @sleepTooLong.
  ///
  /// In en, this message translates to:
  /// **'A sleep entry can be at most 16 hours.'**
  String get sleepTooLong;

  /// No description provided for @sleepInFuture.
  ///
  /// In en, this message translates to:
  /// **'Wake-up time can\'t be in the future.'**
  String get sleepInFuture;

  /// No description provided for @sleepWakingsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Night wakings must be during your sleep and in order.'**
  String get sleepWakingsInvalid;

  /// No description provided for @sleepOverlap.
  ///
  /// In en, this message translates to:
  /// **'This sleep overlaps another entry.'**
  String get sleepOverlap;

  /// No description provided for @sleepInfoHowTitle.
  ///
  /// In en, this message translates to:
  /// **'How we count your sleep'**
  String get sleepInfoHowTitle;

  /// No description provided for @sleepInfoHowBody.
  ///
  /// In en, this message translates to:
  /// **'Counted sleep = wake-up time minus bedtime, without the time it usually takes to fall asleep (15 minutes) and the last 15 minutes before waking. Each night waking removes the time you were awake plus 10 minutes to fall back asleep. Naps on the same day add up.'**
  String get sleepInfoHowBody;

  /// No description provided for @sleepInfoGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'Your goal and score'**
  String get sleepInfoGoalTitle;

  /// No description provided for @sleepInfoGoalBody.
  ///
  /// In en, this message translates to:
  /// **'Your goal starts from your age (8 hours for adults, 7.5 hours from 65) and you can change it. The score is your counted sleep as a share of your goal, up to 100 %: 90 % and above is Good, 70-89 % Fair, below 70 % Low.'**
  String get sleepInfoGoalBody;

  /// No description provided for @sleepInfoNoteBody.
  ///
  /// In en, this message translates to:
  /// **'Sleep scores are estimates from the times you enter. This isn\'t medical advice. If you have trouble sleeping often, talk to a doctor.'**
  String get sleepInfoNoteBody;

  /// No description provided for @subscriptionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This isn\'t available right now. Please try again.'**
  String get subscriptionUnavailable;

  /// No description provided for @upgradeToStar.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to STAR'**
  String get upgradeToStar;

  /// No description provided for @planStandard.
  ///
  /// In en, this message translates to:
  /// **'STANDARD'**
  String get planStandard;

  /// No description provided for @planStar.
  ///
  /// In en, this message translates to:
  /// **'STAR'**
  String get planStar;

  /// No description provided for @perMonthSuffix.
  ///
  /// In en, this message translates to:
  /// **'/ month'**
  String get perMonthSuffix;

  /// No description provided for @perYearSuffix.
  ///
  /// In en, this message translates to:
  /// **'/ year'**
  String get perYearSuffix;

  /// No description provided for @saveBadge.
  ///
  /// In en, this message translates to:
  /// **'SAVE {percent}%'**
  String saveBadge(String percent);

  /// No description provided for @activeBadge.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeBadge;

  /// No description provided for @recommendedBadge.
  ///
  /// In en, this message translates to:
  /// **'RECOMMENDED'**
  String get recommendedBadge;

  /// No description provided for @yourCurrentPlan.
  ///
  /// In en, this message translates to:
  /// **'Your Current Plan'**
  String get yourCurrentPlan;

  /// No description provided for @featHydrationNutrition.
  ///
  /// In en, this message translates to:
  /// **'Hydration & Nutrition tracking'**
  String get featHydrationNutrition;

  /// No description provided for @featCareCircle.
  ///
  /// In en, this message translates to:
  /// **'Care Circle'**
  String get featCareCircle;

  /// No description provided for @featBasicReports.
  ///
  /// In en, this message translates to:
  /// **'Basic health reports'**
  String get featBasicReports;

  /// No description provided for @featMeals4.
  ///
  /// In en, this message translates to:
  /// **'4 meal logs/day'**
  String get featMeals4;

  /// No description provided for @featReferral30.
  ///
  /// In en, this message translates to:
  /// **'30 day free STAR plan with referral program'**
  String get featReferral30;

  /// No description provided for @featTicketSupport.
  ///
  /// In en, this message translates to:
  /// **'Ticket Support'**
  String get featTicketSupport;

  /// No description provided for @featRin.
  ///
  /// In en, this message translates to:
  /// **'Rin AI'**
  String get featRin;

  /// No description provided for @featInsights.
  ///
  /// In en, this message translates to:
  /// **'Advanced insights & trends'**
  String get featInsights;

  /// No description provided for @featEverythingStandard.
  ///
  /// In en, this message translates to:
  /// **'Everything in Standard'**
  String get featEverythingStandard;

  /// No description provided for @featCustomReports.
  ///
  /// In en, this message translates to:
  /// **'Custom health reports'**
  String get featCustomReports;

  /// No description provided for @featMeals8.
  ///
  /// In en, this message translates to:
  /// **'8 meal logs/day'**
  String get featMeals8;

  /// No description provided for @featSleepAvatar.
  ///
  /// In en, this message translates to:
  /// **'Sleep Avatar unlocked'**
  String get featSleepAvatar;

  /// No description provided for @featBarcodeVoice.
  ///
  /// In en, this message translates to:
  /// **'Bar-code & Voice input available'**
  String get featBarcodeVoice;

  /// No description provided for @featPrioritySupport.
  ///
  /// In en, this message translates to:
  /// **'Priority support'**
  String get featPrioritySupport;

  /// No description provided for @featReferral50.
  ///
  /// In en, this message translates to:
  /// **'50 day free STAR plan with referral program'**
  String get featReferral50;

  /// No description provided for @starPlan.
  ///
  /// In en, this message translates to:
  /// **'STAR Plan'**
  String get starPlan;

  /// No description provided for @billingCycle.
  ///
  /// In en, this message translates to:
  /// **'Billing Cycle'**
  String get billingCycle;

  /// No description provided for @pricePerMonthShort.
  ///
  /// In en, this message translates to:
  /// **'{price}/ mo'**
  String pricePerMonthShort(String price);

  /// No description provided for @pricePerYearShort.
  ///
  /// In en, this message translates to:
  /// **'{price} / year'**
  String pricePerYearShort(String price);

  /// No description provided for @startsToday.
  ///
  /// In en, this message translates to:
  /// **'Starts today'**
  String get startsToday;

  /// No description provided for @renewsOnLabel.
  ///
  /// In en, this message translates to:
  /// **'Renews on'**
  String get renewsOnLabel;

  /// No description provided for @paymentVia.
  ///
  /// In en, this message translates to:
  /// **'Payment via'**
  String get paymentVia;

  /// No description provided for @paymentViaStores.
  ///
  /// In en, this message translates to:
  /// **'App Store / Google Play'**
  String get paymentViaStores;

  /// No description provided for @chargedThroughStore.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be charged through your Apple App Store/ Google Play account. You can manage or cancel anytime.'**
  String get chargedThroughStore;

  /// No description provided for @confirmSubscribe.
  ///
  /// In en, this message translates to:
  /// **'Confirm & Subscribe'**
  String get confirmSubscribe;

  /// No description provided for @storePriceLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading the store price…'**
  String get storePriceLoading;

  /// No description provided for @currentPlanCaps.
  ///
  /// In en, this message translates to:
  /// **'CURRENT PLAN'**
  String get currentPlanCaps;

  /// No description provided for @currentPlan.
  ///
  /// In en, this message translates to:
  /// **'Current plan'**
  String get currentPlan;

  /// No description provided for @annualPrice.
  ///
  /// In en, this message translates to:
  /// **'Annual Price'**
  String get annualPrice;

  /// No description provided for @monthlyPrice.
  ///
  /// In en, this message translates to:
  /// **'Monthly Price'**
  String get monthlyPrice;

  /// No description provided for @nextBillingDate.
  ///
  /// In en, this message translates to:
  /// **'Next billing date'**
  String get nextBillingDate;

  /// No description provided for @accessUntilLabel.
  ///
  /// In en, this message translates to:
  /// **'Access until'**
  String get accessUntilLabel;

  /// No description provided for @autoRenewal.
  ///
  /// In en, this message translates to:
  /// **'Auto-renewal'**
  String get autoRenewal;

  /// No description provided for @autoRenewalOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get autoRenewalOn;

  /// No description provided for @autoRenewalOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get autoRenewalOff;

  /// No description provided for @receiptSent.
  ///
  /// In en, this message translates to:
  /// **'A receipt has been sent to your registered email address.'**
  String get receiptSent;

  /// No description provided for @goToSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Go to My Subscriptions'**
  String get goToSubscriptions;

  /// No description provided for @planIncludes.
  ///
  /// In en, this message translates to:
  /// **'Your Plan Includes:'**
  String get planIncludes;

  /// No description provided for @subscriptionActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get subscriptionActions;

  /// No description provided for @updatePaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Update Payment Method'**
  String get updatePaymentMethod;

  /// No description provided for @planNameYearly.
  ///
  /// In en, this message translates to:
  /// **'STAR Plan (Yearly)'**
  String get planNameYearly;

  /// No description provided for @planNameMonthly.
  ///
  /// In en, this message translates to:
  /// **'STAR Plan (Monthly)'**
  String get planNameMonthly;

  /// No description provided for @paidBadge.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paidBadge;

  /// No description provided for @refundedBadge.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get refundedBadge;

  /// No description provided for @receiptsByEmail.
  ///
  /// In en, this message translates to:
  /// **'Receipts are sent to your registered email.'**
  String get receiptsByEmail;

  /// No description provided for @ifYouCancel.
  ///
  /// In en, this message translates to:
  /// **'If you cancel:'**
  String get ifYouCancel;

  /// No description provided for @cancelAccessTill.
  ///
  /// In en, this message translates to:
  /// **'You will have access till {date}.'**
  String cancelAccessTill(String date);

  /// No description provided for @cancelAccessTillPeriodEnd.
  ///
  /// In en, this message translates to:
  /// **'You will have access till the end of the paid period.'**
  String get cancelAccessTillPeriodEnd;

  /// No description provided for @cancelAutoRenewOff.
  ///
  /// In en, this message translates to:
  /// **'Auto renewal will be turned off.'**
  String get cancelAutoRenewOff;

  /// No description provided for @cancelNoCharge.
  ///
  /// In en, this message translates to:
  /// **'You won\'t be charged again.'**
  String get cancelNoCharge;

  /// No description provided for @cancelUpgradeBack.
  ///
  /// In en, this message translates to:
  /// **'You can upgrade back to STAR anytime if you change your mind.'**
  String get cancelUpgradeBack;

  /// No description provided for @cancelInStore.
  ///
  /// In en, this message translates to:
  /// **'You\'ll finish cancelling in your App Store / Google Play account.'**
  String get cancelInStore;

  /// No description provided for @stayOnStar.
  ///
  /// In en, this message translates to:
  /// **'Stay on STAR'**
  String get stayOnStar;

  /// No description provided for @subscriptionCancelled.
  ///
  /// In en, this message translates to:
  /// **'Subscription Cancelled'**
  String get subscriptionCancelled;

  /// No description provided for @subscriptionCancelledBody.
  ///
  /// In en, this message translates to:
  /// **'Your STAR plan subscription has been cancelled.'**
  String get subscriptionCancelledBody;

  /// No description provided for @cancelledAccessTill.
  ///
  /// In en, this message translates to:
  /// **'You have access to STAR plan features till {date}. After that you will be moved to STANDARD plan.'**
  String cancelledAccessTill(String date);

  /// No description provided for @planMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get planMonthly;

  /// No description provided for @planYearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get planYearly;

  /// No description provided for @upgradeButton.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get upgradeButton;

  /// No description provided for @restorePurchases.
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get restorePurchases;

  /// No description provided for @purchasePending.
  ///
  /// In en, this message translates to:
  /// **'Your payment is pending. STAR unlocks as soon as the store confirms it.'**
  String get purchasePending;

  /// No description provided for @storeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The store isn\'t available on this device right now.'**
  String get storeUnavailable;

  /// No description provided for @purchaseFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm this purchase. You haven\'t lost anything; try Restore purchases.'**
  String get purchaseFailed;

  /// No description provided for @paymentIssue.
  ///
  /// In en, this message translates to:
  /// **'There\'s a problem with your payment. Please update it in the store to keep STAR.'**
  String get paymentIssue;

  /// No description provided for @billingHistory.
  ///
  /// In en, this message translates to:
  /// **'Billing History'**
  String get billingHistory;

  /// No description provided for @noBillingHistory.
  ///
  /// In en, this message translates to:
  /// **'No payments yet.'**
  String get noBillingHistory;

  /// No description provided for @cancelSubscription.
  ///
  /// In en, this message translates to:
  /// **'Cancel Subscription'**
  String get cancelSubscription;

  /// No description provided for @starFromReward.
  ///
  /// In en, this message translates to:
  /// **'You have STAR from a reward or promotion. Enjoy!'**
  String get starFromReward;

  /// No description provided for @nowOnStar.
  ///
  /// In en, this message translates to:
  /// **'You\'re now on STAR plan.'**
  String get nowOnStar;

  /// No description provided for @nowOnStarBody.
  ///
  /// In en, this message translates to:
  /// **'Your health journey just got a major upgrade.'**
  String get nowOnStarBody;

  /// No description provided for @referTitle.
  ///
  /// In en, this message translates to:
  /// **'Refer 5 friends, get STAR free'**
  String get referTitle;

  /// No description provided for @referBody.
  ///
  /// In en, this message translates to:
  /// **'Share your link. When 5 friends each use NaraaCare on 30 days within their first 60, you get 30 days of STAR (50 days if you\'re already on STAR).'**
  String get referBody;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get linkCopied;

  /// No description provided for @referProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} friends qualified'**
  String referProgress(int done, int total);

  /// No description provided for @referRewardGranted.
  ///
  /// In en, this message translates to:
  /// **'Reward unlocked: {days} days of STAR'**
  String referRewardGranted(int days);

  /// No description provided for @friendQualified.
  ///
  /// In en, this message translates to:
  /// **'Qualified'**
  String get friendQualified;

  /// No description provided for @friendNotQualified.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t qualify in time'**
  String get friendNotQualified;

  /// No description provided for @friendActiveDays.
  ///
  /// In en, this message translates to:
  /// **'{days} of 30 active days'**
  String friendActiveDays(int days);

  /// No description provided for @referRules.
  ///
  /// In en, this message translates to:
  /// **'Friends must be new to NaraaCare and sign up within 7 days of opening your link. One reward per person.'**
  String get referRules;

  /// No description provided for @invitedTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ve been invited to NaraaCare'**
  String get invitedTitle;

  /// No description provided for @invitedBody.
  ///
  /// In en, this message translates to:
  /// **'Create your account to get started. Your friend gets closer to a STAR reward when you use NaraaCare.'**
  String get invitedBody;

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// No description provided for @addWaterDrinkButton.
  ///
  /// In en, this message translates to:
  /// **'Add Water/Drink'**
  String get addWaterDrinkButton;

  /// No description provided for @addMealLongButton.
  ///
  /// In en, this message translates to:
  /// **'Add Meal'**
  String get addMealLongButton;

  /// No description provided for @logSleepButton.
  ///
  /// In en, this message translates to:
  /// **'Log Sleep'**
  String get logSleepButton;

  /// No description provided for @pageOf.
  ///
  /// In en, this message translates to:
  /// **'Page {page} of {count}'**
  String pageOf(int page, int count);

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @addMembers.
  ///
  /// In en, this message translates to:
  /// **'Add Members'**
  String get addMembers;

  /// No description provided for @adminRequired.
  ///
  /// In en, this message translates to:
  /// **'Only a circle admin can do this.'**
  String get adminRequired;

  /// No description provided for @admins.
  ///
  /// In en, this message translates to:
  /// **'ADMINS'**
  String get admins;

  /// No description provided for @allMembers.
  ///
  /// In en, this message translates to:
  /// **'All Members'**
  String get allMembers;

  /// No description provided for @backToCircles.
  ///
  /// In en, this message translates to:
  /// **'Back to Your Circles'**
  String get backToCircles;

  /// No description provided for @cancelInvite.
  ///
  /// In en, this message translates to:
  /// **'Cancel invite'**
  String get cancelInvite;

  /// No description provided for @changeSharesLater.
  ///
  /// In en, this message translates to:
  /// **'You can change these anytime from the circle Settings.'**
  String get changeSharesLater;

  /// No description provided for @chatSection.
  ///
  /// In en, this message translates to:
  /// **'CHAT'**
  String get chatSection;

  /// No description provided for @chooseShares.
  ///
  /// In en, this message translates to:
  /// **'Choose at least 1 avatar to share with all members of this circle.'**
  String get chooseShares;

  /// No description provided for @circleActivity.
  ///
  /// In en, this message translates to:
  /// **'CIRCLE ACTIVITY'**
  String get circleActivity;

  /// No description provided for @circleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Circle Admin'**
  String get circleAdmin;

  /// No description provided for @circleChat.
  ///
  /// In en, this message translates to:
  /// **'Circle Chat'**
  String get circleChat;

  /// No description provided for @circleFull.
  ///
  /// In en, this message translates to:
  /// **'This circle is full (50 members).'**
  String get circleFull;

  /// No description provided for @circleName.
  ///
  /// In en, this message translates to:
  /// **'Circle name'**
  String get circleName;

  /// No description provided for @circleNameHelper.
  ///
  /// In en, this message translates to:
  /// **'You can change this later'**
  String get circleNameHelper;

  /// No description provided for @circleNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Gym Buddies'**
  String get circleNameHint;

  /// No description provided for @circleNotFound.
  ///
  /// In en, this message translates to:
  /// **'This circle is not available.'**
  String get circleNotFound;

  /// No description provided for @circlesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not load. Pull to try again.'**
  String get circlesUnavailable;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @connectedOnNaraaCare.
  ///
  /// In en, this message translates to:
  /// **'CONNECTED ON NARAACARE'**
  String get connectedOnNaraaCare;

  /// No description provided for @connections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get connections;

  /// No description provided for @copyInviteLink.
  ///
  /// In en, this message translates to:
  /// **'Copy invite link'**
  String get copyInviteLink;

  /// No description provided for @createCircle.
  ///
  /// In en, this message translates to:
  /// **'Create a circle'**
  String get createCircle;

  /// No description provided for @createCircleButton.
  ///
  /// In en, this message translates to:
  /// **'Create Circle'**
  String get createCircleButton;

  /// No description provided for @createCircleTip.
  ///
  /// In en, this message translates to:
  /// **'Invite friends and family to share avatars and support each other'**
  String get createCircleTip;

  /// No description provided for @createCircleTitle.
  ///
  /// In en, this message translates to:
  /// **'Create a Care Circle'**
  String get createCircleTitle;

  /// No description provided for @createCircleTitleShort.
  ///
  /// In en, this message translates to:
  /// **'Create a Circle'**
  String get createCircleTitleShort;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @deleteMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this message?'**
  String get deleteMessageTitle;

  /// No description provided for @findPeople.
  ///
  /// In en, this message translates to:
  /// **'Find People'**
  String get findPeople;

  /// No description provided for @healthUpdates.
  ///
  /// In en, this message translates to:
  /// **'HEALTH UPDATES'**
  String get healthUpdates;

  /// No description provided for @invite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get invite;

  /// No description provided for @inviteLink.
  ///
  /// In en, this message translates to:
  /// **'Invite Link'**
  String get inviteLink;

  /// No description provided for @inviteLinkAfterCreate.
  ///
  /// In en, this message translates to:
  /// **'Create the circle first, then share an invite link from its Settings.'**
  String get inviteLinkAfterCreate;

  /// No description provided for @inviteLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Invite link copied. It works for 7 days.'**
  String get inviteLinkCopied;

  /// No description provided for @inviteLinkExpired.
  ///
  /// In en, this message translates to:
  /// **'This invite link has expired.'**
  String get inviteLinkExpired;

  /// No description provided for @inviteLinkLimit.
  ///
  /// In en, this message translates to:
  /// **'Too many invite links today. Try again tomorrow.'**
  String get inviteLinkLimit;

  /// No description provided for @inviteNotFound.
  ///
  /// In en, this message translates to:
  /// **'This invite is no longer open.'**
  String get inviteNotFound;

  /// No description provided for @invitePeopleBody.
  ///
  /// In en, this message translates to:
  /// **'Share this invite link with someone who isn\'t on NaraaCare yet so they can join your circle.'**
  String get invitePeopleBody;

  /// No description provided for @invitePeopleTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite people on NaraaCare'**
  String get invitePeopleTitle;

  /// No description provided for @invited.
  ///
  /// In en, this message translates to:
  /// **'Invited'**
  String get invited;

  /// No description provided for @invitedToJoin.
  ///
  /// In en, this message translates to:
  /// **'You are invited to join'**
  String get invitedToJoin;

  /// No description provided for @invitesHeader.
  ///
  /// In en, this message translates to:
  /// **'INVITES'**
  String get invitesHeader;

  /// No description provided for @invitesSent.
  ///
  /// In en, this message translates to:
  /// **'Invites sent'**
  String get invitesSent;

  /// No description provided for @joinCircle.
  ///
  /// In en, this message translates to:
  /// **'Join Circle'**
  String get joinCircle;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @lastAdmin.
  ///
  /// In en, this message translates to:
  /// **'A circle needs at least one admin.'**
  String get lastAdmin;

  /// No description provided for @leave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leave;

  /// No description provided for @leaveCircleBody.
  ///
  /// In en, this message translates to:
  /// **'You will no longer be able to see this circle\'s chat or shared health updates.'**
  String get leaveCircleBody;

  /// No description provided for @leaveCircleTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave this circle?'**
  String get leaveCircleTitle;

  /// No description provided for @makeAdmin.
  ///
  /// In en, this message translates to:
  /// **'Make admin'**
  String get makeAdmin;

  /// No description provided for @manageMembers.
  ///
  /// In en, this message translates to:
  /// **'Manage Members'**
  String get manageMembers;

  /// No description provided for @maybeLater.
  ///
  /// In en, this message translates to:
  /// **'Maybe Later'**
  String get maybeLater;

  /// No description provided for @mealLogged.
  ///
  /// In en, this message translates to:
  /// **'Meal logged'**
  String get mealLogged;

  /// No description provided for @membersTitle.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get membersTitle;

  /// No description provided for @mentionInvalid.
  ///
  /// In en, this message translates to:
  /// **'You can only mention members of this circle.'**
  String get mentionInvalid;

  /// No description provided for @messageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Message deleted'**
  String get messageDeleted;

  /// No description provided for @messageNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This message contains characters that are not allowed.'**
  String get messageNotAllowed;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @myConnections.
  ///
  /// In en, this message translates to:
  /// **'My Connections'**
  String get myConnections;

  /// No description provided for @namePicture.
  ///
  /// In en, this message translates to:
  /// **'Name & Picture'**
  String get namePicture;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @noConnectionsYet.
  ///
  /// In en, this message translates to:
  /// **'No connections yet.'**
  String get noConnectionsYet;

  /// No description provided for @noMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet. Say hello!'**
  String get noMessagesYet;

  /// No description provided for @noNewUpdates.
  ///
  /// In en, this message translates to:
  /// **'No new updates'**
  String get noNewUpdates;

  /// No description provided for @noNotificationsYet.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet.'**
  String get noNotificationsYet;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No one found.'**
  String get noResults;

  /// No description provided for @noUpdatesYet.
  ///
  /// In en, this message translates to:
  /// **'No updates yet today.'**
  String get noUpdatesYet;

  /// No description provided for @notifAdmin.
  ///
  /// In en, this message translates to:
  /// **'You are now an admin of this circle.'**
  String get notifAdmin;

  /// No description provided for @notifConnectionAccepted.
  ///
  /// In en, this message translates to:
  /// **'Your connection request was accepted.'**
  String get notifConnectionAccepted;

  /// No description provided for @notifConnectionRequest.
  ///
  /// In en, this message translates to:
  /// **'You have a new connection request.'**
  String get notifConnectionRequest;

  /// No description provided for @notifDeleted.
  ///
  /// In en, this message translates to:
  /// **'A circle you were in was deleted.'**
  String get notifDeleted;

  /// No description provided for @notifGeneric.
  ///
  /// In en, this message translates to:
  /// **'Circle update'**
  String get notifGeneric;

  /// No description provided for @notifInvite.
  ///
  /// In en, this message translates to:
  /// **'You were invited to a circle.'**
  String get notifInvite;

  /// No description provided for @notifMessage.
  ///
  /// In en, this message translates to:
  /// **'New message in the chat.'**
  String get notifMessage;

  /// No description provided for @notifRemoved.
  ///
  /// In en, this message translates to:
  /// **'You were removed from this circle.'**
  String get notifRemoved;

  /// No description provided for @notificationSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification Settings'**
  String get notificationSettingsTitle;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @peopleOnNaraaCare.
  ///
  /// In en, this message translates to:
  /// **'People on NaraaCare'**
  String get peopleOnNaraaCare;

  /// No description provided for @prefAvatarUpdates.
  ///
  /// In en, this message translates to:
  /// **'Avatar updates'**
  String get prefAvatarUpdates;

  /// No description provided for @prefAvatarUpdatesBody.
  ///
  /// In en, this message translates to:
  /// **'Know when shared information is updated.'**
  String get prefAvatarUpdatesBody;

  /// No description provided for @prefCircleUpdates.
  ///
  /// In en, this message translates to:
  /// **'Circle updates'**
  String get prefCircleUpdates;

  /// No description provided for @prefCircleUpdatesBody.
  ///
  /// In en, this message translates to:
  /// **'Stay informed about important circle changes.'**
  String get prefCircleUpdatesBody;

  /// No description provided for @prefGoals.
  ///
  /// In en, this message translates to:
  /// **'Goal completions'**
  String get prefGoals;

  /// No description provided for @prefGoalsBody.
  ///
  /// In en, this message translates to:
  /// **'Celebrate members reaching their health goals.'**
  String get prefGoalsBody;

  /// No description provided for @prefJoinLeave.
  ///
  /// In en, this message translates to:
  /// **'Member joins or leaves'**
  String get prefJoinLeave;

  /// No description provided for @prefJoinLeaveBody.
  ///
  /// In en, this message translates to:
  /// **'Get notified when members join or leave this circle.'**
  String get prefJoinLeaveBody;

  /// No description provided for @prefMentions.
  ///
  /// In en, this message translates to:
  /// **'Mentions'**
  String get prefMentions;

  /// No description provided for @prefMentionsBody.
  ///
  /// In en, this message translates to:
  /// **'Get notified if someone mentions you in chat.'**
  String get prefMentionsBody;

  /// No description provided for @prefNewMessages.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get prefNewMessages;

  /// No description provided for @prefNewMessagesBody.
  ///
  /// In en, this message translates to:
  /// **'Stay up to date with new messages in chats.'**
  String get prefNewMessagesBody;

  /// No description provided for @queryTooShort.
  ///
  /// In en, this message translates to:
  /// **'Type at least 3 characters.'**
  String get queryTooShort;

  /// No description provided for @removeAdmin.
  ///
  /// In en, this message translates to:
  /// **'Remove admin'**
  String get removeAdmin;

  /// No description provided for @removeFromCircle.
  ///
  /// In en, this message translates to:
  /// **'Remove from circle'**
  String get removeFromCircle;

  /// No description provided for @requestSent.
  ///
  /// In en, this message translates to:
  /// **'Request sent'**
  String get requestSent;

  /// No description provided for @requested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get requested;

  /// No description provided for @results.
  ///
  /// In en, this message translates to:
  /// **'RESULTS'**
  String get results;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @searchByUsername.
  ///
  /// In en, this message translates to:
  /// **'Search by username'**
  String get searchByUsername;

  /// No description provided for @selectWallpaper.
  ///
  /// In en, this message translates to:
  /// **'SELECT WALLPAPER'**
  String get selectWallpaper;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @sharesInvalid.
  ///
  /// In en, this message translates to:
  /// **'Share 1 to 3 avatars.'**
  String get sharesInvalid;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @sleepStarOnly.
  ///
  /// In en, this message translates to:
  /// **'Sleep avatar is available with STAR plan'**
  String get sleepStarOnly;

  /// No description provided for @someone.
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get someone;

  /// No description provided for @suggestedForYou.
  ///
  /// In en, this message translates to:
  /// **'SUGGESTED FOR YOU'**
  String get suggestedForYou;

  /// No description provided for @tooManyMentions.
  ///
  /// In en, this message translates to:
  /// **'A message can mention at most 20 people.'**
  String get tooManyMentions;

  /// No description provided for @typeHere.
  ///
  /// In en, this message translates to:
  /// **'Type here..'**
  String get typeHere;

  /// No description provided for @upgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get upgrade;

  /// No description provided for @usernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please choose a username first.'**
  String get usernameRequired;

  /// No description provided for @viewMembers.
  ///
  /// In en, this message translates to:
  /// **'View Members'**
  String get viewMembers;

  /// No description provided for @whyStar.
  ///
  /// In en, this message translates to:
  /// **'Why STAR?'**
  String get whyStar;

  /// No description provided for @whyStarBody.
  ///
  /// In en, this message translates to:
  /// **'STAR members can share and view sleep insights with their care circles.'**
  String get whyStarBody;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @yourCircles.
  ///
  /// In en, this message translates to:
  /// **'Your Circles'**
  String get yourCircles;

  /// No description provided for @yourSharedAvatars.
  ///
  /// In en, this message translates to:
  /// **'Your Shared Avatars'**
  String get yourSharedAvatars;

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String daysAgo(int count);

  /// No description provided for @feedGoalCompleted.
  ///
  /// In en, this message translates to:
  /// **'{who} completed their {avatar} goal.'**
  String feedGoalCompleted(String who, String avatar);

  /// No description provided for @feedJoined.
  ///
  /// In en, this message translates to:
  /// **'{who} joined the circle.'**
  String feedJoined(String who);

  /// No description provided for @feedLeft.
  ///
  /// In en, this message translates to:
  /// **'{who} left the circle.'**
  String feedLeft(String who);

  /// No description provided for @feedUpdated.
  ///
  /// In en, this message translates to:
  /// **'{who} updated {avatar}.'**
  String feedUpdated(String who, String avatar);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String hoursAgo(int count);

  /// No description provided for @inviteCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Invite} other{Invite ({count})}}'**
  String inviteCount(int count);

  /// No description provided for @invitedBy.
  ///
  /// In en, this message translates to:
  /// **'Invited by {name}'**
  String invitedBy(String name);

  /// No description provided for @invitedCount.
  ///
  /// In en, this message translates to:
  /// **'INVITED ({count})'**
  String invitedCount(int count);

  /// No description provided for @isTyping.
  ///
  /// In en, this message translates to:
  /// **'{who} is typing…'**
  String isTyping(String who);

  /// No description provided for @joinedDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{Joined today} =1{Joined since 1 day} other{Joined since {days} days}}'**
  String joinedDaysAgo(int days);

  /// No description provided for @leaveCircle.
  ///
  /// In en, this message translates to:
  /// **'Leave {name}'**
  String leaveCircle(String name);

  /// No description provided for @leftCircle.
  ///
  /// In en, this message translates to:
  /// **'You left {name}'**
  String leftCircle(String name);

  /// No description provided for @litresValue.
  ///
  /// In en, this message translates to:
  /// **'{litres} L'**
  String litresValue(double litres);

  /// No description provided for @membersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member} other{{count} members}}'**
  String membersCount(int count);

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String minutesAgo(int count);

  /// No description provided for @nextWithCount.
  ///
  /// In en, this message translates to:
  /// **'Next ({count})'**
  String nextWithCount(int count);

  /// No description provided for @notSharedAvatar.
  ///
  /// In en, this message translates to:
  /// **'{avatar} is not shared'**
  String notSharedAvatar(String avatar);

  /// No description provided for @notifGoal.
  ///
  /// In en, this message translates to:
  /// **'{who} completed their hydration goal.'**
  String notifGoal(String who);

  /// No description provided for @notifJoined.
  ///
  /// In en, this message translates to:
  /// **'{who} joined the circle.'**
  String notifJoined(String who);

  /// No description provided for @notifLeft.
  ///
  /// In en, this message translates to:
  /// **'{who} left the circle.'**
  String notifLeft(String who);

  /// No description provided for @notifMention.
  ///
  /// In en, this message translates to:
  /// **'{who} mentioned you in the chat.'**
  String notifMention(String who);

  /// No description provided for @ofGoalLitres.
  ///
  /// In en, this message translates to:
  /// **'of {litres} L goal'**
  String ofGoalLitres(double litres);

  /// No description provided for @shareWith.
  ///
  /// In en, this message translates to:
  /// **'Share with {name}'**
  String shareWith(String name);

  /// No description provided for @updatesToday.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 update today} other{{count} updates today}}'**
  String updatesToday(int count);

  /// No description provided for @aboutRin.
  ///
  /// In en, this message translates to:
  /// **'About Rin AI'**
  String get aboutRin;

  /// No description provided for @aboutRinBody.
  ///
  /// In en, this message translates to:
  /// **'Rin is your AI health companion. It understands your health data and helps you make better choices every day.'**
  String get aboutRinBody;

  /// No description provided for @allow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allow;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @less.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get less;

  /// No description provided for @rinActionExpired.
  ///
  /// In en, this message translates to:
  /// **'This suggestion has expired.'**
  String get rinActionExpired;

  /// No description provided for @rinActionResolved.
  ///
  /// In en, this message translates to:
  /// **'This suggestion was already handled.'**
  String get rinActionResolved;

  /// No description provided for @rinAddQuestion.
  ///
  /// In en, this message translates to:
  /// **'Should I add this to your avatar?'**
  String get rinAddQuestion;

  /// No description provided for @rinAddToAvatar.
  ///
  /// In en, this message translates to:
  /// **'Add to Avatar'**
  String get rinAddToAvatar;

  /// No description provided for @rinAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to your avatar'**
  String get rinAdded;

  /// No description provided for @rinAi.
  ///
  /// In en, this message translates to:
  /// **'Rin AI'**
  String get rinAi;

  /// No description provided for @rinClearMemory.
  ///
  /// In en, this message translates to:
  /// **'Clear Rin\'s memory'**
  String get rinClearMemory;

  /// No description provided for @rinConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow Rin to use your health data?'**
  String get rinConsentTitle;

  /// No description provided for @rinConsentBody.
  ///
  /// In en, this message translates to:
  /// **'To answer, Rin sends your own profile summary, today\'s and last week\'s totals and your question to our AI provider (Anthropic, outside India). Nothing about other people is shared. You can turn this off anytime in Settings.'**
  String get rinConsentBody;

  /// No description provided for @rinConversations.
  ///
  /// In en, this message translates to:
  /// **'CONVERSATIONS'**
  String get rinConversations;

  /// No description provided for @rinDeleteChat.
  ///
  /// In en, this message translates to:
  /// **'Delete Chat'**
  String get rinDeleteChat;

  /// No description provided for @rinDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this chat?'**
  String get rinDeleteTitle;

  /// No description provided for @rinDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This will remove your entire conversation with Rin AI. It will not affect your avatar updates.'**
  String get rinDeleteBody;

  /// No description provided for @rinDeleted.
  ///
  /// In en, this message translates to:
  /// **'Your conversation with Rin AI has been deleted.'**
  String get rinDeleted;

  /// No description provided for @rinDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Rin AI is a support tool, not a substitute for professional medical advice.'**
  String get rinDisclaimer;

  /// No description provided for @rinEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit meal'**
  String get rinEditTitle;

  /// No description provided for @rinFeatureAvatar.
  ///
  /// In en, this message translates to:
  /// **'Reflect updates on your avatar.'**
  String get rinFeatureAvatar;

  /// No description provided for @rinFeatureChat.
  ///
  /// In en, this message translates to:
  /// **'Chat & get personalized insights'**
  String get rinFeatureChat;

  /// No description provided for @rinFeatureLog.
  ///
  /// In en, this message translates to:
  /// **'Log food, water & sleep by voice/text.'**
  String get rinFeatureLog;

  /// No description provided for @rinFeatureTips.
  ///
  /// In en, this message translates to:
  /// **'Smart recommendations just for you.'**
  String get rinFeatureTips;

  /// No description provided for @rinHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get rinHelp;

  /// No description provided for @rinHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'Rin AI help'**
  String get rinHelpTitle;

  /// No description provided for @rinHi.
  ///
  /// In en, this message translates to:
  /// **'Hi! 👋'**
  String get rinHi;

  /// No description provided for @rinIntro.
  ///
  /// In en, this message translates to:
  /// **'I\'m Rin, your AI health companion. Ask me anything about your health, or choose a suggestion to get started.'**
  String get rinIntro;

  /// No description provided for @rinLimitReached.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used this month\'s Rin allowance. It resets on the 1st of next month.'**
  String get rinLimitReached;

  /// No description provided for @rinMemoryCleared.
  ///
  /// In en, this message translates to:
  /// **'Rin\'s memory has been cleared.'**
  String get rinMemoryCleared;

  /// No description provided for @rinNotAdded.
  ///
  /// In en, this message translates to:
  /// **'Not added'**
  String get rinNotAdded;

  /// No description provided for @rinResting.
  ///
  /// In en, this message translates to:
  /// **'Rin is resting right now. Please try again soon.'**
  String get rinResting;

  /// No description provided for @rinSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search conversations'**
  String get rinSearchHint;

  /// No description provided for @rinSearchHistory.
  ///
  /// In en, this message translates to:
  /// **'Search History'**
  String get rinSearchHistory;

  /// No description provided for @rinSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search in Rin AI'**
  String get rinSearchTitle;

  /// No description provided for @rinSuggestDinner.
  ///
  /// In en, this message translates to:
  /// **'What should I eat for dinner?'**
  String get rinSuggestDinner;

  /// No description provided for @rinSuggestTired.
  ///
  /// In en, this message translates to:
  /// **'Why am I feeling tired?'**
  String get rinSuggestTired;

  /// No description provided for @rinSuggestToday.
  ///
  /// In en, this message translates to:
  /// **'How am I doing today?'**
  String get rinSuggestToday;

  /// No description provided for @rinSuggestWater.
  ///
  /// In en, this message translates to:
  /// **'How much water should I drink?'**
  String get rinSuggestWater;

  /// No description provided for @unlockRin.
  ///
  /// In en, this message translates to:
  /// **'Unlock Rin AI'**
  String get unlockRin;

  /// No description provided for @unlockRinBody.
  ///
  /// In en, this message translates to:
  /// **'Your personal AI health companion. Understand your health, take guidance and take action.'**
  String get unlockRinBody;

  /// No description provided for @rinDrinkCard.
  ///
  /// In en, this message translates to:
  /// **'Log {amount} of {drink}?'**
  String rinDrinkCard(String amount, String drink);

  /// No description provided for @rinHiName.
  ///
  /// In en, this message translates to:
  /// **'Hi {name}! 👋'**
  String rinHiName(String name);

  /// No description provided for @rinMealTotals.
  ///
  /// In en, this message translates to:
  /// **'Calories {kcal} kcal · Protein {protein} g · Carbs {carbs} g · Fat {fat} g'**
  String rinMealTotals(int kcal, int protein, int carbs, int fat);

  /// No description provided for @rinUsage.
  ///
  /// In en, this message translates to:
  /// **'{pct} % used this month'**
  String rinUsage(String pct);

  /// No description provided for @profileConnections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get profileConnections;

  /// No description provided for @profileCircles.
  ///
  /// In en, this message translates to:
  /// **'Care Circles'**
  String get profileCircles;

  /// No description provided for @profileAvatarLabel.
  ///
  /// In en, this message translates to:
  /// **'Your avatar'**
  String get profileAvatarLabel;

  /// No description provided for @activeStreak.
  ///
  /// In en, this message translates to:
  /// **'Active Streak'**
  String get activeStreak;

  /// No description provided for @longestStreak.
  ///
  /// In en, this message translates to:
  /// **'Longest Streak'**
  String get longestStreak;

  /// No description provided for @streakCalendar.
  ///
  /// In en, this message translates to:
  /// **'Streak calendar'**
  String get streakCalendar;

  /// No description provided for @streakRule.
  ///
  /// In en, this message translates to:
  /// **'Your streak increases when you log any data (hydration, nutrition, sleep) in a day.'**
  String get streakRule;

  /// No description provided for @streakBrokenTitle.
  ///
  /// In en, this message translates to:
  /// **'Oh no! Streak Broken.'**
  String get streakBrokenTitle;

  /// No description provided for @streakBrokenBody.
  ///
  /// In en, this message translates to:
  /// **'You didn\'t log any data yesterday. Don\'t worry, you can start again and keep your momentum going.'**
  String get streakBrokenBody;

  /// No description provided for @streakDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String streakDays(int count);

  /// No description provided for @activeDay.
  ///
  /// In en, this message translates to:
  /// **'Active day'**
  String get activeDay;

  /// No description provided for @noData.
  ///
  /// In en, this message translates to:
  /// **'No Data'**
  String get noData;

  /// No description provided for @previousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get previousMonth;

  /// No description provided for @nextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get nextMonth;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this. Check your connection and try again.'**
  String get loadFailed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @todayHeader.
  ///
  /// In en, this message translates to:
  /// **'TODAY'**
  String get todayHeader;

  /// No description provided for @earlierHeader.
  ///
  /// In en, this message translates to:
  /// **'EARLIER'**
  String get earlierHeader;

  /// No description provided for @notifStreak.
  ///
  /// In en, this message translates to:
  /// **'Your streak reached {days} days!'**
  String notifStreak(int days);

  /// No description provided for @notifReportReady.
  ///
  /// In en, this message translates to:
  /// **'Your report is ready to download.'**
  String get notifReportReady;

  /// No description provided for @notifReportFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t create your report. Please try again.'**
  String get notifReportFailed;

  /// No description provided for @downloadReport.
  ///
  /// In en, this message translates to:
  /// **'Download Report'**
  String get downloadReport;

  /// No description provided for @downloadReportHint.
  ///
  /// In en, this message translates to:
  /// **'View & analyse your activity summary.'**
  String get downloadReportHint;

  /// No description provided for @createNewReport.
  ///
  /// In en, this message translates to:
  /// **'Create new report'**
  String get createNewReport;

  /// No description provided for @monthlyReport.
  ///
  /// In en, this message translates to:
  /// **'Monthly Report'**
  String get monthlyReport;

  /// No description provided for @monthlyReportHint.
  ///
  /// In en, this message translates to:
  /// **'Get a summary of your data for any month.'**
  String get monthlyReportHint;

  /// No description provided for @customReport.
  ///
  /// In en, this message translates to:
  /// **'Custom Report'**
  String get customReport;

  /// No description provided for @customReportHint.
  ///
  /// In en, this message translates to:
  /// **'Get a summary & insights for any date range.'**
  String get customReportHint;

  /// No description provided for @whatsIncluded.
  ///
  /// In en, this message translates to:
  /// **'What\'s included'**
  String get whatsIncluded;

  /// No description provided for @hydrationLabel.
  ///
  /// In en, this message translates to:
  /// **'Hydration'**
  String get hydrationLabel;

  /// No description provided for @nutritionLabel.
  ///
  /// In en, this message translates to:
  /// **'Nutrition'**
  String get nutritionLabel;

  /// No description provided for @sleepLabel.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get sleepLabel;

  /// No description provided for @insightsLabel.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get insightsLabel;

  /// No description provided for @reportUpsell.
  ///
  /// In en, this message translates to:
  /// **'STAR members can choose a custom date range and get advanced health insights.'**
  String get reportUpsell;

  /// No description provided for @chooseMonth.
  ///
  /// In en, this message translates to:
  /// **'Choose a month'**
  String get chooseMonth;

  /// No description provided for @chooseYear.
  ///
  /// In en, this message translates to:
  /// **'Choose a year'**
  String get chooseYear;

  /// No description provided for @reportNoData.
  ///
  /// In en, this message translates to:
  /// **'Log water, food or sleep first. A report needs at least one day with data.'**
  String get reportNoData;

  /// No description provided for @createReport.
  ///
  /// In en, this message translates to:
  /// **'Create report'**
  String get createReport;

  /// No description provided for @yourReports.
  ///
  /// In en, this message translates to:
  /// **'Your reports (kept for 7 days)'**
  String get yourReports;

  /// No description provided for @reportReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get reportReady;

  /// No description provided for @reportFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get reportFailed;

  /// No description provided for @reportExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get reportExpired;

  /// No description provided for @reportPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get reportPreparing;

  /// No description provided for @customizeReport.
  ///
  /// In en, this message translates to:
  /// **'Customize Report'**
  String get customizeReport;

  /// No description provided for @selectDateRange.
  ///
  /// In en, this message translates to:
  /// **'Select Date Range'**
  String get selectDateRange;

  /// No description provided for @last7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get last7Days;

  /// No description provided for @last30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get last30Days;

  /// No description provided for @last3Months.
  ///
  /// In en, this message translates to:
  /// **'Last 3 months'**
  String get last3Months;

  /// No description provided for @last6Months.
  ///
  /// In en, this message translates to:
  /// **'Last 6 months'**
  String get last6Months;

  /// No description provided for @thisYear.
  ///
  /// In en, this message translates to:
  /// **'This Year'**
  String get thisYear;

  /// No description provided for @fromLabel.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get fromLabel;

  /// No description provided for @toLabel.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get toLabel;

  /// No description provided for @enterStartDate.
  ///
  /// In en, this message translates to:
  /// **'Enter start date'**
  String get enterStartDate;

  /// No description provided for @enterEndDate.
  ///
  /// In en, this message translates to:
  /// **'Enter end date'**
  String get enterEndDate;

  /// No description provided for @whatToInclude.
  ///
  /// In en, this message translates to:
  /// **'What do you want to include?'**
  String get whatToInclude;

  /// No description provided for @generateReport.
  ///
  /// In en, this message translates to:
  /// **'Generate Report'**
  String get generateReport;

  /// No description provided for @reportPreview.
  ///
  /// In en, this message translates to:
  /// **'Report Preview'**
  String get reportPreview;

  /// No description provided for @reportSummary.
  ///
  /// In en, this message translates to:
  /// **'Report Summary'**
  String get reportSummary;

  /// No description provided for @reportPeriod.
  ///
  /// In en, this message translates to:
  /// **'{from} - {to} ({days, plural, =1{1 day} other{{days} days}})'**
  String reportPeriod(String from, String to, int days);

  /// No description provided for @reportTitle.
  ///
  /// In en, this message translates to:
  /// **'{sections} Report'**
  String reportTitle(String sections);

  /// No description provided for @reportIncludes.
  ///
  /// In en, this message translates to:
  /// **'Report will include overall metrics, daily averages, trends and insights.'**
  String get reportIncludes;

  /// No description provided for @reportPreparingLong.
  ///
  /// In en, this message translates to:
  /// **'We\'re preparing your report. This usually takes a few seconds.'**
  String get reportPreparingLong;

  /// No description provided for @reportSlow.
  ///
  /// In en, this message translates to:
  /// **'This is taking longer than usual. You can leave this screen; we\'ll notify you when your report is ready.'**
  String get reportSlow;

  /// No description provided for @reportFailedLong.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t create this report. Please create it again.'**
  String get reportFailedLong;

  /// No description provided for @shareReport.
  ///
  /// In en, this message translates to:
  /// **'Share report'**
  String get shareReport;

  /// No description provided for @reportDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Report Downloaded'**
  String get reportDownloaded;

  /// No description provided for @reportSavedBody.
  ///
  /// In en, this message translates to:
  /// **'Your report is saved in the app. Use Share to save a copy to your phone\'s files.'**
  String get reportSavedBody;

  /// No description provided for @reportSavedDownloads.
  ///
  /// In en, this message translates to:
  /// **'Saved to Downloads › NaraaCare on your phone. You can open it from the Files app.'**
  String get reportSavedDownloads;

  /// No description provided for @reportSavedFiles.
  ///
  /// In en, this message translates to:
  /// **'Saved on your iPhone. Open the Files app › On My iPhone › NaraaCare › reports.'**
  String get reportSavedFiles;

  /// No description provided for @reportSize.
  ///
  /// In en, this message translates to:
  /// **'Size: {kb} KB'**
  String reportSize(String kb);

  /// No description provided for @reportSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the report on this device.'**
  String get reportSaveFailed;

  /// No description provided for @reportLimitReached.
  ///
  /// In en, this message translates to:
  /// **'You can create 10 reports a day. Try again tomorrow.'**
  String get reportLimitReached;

  /// No description provided for @reportRangeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Choose dates up to today, at most 366 days apart.'**
  String get reportRangeInvalid;

  /// No description provided for @reportNeedsStar.
  ///
  /// In en, this message translates to:
  /// **'This report option is part of STAR.'**
  String get reportNeedsStar;

  /// No description provided for @reportNeedsAiConsent.
  ///
  /// In en, this message translates to:
  /// **'Insights need your consent to AI processing. Your report was made without them.'**
  String get reportNeedsAiConsent;

  /// No description provided for @faqs.
  ///
  /// In en, this message translates to:
  /// **'FAQs'**
  String get faqs;

  /// No description provided for @faqsLong.
  ///
  /// In en, this message translates to:
  /// **'Frequently Asked Questions'**
  String get faqsLong;

  /// No description provided for @contactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get contactSupport;

  /// No description provided for @reportProblem.
  ///
  /// In en, this message translates to:
  /// **'Report a Problem'**
  String get reportProblem;

  /// No description provided for @requestFeature.
  ///
  /// In en, this message translates to:
  /// **'Request a Feature'**
  String get requestFeature;

  /// No description provided for @gettingStartedGuide.
  ///
  /// In en, this message translates to:
  /// **'Getting started guide'**
  String get gettingStartedGuide;

  /// No description provided for @guide.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get guide;

  /// No description provided for @searchQuestions.
  ///
  /// In en, this message translates to:
  /// **'Search questions'**
  String get searchQuestions;

  /// No description provided for @noFaqMatch.
  ///
  /// In en, this message translates to:
  /// **'No questions match your search.'**
  String get noFaqMatch;

  /// No description provided for @emailSupport.
  ///
  /// In en, this message translates to:
  /// **'Email Support'**
  String get emailSupport;

  /// No description provided for @emailSupportBody.
  ///
  /// In en, this message translates to:
  /// **'Detailed inquiries & feedback.'**
  String get emailSupportBody;

  /// No description provided for @sendAnEmail.
  ///
  /// In en, this message translates to:
  /// **'Send an email'**
  String get sendAnEmail;

  /// No description provided for @callUs.
  ///
  /// In en, this message translates to:
  /// **'Call Us'**
  String get callUs;

  /// No description provided for @callUsBody.
  ///
  /// In en, this message translates to:
  /// **'Direct support for urgent issues.'**
  String get callUsBody;

  /// No description provided for @callUsStarOnly.
  ///
  /// In en, this message translates to:
  /// **'Phone support is available with the STAR plan.'**
  String get callUsStarOnly;

  /// No description provided for @couldNotOpenApp.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open an app for this.'**
  String get couldNotOpenApp;

  /// No description provided for @issueCategory.
  ///
  /// In en, this message translates to:
  /// **'ISSUE CATEGORY'**
  String get issueCategory;

  /// No description provided for @catAppCrash.
  ///
  /// In en, this message translates to:
  /// **'App Crash'**
  String get catAppCrash;

  /// No description provided for @catDataSync.
  ///
  /// In en, this message translates to:
  /// **'Data Sync'**
  String get catDataSync;

  /// No description provided for @catBilling.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get catBilling;

  /// No description provided for @catDeviceLink.
  ///
  /// In en, this message translates to:
  /// **'Device Link'**
  String get catDeviceLink;

  /// No description provided for @catAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get catAccount;

  /// No description provided for @catOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get catOther;

  /// No description provided for @problemDescription.
  ///
  /// In en, this message translates to:
  /// **'PROBLEM DESCRIPTION'**
  String get problemDescription;

  /// No description provided for @tellUsWhatHappened.
  ///
  /// In en, this message translates to:
  /// **'Tell us what happened...'**
  String get tellUsWhatHappened;

  /// No description provided for @uploadScreenshotOptional.
  ///
  /// In en, this message translates to:
  /// **'UPLOAD SCREENSHOT (OPTIONAL)'**
  String get uploadScreenshotOptional;

  /// No description provided for @tapToUpload.
  ///
  /// In en, this message translates to:
  /// **'Tap to upload an image'**
  String get tapToUpload;

  /// No description provided for @uploadLimits.
  ///
  /// In en, this message translates to:
  /// **'PNG, JPG up to 10 MB'**
  String get uploadLimits;

  /// No description provided for @screenshotAttached.
  ///
  /// In en, this message translates to:
  /// **'Screenshot attached'**
  String get screenshotAttached;

  /// No description provided for @uploadInvalid.
  ///
  /// In en, this message translates to:
  /// **'Upload a PNG or JPG image up to 10 MB.'**
  String get uploadInvalid;

  /// No description provided for @submitReport.
  ///
  /// In en, this message translates to:
  /// **'Submit Report'**
  String get submitReport;

  /// No description provided for @responseTime.
  ///
  /// In en, this message translates to:
  /// **'Estimated response time: < 24 hours'**
  String get responseTime;

  /// No description provided for @ticketSent.
  ///
  /// In en, this message translates to:
  /// **'Thanks! Your report {ref} was sent.'**
  String ticketSent(String ref);

  /// No description provided for @supportLimitReached.
  ///
  /// In en, this message translates to:
  /// **'You\'ve sent 5 requests today. Try again tomorrow.'**
  String get supportLimitReached;

  /// No description provided for @whatShouldWeAdd.
  ///
  /// In en, this message translates to:
  /// **'What should we add?'**
  String get whatShouldWeAdd;

  /// No description provided for @featureTitleHint.
  ///
  /// In en, this message translates to:
  /// **'eg: new sleep tracking method'**
  String get featureTitleHint;

  /// No description provided for @howWouldThisHelp.
  ///
  /// In en, this message translates to:
  /// **'How would this help you?'**
  String get howWouldThisHelp;

  /// No description provided for @sendRequest.
  ///
  /// In en, this message translates to:
  /// **'Send Request'**
  String get sendRequest;

  /// No description provided for @featureRequestNote.
  ///
  /// In en, this message translates to:
  /// **'Our product team reviews every suggestion. Thank you for helping us grow.'**
  String get featureRequestNote;

  /// No description provided for @featureRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Thanks! Your suggestion was sent.'**
  String get featureRequestSent;

  /// No description provided for @guideWaterTitle.
  ///
  /// In en, this message translates to:
  /// **'Log your drinks'**
  String get guideWaterTitle;

  /// No description provided for @guideWaterBody.
  ///
  /// In en, this message translates to:
  /// **'Swipe up on the Home avatar or tap Add Water/Drink. The avatar fills as you get closer to your daily need.'**
  String get guideWaterBody;

  /// No description provided for @guideMealTitle.
  ///
  /// In en, this message translates to:
  /// **'Add your meals'**
  String get guideMealTitle;

  /// No description provided for @guideMealBody.
  ///
  /// In en, this message translates to:
  /// **'Search for foods, scan a barcode or say what you ate. Your calories and nutrients add up through the day.'**
  String get guideMealBody;

  /// No description provided for @guideSleepTitle.
  ///
  /// In en, this message translates to:
  /// **'Track your sleep (STAR)'**
  String get guideSleepTitle;

  /// No description provided for @guideSleepBody.
  ///
  /// In en, this message translates to:
  /// **'Log when you went to bed and woke up to see your sleep score.'**
  String get guideSleepBody;

  /// No description provided for @guideStreakTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep your streak'**
  String get guideStreakTitle;

  /// No description provided for @guideStreakBody.
  ///
  /// In en, this message translates to:
  /// **'Log anything each day to grow your streak. Find it on your Profile.'**
  String get guideStreakBody;

  /// No description provided for @guideCircleTitle.
  ///
  /// In en, this message translates to:
  /// **'Join a Care Circle'**
  String get guideCircleTitle;

  /// No description provided for @guideCircleBody.
  ///
  /// In en, this message translates to:
  /// **'Share your avatars with family and friends and cheer each other on.'**
  String get guideCircleBody;

  /// No description provided for @guideReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Download reports'**
  String get guideReportTitle;

  /// No description provided for @guideReportBody.
  ///
  /// In en, this message translates to:
  /// **'Get a monthly PDF of your progress from Active Streak > Download report.'**
  String get guideReportBody;

  /// No description provided for @syncConflictBanner.
  ///
  /// In en, this message translates to:
  /// **'An entry was changed on another device. Showing the latest saved version.'**
  String get syncConflictBanner;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @privacyCentre.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacyCentre;

  /// No description provided for @privacyCentreIntro.
  ///
  /// In en, this message translates to:
  /// **'See what you have agreed to, change optional choices, download your data or delete your account.'**
  String get privacyCentreIntro;

  /// No description provided for @consentsRequiredHeader.
  ///
  /// In en, this message translates to:
  /// **'NEEDED TO USE NARAACARE'**
  String get consentsRequiredHeader;

  /// No description provided for @consentsOptionalHeader.
  ///
  /// In en, this message translates to:
  /// **'YOUR CHOICES'**
  String get consentsOptionalHeader;

  /// No description provided for @yourDataHeader.
  ///
  /// In en, this message translates to:
  /// **'YOUR DATA'**
  String get yourDataHeader;

  /// No description provided for @requiredLabel.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredLabel;

  /// No description provided for @consentRecorded.
  ///
  /// In en, this message translates to:
  /// **'Accepted version {version} on {date}'**
  String consentRecorded(String version, String date);

  /// No description provided for @consentRequiredExplain.
  ///
  /// In en, this message translates to:
  /// **'These are needed for the app to work. To stop them, delete your account.'**
  String get consentRequiredExplain;

  /// No description provided for @consentGranted.
  ///
  /// In en, this message translates to:
  /// **'Saved. Thank you.'**
  String get consentGranted;

  /// No description provided for @consentWithdrawn.
  ///
  /// In en, this message translates to:
  /// **'Withdrawn. This takes effect right away.'**
  String get consentWithdrawn;

  /// No description provided for @purposeHealthData.
  ///
  /// In en, this message translates to:
  /// **'Health data'**
  String get purposeHealthData;

  /// No description provided for @purposeHealthDataBody.
  ///
  /// In en, this message translates to:
  /// **'Your health logs and profile are used to work out your targets and fill your avatars.'**
  String get purposeHealthDataBody;

  /// No description provided for @purposeRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'The rules for using NaraaCare and how we handle your data.'**
  String get purposeRequiredBody;

  /// No description provided for @purposeAi.
  ///
  /// In en, this message translates to:
  /// **'AI processing (Rin AI)'**
  String get purposeAi;

  /// No description provided for @purposeAiBody.
  ///
  /// In en, this message translates to:
  /// **'Lets Rin AI, drink estimates and report insights send your own data to our AI provider. Turning it off stops these at once.'**
  String get purposeAiBody;

  /// No description provided for @purposeCircleSharing.
  ///
  /// In en, this message translates to:
  /// **'Care Circle sharing'**
  String get purposeCircleSharing;

  /// No description provided for @purposeCircleSharingBody.
  ///
  /// In en, this message translates to:
  /// **'Lets you share the avatars you choose with your Care Circles.'**
  String get purposeCircleSharingBody;

  /// No description provided for @purposeMarketing.
  ///
  /// In en, this message translates to:
  /// **'News and offers'**
  String get purposeMarketing;

  /// No description provided for @purposeMarketingBody.
  ///
  /// In en, this message translates to:
  /// **'Occasional emails about new features and offers.'**
  String get purposeMarketingBody;

  /// No description provided for @downloadMyData.
  ///
  /// In en, this message translates to:
  /// **'Download my data'**
  String get downloadMyData;

  /// No description provided for @privacyNotice.
  ///
  /// In en, this message translates to:
  /// **'Privacy notice'**
  String get privacyNotice;

  /// No description provided for @exportIntro.
  ///
  /// In en, this message translates to:
  /// **'Get a copy of all the personal data NaraaCare keeps about you, as a ZIP file you can open on a computer.'**
  String get exportIntro;

  /// No description provided for @exportWhatsIncluded.
  ///
  /// In en, this message translates to:
  /// **'Included: your profile, health logs, goals, Care Circles and messages, Rin AI chats, reports, payments and consents, as JSON and spreadsheet (CSV) files. Passwords and sign-in secrets are never included.'**
  String get exportWhatsIncluded;

  /// No description provided for @requestExport.
  ///
  /// In en, this message translates to:
  /// **'Request my data'**
  String get requestExport;

  /// No description provided for @exportPreparing.
  ///
  /// In en, this message translates to:
  /// **'We\'re preparing your file. You can leave this screen; we\'ll notify you when it\'s ready.'**
  String get exportPreparing;

  /// No description provided for @exportReady.
  ///
  /// In en, this message translates to:
  /// **'Your file is ready until {date}.'**
  String exportReady(String date);

  /// No description provided for @downloadAndShare.
  ///
  /// In en, this message translates to:
  /// **'Download and share'**
  String get downloadAndShare;

  /// No description provided for @exportLimitNote.
  ///
  /// In en, this message translates to:
  /// **'You can ask for one copy a day. The file is kept for 7 days.'**
  String get exportLimitNote;

  /// No description provided for @exportLimitReached.
  ///
  /// In en, this message translates to:
  /// **'You can request one data export a day. Try again tomorrow.'**
  String get exportLimitReached;

  /// No description provided for @reauthTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm it\'s you'**
  String get reauthTitle;

  /// No description provided for @reauthPasswordBody.
  ///
  /// In en, this message translates to:
  /// **'Enter your password to continue.'**
  String get reauthPasswordBody;

  /// No description provided for @reauthCodeBody.
  ///
  /// In en, this message translates to:
  /// **'We emailed you a 6-digit code. Enter it to continue.'**
  String get reauthCodeBody;

  /// No description provided for @reauthCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get reauthCodeLabel;

  /// No description provided for @reauthUseCode.
  ///
  /// In en, this message translates to:
  /// **'No password? Email me a code'**
  String get reauthUseCode;

  /// No description provided for @reauthResend.
  ///
  /// In en, this message translates to:
  /// **'Send a new code'**
  String get reauthResend;

  /// No description provided for @reauthCodeSent.
  ///
  /// In en, this message translates to:
  /// **'Code sent to your email.'**
  String get reauthCodeSent;

  /// No description provided for @reauthWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'That password is not correct.'**
  String get reauthWrongPassword;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @okLabel.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get okLabel;

  /// No description provided for @deleteAccountIntro.
  ///
  /// In en, this message translates to:
  /// **'Deleting your account is permanent.'**
  String get deleteAccountIntro;

  /// No description provided for @deleteWhatGoes.
  ///
  /// In en, this message translates to:
  /// **'Your profile, health logs, avatars, Care Circle memberships, messages, Rin AI chats, reports and files will be erased.'**
  String get deleteWhatGoes;

  /// No description provided for @deleteGrace.
  ///
  /// In en, this message translates to:
  /// **'You have 30 days to change your mind: sign in again and tap Cancel deletion.'**
  String get deleteGrace;

  /// No description provided for @deleteKept.
  ///
  /// In en, this message translates to:
  /// **'As the law requires, a record of your consents and store payments is kept for up to 8 years, without your name, email or account id.'**
  String get deleteKept;

  /// No description provided for @deleteSignedOut.
  ///
  /// In en, this message translates to:
  /// **'You will be signed out on all your devices straight away.'**
  String get deleteSignedOut;

  /// No description provided for @deleteSubscriptionWarning.
  ///
  /// In en, this message translates to:
  /// **'Deleting your account does not cancel a STAR subscription. Cancel it in Google Play or the App Store first.'**
  String get deleteSubscriptionWarning;

  /// No description provided for @manageSubscription.
  ///
  /// In en, this message translates to:
  /// **'Manage subscription'**
  String get manageSubscription;

  /// No description provided for @deleteConfirmCheck.
  ///
  /// In en, this message translates to:
  /// **'I understand my account and data will be deleted after 30 days.'**
  String get deleteConfirmCheck;

  /// No description provided for @deleteAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get deleteAccountButton;

  /// No description provided for @deletionScheduledTitle.
  ///
  /// In en, this message translates to:
  /// **'Deletion scheduled'**
  String get deletionScheduledTitle;

  /// No description provided for @deletionScheduledBody.
  ///
  /// In en, this message translates to:
  /// **'Your account will be deleted on {date}. We\'ve emailed you. Sign in before then if you change your mind.'**
  String deletionScheduledBody(String date);

  /// No description provided for @deletionPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Your account is scheduled for deletion'**
  String get deletionPendingTitle;

  /// No description provided for @deletionPendingBody.
  ///
  /// In en, this message translates to:
  /// **'It will be permanently deleted on {date}. Do you want to keep it?'**
  String deletionPendingBody(String date);

  /// No description provided for @cancelDeletion.
  ///
  /// In en, this message translates to:
  /// **'Cancel deletion'**
  String get cancelDeletion;

  /// No description provided for @keepDeletionSignOut.
  ///
  /// In en, this message translates to:
  /// **'Keep deletion and sign out'**
  String get keepDeletionSignOut;

  /// No description provided for @deletionCancelled.
  ///
  /// In en, this message translates to:
  /// **'Deletion cancelled. Welcome back!'**
  String get deletionCancelled;

  /// No description provided for @reconsentTitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ve updated our policies'**
  String get reconsentTitle;

  /// No description provided for @reconsentBody.
  ///
  /// In en, this message translates to:
  /// **'Please read and accept the new versions to keep using NaraaCare.'**
  String get reconsentBody;

  /// No description provided for @acceptAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Accept and continue'**
  String get acceptAndContinue;

  /// No description provided for @readFullPolicy.
  ///
  /// In en, this message translates to:
  /// **'Read the full Privacy Policy'**
  String get readFullPolicy;

  /// No description provided for @noticeCollectTitle.
  ///
  /// In en, this message translates to:
  /// **'What we collect'**
  String get noticeCollectTitle;

  /// No description provided for @noticeCollectBody.
  ///
  /// In en, this message translates to:
  /// **'Your name, email and username; your age, sex, height, weight, activity level, goals and any health conditions you choose to add; what you log (drinks, meals, workouts, sleep); your Care Circle messages and Rin AI chats; and basic device information needed to sign you in and send notifications.'**
  String get noticeCollectBody;

  /// No description provided for @noticeWhyTitle.
  ///
  /// In en, this message translates to:
  /// **'Why we use it'**
  String get noticeWhyTitle;

  /// No description provided for @noticeWhyBody.
  ///
  /// In en, this message translates to:
  /// **'To work out your daily targets, show your progress, run Care Circles and Rin AI, keep your account secure, and handle your subscription. We never sell your data or use it for advertising.'**
  String get noticeWhyBody;

  /// No description provided for @noticeNotCollectTitle.
  ///
  /// In en, this message translates to:
  /// **'What we don\'t collect'**
  String get noticeNotCollectTitle;

  /// No description provided for @noticeNotCollectBody.
  ///
  /// In en, this message translates to:
  /// **'No phone number, date of birth, precise location, contacts, photos (except a screenshot you choose to send to support) or data from other apps.'**
  String get noticeNotCollectBody;

  /// No description provided for @noticeProcessorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Who helps us'**
  String get noticeProcessorsTitle;

  /// No description provided for @noticeProcessorsBody.
  ///
  /// In en, this message translates to:
  /// **'Our hosting and email providers; Google and Apple for sign-in, payments and notifications; and Anthropic, our AI provider for Rin AI, only if you turn on AI processing. They may only use your data to provide their service to us.'**
  String get noticeProcessorsBody;

  /// No description provided for @noticeRetentionTitle.
  ///
  /// In en, this message translates to:
  /// **'How long we keep it'**
  String get noticeRetentionTitle;

  /// No description provided for @noticeRetentionBody.
  ///
  /// In en, this message translates to:
  /// **'Your health data stays while you have an account and is erased 30 days after you ask us to delete it. Security logs are kept for up to 1 year, inactive Rin AI chats for 12 months, and consent and payment records (without your identity) for up to 8 years.'**
  String get noticeRetentionBody;

  /// No description provided for @noticeRightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your rights'**
  String get noticeRightsTitle;

  /// No description provided for @noticeRightsBody.
  ///
  /// In en, this message translates to:
  /// **'You can see and correct your data in the app, download a copy, withdraw optional consents at any time, and delete your account. Under India\'s Digital Personal Data Protection Act you can also raise a grievance with us and, if not resolved, with the Data Protection Board of India.'**
  String get noticeRightsBody;

  /// No description provided for @noticeGrievanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Grievance contact'**
  String get noticeGrievanceTitle;

  /// No description provided for @noticeGrievanceBody.
  ///
  /// In en, this message translates to:
  /// **'Write to {contact}. We reply within 7 days.'**
  String noticeGrievanceBody(String contact);

  /// No description provided for @noticeGrievancePending.
  ///
  /// In en, this message translates to:
  /// **'our support team (Help & Support)'**
  String get noticeGrievancePending;

  /// No description provided for @shareAvatarTitle.
  ///
  /// In en, this message translates to:
  /// **'Share your {avatar} avatar'**
  String shareAvatarTitle(String avatar);

  /// No description provided for @shareAvatarHint.
  ///
  /// In en, this message translates to:
  /// **'Only people in NaraaCare see it. Today\'s progress is shared, nothing else.'**
  String get shareAvatarHint;

  /// No description provided for @shareAvatarNobody.
  ///
  /// In en, this message translates to:
  /// **'Join a Care Circle or connect with someone to share your avatar.'**
  String get shareAvatarNobody;

  /// No description provided for @shareToCircles.
  ///
  /// In en, this message translates to:
  /// **'Your circles'**
  String get shareToCircles;

  /// No description provided for @shareToConnections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get shareToConnections;

  /// No description provided for @shareSend.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareSend;

  /// No description provided for @avatarShared.
  ///
  /// In en, this message translates to:
  /// **'Shared'**
  String get avatarShared;

  /// No description provided for @feedShared.
  ///
  /// In en, this message translates to:
  /// **'{who} shared their {avatar} avatar.'**
  String feedShared(String who, String avatar);

  /// No description provided for @notifAvatarShared.
  ///
  /// In en, this message translates to:
  /// **'{who} shared their {avatar} avatar with you.'**
  String notifAvatarShared(String who, String avatar);

  /// No description provided for @notifCircleAvatarShared.
  ///
  /// In en, this message translates to:
  /// **'{who} shared their {avatar} avatar in your circle.'**
  String notifCircleAvatarShared(String who, String avatar);

  /// No description provided for @sharedProgress.
  ///
  /// In en, this message translates to:
  /// **'{value} % of today\'s goal'**
  String sharedProgress(int value);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
