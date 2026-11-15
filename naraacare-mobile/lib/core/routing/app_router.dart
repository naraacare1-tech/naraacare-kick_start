import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/routing/guards.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/routing/splash_screen.dart';
import 'package:naraacare/core/security/deep_link_validator.dart';
import 'package:naraacare/core/session/auth_controller.dart';
import 'package:naraacare/features/auth/presentation/auth_args.dart';
import 'package:naraacare/features/auth/presentation/screens/code_entry_screen.dart';
import 'package:naraacare/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:naraacare/features/auth/presentation/screens/new_password_screen.dart';
import 'package:naraacare/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:naraacare/features/auth/presentation/screens/sign_up_screen.dart';
import 'package:naraacare/features/auth/presentation/screens/welcome_screen.dart';
import 'package:naraacare/features/care_circle/circle_providers.dart';
import 'package:naraacare/features/care_circle/presentation/circle_chat_screen.dart';
import 'package:naraacare/features/care_circle/presentation/circle_home_screen.dart';
import 'package:naraacare/features/care_circle/presentation/circle_members_screens.dart';
import 'package:naraacare/features/care_circle/presentation/circle_settings_screens.dart';
import 'package:naraacare/features/care_circle/presentation/connections_screen.dart';
import 'package:naraacare/features/care_circle/presentation/create_circle_screens.dart';
import 'package:naraacare/features/care_circle/presentation/invite_screens.dart';
import 'package:naraacare/features/care_circle/presentation/your_circles_screen.dart';
import 'package:naraacare/features/home/presentation/home_screen.dart';
import 'package:naraacare/features/hydration/presentation/recent_intakes_screen.dart';
import 'package:naraacare/features/notifications/data/local_reminders.dart';
import 'package:naraacare/features/notifications/presentation/notification_settings_screen.dart';
import 'package:naraacare/features/nutrition/data/nutrition_models.dart';
import 'package:naraacare/features/nutrition/presentation/screens/add_meal_screen.dart';
import 'package:naraacare/features/nutrition/presentation/screens/meal_screens.dart';
import 'package:naraacare/features/nutrition/presentation/screens/voice_barcode_screens.dart';
import 'package:naraacare/features/onboarding/presentation/screens/completion_screens.dart';
import 'package:naraacare/features/onboarding/presentation/screens/intro_screen.dart';
import 'package:naraacare/features/onboarding/presentation/screens/onboarding_start_screen.dart';
import 'package:naraacare/features/onboarding/presentation/screens/result_screen.dart';
import 'package:naraacare/features/onboarding/presentation/screens/step1_identity_screen.dart';
import 'package:naraacare/features/onboarding/presentation/screens/step2_height_screen.dart';
import 'package:naraacare/features/onboarding/presentation/screens/step3_weight_goal_screen.dart';
import 'package:naraacare/features/onboarding/presentation/screens/step4_target_conditions_screen.dart';
import 'package:naraacare/features/onboarding/presentation/screens/step5_age_activity_screen.dart';
import 'package:naraacare/features/onboarding/presentation/screens/step6_body_type_screen.dart';
import 'package:naraacare/features/privacy/presentation/privacy_screens.dart';
import 'package:naraacare/features/profile/presentation/my_notifications_screen.dart';
import 'package:naraacare/features/profile/presentation/profile_tab_screen.dart';
import 'package:naraacare/features/profile/presentation/report_screens.dart';
import 'package:naraacare/features/profile/presentation/streak_screens.dart';
import 'package:naraacare/features/profile/presentation/support_screens.dart';
import 'package:naraacare/features/rin_ai/presentation/rin_screens.dart';
import 'package:naraacare/features/settings/presentation/screens/account_screens.dart';
import 'package:naraacare/features/settings/presentation/screens/edit_profile_screen.dart';
import 'package:naraacare/features/settings/presentation/screens/settings_screen.dart';
import 'package:naraacare/features/sleep/data/sleep_data.dart';
import 'package:naraacare/features/sleep/presentation/sleep_screens.dart';
import 'package:naraacare/features/subscriptions/presentation/invite_screen.dart';
import 'package:naraacare/features/subscriptions/presentation/subscription_screens.dart';
import 'package:naraacare/shared/widgets/nc_bottom_nav.dart';

/// Report ids in routes must be UUIDs (anything else goes back to Reports).
final _uuid = RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$');

