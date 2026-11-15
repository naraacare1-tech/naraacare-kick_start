import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/session/auth_controller.dart';

/// Where the app must go for an auth state, or null to stay (doc 02 2.0):
///
/// ```text
/// unknown      -> splash
/// introNeeded  -> intro slides (first install only)
/// signedOut    -> Welcome / Sign up / Sign in / Forgot password
/// onboarding   -> onboarding (resume step)
/// signedIn     -> the 4-tab app; leaving splash/intro/auth goes Home
/// ```
///
/// Invite and circle links wait until the user is signed in and onboarded;
/// the link is kept by the caller and opened afterwards (Session 12).
///
/// [onboardingEntry] is where a newly signed-in user lands inside onboarding
/// (Email Verified after sign-up, else the onboarding start).
String? authRedirect(
  AuthStatus status,
  String location, {
  String onboardingEntry = Routes.onboarding,
  bool holdSplash = false,
}) {
  final path = Uri.parse(location).path;
  bool at(String route) => path == route || path.startsWith('$route/');
  // The splash animation plays in full before anything else opens.
  if (holdSplash && at(Routes.splash)) return null;

  switch (status) {
    case AuthStatus.unknown:
      return at(Routes.splash) ? null : Routes.splash;
    case AuthStatus.introNeeded:
      // An invite link on a fresh install keeps its code first (S11).
      return at(Routes.intro) || at(Routes.invite) ? null : Routes.intro;
    case AuthStatus.signedOut:
      return Routes.signedOutPaths.any(at) ? null : Routes.welcome;
    case AuthStatus.onboarding:
      return at(Routes.onboarding) ? null : onboardingEntry;
    case AuthStatus.signedIn:
      final inApp =
          Routes.tabs.any(at) ||
          at(Routes.invite) ||
          at(Routes.circleInvite) ||
          at(Routes.deletionScheduled) ||
          at(Routes.reconsent);
      return inApp ? null : Routes.home;
  }
}

/// Social features need a username (doc 04 403 USERNAME_REQUIRED): screens
/// call this before navigating and show the username sheet when it fails.
bool hasUsername(String? username) => username != null && username.isNotEmpty;

/// STAR-only features: the UI hides or locks them, the API enforces them.
bool hasFeature(Map<String, bool> features, String feature) =>
    features[feature] ?? false;
