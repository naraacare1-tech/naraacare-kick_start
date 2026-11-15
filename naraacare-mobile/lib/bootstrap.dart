import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/app.dart';
import 'package:naraacare/core/config/app_config.dart';
import 'package:naraacare/core/config/flavor.dart';
import 'package:naraacare/core/config/providers.dart';
import 'package:naraacare/features/profile/presentation/support_screens.dart';

/// Shared start-up for all flavors. Fails fast if the build was made with an
/// unsafe or incomplete `--dart-define-from-file`.
void bootstrap(Flavor flavor) {
  WidgetsFlutterBinding.ensureInitialized();
  registerDataSourceLicenses();
  final config = AppConfig.fromEnvironment(flavor);
  runApp(_RestartableApp(config: config));
}

/// Owns the [ProviderScope]. A new key on sign-out builds a fresh scope, so
/// no provider keeps the previous user's data in memory (profile, home,
/// circles, Rin chat, sockets).
class _RestartableApp extends StatefulWidget {
  const new({required this.config});

  final AppConfig config;

  @override
  State<_RestartableApp> createState() => _RestartableAppState();
}

class _RestartableAppState extends State<_RestartableApp> {
  Key _scope = UniqueKey();

  void _restart() {
    if (mounted) setState(() => _scope = UniqueKey());
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    key: _scope,
    overrides: [
      appConfigProvider.overrideWithValue(widget.config),
      restartAppProvider.overrideWithValue(_restart),
    ],
    child: const NaraaCareApp(),
  );
}