/// The app's router (go_router). Redirects follow [authRedirect]; the auth
/// controller is the refresh listenable, so a sign-in or a revoked session
/// re-routes immediately. Deep links (`/invite/<code>`, `/circle/<token>`)
/// are validated again here, whatever opened them (doc 07 SEC-5.8).
///
/// Screens that need in-memory arguments (`extra`) go back to the start of
/// their flow when opened without them (e.g. after the app was killed).
GoRouter buildRouter(AuthController auth, {String? initialLocation}) {
  GoRoute withArgs<T>(
    String path,
    String fallback,
    Widget Function(T args) builder,
  ) => GoRoute(
    path: path,
    redirect: (context, state) => state.extra is T ? null : fallback,
    builder: (context, state) => builder(state.extra! as T),
  );

  return GoRouter(
    initialLocation: initialLocation ?? Routes.splash,
    refreshListenable: auth,
    redirect: (context, state) => authRedirect(
      auth.status,
      state.uri.toString(),
      onboardingEntry: auth.onboardingEntry,
      holdSplash: !auth.splashDone,
    ),
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) =>
            SplashScreen(onStart: auth.start, onFinished: auth.finishSplash),
      ),
      GoRoute(
        path: Routes.intro,
        // Figma: Splash -> Onboarding 1-3 -> Sign Up. Get Started (or Skip)
        // records intro_seen and opens Sign Up; from Welcome, Back returns
        // to Welcome.
        builder: (context, state) => IntroScreen(
          onDone: () async {
            await auth.introCompleted();
            if (!context.mounted) return;
            if (context.canPop()) {
              context.pushReplacement(Routes.signUp);
            } else {
              context.go(Routes.signUp);
            }
          },
        ),
      ),
      GoRoute(
        path: Routes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: Routes.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      withArgs<CodeArgs>(
        Routes.verifyEmail,
        Routes.signUp,
        (args) => CodeEntryScreen(purpose: CodePurpose.verifyEmail, args: args),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      withArgs<CodeArgs>(
        Routes.resetCode,
        Routes.forgotPassword,
        (args) =>
            CodeEntryScreen(purpose: CodePurpose.resetPassword, args: args),
      ),
      withArgs<NewPasswordArgs>(
        Routes.newPassword,
        Routes.forgotPassword,
        (args) => NewPasswordScreen(args: args),
      ),
      GoRoute(
        path: Routes.passwordChanged,
        builder: (context, state) => const PasswordChangedScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingStartScreen(),
      ),
      GoRoute(
        path: Routes.emailVerified,
        builder: (context, state) => const EmailVerifiedScreen(),
      ),
      GoRoute(
        path: '${Routes.onboarding}/step/:n',
        redirect: (context, state) {
          final n = int.tryParse(state.pathParameters['n'] ?? '');
          return n != null && n >= 1 && n <= 6 ? null : Routes.onboarding;
        },
        builder: (context, state) =>
            switch (int.parse(state.pathParameters['n']!)) {
              1 => const Step1IdentityScreen(),
              2 => const Step2HeightScreen(),
              3 => const Step3WeightGoalScreen(),
              4 => const Step4TargetConditionsScreen(),
              5 => const Step5AgeActivityScreen(),
              _ => const Step6BodyTypeScreen(),
            },
      ),
      GoRoute(
        path: Routes.onboardingResult,
        builder: (context, state) => const ResultScreen(),
      ),
      withArgs<List<Map<String, Object?>>>(
        Routes.onboardingGenerating,
        Routes.onboardingResult,
        (consents) => GeneratingScreen(consents: consents),
      ),
      GoRoute(
        path: Routes.onboardingSaved,
        builder: (context, state) => const SavedScreen(),
      ),
      GoRoute(
        path: '${Routes.invite}/:code',
        redirect: (context, state) =>
            DeepLinkValidator.isInviteCode(state.pathParameters['code'] ?? '')
            ? null
            : Routes.home,
        builder: (context, state) =>
            InviteScreen(code: state.pathParameters['code']!.toUpperCase()),
      ),
      GoRoute(
        path: '${Routes.circleInvite}/:token',
        redirect: (context, state) =>
            DeepLinkValidator.isCircleToken(state.pathParameters['token'] ?? '')
            ? null
            : Routes.home,
        builder: (context, state) =>
            CircleLinkScreen(token: state.pathParameters['token']!),
      ),
      // S15: shown at launch before the tabs (no bottom bar, no back).
      GoRoute(
        path: Routes.deletionScheduled,
        builder: (context, state) => const DeletionScheduledScreen(),
      ),
      GoRoute(
        path: Routes.reconsent,
        builder: (context, state) => const ReconsentScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => Scaffold(
          // Signed in: mirror the user's reminders on the phone once per
          // app start (local reminders, step 1).
          body: LocalReminderSync(child: shell),
          bottomNavigationBar: NcBottomNav(
            currentIndex: shell.currentIndex,
            onTap: (i) =>
                shell.goBranch(i, initialLocation: i == shell.currentIndex),
          ),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'nutrition/add',
                    builder: (context, state) => const AddMealScreen(),
                  ),
                  GoRoute(
                    path: 'nutrition/summary',
                    builder: (context, state) => const MealSummaryScreen(),
                  ),
                  GoRoute(
                    path: 'nutrition/recent',
                    builder: (context, state) => const RecentMealsScreen(),
                  ),
                  GoRoute(
                    path: 'nutrition/edit',
                    redirect: (context, state) =>
                        state.extra is Meal ? null : Routes.recentMeals,
                    builder: (context, state) =>
                        EditMealScreen(meal: state.extra! as Meal),
                  ),
                  GoRoute(
                    path: 'nutrition/voice',
                    builder: (context, state) => const VoiceMealScreen(),
                  ),
                  GoRoute(
                    path: 'sleep/update',
                    builder: (context, state) => UpdateSleepScreen(
                      entry: state.extra is SleepEntry
                          ? state.extra! as SleepEntry
                          : null,
                    ),
                  ),
                  GoRoute(
                    path: 'hydration/recent',
                    builder: (context, state) => const RecentIntakesScreen(),
                  ),
                  GoRoute(
                    path: 'nutrition/barcode',
                    builder: (context, state) => BarcodeMealScreen(
                      initialCode: state.extra is String
                          ? state.extra! as String
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(routes: [_careCircleRoutes()]),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.rinAi,
                builder: (context, state) => const RinTabScreen(),
                routes: [
                  GoRoute(
                    path: 'search',
                    builder: (context, state) => const RinSearchScreen(),
                  ),
                  GoRoute(
                    path: 'help',
                    builder: (context, state) => const RinHelpScreen(),
                  ),
                  GoRoute(
                    path: 'c/:id',
                    builder: (context, state) =>
                        RinChatScreen(conversationId: _id(state)),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (context, state) => const ProfileTabScreen(),
                routes: [
                  GoRoute(
                    path: 'connections',
                    builder: (context, state) => const ConnectionsScreen(),
                  ),
                  GoRoute(
                    path: 'notifications',
                    builder: (context, state) => const MyNotificationsScreen(),
                  ),
                  GoRoute(
                    path: 'streak',
                    builder: (context, state) => const ActiveStreakScreen(),
                    routes: [
                      GoRoute(
                        path: 'calendar',
                        builder: (context, state) =>
                            const StreakCalendarScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'reports',
                    builder: (context, state) => const DownloadReportScreen(),
                    routes: [
                      GoRoute(
                        path: 'custom',
                        builder: (context, state) =>
                            const CustomizeReportScreen(),
                      ),
                      GoRoute(
                        path: 'r/:reportId',
                        redirect: (context, state) =>
                            _uuid.hasMatch(
                              state.pathParameters['reportId'] ?? '',
                            )
                            ? null
                            : Routes.reports,
                        builder: (context, state) => ReportPreviewScreen(
                          reportId: state.pathParameters['reportId']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'saved',
                            builder: (context, state) => ReportDownloadedScreen(
                              reportId: state.pathParameters['reportId']!,
                              inDownloads:
                                  state.uri.queryParameters['in'] ==
                                  'downloads',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'settings',
                    builder: (context, state) => const SettingsScreen(),
                    routes: [
                      GoRoute(
                        path: 'privacy',
                        builder: (context, state) =>
                            const PrivacyCentreScreen(),
                        routes: [
                          GoRoute(
                            path: 'export',
                            builder: (context, state) =>
                                const DataExportScreen(),
                          ),
                          GoRoute(
                            path: 'notice',
                            builder: (context, state) =>
                                const PrivacyNoticeScreen(),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'help',
                        builder: (context, state) => const HelpSupportScreen(),
                        routes: [
                          GoRoute(
                            path: 'faqs',
                            builder: (context, state) => const FaqsScreen(),
                          ),
                          GoRoute(
                            path: 'contact',
                            builder: (context, state) =>
                                const ContactSupportScreen(),
                          ),
                          GoRoute(
                            path: 'problem',
                            builder: (context, state) =>
                                const ReportProblemScreen(),
                          ),
                          GoRoute(
                            path: 'feature',
                            builder: (context, state) =>
                                const RequestFeatureScreen(),
                          ),
                          GoRoute(
                            path: 'guide',
                            builder: (context, state) => const GuideScreen(),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'edit',
                        builder: (context, state) => const EditProfileScreen(),
                      ),
                      GoRoute(
                        path: 'subscriptions',
                        builder: (context, state) => const SubscriptionScreen(),
                        routes: [
                          GoRoute(
                            path: 'success',
                            builder: (context, state) =>
                                const PurchaseSuccessScreen(),
                          ),
                          GoRoute(
                            path: 'history',
                            builder: (context, state) =>
                                const BillingHistoryScreen(),
                          ),
                          GoRoute(
                            path: 'upgrade',
                            builder: (context, state) => UpgradeScreen(
                              yearly:
                                  state.uri.queryParameters['cycle'] ==
                                  'yearly',
                            ),
                          ),
                          GoRoute(
                            path: 'cancel',
                            builder: (context, state) =>
                                const CancelSubscriptionScreen(),
                          ),
                          GoRoute(
                            path: 'cancelled',
                            builder: (context, state) =>
                                const SubscriptionCancelledScreen(),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'refer',
                        builder: (context, state) => const ReferFriendsScreen(),
                      ),
                      GoRoute(
                        path: 'notifications',
                        builder: (context, state) =>
                            const NotificationSettingsScreen(),
                      ),
                      GoRoute(
                        path: 'username',
                        builder: (context, state) => const UsernameScreen(),
                      ),
                      GoRoute(
                        path: 'account',
                        builder: (context, state) => const AccountScreen(),
                        routes: [
                          GoRoute(
                            path: 'password',
                            builder: (context, state) =>
                                const ChangePasswordScreen(),
                          ),
                          GoRoute(
                            path: 'delete',
                            builder: (context, state) =>
                                const DeleteAccountScreen(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

String _id(GoRouterState state) => state.pathParameters['id']!;

/// The Care Circle tab (S12). Every circle route takes the id from the path;
/// the API answers 404 to non-members, which the screens show as "not
/// available".
GoRoute _careCircleRoutes() => GoRoute(
  path: Routes.careCircle,
  builder: (context, state) => const YourCirclesScreen(),
  routes: [
    GoRoute(
      path: 'new',
      builder: (context, state) => const CreateCircleScreen(),
      routes: [
        GoRoute(
          path: 'members',
          builder: (context, state) => const AddMembersScreen(),
        ),
        GoRoute(
          path: 'share',
          builder: (context, state) =>
              const ShareAvatarsScreen(mode: ShareMode.create),
        ),
      ],
    ),
    GoRoute(
      path: 'invites/:id',
      builder: (context, state) => CircleInviteScreen(circleId: _id(state)),
      routes: [
        GoRoute(
          path: 'share',
          builder: (context, state) => Consumer(
            builder: (context, ref, _) => ShareAvatarsScreen(
              mode: ShareMode.accept,
              circleId: _id(state),
              circleName: ref
                  .watch(circleInvitesProvider)
                  .value
                  ?.where((i) => i.circleId == _id(state))
                  .firstOrNull
                  ?.name,
            ),
          ),
        ),
      ],
    ),
    GoRoute(
      path: 'c/:id',
      builder: (context, state) => CircleHomeScreen(circleId: _id(state)),
      routes: [
        GoRoute(
          path: 'chat',
          builder: (context, state) => CircleChatScreen(circleId: _id(state)),
        ),
        GoRoute(
          path: 'feed',
          builder: (context, state) => CircleFeedScreen(circleId: _id(state)),
        ),
        GoRoute(
          path: 'members',
          builder: (context, state) => CircleMembersScreen(
            circleId: _id(state),
            manage: state.uri.queryParameters['manage'] == '1',
          ),
          routes: [
            GoRoute(
              path: ':userId',
              builder: (context, state) => MemberAvatarScreen(
                circleId: _id(state),
                userId: state.pathParameters['userId']!,
              ),
            ),
          ],
        ),
        GoRoute(
          path: 'add',
          builder: (context, state) => AddMembersScreen(circleId: _id(state)),
        ),
        GoRoute(
          path: 'notifications',
          builder: (context, state) =>
              CircleNotificationsScreen(circleId: _id(state)),
        ),
        GoRoute(
          path: 'settings',
          builder: (context, state) =>
              CircleSettingsScreen(circleId: _id(state)),
          routes: [
            GoRoute(
              path: 'notifications',
              builder: (context, state) =>
                  CircleNotificationSettingsScreen(circleId: _id(state)),
            ),
            GoRoute(
              path: 'profile',
              builder: (context, state) =>
                  CircleProfileScreen(circleId: _id(state)),
            ),
            GoRoute(
              path: 'share',
              builder: (context, state) => Consumer(
                builder: (context, ref, _) {
                  final c = ref.watch(circleDetailProvider(_id(state))).value;
                  return c == null
                      ? const Scaffold(
                          body: Center(child: CircularProgressIndicator()),
                        )
                      : ShareAvatarsScreen(
                          mode: ShareMode.update,
                          circleId: c.id,
                          circleName: c.name,
                          initial: c.myShares,
                        );
                },
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
