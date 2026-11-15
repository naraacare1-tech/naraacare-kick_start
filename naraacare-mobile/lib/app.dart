import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/config/providers.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/core/session/auth_controller.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/shared/widgets/app_switcher_privacy.dart';
import 'package:naraacare/shared/widgets/biometric_lock.dart';
import 'package:naraacare/shared/widgets/nc_offline_banner.dart';

/// Root widget: theme, localisation, routing and the app-wide security
/// layers (app-switcher cover, biometric lock, rooted-device warning) and
/// the offline banner.
class NaraaCareApp extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        Widget app = MediaQuery(
          // Dynamic type up to 130 % (doc 02 section 1.4).
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              maxScaleFactor: NcSize.maxTextScale,
            ),
          ),
          child: Column(
            children: [
              NcOfflineBanner(
                offline: ref.watch(onlineProvider).value == false,
              ),
              if (ref.watch(deviceCompromisedProvider).value ?? false)
                const _RootedWarning(),
              const _SyncConflictBanner(),
              Expanded(
                child: _SyncOnResume(child: child ?? const SizedBox.shrink()),
              ),
            ],
          ),
        );
        app = BiometricLock(
          enabled: ref.watch(biometricLockEnabledProvider),
          authenticator: ref.watch(authenticatorProvider),
          child: app,
        );
        app = AppSwitcherPrivacy(child: app);
        if (config.isProduction) return app;
        return Banner(
          message: config.flavor.name.toUpperCase(),
          location: BannerLocation.topEnd,
          child: app,
        );
      },
    );
  }
}

/// Warn-only banner on rooted/jailbroken devices (doc 07 SEC-5.4).
class _RootedWarning extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    return Material(
      key: const Key('rooted-warning'),
      color: nc.errorSurface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(NcSpace.inputGap),
          child: Text(
            AppLocalizations.of(context).rootedWarning,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: nc.error),
          ),
        ),
      ),
    );
  }
}

/// "Changed on another device" (doc 03 section 3.1): shown while the server
/// copy of a local entry has replaced it, until the user dismisses it.
class _SyncConflictBanner extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if ((ref.watch(syncConflictCountProvider).value ?? 0) == 0) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    return Material(
      color: nc.primarySurface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NcSpace.cardPadding,
            vertical: NcSpace.xs,
          ),
          child: Row(
            children: [
              Icon(Icons.sync_problem, color: nc.primary),
              const SizedBox(width: NcSpace.buttonGap),
              Expanded(child: Text(l10n.syncConflictBanner)),
              TextButton(
                onPressed: () =>
                    acknowledgeSyncConflicts(ref.read(databaseProvider)),
                child: Text(l10n.dismiss),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sends queued entries and pulls other devices' changes whenever the app
/// comes back to the foreground (background sync is planned for S17).
class _SyncOnResume extends ConsumerStatefulWidget {
  const new({required this.child});

  final Widget child;

  @override
  ConsumerState<_SyncOnResume> createState() => _SyncOnResumeState();
}

class _SyncOnResumeState extends ConsumerState<_SyncOnResume> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onResume: () {
        if (ref.read(authControllerProvider).status == AuthStatus.signedIn) {
          unawaited(ref.read(syncEngineProvider).flush());
        }
      },
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
