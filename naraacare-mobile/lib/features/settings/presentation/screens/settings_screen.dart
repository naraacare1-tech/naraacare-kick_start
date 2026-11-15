import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/config/providers.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/shared/widgets/legal_links.dart';

/// ST1 Settings (Figma Profile/Settings). Legal documents open in the
/// external browser (never a WebView); Licenses lists the packages and the
/// data sources (registered at start-up).
class SettingsScreen extends ConsumerWidget {
  const new({super.key});

  Future<void> _logOut(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.logOut),
        content: Text(l10n.logOutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.logOut),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(authControllerProvider).signOut();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final config = ref.watch(appConfigProvider);
    final me = ref.watch(meProvider).value;
    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(
        top: NcSpace.sectionGap,
        bottom: NcSpace.inputGap,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: nc.textSecondary),
      ),
    );
    Widget item(String label, IconData icon, VoidCallback? onTap) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: onTap == null ? nc.primaryDisabled : null),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      enabled: onTap != null,
      onTap: onTap,
    );
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        backgroundColor: nc.surface,
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: nc.screenPadding),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: nc.primarySurface,
              child: Icon(Icons.person, color: nc.primary),
            ),
            title: Text(me?.profile.fullName ?? ''),
            subtitle: me?.username == null ? null : Text('@${me!.username}'),
          ),
          section(l10n.settingsProfileSection),
          item(
            l10n.editProfile,
            Icons.edit_outlined,
            () => context.push(Routes.editProfile),
          ),
          item(
            l10n.usernameLabel,
            Icons.alternate_email,
            () => context.push(Routes.username),
          ),
          item(
            l10n.account,
            Icons.lock_outline,
            () => context.push(Routes.account),
          ),
          item(
            l10n.notificationsReminders,
            Icons.notifications_none,
            () => context.push(Routes.notificationSettings),
          ),
          section(l10n.settingsSubscriptionSection),
          item(
            l10n.mySubscriptions,
            Icons.workspace_premium_outlined,
            () => context.push(Routes.subscriptions),
          ),
          item(
            l10n.referFriend,
            Icons.card_giftcard,
            () => context.push(Routes.referFriends),
          ),
          section(l10n.settingsSupportSection),
          item(
            l10n.privacyCentre,
            Icons.shield_outlined,
            () => context.push(Routes.privacyCentre),
          ),
          item(
            l10n.termsTitle,
            Icons.description_outlined,
            () => openLegalLink(context, config.termsUrl),
          ),
          item(
            l10n.privacyTitle,
            Icons.privacy_tip_outlined,
            () => openLegalLink(context, config.privacyUrl),
          ),
          item(
            l10n.licensesTitle,
            Icons.article_outlined,
            () => showLicensePage(
              context: context,
              applicationName: l10n.appName,
            ),
          ),
          item(
            l10n.helpSupport,
            Icons.support_agent,
            () => context.push(Routes.help),
          ),
          const SizedBox(height: NcSpace.cardGap),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, color: nc.error),
            title: Text(l10n.logOut, style: TextStyle(color: nc.error)),
            onTap: () => _logOut(context, ref),
          ),
          const SizedBox(height: NcSpace.sectionGap),
        ],
      ),
    );
  }
}
