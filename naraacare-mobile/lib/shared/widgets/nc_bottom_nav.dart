import 'package:flutter/material.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// Home | Care Circle | Rin AI | Profile (DOC section 1 app flow; fixed
/// bottom navigation, doc 02 section 1.1).
class NcBottomNav extends StatelessWidget {
  const new({required this.currentIndex, required this.onTap, super.key});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    return NavigationBar(
      height: NcSize.bottomNavHeight,
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      backgroundColor: nc.surface,
      indicatorColor: nc.primarySurface,
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home, color: nc.primary),
          label: l10n.tabHome,
        ),
        NavigationDestination(
          icon: const Icon(Icons.group_outlined),
          selectedIcon: Icon(Icons.group, color: nc.primary),
          label: l10n.tabCareCircle,
        ),
        NavigationDestination(
          icon: const Icon(Icons.auto_awesome_outlined),
          selectedIcon: Icon(Icons.auto_awesome, color: nc.primary),
          label: l10n.tabRinAi,
        ),
        NavigationDestination(
          icon: const Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person, color: nc.primary),
          label: l10n.tabProfile,
        ),
      ],
    );
  }
}
