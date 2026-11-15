/// Route paths (doc 02 section 2.0).
abstract final class Routes {
  static const splash = '/splash';
  static const intro = '/intro';
  static const welcome = '/welcome';

  // Sign up (A3-A4). Email Verified (A5) is shown once signed in, inside the
  // onboarding area.
  static const signUp = '/sign-up';
  static const verifyEmail = '/sign-up/verify';

  static const signIn = '/sign-in';

  // Forgot password (A7-A10).
  static const forgotPassword = '/forgot-password';
  static const resetCode = '/forgot-password/code';
  static const newPassword = '/forgot-password/new';
  static const passwordChanged = '/forgot-password/done';

  // Onboarding (O0-O7). Steps are `/onboarding/step/1` .. `/6`.
  static const onboarding = '/onboarding';
  static const emailVerified = '/onboarding/verified';
  static const onboardingResult = '/onboarding/result';
  static const onboardingGenerating = '/onboarding/generating';
  static const onboardingSaved = '/onboarding/saved';
  static String onboardingStep(int step) => '/onboarding/step/$step';

  static const home = '/home';

  // Nutrition (N3-N10) under the Home tab.
  static const addMeal = '/home/nutrition/add';
  static const mealSummary = '/home/nutrition/summary';
  static const recentMeals = '/home/nutrition/recent';
  static const editMeal = '/home/nutrition/edit';
  static const voiceMeal = '/home/nutrition/voice';
  static const barcodeMeal = '/home/nutrition/barcode';

  // Hydration (H5) under the Home tab.
  static const recentIntakes = '/home/hydration/recent';

  // Sleep (S10, STAR) under the Home tab.
  static const updateSleep = '/home/sleep/update';
  static const careCircle = '/care-circle';

  // Care Circles (S12) under the Care Circle tab.
  static const createCircle = '/care-circle/new';
  static const createCircleMembers = '/care-circle/new/members';
  static const createCircleShares = '/care-circle/new/share';
  static String circleInviteDetail(String id) => '/care-circle/invites/$id';
  static String circleInviteAccept(String id) =>
      '/care-circle/invites/$id/share';
  static String circle(String id) => '/care-circle/c/$id';
  static String circleChat(String id) => '/care-circle/c/$id/chat';
  static String circleFeed(String id) => '/care-circle/c/$id/feed';
  static String circleMembers(String id) => '/care-circle/c/$id/members';
  static String circleMember(String id, String userId) =>
      '/care-circle/c/$id/members/$userId';
  static String circleAddMembers(String id) => '/care-circle/c/$id/add';
  static String circleNotifications(String id) =>
      '/care-circle/c/$id/notifications';
  static String circleSettings(String id) => '/care-circle/c/$id/settings';
  static String circleNotificationSettings(String id) =>
      '/care-circle/c/$id/settings/notifications';
  static String circleProfile(String id) =>
      '/care-circle/c/$id/settings/profile';
  static String circleShares(String id) => '/care-circle/c/$id/settings/share';
  static const rinAi = '/rin-ai';

  // Rin AI (S13) under the Rin AI tab.
  static const rinSearch = '/rin-ai/search';
  static const rinHelp = '/rin-ai/help';
  static String rinConversation(String id) => '/rin-ai/c/$id';
  static const profile = '/profile';

  // Settings (ST1-ST4) live under the Profile tab.
  static const settings = '/profile/settings';
  static const editProfile = '/profile/settings/edit';
  static const username = '/profile/settings/username';
  static const account = '/profile/settings/account';
  static const changePassword = '/profile/settings/account/password';
  static const notificationSettings = '/profile/settings/notifications';

  // Subscriptions and referral (S11).
  static const subscriptions = '/profile/settings/subscriptions';
  static const purchaseSuccess = '/profile/settings/subscriptions/success';
  static const billingHistory = '/profile/settings/subscriptions/history';
  static const cancelSubscription = '/profile/settings/subscriptions/cancel';
  static const subscriptionCancelled =
      '/profile/settings/subscriptions/cancelled';
  static String upgradeToStar({required bool yearly}) =>
      '/profile/settings/subscriptions/upgrade?cycle=${yearly ? 'yearly' : 'monthly'}';
  static const referFriends = '/profile/settings/refer';

  // Connections (S12, Figma "Profile/ Connections").
  static const connections = '/profile/connections';

  // Profile tab (S14): notifications, streak, reports, help & support.
  static const myNotifications = '/profile/notifications';
  static const streak = '/profile/streak';
  static const streakCalendar = '/profile/streak/calendar';
  static const reports = '/profile/reports';
  static const customReport = '/profile/reports/custom';
  static String reportPreview(String id) => '/profile/reports/r/$id';
  static String reportDownloaded(String id, {bool inDownloads = false}) =>
      '/profile/reports/r/$id/saved${inDownloads ? '?in=downloads' : ''}';
  static const help = '/profile/settings/help';
  static const faqs = '/profile/settings/help/faqs';
  static const contactSupport = '/profile/settings/help/contact';
  static const reportProblem = '/profile/settings/help/problem';
  static const requestFeature = '/profile/settings/help/feature';
  static const guide = '/profile/settings/help/guide';

  // Privacy (S15): centre, export, notice, delete; launch-time takeovers.
  static const privacyCentre = '/profile/settings/privacy';
  static const dataExport = '/profile/settings/privacy/export';
  static const privacyNotice = '/profile/settings/privacy/notice';
  static const deleteAccount = '/profile/settings/account/delete';
  static const deletionScheduled = '/account-deletion';
  static const reconsent = '/policy-update';

  static const invite = '/invite';
  static const circleInvite = '/circle';

  /// Reachable while signed out (Welcome and the sign-in/up flows, with
  /// their sub-pages).
  static const Set<String> signedOutPaths = {
    welcome,
    // Welcome's Get Started opens the intro slides, then Sign Up (owner).
    intro,
    signUp,
    signIn,
    forgotPassword,
    // S11: an invite link must open before sign-up to keep the code.
    invite,
  };

  /// The four tabs of the main app.
  static const List<String> tabs = [home, careCircle, rinAi, profile];
}
