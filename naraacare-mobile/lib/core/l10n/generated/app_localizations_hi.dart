// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appName => 'NaraaCare';

  @override
  String get validationRequired => 'This field is required.';

  @override
  String get validationUnsafe =>
      'Please use letters, numbers and basic punctuation only.';

  @override
  String get validationFormat =>
      'This doesn\'t look right. Please check and try again.';

  @override
  String get validationTooShort => 'This is too short.';

  @override
  String get validationTooLong => 'This is too long.';

  @override
  String get validationMismatch => 'Passwords do not match.';

  @override
  String get validationWeakPassword =>
      'Use at least 8 characters with one uppercase letter and one number.';

  @override
  String get validationOutOfRange => 'This value is outside the allowed range.';

  @override
  String get errorNetwork =>
      'No internet connection. We\'ll try again when you\'re back online.';

  @override
  String get errorTimeout => 'This is taking too long. Please try again.';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get errorRateLimited =>
      'Too many attempts. Please wait a moment and try again.';

  @override
  String get errorSessionExpired =>
      'Your session has expired. Please sign in again.';

  @override
  String get errorUpgradeRequired => 'This feature is available with STAR.';

  @override
  String get errorCertificate =>
      'We couldn\'t verify a secure connection. Please check your network.';

  @override
  String get errorConflict => 'This entry was changed on another device.';

  @override
  String get offlineBanner =>
      'You\'re offline. Changes will sync when you\'re back online.';

  @override
  String get rootedWarning =>
      'This device appears to be rooted or jailbroken. Your data may be less secure.';

  @override
  String get biometricReason => 'Unlock NaraaCare';

  @override
  String get biometricUnlock => 'Unlock';

  @override
  String get tabHome => 'Home';

  @override
  String get tabCareCircle => 'Care Circle';

  @override
  String get tabRinAi => 'Rin AI';

  @override
  String get tabProfile => 'Profile';

  @override
  String get starBadge => 'STAR';

  @override
  String get upsellTitle => 'Unlock STAR';

  @override
  String get upsellBody =>
      'Get detailed insights and more features with the STAR plan.';

  @override
  String get actionRetry => 'Try again';

  @override
  String get actionClose => 'Close';

  @override
  String get actionContinue => 'Continue';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get pendingSync => 'Waiting to sync';

  @override
  String get introSkip => 'Skip';

  @override
  String get introNext => 'Next →';

  @override
  String get introGetStarted => 'Get Started';

  @override
  String get intro1Title => 'Meet your health avatars';

  @override
  String get intro1Body =>
      'Three avatars for water, food and sleep. They fill up through the day as you reach your goals.';

  @override
  String get intro2Title => 'Goals made for your body';

  @override
  String get intro2Body =>
      'Tell us about yourself once. We work out your daily water and calorie goals, then adjust them for hot days and workouts.';

  @override
  String get intro3Title => 'Care for each other';

  @override
  String get intro3Body =>
      'Share your avatars with family and friends in a Care Circle, cheer each other on, and ask Rin AI when you need help.';

  @override
  String introStep(int current, int total) {
    return '$current of $total';
  }

  @override
  String get introWater => 'Water';

  @override
  String get introWaterValue => '2.1 L';

  @override
  String get introWaterCaption => 'of 3.5 L goal';

  @override
  String get introMeal => 'Meal';

  @override
  String get introMealValue => '1,454';

  @override
  String get introMealCaption => 'kcal today';

  @override
  String get introSleep => 'Sleep';

  @override
  String get introSleepValue => '7h 4m';

  @override
  String get introSleepCaption => 'Good sleep';

  @override
  String get introFromProfile => 'FROM YOUR PROFILE';

  @override
  String get introTagFemale => 'Female';

  @override
  String get introTagAge => '28 yrs';

  @override
  String get introTagHeight => '5 ft 5 in';

  @override
  String get introTagBody => 'Mesomorph';

  @override
  String get introTagActivity => 'Moderately active';

  @override
  String get introDailyWater => 'Daily water goal';

  @override
  String get introDailyWaterValue => '3.7 L';

  @override
  String get introDailyCalories => 'Daily calorie goal';

  @override
  String get introDailyCaloriesValue => '2,374 kcal';

  @override
  String get introCircleNotice => 'Family circle · 1h ago';

  @override
  String get introCircleNoticeValue => '@priya hit her water goal';

  @override
  String get introStreak => 'Active streak';

  @override
  String get introStreakValue => '7 days';

  @override
  String get introRin => 'Rin AI';

  @override
  String get introRinBody =>
      'Add about 30 g protein at dinner for a balanced day.';

  @override
  String get welcomeTagline =>
      'Glow when you\'re well.\nKnow when they\'re not';

  @override
  String get welcomeGetStarted => 'Get Started';

  @override
  String get haveAccountPrompt => 'Already have an account?';

  @override
  String get signInLink => 'Sign In';

  @override
  String get noAccountPrompt => 'New here?';

  @override
  String get createAccountLink => 'Create an Account';

  @override
  String get signUpTitle => 'Create your account';

  @override
  String get signUpSubtitle => 'Start your journey to a healthier you';

  @override
  String get emailLabel => 'Email';

  @override
  String get emailHint => 'Enter your email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get passwordCreateHint => 'Create a password';

  @override
  String get passwordHint => 'Enter your password';

  @override
  String get confirmPasswordLabel => 'Confirm Password';

  @override
  String get confirmPasswordHint => 'Re-enter your password';

  @override
  String get termsAgreePrefix => 'I agree to the ';

  @override
  String get termsLink => 'Terms & Conditions';

  @override
  String get termsAnd => ' and ';

  @override
  String get privacyLink => 'Privacy Policy';

  @override
  String get termsRequired =>
      'Please accept the Terms & Conditions and Privacy Policy.';

  @override
  String get signUpButton => 'Sign Up';

  @override
  String get orDivider => 'or';

  @override
  String get continueWithGoogle => 'Sign up with Google';

  @override
  String get continueWithApple => 'Sign up with Apple';

  @override
  String get emailRegistered =>
      'This email is already registered. Try Signing In instead.';

  @override
  String get passwordWeak =>
      'This password is too common or too weak. Please choose another.';

  @override
  String get socialError =>
      'It looks like there was an error signing into your account. Please try again.';

  @override
  String get appleUnavailable =>
      'Unable to connect to Apple. Please check your internet connection and try again.';

  @override
  String get googleUnavailable =>
      'Unable to connect to Google. Please check your internet connection and try again.';

  @override
  String get linkAccountTitle => 'Link your account';

  @override
  String get linkAccountBody =>
      'An account with this email already exists. Enter its password to link your sign-in.';

  @override
  String get linkAccountButton => 'Link and sign in';

  @override
  String get verifyTitle => 'Verify your email';

  @override
  String get verifyBody =>
      'We sent a verification code to your email. Enter the 6-digit code below.';

  @override
  String get verifyButton => 'Verify Email';

  @override
  String get resendPrompt => 'Didn\'t receive the code?';

  @override
  String get resendCode => 'Resend Code.';

  @override
  String resendIn(String time) {
    return 'Resend available in $time';
  }

  @override
  String get codeResent => 'New code sent successfully on your email';

  @override
  String get otpInvalid => 'Invalid verification code. Please try again';

  @override
  String otpInvalidAttempts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attempts left.',
      one: '1 attempt left.',
    );
    return 'Invalid verification code. $_temp0';
  }

  @override
  String get otpExpired => 'This code has expired. Request a new code.';

  @override
  String get otpLocked => 'Too many wrong codes. Request a new code.';

  @override
  String get emailVerifiedTitle => 'Email Verified';

  @override
  String get emailVerifiedBody =>
      'Your account is now ready to use. Just one more step.';

  @override
  String get signInTitle => 'Welcome Back';

  @override
  String get signInSubtitle => 'Sign In to Continue';

  @override
  String get forgotPasswordLink => 'Forgot Password?';

  @override
  String get signInButton => 'Sign In';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get signInWithApple => 'Sign in with Apple';

  @override
  String get invalidCredentials =>
      'Incorrect email or password. Please try again.';

  @override
  String accountLocked(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    return 'Too many attempts. Try again in $_temp0.';
  }

  @override
  String get emailNotVerified =>
      'Please verify your email first. We\'ve sent you a new code.';

  @override
  String get forgotTitle => 'Forgot Password';

  @override
  String get forgotBody =>
      'Enter the email linked to your account and we\'ll send you a code to reset your password.';

  @override
  String get resetPasswordButton => 'Reset Password';

  @override
  String get backToSignIn => 'Back to Sign In';

  @override
  String get resetCodeTitle => 'Check Your Email';

  @override
  String get resetCodeBody =>
      'If an account exists for this email, we\'ve sent a 6-digit code. Enter it below to continue.';

  @override
  String get resetCodeSpamHint =>
      'Didn\'t receive the email? Check your spam folder or try another email.';

  @override
  String get continueButton => 'Continue';

  @override
  String get newPasswordTitle => 'Set New Password';

  @override
  String get newPasswordBody =>
      'Your new password must be different from previously used passwords.';

  @override
  String get newPasswordLabel => 'New Password';

  @override
  String get newPasswordHint => 'Enter new password';

  @override
  String get confirmNewPasswordHint => 'Re-enter new password';

  @override
  String get passwordRulesTitle => 'Password must contain:';

  @override
  String get ruleLength => 'At least 8 characters';

  @override
  String get ruleUppercase => 'One uppercase letter';

  @override
  String get ruleNumber => 'One number';

  @override
  String get passwordReused =>
      'Please choose a password you haven\'t used before.';

  @override
  String get passwordChangedTitle => 'Password Changed';

  @override
  String get passwordChangedBody =>
      'Your password has been successfully updated. You can now sign in with your new credentials.';

  @override
  String get onboardingIntroTitle => 'Let\'s build your healthy avatar';

  @override
  String get onboardingIntroBody =>
      'NaraaCare uses your details to map food and water directly to your body.';

  @override
  String get onboardingIntroButton => 'Build my avatar';

  @override
  String stepOf(int step, int total) {
    return '$step/$total';
  }

  @override
  String get goBack => 'Go Back';

  @override
  String get nextButton => 'Next';

  @override
  String get whyItMatters => 'Why it matters?';

  @override
  String get step1Title => 'Choose your gender';

  @override
  String get step1Why => 'Bodies need different amounts of energy and water.';

  @override
  String get sexFemale => 'Female';

  @override
  String get sexMale => 'Male';

  @override
  String get fullNameLabel => 'Full Name';

  @override
  String get fullNameHint => 'Enter your full name';

  @override
  String get step2Title => 'How tall are you?';

  @override
  String get step2Why => 'Helps calculate your BMI & nutrition.';

  @override
  String get unitCm => 'cm';

  @override
  String get unitFtIn => 'ft/in';

  @override
  String get unitKg => 'kg';

  @override
  String get unitLb => 'lb';

  @override
  String feetInches(int feet, int inches) {
    return '$feet’$inches”';
  }

  @override
  String get step3Title => 'What\'s your current weight?';

  @override
  String get step3Why =>
      'We don\'t show anyone, not your family, not us. Your weight helps us estimate hydration needs and personalize your daily targets.';

  @override
  String get weightHint => 'Enter your weight';

  @override
  String get goalLabel => 'Your goal';

  @override
  String get goalHint => 'Select your goal';

  @override
  String get step4Title => 'What\'s your target weight?';

  @override
  String get step4Why => 'Your target helps us support you in this journey.';

  @override
  String get targetHint => 'Enter your target weight';

  @override
  String healthyRange(int min, int max) {
    return 'This target falls within the healthy BMI range $min-$max kg for your height.';
  }

  @override
  String outsideRange(int min, int max) {
    return 'You\'re outside the recommended BMI range $min-$max kg.';
  }

  @override
  String get conditionsLabel => 'Any medical conditions or allergies?';

  @override
  String get conditionsHint => 'Search conditions';

  @override
  String get conditionsNone => 'None';

  @override
  String get step5Title => 'How old are you?';

  @override
  String get step5Why =>
      'Organ function changes with age. Helps personalize hydration & nutrition for you.';

  @override
  String get ageHint => 'Enter your age';

  @override
  String get activityLabel => 'How active are you?';

  @override
  String get step6Title => 'Choose your body type';

  @override
  String get step6Why =>
      'It gives us a better understanding of your metabolic needs. Select what best represents you from the 3 types.';

  @override
  String bodyTypeChosen(String name) {
    return 'You chose $name.';
  }

  @override
  String get resultTitle => 'Your avatar is ready';

  @override
  String get resultName => 'Name:';

  @override
  String get resultHeight => 'Height:';

  @override
  String get resultWeight => 'Weight:';

  @override
  String get resultAge => 'Age:';

  @override
  String get resultGoal => 'Goal:';

  @override
  String get resultTarget => 'Target weight:';

  @override
  String get resultActivity => 'Activity:';

  @override
  String get resultConditions => 'Allergy:';

  @override
  String get resultBodyType => 'Body type:';

  @override
  String get resultCalories => 'Daily calories:';

  @override
  String get resultWater => 'Daily water:';

  @override
  String kcalValue(int value) {
    return '$value kcal';
  }

  @override
  String mlValue(int value) {
    return '$value mL';
  }

  @override
  String get editDetails => 'Edit Details';

  @override
  String get saveAvatar => 'Save my avatar';

  @override
  String get generatingTitle => 'Generating your health profile…';

  @override
  String get savedTitle => 'Saved Details';

  @override
  String get savedBody => 'Redirecting in a moment...';

  @override
  String get goalNotAllowed =>
      'This goal is not available for your current weight. Please choose another.';

  @override
  String get consentTitle => 'Before we start';

  @override
  String get consentTerms => 'I accept the Terms & Conditions';

  @override
  String get consentPrivacy => 'I accept the Privacy Policy';

  @override
  String get consentHealth =>
      'I agree that NaraaCare processes my health data to give me targets and tracking';

  @override
  String get consentAi => 'Allow Rin AI to process my messages (optional)';

  @override
  String get consentRequired => 'Required';

  @override
  String get consentAgree => 'Agree and continue';

  @override
  String get greetingMorning => 'Good Morning';

  @override
  String get greetingAfternoon => 'Good Afternoon';

  @override
  String get greetingEvening => 'Good Evening';

  @override
  String greetingName(String greeting, String name) {
    return '$greeting, $name';
  }

  @override
  String get avatarWater => 'Water';

  @override
  String get avatarFood => 'Food';

  @override
  String get avatarSleep => 'Sleep';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get usernameSheetTitle => 'Create your NaraaCare username';

  @override
  String get usernameSheetBody =>
      'Your username helps people find and connect with you.';

  @override
  String get usernameLabel => 'Username';

  @override
  String get usernameHint => 'e.g. priya.s';

  @override
  String get usernameAvailable => 'Username available';

  @override
  String get usernameTaken => 'Username is already taken';

  @override
  String get usernameTooSoon =>
      'You can change your username once every 3 months.';

  @override
  String get usernameRule =>
      'Your username should be unique and can include letters, special characters and numbers. You can change your username once every 3 months.';

  @override
  String get setUpLater => 'Set up later';

  @override
  String get saveButton => 'Save';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsProfileSection => 'PROFILE';

  @override
  String get settingsSubscriptionSection => 'SUBSCRIPTIONS & PAYMENTS';

  @override
  String get settingsSupportSection => 'SUPPORT & LEGAL';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get account => 'Account';

  @override
  String get notificationsReminders => 'Notifications & Reminders';

  @override
  String get mySubscriptions => 'My Subscriptions';

  @override
  String get referFriend => 'Refer a Friend';

  @override
  String get termsTitle => 'Terms and Conditions';

  @override
  String get privacyTitle => 'Privacy policy';

  @override
  String get licensesTitle => 'Licenses';

  @override
  String get helpSupport => 'Help & Support';

  @override
  String get logOut => 'Log Out';

  @override
  String get logOutConfirm =>
      'Do you want to log out of NaraaCare on this device?';

  @override
  String get cancel => 'Cancel';

  @override
  String get profileSaved => 'Profile updated';

  @override
  String get bmiLabel => 'BMI';

  @override
  String get ageLabel => 'Age';

  @override
  String get heightLabel => 'Height';

  @override
  String get weightLabel => 'Weight';

  @override
  String get targetWeightLabel => 'Target weight';

  @override
  String get bodyTypeLabel => 'Body type';

  @override
  String get sexLabel => 'Gender';

  @override
  String get changePassword => 'Change Password';

  @override
  String get currentPasswordLabel => 'Current Password';

  @override
  String get currentPasswordHint => 'Enter current password';

  @override
  String get passwordUpdated => 'Password updated';

  @override
  String get deleteAccount => 'Delete Account';

  @override
  String get usernameSaved => 'Username updated';

  @override
  String get linkOpenFailed =>
      'Couldn\'t open the page. Please try again later.';

  @override
  String kcalValueShort(int value) {
    return '$value kcal';
  }

  @override
  String ofGoalKcal(int goal) {
    return 'of $goal kcal';
  }

  @override
  String get addMealButton => 'Meal';

  @override
  String get nutritionInfo => 'About your calorie goal';

  @override
  String get todaysNutrition => 'Today\'s Nutrition';

  @override
  String get basedOnLoggedMeals => 'Based on today\'s logged meals';

  @override
  String get tierFree => 'Free';

  @override
  String get tierIncluded => 'Included';

  @override
  String caloriesOfGoal(int eaten, int goal) {
    return 'Calories ($eaten / $goal kcal)';
  }

  @override
  String lastUpdatedAt(String time) {
    return 'Last updated • $time';
  }

  @override
  String get unlockStarNutrients =>
      'Get detailed insights on 10+ nutrients with STAR plan.';

  @override
  String lockedNutrients(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more nutrients with STAR',
      one: '1 more nutrient with STAR',
    );
    return '$_temp0';
  }

  @override
  String get allNutrientsUnlocked => 'All nutritional values unlocked';

  @override
  String get nutrientUnknown => '—';

  @override
  String get nutritionUnavailable => 'Nutrition isn\'t available right now.';

  @override
  String pendingMeals(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count meals are waiting to sync',
      one: '1 meal is waiting to sync',
    );
    return '$_temp0';
  }

  @override
  String get avatarEmpty => 'Let\'s get started!';

  @override
  String get avatarFueling => 'Fueling up';

  @override
  String get avatarEnergized => 'Energized';

  @override
  String get avatarGoalMet => 'Goal met';

  @override
  String get avatarOverfilled => 'Over your goal';

  @override
  String get addMealTitle => 'Nutrition Update';

  @override
  String get searchFoodHint => 'Search here';

  @override
  String get searchFoodOrBarcodeHint => 'Enter product name or barcode number';

  @override
  String get recentChips => 'Recent';

  @override
  String addItemsCount(int count) {
    return 'Add Items($count)';
  }

  @override
  String get saveMealButton => 'Save Meal';

  @override
  String get updateMealButton => 'Update Meal';

  @override
  String get viewNutritionSummary => 'View Nutrition Summary';

  @override
  String get nutritionSummaryTitle => 'Nutrition Summary';

  @override
  String get addToMeal => 'Add to Meal';

  @override
  String get noFoodsFound => 'No foods found. Try another name.';

  @override
  String get emptyMeal => 'Search for a food to start your meal.';

  @override
  String get maxMealItems => 'A meal can have up to 30 items.';

  @override
  String get quantityLabel => 'Quantity';

  @override
  String get unitLabel => 'Unit';

  @override
  String get removeItem => 'Remove';

  @override
  String get increaseQuantity => 'Increase';

  @override
  String get decreaseQuantity => 'Decrease';

  @override
  String get voiceLogging => 'Log by voice';

  @override
  String get barcodeLogging => 'Scan a barcode';

  @override
  String get mealTypeLabel => 'Meal';

  @override
  String get mealTypeBreakfast => 'Breakfast';

  @override
  String get mealTypeLunch => 'Lunch';

  @override
  String get mealTypeSnack => 'Snack';

  @override
  String get mealTypeDinner => 'Dinner';

  @override
  String get alsoSaveFavourite => 'Also add to Saved Meals';

  @override
  String get savedMealNameLabel => 'Saved meal name';

  @override
  String get savedMealNameHint => 'e.g. Dal Chawal';

  @override
  String get mealSaved => 'Meal saved';

  @override
  String get mealQueued =>
      'Saved offline. It will sync when you\'re back online.';

  @override
  String get savedMealLimit =>
      'You have saved the maximum of 50 meals. Remove one first.';

  @override
  String get limitTitle => 'Daily meal limit reached';

  @override
  String limitBodyStandard(int limit) {
    return 'You\'ve logged $limit meals today, the most on the free plan. STAR lets you log up to 8 meals a day.';
  }

  @override
  String limitBodyStar(int limit) {
    return 'You\'ve logged $limit meals today. You can log more tomorrow.';
  }

  @override
  String get gotIt => 'Got it';

  @override
  String get recentUpdates => 'Recent Updates';

  @override
  String get viewAll => 'View All';

  @override
  String get savedMealsTab => 'Saved Meals';

  @override
  String get lastTwoUpdates => 'Last 2 Updates';

  @override
  String get otherEntry => 'Other entry';

  @override
  String get onlyLastTwoEditable => 'Only last 2 entries can be updated';

  @override
  String get editYourEntry => 'Edit your entry';

  @override
  String get noRecentMeals => 'No meals logged yet.';

  @override
  String get noSavedMeals =>
      'No saved meals yet. Turn on \"Also add to Saved Meals\" when you save a meal.';

  @override
  String get useSavedMeal => 'Add';

  @override
  String get deleteEntry => 'Delete entry';

  @override
  String get deleteEntryConfirm => 'Delete this meal? This cannot be undone.';

  @override
  String get delete => 'Delete';

  @override
  String get entryUpdated => 'Entry updated';

  @override
  String get entryDeleted => 'Entry deleted';

  @override
  String get editWindowClosed => 'This entry can no longer be edited.';

  @override
  String get syncingLabel => 'Syncing';

  @override
  String mealItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get voiceTitle => 'Nutrition Update';

  @override
  String get voiceListening => 'Listening for ingredients…';

  @override
  String get voiceTrySaying => 'Try saying: \"2 roti and 1 katori dal\"';

  @override
  String get voiceTranscriptLabel => 'What you said';

  @override
  String get voiceTranscriptHint => 'Your meal in words';

  @override
  String get voiceStart => 'Tap to speak';

  @override
  String get voiceStop => 'Stop';

  @override
  String get voiceFindFoods => 'Find foods';

  @override
  String voiceUnmatched(String items) {
    return 'Not found: $items';
  }

  @override
  String get voiceUnavailable =>
      'Speech recognition isn\'t available on this device. You can type instead.';

  @override
  String get voiceDidNotHear =>
      'We couldn\'t hear you. Check the microphone and try again, or type instead.';

  @override
  String get voiceNothingFound =>
      'We couldn\'t match any foods. Try again or search by name.';

  @override
  String get checkBeforeSaving => 'Check the items before saving.';

  @override
  String get barcodeTitle => 'Scan barcode';

  @override
  String get barcodePermission =>
      'Allow camera access to scan barcodes, or type the number below.';

  @override
  String get barcodeManualLabel => 'Barcode number';

  @override
  String get barcodeManualHint => '8 to 14 digits';

  @override
  String get barcodeLookup => 'Look up';

  @override
  String get barcodeNotFound =>
      'We couldn\'t find this product. Try searching by name.';

  @override
  String get barcodeNotLoggable =>
      'This product\'s nutrition data is incomplete. Try searching by name.';

  @override
  String get scanAnother => 'Scan Another';

  @override
  String get per100g => 'Per 100 g';

  @override
  String servingSize(String grams) {
    return 'Serving: $grams g';
  }

  @override
  String get searchByName => 'Search by name';

  @override
  String get openFoodFactsCredit => 'Product data: Open Food Facts (ODbL)';

  @override
  String macroSplit(int carbs, int protein, int fat) {
    return 'Carbs $carbs% · Protein $protein% · Fat $fat%';
  }

  @override
  String get mealBreakdown => 'Meal breakdown';

  @override
  String get infoGoalTitle => 'How your calorie goal is set';

  @override
  String get infoGoalBody =>
      'NaraaCare works out your daily calorie goal from the details you gave us: the energy your body burns at rest (from your gender, height, weight and age), plus your normal daily movement, adjusted for your goal. It never goes below 1,200 kcal a day for women or 1,500 kcal for men; if that happens, we\'ll tell you.';

  @override
  String infoTodayGoal(int kcal) {
    return 'Today\'s goal: $kcal kcal';
  }

  @override
  String get infoWorkoutsTitle => 'Workouts give you more to eat';

  @override
  String get infoWorkoutsBody =>
      'When you log a workout, the calories you burn are added to today\'s goal. For example, if your goal is 1,800 kcal and a run burns 400 kcal, you can eat 2,200 kcal today and stay on track.';

  @override
  String get infoNutrientsTitle => 'Your daily nutrients';

  @override
  String get infoNutrientsBody =>
      'Your calories are split into a balanced mix: 55% carbohydrates, 25% fat and 20% protein. STANDARD shows 6 nutrients: calories, protein, carbohydrates, fat, dietary fibre and total sugar. STAR adds 11 more.';

  @override
  String infoTargets(int carbs, int fat, int protein) {
    return 'Today\'s targets: carbs $carbs g, fat $fat g, protein $protein g';
  }

  @override
  String get infoLoggingTitle => 'Logging your meals';

  @override
  String get infoLoggingBody =>
      'Search for a food, pick the amount and unit (katori, piece, cup, glass, tsp, tbsp) and add it to your meal. Add more items, then tap Save Meal. Use Recent and Saved Meals to log favourites quickly. Voice and barcode logging are part of STAR. You can change or delete your last 2 entries.';

  @override
  String get infoNoteTitle => 'Please note';

  @override
  String get infoNoteBody =>
      'Nutrition values are estimates and real foods vary. This isn\'t medical or dietary advice. If you have a medical condition, are pregnant, or follow a diet set by your doctor, follow their advice.';

  @override
  String get hydrationEmpty => 'Let\'s get started!';

  @override
  String hydrationProgress(String intake, String goal) {
    return '$intake L of $goal L goal';
  }

  @override
  String get hydrationGoalCompleted => 'Goal Completed';

  @override
  String hydrationAboveGoal(String intake) {
    return 'Above Goal · $intake L';
  }

  @override
  String get hydrationUnavailable => 'Hydration isn\'t available right now.';

  @override
  String get bandWell => 'Well hydrated';

  @override
  String get bandDrinkSoon => 'Drink soon';

  @override
  String get bandLow => 'Low';

  @override
  String get bandCritical => 'Critical, drink now';

  @override
  String goalPct(int value) {
    return '$value % of today\'s goal';
  }

  @override
  String levelPct(int value) {
    return '$value %';
  }

  @override
  String leftToDrink(String litres) {
    return '$litres L left to drink today';
  }

  @override
  String get dayEndingSoon =>
      'Your day is ending soon. There\'s still time to reach your goal.';

  @override
  String get overhydrationCaution =>
      'That\'s a lot of fluid today. Drinking far more than you need can be harmful.';

  @override
  String get temperatureNotUpdated =>
      'Temperature not updated today: we\'re using 25 °C.';

  @override
  String get swipeHint =>
      'Swipe up to add 100 ml of water, swipe down to remove 100 ml';

  @override
  String swipeAdded(int ml) {
    return '$ml ml of water added';
  }

  @override
  String swipeRemoved(int ml) {
    return '$ml ml of water removed';
  }

  @override
  String get waterBelowZero => 'Today\'s water can\'t go below zero.';

  @override
  String get addWaterButton => 'Water';

  @override
  String get temperatureActivity => 'Temperature & Activity';

  @override
  String get hydrationInfo => 'About your water goal';

  @override
  String get todaysHydration => 'Today\'s Hydration';

  @override
  String get tankLevel => 'Hydration level';

  @override
  String get dailyGoal => 'Daily goal';

  @override
  String get drinksToday => 'Drinks today';

  @override
  String get waterFromFood => 'Water from food';

  @override
  String get workoutSweat => 'Lost in workouts';

  @override
  String get temperature => 'Temperature';

  @override
  String get leftToDrinkLabel => 'Left to drink';

  @override
  String get addIntakeTitle => 'Add a drink';

  @override
  String get waterTab => 'Water';

  @override
  String get otherDrinksTab => 'Other drinks';

  @override
  String get searchDrinkHint => 'Search drinks';

  @override
  String get customDrink => 'Custom drink';

  @override
  String get amountMl => 'Amount (ml)';

  @override
  String get addIntakeButton => 'Add';

  @override
  String get intakeAdded => 'Drink added';

  @override
  String get savedOffline => 'Saved. It will sync when you\'re back online.';

  @override
  String get customDrinkName => 'Drink name';

  @override
  String get customDrinkHint => 'e.g. Banana Shake';

  @override
  String get estimateFactor => 'Estimate hydration';

  @override
  String get estimateFromAi =>
      'Estimated by Rin AI. Adjust it if you know better.';

  @override
  String get estimateDefault =>
      'We couldn\'t estimate this drink, so we start at 85 %. Adjust it if you know better.';

  @override
  String get estimateNoConsent =>
      'AI estimates need your AI consent (Privacy settings). We start at 85 %; adjust it if you know better.';

  @override
  String factorPct(int value) {
    return '$value %';
  }

  @override
  String factorExplain(int value) {
    return '$value % of this drink counts as water';
  }

  @override
  String get saveCustomDrink => 'Save drink';

  @override
  String get noDrinksYet => 'No drinks logged today yet.';

  @override
  String swipeDownEntry(int ml) {
    return 'Water removed · $ml ml';
  }

  @override
  String get editEntry => 'Edit your entry';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get changedElsewhere =>
      'This entry was changed on another device. We\'ve loaded the latest version.';

  @override
  String get temperatureActivityUpsell =>
      'Set today\'s temperature and log workouts so your water goal follows your day. Part of STAR.';

  @override
  String get saveTemperature => 'Save temperature';

  @override
  String temperatureSaved(String value) {
    return 'Temperature set to $value';
  }

  @override
  String get activity => 'Activity';

  @override
  String minutesValue(int value) {
    return '$value min';
  }

  @override
  String get customMinutes => 'Other duration (minutes)';

  @override
  String get saveWorkout => 'Save workout';

  @override
  String get workoutSaved => 'Workout saved';

  @override
  String get workoutWalking => 'Walking';

  @override
  String get workoutGym => 'Gym';

  @override
  String get workoutCycling => 'Cycling';

  @override
  String get workoutSwimming => 'Swimming';

  @override
  String get workoutRunning => 'Running';

  @override
  String get workoutTrekking => 'Trekking';

  @override
  String get hydrationInfoGoalTitle => 'Your daily water goal';

  @override
  String get hydrationInfoGoalBody =>
      'Your goal comes from your body (sex, height, weight, age, body type) and how active you are, using the Yamada 2022 water turnover model. With STAR it also follows the temperature and your workouts.';

  @override
  String get hydrationInfoTankTitle => 'Your water avatar';

  @override
  String get hydrationInfoTankBody =>
      'The avatar shows how full your body\'s water reserve is right now. It drains through the day and fills when you drink. Meals add a little water too.';

  @override
  String get hydrationInfoLoggingTitle => 'Logging drinks';

  @override
  String get hydrationInfoLoggingBody =>
      'Swipe up on the water card to add 100 ml of water, or swipe down to remove 100 ml. Tap Water to add other amounts and drinks. You can change or delete your last 2 entries.';

  @override
  String get hydrationInfoNoteBody =>
      'Water needs are estimates and vary from person to person. This isn\'t medical advice. If your doctor has limited how much you should drink, follow their advice.';

  @override
  String get notificationsExplainerTitle => 'Stay on track with reminders';

  @override
  String get notificationsExplainerBody =>
      'NaraaCare can remind you to drink water, log meals and wind down for sleep. Reminders never show your health numbers on the lock screen, and you can change them any time.';

  @override
  String get allowNotifications => 'Allow notifications';

  @override
  String get notNow => 'Not now';

  @override
  String get pushUnavailable =>
      'Notifications are off for NaraaCare. Turn them on in your phone\'s settings to get reminders. Your settings are saved.';

  @override
  String get reminderWaterTitle => 'Time for some water';

  @override
  String get reminderWaterBody => 'A few sips keep your avatar happy.';

  @override
  String get reminderMealTitle => 'Log your meal';

  @override
  String get reminderMealBody => 'Add what you ate to keep your day on track.';

  @override
  String get reminderSleepTitle => 'Wind down';

  @override
  String get reminderSleepBody =>
      'Getting ready for bed? Log your sleep in the morning.';

  @override
  String get reminderCheckinTitle => 'Daily check-in';

  @override
  String get reminderCheckinBody =>
      'Take a moment to check in with your avatars.';

  @override
  String get reminderProfileTitle => 'Keep your profile current';

  @override
  String get reminderProfileBody =>
      'Review your health profile for accurate goals.';

  @override
  String get remindersSection => 'Reminders';

  @override
  String get notificationTypesSection => 'Notify me about';

  @override
  String get settingsUnavailable => 'Settings aren\'t available right now.';

  @override
  String everyMinutes(int value) {
    return 'Every $value minutes while you\'re awake';
  }

  @override
  String get addTime => 'Add time';

  @override
  String get quietHoursNote => 'No reminders between 22:30 and 07:00.';

  @override
  String get prefGoalCompletions => 'Goal completions';

  @override
  String get prefStreakMilestones => 'Streak milestones';

  @override
  String get prefHealthInsights => 'Health insights';

  @override
  String get prefHydrationReminders => 'Hydration reminders';

  @override
  String get prefNutritionReminders => 'Meal reminders';

  @override
  String get prefSleepReminders => 'Sleep reminders';

  @override
  String get prefDailyCheckin => 'Daily check-in';

  @override
  String get prefHealthProfile => 'Health profile reminders';

  @override
  String get prefConnectionRequests => 'Connection requests';

  @override
  String get prefConnectionActivity => 'Connection activity';

  @override
  String get prefReportsReady => 'Reports ready';

  @override
  String get prefSubscriptionPayments => 'Subscription and payments';

  @override
  String hoursMinutes(int hours, int minutes) {
    return '$hours h $minutes m';
  }

  @override
  String get sleepGood => 'Good';

  @override
  String get sleepFair => 'Fair';

  @override
  String get sleepLow => 'Low';

  @override
  String get sleepNone => 'Not logged';

  @override
  String get sleepNotLogged => 'No sleep logged yet';

  @override
  String get sleepUnavailable => 'Sleep isn\'t available right now.';

  @override
  String get sleepButton => 'Sleep';

  @override
  String get sleepInfo => 'About your sleep score';

  @override
  String get unlockSleepAvatar => 'Unlock your Sleep Avatar';

  @override
  String get todaysSleep => 'Today\'s Sleep';

  @override
  String sleepOfGoal(String achieved, String goal) {
    return '$achieved of $goal';
  }

  @override
  String nightWakings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count night wakings',
      one: '1 night waking',
    );
    return '$_temp0';
  }

  @override
  String sleepBuffersExplain(int onset, int wake, int waking) {
    return 'We don\'t count the first $onset minutes after you go to bed (falling asleep) or the last $wake minutes before you wake. Each night waking also removes $waking extra minutes.';
  }

  @override
  String get sleepGoal => 'Your sleep goal';

  @override
  String get updateSleep => 'Update Sleep';

  @override
  String get sleepStartLabel => 'Went to bed';

  @override
  String get wakeTimeLabel => 'Woke up';

  @override
  String get nightWakingsTitle => 'Night wakings';

  @override
  String get wokeAtLabel => 'Woke at';

  @override
  String get backAsleepLabel => 'Back asleep';

  @override
  String get addNightWaking => 'Add night waking';

  @override
  String get saveSleep => 'Save sleep';

  @override
  String get sleepSaved => 'Sleep saved';

  @override
  String get badgeSaved => 'Saved';

  @override
  String get badgeSyncsLater => 'Syncs when online';

  @override
  String get sleepWakeAfterStart => 'Wake-up time must be after bedtime.';

  @override
  String get sleepTooLong => 'A sleep entry can be at most 16 hours.';

  @override
  String get sleepInFuture => 'Wake-up time can\'t be in the future.';

  @override
  String get sleepWakingsInvalid =>
      'Night wakings must be during your sleep and in order.';

  @override
  String get sleepOverlap => 'This sleep overlaps another entry.';

  @override
  String get sleepInfoHowTitle => 'How we count your sleep';

  @override
  String get sleepInfoHowBody =>
      'Counted sleep = wake-up time minus bedtime, without the time it usually takes to fall asleep (15 minutes) and the last 15 minutes before waking. Each night waking removes the time you were awake plus 10 minutes to fall back asleep. Naps on the same day add up.';

  @override
  String get sleepInfoGoalTitle => 'Your goal and score';

  @override
  String get sleepInfoGoalBody =>
      'Your goal starts from your age (8 hours for adults, 7.5 hours from 65) and you can change it. The score is your counted sleep as a share of your goal, up to 100 %: 90 % and above is Good, 70-89 % Fair, below 70 % Low.';

  @override
  String get sleepInfoNoteBody =>
      'Sleep scores are estimates from the times you enter. This isn\'t medical advice. If you have trouble sleeping often, talk to a doctor.';

  @override
  String get subscriptionUnavailable =>
      'This isn\'t available right now. Please try again.';

  @override
  String get upgradeToStar => 'Upgrade to STAR';

  @override
  String get planStandard => 'STANDARD';

  @override
  String get planStar => 'STAR';

  @override
  String get perMonthSuffix => '/ month';

  @override
  String get perYearSuffix => '/ year';

  @override
  String saveBadge(String percent) {
    return 'SAVE $percent%';
  }

  @override
  String get activeBadge => 'Active';

  @override
  String get recommendedBadge => 'RECOMMENDED';

  @override
  String get yourCurrentPlan => 'Your Current Plan';

  @override
  String get featHydrationNutrition => 'Hydration & Nutrition tracking';

  @override
  String get featCareCircle => 'Care Circle';

  @override
  String get featBasicReports => 'Basic health reports';

  @override
  String get featMeals4 => '4 meal logs/day';

  @override
  String get featReferral30 => '30 day free STAR plan with referral program';

  @override
  String get featTicketSupport => 'Ticket Support';

  @override
  String get featRin => 'Rin AI';

  @override
  String get featInsights => 'Advanced insights & trends';

  @override
  String get featEverythingStandard => 'Everything in Standard';

  @override
  String get featCustomReports => 'Custom health reports';

  @override
  String get featMeals8 => '8 meal logs/day';

  @override
  String get featSleepAvatar => 'Sleep Avatar unlocked';

  @override
  String get featBarcodeVoice => 'Bar-code & Voice input available';

  @override
  String get featPrioritySupport => 'Priority support';

  @override
  String get featReferral50 => '50 day free STAR plan with referral program';

  @override
  String get starPlan => 'STAR Plan';

  @override
  String get billingCycle => 'Billing Cycle';

  @override
  String pricePerMonthShort(String price) {
    return '$price/ mo';
  }

  @override
  String pricePerYearShort(String price) {
    return '$price / year';
  }

  @override
  String get startsToday => 'Starts today';

  @override
  String get renewsOnLabel => 'Renews on';

  @override
  String get paymentVia => 'Payment via';

  @override
  String get paymentViaStores => 'App Store / Google Play';

  @override
  String get chargedThroughStore =>
      'You\'ll be charged through your Apple App Store/ Google Play account. You can manage or cancel anytime.';

  @override
  String get confirmSubscribe => 'Confirm & Subscribe';

  @override
  String get storePriceLoading => 'Loading the store price…';

  @override
  String get currentPlanCaps => 'CURRENT PLAN';

  @override
  String get currentPlan => 'Current plan';

  @override
  String get annualPrice => 'Annual Price';

  @override
  String get monthlyPrice => 'Monthly Price';

  @override
  String get nextBillingDate => 'Next billing date';

  @override
  String get accessUntilLabel => 'Access until';

  @override
  String get autoRenewal => 'Auto-renewal';

  @override
  String get autoRenewalOn => 'On';

  @override
  String get autoRenewalOff => 'Off';

  @override
  String get receiptSent =>
      'A receipt has been sent to your registered email address.';

  @override
  String get goToSubscriptions => 'Go to My Subscriptions';

  @override
  String get planIncludes => 'Your Plan Includes:';

  @override
  String get subscriptionActions => 'Actions';

  @override
  String get updatePaymentMethod => 'Update Payment Method';

  @override
  String get planNameYearly => 'STAR Plan (Yearly)';

  @override
  String get planNameMonthly => 'STAR Plan (Monthly)';

  @override
  String get paidBadge => 'Paid';

  @override
  String get refundedBadge => 'Refunded';

  @override
  String get receiptsByEmail => 'Receipts are sent to your registered email.';

  @override
  String get ifYouCancel => 'If you cancel:';

  @override
  String cancelAccessTill(String date) {
    return 'You will have access till $date.';
  }

  @override
  String get cancelAccessTillPeriodEnd =>
      'You will have access till the end of the paid period.';

  @override
  String get cancelAutoRenewOff => 'Auto renewal will be turned off.';

  @override
  String get cancelNoCharge => 'You won\'t be charged again.';

  @override
  String get cancelUpgradeBack =>
      'You can upgrade back to STAR anytime if you change your mind.';

  @override
  String get cancelInStore =>
      'You\'ll finish cancelling in your App Store / Google Play account.';

  @override
  String get stayOnStar => 'Stay on STAR';

  @override
  String get subscriptionCancelled => 'Subscription Cancelled';

  @override
  String get subscriptionCancelledBody =>
      'Your STAR plan subscription has been cancelled.';

  @override
  String cancelledAccessTill(String date) {
    return 'You have access to STAR plan features till $date. After that you will be moved to STANDARD plan.';
  }

  @override
  String get planMonthly => 'Monthly';

  @override
  String get planYearly => 'Yearly';

  @override
  String get upgradeButton => 'Upgrade';

  @override
  String get restorePurchases => 'Restore purchases';

  @override
  String get purchasePending =>
      'Your payment is pending. STAR unlocks as soon as the store confirms it.';

  @override
  String get storeUnavailable =>
      'The store isn\'t available on this device right now.';

  @override
  String get purchaseFailed =>
      'We couldn\'t confirm this purchase. You haven\'t lost anything; try Restore purchases.';

  @override
  String get paymentIssue =>
      'There\'s a problem with your payment. Please update it in the store to keep STAR.';

  @override
  String get billingHistory => 'Billing History';

  @override
  String get noBillingHistory => 'No payments yet.';

  @override
  String get cancelSubscription => 'Cancel Subscription';

  @override
  String get starFromReward =>
      'You have STAR from a reward or promotion. Enjoy!';

  @override
  String get nowOnStar => 'You\'re now on STAR plan.';

  @override
  String get nowOnStarBody => 'Your health journey just got a major upgrade.';

  @override
  String get referTitle => 'Refer 5 friends, get STAR free';

  @override
  String get referBody =>
      'Share your link. When 5 friends each use NaraaCare on 30 days within their first 60, you get 30 days of STAR (50 days if you\'re already on STAR).';

  @override
  String get copyLink => 'Copy link';

  @override
  String get linkCopied => 'Link copied';

  @override
  String referProgress(int done, int total) {
    return '$done of $total friends qualified';
  }

  @override
  String referRewardGranted(int days) {
    return 'Reward unlocked: $days days of STAR';
  }

  @override
  String get friendQualified => 'Qualified';

  @override
  String get friendNotQualified => 'Didn\'t qualify in time';

  @override
  String friendActiveDays(int days) {
    return '$days of 30 active days';
  }

  @override
  String get referRules =>
      'Friends must be new to NaraaCare and sign up within 7 days of opening your link. One reward per person.';

  @override
  String get invitedTitle => 'You\'ve been invited to NaraaCare';

  @override
  String get invitedBody =>
      'Create your account to get started. Your friend gets closer to a STAR reward when you use NaraaCare.';

  @override
  String get moreOptions => 'More options';

  @override
  String get addWaterDrinkButton => 'Add Water/Drink';

  @override
  String get addMealLongButton => 'Add Meal';

  @override
  String get logSleepButton => 'Log Sleep';

  @override
  String pageOf(int page, int count) {
    return 'Page $page of $count';
  }

  @override
  String get accept => 'Accept';

  @override
  String get addMembers => 'Add Members';

  @override
  String get adminRequired => 'Only a circle admin can do this.';

  @override
  String get admins => 'ADMINS';

  @override
  String get allMembers => 'All Members';

  @override
  String get backToCircles => 'Back to Your Circles';

  @override
  String get cancelInvite => 'Cancel invite';

  @override
  String get changeSharesLater =>
      'You can change these anytime from the circle Settings.';

  @override
  String get chatSection => 'CHAT';

  @override
  String get chooseShares =>
      'Choose at least 1 avatar to share with all members of this circle.';

  @override
  String get circleActivity => 'CIRCLE ACTIVITY';

  @override
  String get circleAdmin => 'Circle Admin';

  @override
  String get circleChat => 'Circle Chat';

  @override
  String get circleFull => 'This circle is full (50 members).';

  @override
  String get circleName => 'Circle name';

  @override
  String get circleNameHelper => 'You can change this later';

  @override
  String get circleNameHint => 'e.g. Gym Buddies';

  @override
  String get circleNotFound => 'This circle is not available.';

  @override
  String get circlesUnavailable => 'Could not load. Pull to try again.';

  @override
  String get connect => 'Connect';

  @override
  String get connected => 'Connected';

  @override
  String get connectedOnNaraaCare => 'CONNECTED ON NARAACARE';

  @override
  String get connections => 'Connections';

  @override
  String get copyInviteLink => 'Copy invite link';

  @override
  String get createCircle => 'Create a circle';

  @override
  String get createCircleButton => 'Create Circle';

  @override
  String get createCircleTip =>
      'Invite friends and family to share avatars and support each other';

  @override
  String get createCircleTitle => 'Create a Care Circle';

  @override
  String get createCircleTitleShort => 'Create a Circle';

  @override
  String get decline => 'Decline';

  @override
  String get deleteMessageTitle => 'Delete this message?';

  @override
  String get findPeople => 'Find People';

  @override
  String get healthUpdates => 'HEALTH UPDATES';

  @override
  String get invite => 'Invite';

  @override
  String get inviteLink => 'Invite Link';

  @override
  String get inviteLinkAfterCreate =>
      'Create the circle first, then share an invite link from its Settings.';

  @override
  String get inviteLinkCopied => 'Invite link copied. It works for 7 days.';

  @override
  String get inviteLinkExpired => 'This invite link has expired.';

  @override
  String get inviteLinkLimit =>
      'Too many invite links today. Try again tomorrow.';

  @override
  String get inviteNotFound => 'This invite is no longer open.';

  @override
  String get invitePeopleBody =>
      'Share this invite link with someone who isn\'t on NaraaCare yet so they can join your circle.';

  @override
  String get invitePeopleTitle => 'Invite people on NaraaCare';

  @override
  String get invited => 'Invited';

  @override
  String get invitedToJoin => 'You are invited to join';

  @override
  String get invitesHeader => 'INVITES';

  @override
  String get invitesSent => 'Invites sent';

  @override
  String get joinCircle => 'Join Circle';

  @override
  String get justNow => 'Just now';

  @override
  String get lastAdmin => 'A circle needs at least one admin.';

  @override
  String get leave => 'Leave';

  @override
  String get leaveCircleBody =>
      'You will no longer be able to see this circle\'s chat or shared health updates.';

  @override
  String get leaveCircleTitle => 'Leave this circle?';

  @override
  String get makeAdmin => 'Make admin';

  @override
  String get manageMembers => 'Manage Members';

  @override
  String get maybeLater => 'Maybe Later';

  @override
  String get mealLogged => 'Meal logged';

  @override
  String get membersTitle => 'Members';

  @override
  String get mentionInvalid => 'You can only mention members of this circle.';

  @override
  String get messageDeleted => 'Message deleted';

  @override
  String get messageNotAllowed =>
      'This message contains characters that are not allowed.';

  @override
  String get more => 'More';

  @override
  String get myConnections => 'My Connections';

  @override
  String get namePicture => 'Name & Picture';

  @override
  String get next => 'Next';

  @override
  String get noConnectionsYet => 'No connections yet.';

  @override
  String get noMessagesYet => 'No messages yet. Say hello!';

  @override
  String get noNewUpdates => 'No new updates';

  @override
  String get noNotificationsYet => 'No notifications yet.';

  @override
  String get noResults => 'No one found.';

  @override
  String get noUpdatesYet => 'No updates yet today.';

  @override
  String get notifAdmin => 'You are now an admin of this circle.';

  @override
  String get notifConnectionAccepted => 'Your connection request was accepted.';

  @override
  String get notifConnectionRequest => 'You have a new connection request.';

  @override
  String get notifDeleted => 'A circle you were in was deleted.';

  @override
  String get notifGeneric => 'Circle update';

  @override
  String get notifInvite => 'You were invited to a circle.';

  @override
  String get notifMessage => 'New message in the chat.';

  @override
  String get notifRemoved => 'You were removed from this circle.';

  @override
  String get notificationSettingsTitle => 'Notification Settings';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get peopleOnNaraaCare => 'People on NaraaCare';

  @override
  String get prefAvatarUpdates => 'Avatar updates';

  @override
  String get prefAvatarUpdatesBody =>
      'Know when shared information is updated.';

  @override
  String get prefCircleUpdates => 'Circle updates';

  @override
  String get prefCircleUpdatesBody =>
      'Stay informed about important circle changes.';

  @override
  String get prefGoals => 'Goal completions';

  @override
  String get prefGoalsBody => 'Celebrate members reaching their health goals.';

  @override
  String get prefJoinLeave => 'Member joins or leaves';

  @override
  String get prefJoinLeaveBody =>
      'Get notified when members join or leave this circle.';

  @override
  String get prefMentions => 'Mentions';

  @override
  String get prefMentionsBody =>
      'Get notified if someone mentions you in chat.';

  @override
  String get prefNewMessages => 'New message';

  @override
  String get prefNewMessagesBody =>
      'Stay up to date with new messages in chats.';

  @override
  String get queryTooShort => 'Type at least 3 characters.';

  @override
  String get removeAdmin => 'Remove admin';

  @override
  String get removeFromCircle => 'Remove from circle';

  @override
  String get requestSent => 'Request sent';

  @override
  String get requested => 'Requested';

  @override
  String get results => 'RESULTS';

  @override
  String get save => 'Save';

  @override
  String get saved => 'Saved';

  @override
  String get searchByUsername => 'Search by username';

  @override
  String get selectWallpaper => 'SELECT WALLPAPER';

  @override
  String get send => 'Send';

  @override
  String get sharesInvalid => 'Share 1 to 3 avatars.';

  @override
  String get skip => 'Skip';

  @override
  String get sleepStarOnly => 'Sleep avatar is available with STAR plan';

  @override
  String get someone => 'Someone';

  @override
  String get suggestedForYou => 'SUGGESTED FOR YOU';

  @override
  String get tooManyMentions => 'A message can mention at most 20 people.';

  @override
  String get typeHere => 'Type here..';

  @override
  String get upgrade => 'Upgrade';

  @override
  String get usernameRequired => 'Please choose a username first.';

  @override
  String get viewMembers => 'View Members';

  @override
  String get whyStar => 'Why STAR?';

  @override
  String get whyStarBody =>
      'STAR members can share and view sleep insights with their care circles.';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get you => 'You';

  @override
  String get yourCircles => 'Your Circles';

  @override
  String get yourSharedAvatars => 'Your Shared Avatars';

  @override
  String daysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String feedGoalCompleted(String who, String avatar) {
    return '$who completed their $avatar goal.';
  }

  @override
  String feedJoined(String who) {
    return '$who joined the circle.';
  }

  @override
  String feedLeft(String who) {
    return '$who left the circle.';
  }

  @override
  String feedUpdated(String who, String avatar) {
    return '$who updated $avatar.';
  }

  @override
  String hoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String inviteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Invite ($count)',
      zero: 'Invite',
    );
    return '$_temp0';
  }

  @override
  String invitedBy(String name) {
    return 'Invited by $name';
  }

  @override
  String invitedCount(int count) {
    return 'INVITED ($count)';
  }

  @override
  String isTyping(String who) {
    return '$who is typing…';
  }

  @override
  String joinedDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Joined since $days days',
      one: 'Joined since 1 day',
      zero: 'Joined today',
    );
    return '$_temp0';
  }

  @override
  String leaveCircle(String name) {
    return 'Leave $name';
  }

  @override
  String leftCircle(String name) {
    return 'You left $name';
  }

  @override
  String litresValue(double litres) {
    final intl.NumberFormat litresNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String litresString = litresNumberFormat.format(litres);

    return '$litresString L';
  }

  @override
  String membersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String minutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String nextWithCount(int count) {
    return 'Next ($count)';
  }

  @override
  String notSharedAvatar(String avatar) {
    return '$avatar is not shared';
  }

  @override
  String notifGoal(String who) {
    return '$who completed their hydration goal.';
  }

  @override
  String notifJoined(String who) {
    return '$who joined the circle.';
  }

  @override
  String notifLeft(String who) {
    return '$who left the circle.';
  }

  @override
  String notifMention(String who) {
    return '$who mentioned you in the chat.';
  }

  @override
  String ofGoalLitres(double litres) {
    final intl.NumberFormat litresNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String litresString = litresNumberFormat.format(litres);

    return 'of $litresString L goal';
  }

  @override
  String shareWith(String name) {
    return 'Share with $name';
  }

  @override
  String updatesToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count updates today',
      one: '1 update today',
    );
    return '$_temp0';
  }

  @override
  String get aboutRin => 'About Rin AI';

  @override
  String get aboutRinBody =>
      'Rin is your AI health companion. It understands your health data and helps you make better choices every day.';

  @override
  String get allow => 'Allow';

  @override
  String get edit => 'Edit';

  @override
  String get less => 'Less';

  @override
  String get rinActionExpired => 'This suggestion has expired.';

  @override
  String get rinActionResolved => 'This suggestion was already handled.';

  @override
  String get rinAddQuestion => 'Should I add this to your avatar?';

  @override
  String get rinAddToAvatar => 'Add to Avatar';

  @override
  String get rinAdded => 'Added to your avatar';

  @override
  String get rinAi => 'Rin AI';

  @override
  String get rinClearMemory => 'Clear Rin\'s memory';

  @override
  String get rinConsentTitle => 'Allow Rin to use your health data?';

  @override
  String get rinConsentBody =>
      'To answer, Rin sends your own profile summary, today\'s and last week\'s totals and your question to our AI provider (Anthropic, outside India). Nothing about other people is shared. You can turn this off anytime in Settings.';

  @override
  String get rinConversations => 'CONVERSATIONS';

  @override
  String get rinDeleteChat => 'Delete Chat';

  @override
  String get rinDeleteTitle => 'Delete this chat?';

  @override
  String get rinDeleteBody =>
      'This will remove your entire conversation with Rin AI. It will not affect your avatar updates.';

  @override
  String get rinDeleted => 'Your conversation with Rin AI has been deleted.';

  @override
  String get rinDisclaimer =>
      'Rin AI is a support tool, not a substitute for professional medical advice.';

  @override
  String get rinEditTitle => 'Edit meal';

  @override
  String get rinFeatureAvatar => 'Reflect updates on your avatar.';

  @override
  String get rinFeatureChat => 'Chat & get personalized insights';

  @override
  String get rinFeatureLog => 'Log food, water & sleep by voice/text.';

  @override
  String get rinFeatureTips => 'Smart recommendations just for you.';

  @override
  String get rinHelp => 'Help';

  @override
  String get rinHelpTitle => 'Rin AI help';

  @override
  String get rinHi => 'Hi! 👋';

  @override
  String get rinIntro =>
      'I\'m Rin, your AI health companion. Ask me anything about your health, or choose a suggestion to get started.';

  @override
  String get rinLimitReached =>
      'You\'ve used this month\'s Rin allowance. It resets on the 1st of next month.';

  @override
  String get rinMemoryCleared => 'Rin\'s memory has been cleared.';

  @override
  String get rinNotAdded => 'Not added';

  @override
  String get rinResting => 'Rin is resting right now. Please try again soon.';

  @override
  String get rinSearchHint => 'Search conversations';

  @override
  String get rinSearchHistory => 'Search History';

  @override
  String get rinSearchTitle => 'Search in Rin AI';

  @override
  String get rinSuggestDinner => 'What should I eat for dinner?';

  @override
  String get rinSuggestTired => 'Why am I feeling tired?';

  @override
  String get rinSuggestToday => 'How am I doing today?';

  @override
  String get rinSuggestWater => 'How much water should I drink?';

  @override
  String get unlockRin => 'Unlock Rin AI';

  @override
  String get unlockRinBody =>
      'Your personal AI health companion. Understand your health, take guidance and take action.';

  @override
  String rinDrinkCard(String amount, String drink) {
    return 'Log $amount of $drink?';
  }

  @override
  String rinHiName(String name) {
    return 'Hi $name! 👋';
  }

  @override
  String rinMealTotals(int kcal, int protein, int carbs, int fat) {
    return 'Calories $kcal kcal · Protein $protein g · Carbs $carbs g · Fat $fat g';
  }

  @override
  String rinUsage(String pct) {
    return '$pct % used this month';
  }

  @override
  String get profileConnections => 'Connections';

  @override
  String get profileCircles => 'Care Circles';

  @override
  String get profileAvatarLabel => 'Your avatar';

  @override
  String get activeStreak => 'Active Streak';

  @override
  String get longestStreak => 'Longest Streak';

  @override
  String get streakCalendar => 'Streak calendar';

  @override
  String get streakRule =>
      'Your streak increases when you log any data (hydration, nutrition, sleep) in a day.';

  @override
  String get streakBrokenTitle => 'Oh no! Streak Broken.';

  @override
  String get streakBrokenBody =>
      'You didn\'t log any data yesterday. Don\'t worry, you can start again and keep your momentum going.';

  @override
  String streakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get activeDay => 'Active day';

  @override
  String get noData => 'No Data';

  @override
  String get previousMonth => 'Previous month';

  @override
  String get nextMonth => 'Next month';

  @override
  String get loadFailed =>
      'Couldn\'t load this. Check your connection and try again.';

  @override
  String get retry => 'Try again';

  @override
  String get done => 'Done';

  @override
  String get remove => 'Remove';

  @override
  String get todayHeader => 'TODAY';

  @override
  String get earlierHeader => 'EARLIER';

  @override
  String notifStreak(int days) {
    return 'Your streak reached $days days!';
  }

  @override
  String get notifReportReady => 'Your report is ready to download.';

  @override
  String get notifReportFailed =>
      'We couldn\'t create your report. Please try again.';

  @override
  String get downloadReport => 'Download Report';

  @override
  String get downloadReportHint => 'View & analyse your activity summary.';

  @override
  String get createNewReport => 'Create new report';

  @override
  String get monthlyReport => 'Monthly Report';

  @override
  String get monthlyReportHint => 'Get a summary of your data for any month.';

  @override
  String get customReport => 'Custom Report';

  @override
  String get customReportHint => 'Get a summary & insights for any date range.';

  @override
  String get whatsIncluded => 'What\'s included';

  @override
  String get hydrationLabel => 'Hydration';

  @override
  String get nutritionLabel => 'Nutrition';

  @override
  String get sleepLabel => 'Sleep';

  @override
  String get insightsLabel => 'Insights';

  @override
  String get reportUpsell =>
      'STAR members can choose a custom date range and get advanced health insights.';

  @override
  String get chooseMonth => 'Choose a month';

  @override
  String get chooseYear => 'Choose a year';

  @override
  String get reportNoData =>
      'Log water, food or sleep first. A report needs at least one day with data.';

  @override
  String get createReport => 'Create report';

  @override
  String get yourReports => 'Your reports (kept for 7 days)';

  @override
  String get reportReady => 'Ready';

  @override
  String get reportFailed => 'Failed';

  @override
  String get reportExpired => 'Expired';

  @override
  String get reportPreparing => 'Preparing…';

  @override
  String get customizeReport => 'Customize Report';

  @override
  String get selectDateRange => 'Select Date Range';

  @override
  String get last7Days => 'Last 7 days';

  @override
  String get last30Days => 'Last 30 days';

  @override
  String get last3Months => 'Last 3 months';

  @override
  String get last6Months => 'Last 6 months';

  @override
  String get thisYear => 'This Year';

  @override
  String get fromLabel => 'From';

  @override
  String get toLabel => 'To';

  @override
  String get enterStartDate => 'Enter start date';

  @override
  String get enterEndDate => 'Enter end date';

  @override
  String get whatToInclude => 'What do you want to include?';

  @override
  String get generateReport => 'Generate Report';

  @override
  String get reportPreview => 'Report Preview';

  @override
  String get reportSummary => 'Report Summary';

  @override
  String reportPeriod(String from, String to, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$from - $to ($_temp0)';
  }

  @override
  String reportTitle(String sections) {
    return '$sections Report';
  }

  @override
  String get reportIncludes =>
      'Report will include overall metrics, daily averages, trends and insights.';

  @override
  String get reportPreparingLong =>
      'We\'re preparing your report. This usually takes a few seconds.';

  @override
  String get reportSlow =>
      'This is taking longer than usual. You can leave this screen; we\'ll notify you when your report is ready.';

  @override
  String get reportFailedLong =>
      'We couldn\'t create this report. Please create it again.';

  @override
  String get shareReport => 'Share report';

  @override
  String get reportDownloaded => 'Report Downloaded';

  @override
  String get reportSavedBody =>
      'Your report is saved in the app. Use Share to save a copy to your phone\'s files.';

  @override
  String get reportSavedDownloads =>
      'Saved to Downloads › NaraaCare on your phone. You can open it from the Files app.';

  @override
  String get reportSavedFiles =>
      'Saved on your iPhone. Open the Files app › On My iPhone › NaraaCare › reports.';

  @override
  String reportSize(String kb) {
    return 'Size: $kb KB';
  }

  @override
  String get reportSaveFailed => 'Couldn\'t save the report on this device.';

  @override
  String get reportLimitReached =>
      'You can create 10 reports a day. Try again tomorrow.';

  @override
  String get reportRangeInvalid =>
      'Choose dates up to today, at most 366 days apart.';

  @override
  String get reportNeedsStar => 'This report option is part of STAR.';

  @override
  String get reportNeedsAiConsent =>
      'Insights need your consent to AI processing. Your report was made without them.';

  @override
  String get faqs => 'FAQs';

  @override
  String get faqsLong => 'Frequently Asked Questions';

  @override
  String get contactSupport => 'Contact Support';

  @override
  String get reportProblem => 'Report a Problem';

  @override
  String get requestFeature => 'Request a Feature';

  @override
  String get gettingStartedGuide => 'Getting started guide';

  @override
  String get guide => 'Guide';

  @override
  String get searchQuestions => 'Search questions';

  @override
  String get noFaqMatch => 'No questions match your search.';

  @override
  String get emailSupport => 'Email Support';

  @override
  String get emailSupportBody => 'Detailed inquiries & feedback.';

  @override
  String get sendAnEmail => 'Send an email';

  @override
  String get callUs => 'Call Us';

  @override
  String get callUsBody => 'Direct support for urgent issues.';

  @override
  String get callUsStarOnly => 'Phone support is available with the STAR plan.';

  @override
  String get couldNotOpenApp => 'Couldn\'t open an app for this.';

  @override
  String get issueCategory => 'ISSUE CATEGORY';

  @override
  String get catAppCrash => 'App Crash';

  @override
  String get catDataSync => 'Data Sync';

  @override
  String get catBilling => 'Billing';

  @override
  String get catDeviceLink => 'Device Link';

  @override
  String get catAccount => 'Account';

  @override
  String get catOther => 'Other';

  @override
  String get problemDescription => 'PROBLEM DESCRIPTION';

  @override
  String get tellUsWhatHappened => 'Tell us what happened...';

  @override
  String get uploadScreenshotOptional => 'UPLOAD SCREENSHOT (OPTIONAL)';

  @override
  String get tapToUpload => 'Tap to upload an image';

  @override
  String get uploadLimits => 'PNG, JPG up to 10 MB';

  @override
  String get screenshotAttached => 'Screenshot attached';

  @override
  String get uploadInvalid => 'Upload a PNG or JPG image up to 10 MB.';

  @override
  String get submitReport => 'Submit Report';

  @override
  String get responseTime => 'Estimated response time: < 24 hours';

  @override
  String ticketSent(String ref) {
    return 'Thanks! Your report $ref was sent.';
  }

  @override
  String get supportLimitReached =>
      'You\'ve sent 5 requests today. Try again tomorrow.';

  @override
  String get whatShouldWeAdd => 'What should we add?';

  @override
  String get featureTitleHint => 'eg: new sleep tracking method';

  @override
  String get howWouldThisHelp => 'How would this help you?';

  @override
  String get sendRequest => 'Send Request';

  @override
  String get featureRequestNote =>
      'Our product team reviews every suggestion. Thank you for helping us grow.';

  @override
  String get featureRequestSent => 'Thanks! Your suggestion was sent.';

  @override
  String get guideWaterTitle => 'Log your drinks';

  @override
  String get guideWaterBody =>
      'Swipe up on the Home avatar or tap Add Water/Drink. The avatar fills as you get closer to your daily need.';

  @override
  String get guideMealTitle => 'Add your meals';

  @override
  String get guideMealBody =>
      'Search for foods, scan a barcode or say what you ate. Your calories and nutrients add up through the day.';

  @override
  String get guideSleepTitle => 'Track your sleep (STAR)';

  @override
  String get guideSleepBody =>
      'Log when you went to bed and woke up to see your sleep score.';

  @override
  String get guideStreakTitle => 'Keep your streak';

  @override
  String get guideStreakBody =>
      'Log anything each day to grow your streak. Find it on your Profile.';

  @override
  String get guideCircleTitle => 'Join a Care Circle';

  @override
  String get guideCircleBody =>
      'Share your avatars with family and friends and cheer each other on.';

  @override
  String get guideReportTitle => 'Download reports';

  @override
  String get guideReportBody =>
      'Get a monthly PDF of your progress from Active Streak > Download report.';

  @override
  String get syncConflictBanner =>
      'An entry was changed on another device. Showing the latest saved version.';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get privacyCentre => 'Privacy';

  @override
  String get privacyCentreIntro =>
      'See what you have agreed to, change optional choices, download your data or delete your account.';

  @override
  String get consentsRequiredHeader => 'NEEDED TO USE NARAACARE';

  @override
  String get consentsOptionalHeader => 'YOUR CHOICES';

  @override
  String get yourDataHeader => 'YOUR DATA';

  @override
  String get requiredLabel => 'Required';

  @override
  String consentRecorded(String version, String date) {
    return 'Accepted version $version on $date';
  }

  @override
  String get consentRequiredExplain =>
      'These are needed for the app to work. To stop them, delete your account.';

  @override
  String get consentGranted => 'Saved. Thank you.';

  @override
  String get consentWithdrawn => 'Withdrawn. This takes effect right away.';

  @override
  String get purposeHealthData => 'Health data';

  @override
  String get purposeHealthDataBody =>
      'Your health logs and profile are used to work out your targets and fill your avatars.';

  @override
  String get purposeRequiredBody =>
      'The rules for using NaraaCare and how we handle your data.';

  @override
  String get purposeAi => 'AI processing (Rin AI)';

  @override
  String get purposeAiBody =>
      'Lets Rin AI, drink estimates and report insights send your own data to our AI provider. Turning it off stops these at once.';

  @override
  String get purposeCircleSharing => 'Care Circle sharing';

  @override
  String get purposeCircleSharingBody =>
      'Lets you share the avatars you choose with your Care Circles.';

  @override
  String get purposeMarketing => 'News and offers';

  @override
  String get purposeMarketingBody =>
      'Occasional emails about new features and offers.';

  @override
  String get downloadMyData => 'Download my data';

  @override
  String get privacyNotice => 'Privacy notice';

  @override
  String get exportIntro =>
      'Get a copy of all the personal data NaraaCare keeps about you, as a ZIP file you can open on a computer.';

  @override
  String get exportWhatsIncluded =>
      'Included: your profile, health logs, goals, Care Circles and messages, Rin AI chats, reports, payments and consents, as JSON and spreadsheet (CSV) files. Passwords and sign-in secrets are never included.';

  @override
  String get requestExport => 'Request my data';

  @override
  String get exportPreparing =>
      'We\'re preparing your file. You can leave this screen; we\'ll notify you when it\'s ready.';

  @override
  String exportReady(String date) {
    return 'Your file is ready until $date.';
  }

  @override
  String get downloadAndShare => 'Download and share';

  @override
  String get exportLimitNote =>
      'You can ask for one copy a day. The file is kept for 7 days.';

  @override
  String get exportLimitReached =>
      'You can request one data export a day. Try again tomorrow.';

  @override
  String get reauthTitle => 'Confirm it\'s you';

  @override
  String get reauthPasswordBody => 'Enter your password to continue.';

  @override
  String get reauthCodeBody =>
      'We emailed you a 6-digit code. Enter it to continue.';

  @override
  String get reauthCodeLabel => 'Code';

  @override
  String get reauthUseCode => 'No password? Email me a code';

  @override
  String get reauthResend => 'Send a new code';

  @override
  String get reauthCodeSent => 'Code sent to your email.';

  @override
  String get reauthWrongPassword => 'That password is not correct.';

  @override
  String get continueLabel => 'Continue';

  @override
  String get okLabel => 'OK';

  @override
  String get deleteAccountIntro => 'Deleting your account is permanent.';

  @override
  String get deleteWhatGoes =>
      'Your profile, health logs, avatars, Care Circle memberships, messages, Rin AI chats, reports and files will be erased.';

  @override
  String get deleteGrace =>
      'You have 30 days to change your mind: sign in again and tap Cancel deletion.';

  @override
  String get deleteKept =>
      'As the law requires, a record of your consents and store payments is kept for up to 8 years, without your name, email or account id.';

  @override
  String get deleteSignedOut =>
      'You will be signed out on all your devices straight away.';

  @override
  String get deleteSubscriptionWarning =>
      'Deleting your account does not cancel a STAR subscription. Cancel it in Google Play or the App Store first.';

  @override
  String get manageSubscription => 'Manage subscription';

  @override
  String get deleteConfirmCheck =>
      'I understand my account and data will be deleted after 30 days.';

  @override
  String get deleteAccountButton => 'Delete my account';

  @override
  String get deletionScheduledTitle => 'Deletion scheduled';

  @override
  String deletionScheduledBody(String date) {
    return 'Your account will be deleted on $date. We\'ve emailed you. Sign in before then if you change your mind.';
  }

  @override
  String get deletionPendingTitle => 'Your account is scheduled for deletion';

  @override
  String deletionPendingBody(String date) {
    return 'It will be permanently deleted on $date. Do you want to keep it?';
  }

  @override
  String get cancelDeletion => 'Cancel deletion';

  @override
  String get keepDeletionSignOut => 'Keep deletion and sign out';

  @override
  String get deletionCancelled => 'Deletion cancelled. Welcome back!';

  @override
  String get reconsentTitle => 'We\'ve updated our policies';

  @override
  String get reconsentBody =>
      'Please read and accept the new versions to keep using NaraaCare.';

  @override
  String get acceptAndContinue => 'Accept and continue';

  @override
  String get readFullPolicy => 'Read the full Privacy Policy';

  @override
  String get noticeCollectTitle => 'What we collect';

  @override
  String get noticeCollectBody =>
      'Your name, email and username; your age, sex, height, weight, activity level, goals and any health conditions you choose to add; what you log (drinks, meals, workouts, sleep); your Care Circle messages and Rin AI chats; and basic device information needed to sign you in and send notifications.';

  @override
  String get noticeWhyTitle => 'Why we use it';

  @override
  String get noticeWhyBody =>
      'To work out your daily targets, show your progress, run Care Circles and Rin AI, keep your account secure, and handle your subscription. We never sell your data or use it for advertising.';

  @override
  String get noticeNotCollectTitle => 'What we don\'t collect';

  @override
  String get noticeNotCollectBody =>
      'No phone number, date of birth, precise location, contacts, photos (except a screenshot you choose to send to support) or data from other apps.';

  @override
  String get noticeProcessorsTitle => 'Who helps us';

  @override
  String get noticeProcessorsBody =>
      'Our hosting and email providers; Google and Apple for sign-in, payments and notifications; and Anthropic, our AI provider for Rin AI, only if you turn on AI processing. They may only use your data to provide their service to us.';

  @override
  String get noticeRetentionTitle => 'How long we keep it';

  @override
  String get noticeRetentionBody =>
      'Your health data stays while you have an account and is erased 30 days after you ask us to delete it. Security logs are kept for up to 1 year, inactive Rin AI chats for 12 months, and consent and payment records (without your identity) for up to 8 years.';

  @override
  String get noticeRightsTitle => 'Your rights';

  @override
  String get noticeRightsBody =>
      'You can see and correct your data in the app, download a copy, withdraw optional consents at any time, and delete your account. Under India\'s Digital Personal Data Protection Act you can also raise a grievance with us and, if not resolved, with the Data Protection Board of India.';

  @override
  String get noticeGrievanceTitle => 'Grievance contact';

  @override
  String noticeGrievanceBody(String contact) {
    return 'Write to $contact. We reply within 7 days.';
  }

  @override
  String get noticeGrievancePending => 'our support team (Help & Support)';

  @override
  String shareAvatarTitle(String avatar) {
    return 'Share your $avatar avatar';
  }

  @override
  String get shareAvatarHint =>
      'Only people in NaraaCare see it. Today\'s progress is shared, nothing else.';

  @override
  String get shareAvatarNobody =>
      'Join a Care Circle or connect with someone to share your avatar.';

  @override
  String get shareToCircles => 'Your circles';

  @override
  String get shareToConnections => 'Connections';

  @override
  String get shareSend => 'Share';

  @override
  String get avatarShared => 'Shared';

  @override
  String feedShared(String who, String avatar) {
    return '$who shared their $avatar avatar.';
  }

  @override
  String notifAvatarShared(String who, String avatar) {
    return '$who shared their $avatar avatar with you.';
  }

  @override
  String notifCircleAvatarShared(String who, String avatar) {
    return '$who shared their $avatar avatar in your circle.';
  }

  @override
  String sharedProgress(int value) {
    return '$value % of today\'s goal';
  }
}
