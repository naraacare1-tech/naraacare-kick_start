import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/core/routing/guards.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/core/utils/clock.dart';
import 'package:naraacare/features/hydration/presentation/hydration_card.dart';
import 'package:naraacare/features/hydration/presentation/hydration_sheets.dart';
import 'package:naraacare/features/nutrition/nutrition_providers.dart';
import 'package:naraacare/features/nutrition/presentation/screens/nutrition_home.dart';
import 'package:naraacare/features/nutrition/presentation/widgets/nutrition_widgets.dart';
import 'package:naraacare/features/privacy/presentation/privacy_screens.dart';
import 'package:naraacare/features/profile/data/profile_api.dart';
import 'package:naraacare/features/profile/presentation/username_form.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/features/sleep/presentation/sleep_screens.dart';
import 'package:naraacare/features/subscriptions/subscription_providers.dart';
import 'package:naraacare/shared/widgets/nc_avatar_figure.dart';

/// Greeting by local time: Morning 05-12, Afternoon 12-17, Evening 17-05.
String greetingFor(AppLocalizations l10n, DateTime now) => switch (now.hour) {
  >= 5 && < 12 => l10n.greetingMorning,
  >= 12 && < 17 => l10n.greetingAfternoon,
  _ => l10n.greetingEvening,
};

/// Home tab (Figma H1): greeting, the avatar carousel (water S09, food S08,
/// sleep S10; swipe left/right, pager dots) and one primary button for the
/// page shown (Add Water/Drink, Add Meal, Log Sleep or the STAR upsell).
/// Offers the username sheet once per app session when none is set (H2).
class HomeScreen extends ConsumerStatefulWidget {
  const new({super.key, this.clock = const SystemClock()});

  final Clock clock;

  /// The sheet is offered once per app session ("Set up later").
  static bool usernameOffered = false;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Send entries queued offline (the engine also flushes on reconnect).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(syncEngineProvider).flush());
      unawaited(_sendPendingReferral());
      unawaited(checkPrivacyAtLaunch(context, ref));
    });
  }

  /// A code from an invite link opened before sign-up (S11). The API
  /// decides silently whether it counts (new accounts only), so the code is
  /// dropped after one successful call.
  Future<void> _sendPendingReferral() async {
    final storage = ref.read(secureStorageProvider);
    final code = await storage.pendingReferralCode();
    if (code == null) return;
    try {
      await ref
          .read(billingApiProvider)
          .attribute(code, await storage.installationId());
      await storage.clearPendingReferralCode();
    } on Object {
      // Offline or server trouble: try again on the next visit.
    }
  }

  void _offerUsername(Me me) {
    if (HomeScreen.usernameOffered || hasUsername(me.username)) return;
    HomeScreen.usernameOffered = true;
    // After this frame: a sheet cannot open while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(showUsernameSheet(context));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    // Offline or failed: no sheet; it is offered on a later visit.
    ref.listen(meProvider, (_, next) {
      if (next case AsyncData(:final value)) _offerUsername(value);
    });
    final me = ref.watch(meProvider).value;
    final firstName = (me?.profile.fullName ?? '').split(' ').first;
    final greeting = greetingFor(l10n, widget.clock.now());
    final star = ref.watch(isStarProvider);
    final (label, action) = switch (_page) {
      0 => (l10n.addWaterDrinkButton, () => showAddIntakeSheet(context)),
      1 => (l10n.addMealLongButton, () => context.push(Routes.addMeal)),
      _ when star => (
        l10n.logSleepButton,
        () => context.push(Routes.updateSleep),
      ),
      _ => (l10n.unlockSleepAvatar, () => showStarUpsell(context)),
    };
    return Scaffold(
      backgroundColor: nc.surface,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(nc.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                firstName.isEmpty
                    ? greeting
                    : l10n.greetingName(greeting, firstName),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: NcSpace.cardGap),
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: const [
                    _AvatarPage(child: HydrationAvatarCard()),
                    _AvatarPage(child: NutritionAvatarCard()),
                    _AvatarPage(child: SleepAvatarCard()),
                  ],
                ),
              ),
              _PagerDots(
                count: 3,
                index: _page,
                onTap: (i) => _pages.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                ),
              ),
              const SizedBox(height: NcSpace.cardGap),
              Center(
                child: FilledButton.icon(
                  onPressed: () => unawaited(Future.sync(action)),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text(label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One carousel page. The avatar fills the page height down to the pager,
/// keeping room for the notes under it ("0.7 L left to drink today"); on a
/// short screen (or large text) the page scrolls instead.
class _AvatarPage extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  /// Room kept under the figure for the page's notes.
  static const double _notes = 64;
  static const double _minStage = 320;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => NcAvatarStageHeight(
      height: (box.maxHeight - _notes).clamp(_minStage, double.infinity),
      child: SingleChildScrollView(child: child),
    ),
  );
}

/// Pager dots under the avatar (Figma H1); tapping a dot opens that avatar.
class _PagerDots extends StatelessWidget {
  const new({required this.count, required this.index, required this.onTap});

  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.pageOf(index + 1, count),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            // A 32 dp touch target around each 8 dp dot.
            InkResponse(
              onTap: () => onTap(i),
              radius: NcSpace.cardGap,
              child: Padding(
                padding: const EdgeInsets.all(NcSpace.buttonGap),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == index ? nc.primary : nc.inputFill,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
