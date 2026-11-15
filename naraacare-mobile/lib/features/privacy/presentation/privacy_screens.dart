import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:naraacare/core/config/providers.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/security/screen_guard.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/privacy/data/privacy_api.dart';
import 'package:naraacare/features/privacy/privacy_providers.dart';
import 'package:naraacare/features/profile/presentation/report_screens.dart';
import 'package:naraacare/features/profile/presentation/streak_screens.dart';
import 'package:naraacare/features/profile/profile_tab_providers.dart';
import 'package:naraacare/features/subscriptions/subscription_providers.dart';
import 'package:naraacare/shared/widgets/legal_links.dart';
import 'package:naraacare/shared/widgets/nc_bottom_sheet.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';
import 'package:url_launcher/url_launcher.dart';

const _optionalPurposes = ['ai_processing', 'circle_sharing', 'marketing'];
const _requiredPurposes = ['terms', 'privacy', 'health_data'];

String privacyErrorMessage(AppLocalizations l10n, ApiError e) =>
    switch (e.code) {
      'EXPORT_LIMIT_REACHED' => l10n.exportLimitReached,
      'CONSENT_WITHDRAWAL_BLOCKED' => l10n.consentRequiredExplain,
      'INVALID_CREDENTIALS' => l10n.reauthWrongPassword,
      _ => featureErrorMessage(l10n, e),
    };

String _purposeTitle(AppLocalizations l10n, String purpose) =>
    switch (purpose) {
      'terms' => l10n.termsTitle,
      'privacy' => l10n.privacyTitle,
      'health_data' => l10n.purposeHealthData,
      'ai_processing' => l10n.purposeAi,
      'circle_sharing' => l10n.purposeCircleSharing,
      _ => l10n.purposeMarketing,
    };

String _purposeBody(AppLocalizations l10n, String purpose) => switch (purpose) {
  'terms' || 'privacy' => l10n.purposeRequiredBody,
  'health_data' => l10n.purposeHealthDataBody,
  'ai_processing' => l10n.purposeAiBody,
  'circle_sharing' => l10n.purposeCircleSharingBody,
  _ => l10n.purposeMarketingBody,
};

/// Asks the user to prove it is them before an export or a deletion: the
/// account password, or a 6-digit code sent to their email (accounts created
/// with Google / Apple have no password). Returns null when closed.
Future<ReauthProof?> showReauthSheet(BuildContext context) =>
    showNcBottomSheet<ReauthProof>(
      context: context,
      title: AppLocalizations.of(context).reauthTitle,
      builder: (context) => const _ReauthSheet(),
    );

class _ReauthSheet extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_ReauthSheet> createState() => _ReauthSheetState();
}

class _ReauthSheetState extends ConsumerState<_ReauthSheet> {
  final _form = GlobalKey<FormState>();
  final _value = TextEditingController();
  String? _challengeId;
  bool _sending = false;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _sending = true);
    try {
      final id = await ref.read(privacyApiProvider).startReauth();
      if (!mounted) return;
      _value.clear();
      setState(() => _challengeId = id);
      showNcToast(context, l10n.reauthCodeSent, kind: NcToastKind.info);
    } on ApiError catch (e) {
      if (mounted) {
        showNcToast(
          context,
          privacyErrorMessage(l10n, e),
          kind: NcToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final byCode = _challengeId != null;
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(byCode ? l10n.reauthCodeBody : l10n.reauthPasswordBody),
          const SizedBox(height: NcSpace.cardGap),
          NcTextField(
            key: ValueKey(byCode),
            controller: _value,
            label: byCode ? l10n.reauthCodeLabel : l10n.passwordLabel,
            validator: byCode
                ? InputValidators.otp
                : InputValidators.passwordLogin,
            maxLength: byCode ? 6 : 128,
            secret: !byCode,
            keyboardType: byCode ? TextInputType.number : null,
            autofocus: true,
          ),
          const SizedBox(height: NcSpace.buttonGap),
          NcButton(
            label: l10n.continueLabel,
            onPressed: () {
              if (!(_form.currentState?.validate() ?? false)) return;
              Navigator.of(context).pop(
                byCode
                    ? ReauthProof.code(
                        challengeId: _challengeId!,
                        code: _value.text.trim(),
                      )
                    : ReauthProof.password(_value.text),
              );
            },
          ),
          TextButton(
            onPressed: _sending ? null : _sendCode,
            child: Text(byCode ? l10n.reauthResend : l10n.reauthUseCode),
          ),
        ],
      ),
    );
  }
}

/// Settings > Privacy (S15, new screen in the Settings list style; design
/// sign-off pending): consents with their policy version and date, toggles
/// for the optional ones, and the ways to download or delete your data.
class PrivacyCentreScreen extends ConsumerWidget {
  const new({super.key});

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    String purpose,
    bool granted,
  ) async {
    final l10n = AppLocalizations.of(context);
    final consents = ref.read(consentsProvider).value ?? const [];
    final version = consents
        .where((c) => c.purpose == 'privacy')
        .map((c) => c.policyVersion)
        .firstOrNull;
    if (version == null) return;
    try {
      await ref
          .read(privacyApiProvider)
          .recordConsent(
            purpose: purpose,
            policyVersion: version,
            granted: granted,
          );
      ref.invalidate(consentsProvider);
      if (context.mounted) {
        showNcToast(
          context,
          granted ? l10n.consentGranted : l10n.consentWithdrawn,
        );
      }
    } on ApiError catch (e) {
      if (context.mounted) {
        showNcToast(
          context,
          privacyErrorMessage(l10n, e),
          kind: NcToastKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final consents = ref.watch(consentsProvider);
    final date = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    final small = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: nc.textSecondary);
    Widget header(String text) => Padding(
      padding: const EdgeInsets.only(
        top: NcSpace.sectionGap,
        bottom: NcSpace.inputGap,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: nc.textSecondary),
      ),
    );
    Widget link(IconData icon, String label, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: NcSpace.inputGap),
      child: ProfileCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: nc.textPrimary),
            const SizedBox(width: NcSpace.buttonGap),
            Expanded(child: Text(label)),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.privacyCentre)),
      body: consents.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.loadFailed)),
        data: (items) {
          ConsentState? of(String purpose) =>
              items.where((c) => c.purpose == purpose).firstOrNull;
          return ListView(
            padding: EdgeInsets.all(nc.screenPadding),
            children: [
              Text(l10n.privacyCentreIntro),
              header(l10n.consentsRequiredHeader),
              for (final purpose in _requiredPurposes)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_purposeTitle(l10n, purpose)),
                  subtitle: Text(
                    [
                      _purposeBody(l10n, purpose),
                      if (of(purpose) case final c?)
                        l10n.consentRecorded(
                          c.policyVersion,
                          date.format(c.recordedAt.toLocal()),
                        ),
                    ].join('\n'),
                    style: small,
                  ),
                  trailing: Text(l10n.requiredLabel, style: small),
                  isThreeLine: of(purpose) != null,
                ),
              Text(l10n.consentRequiredExplain, style: small),
              header(l10n.consentsOptionalHeader),
              for (final purpose in _optionalPurposes)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: of(purpose)?.granted ?? false,
                  onChanged: (v) => _toggle(context, ref, purpose, v),
                  title: Text(_purposeTitle(l10n, purpose)),
                  subtitle: Text(_purposeBody(l10n, purpose), style: small),
                ),
              header(l10n.yourDataHeader),
              link(
                Icons.download_outlined,
                l10n.downloadMyData,
                () => context.push(Routes.dataExport),
              ),
              link(
                Icons.policy_outlined,
                l10n.privacyNotice,
                () => context.push(Routes.privacyNotice),
              ),
              link(
                Icons.delete_outline,
                l10n.deleteAccount,
                () => context.push(Routes.deleteAccount),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Download my data (right to access): request (with re-auth), wait for the
/// ZIP, then save and share it.
class DataExportScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DataExportScreen> createState() => _ExportState();
}

class _ExportState extends ConsumerState<DataExportScreen> {
  ExportJob? _job;
  Timer? _poll;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({String? id}) async {
    try {
      final api = ref.read(privacyApiProvider);
      final job = id != null
          ? await api.export(id)
          : (await api.status()).latestExport;
      if (!mounted) return;
      setState(() => _job = job);
      if (job != null && job.pending) {
        _poll = Timer(
          const Duration(seconds: 3),
          () => unawaited(_load(id: job.id)),
        );
      }
    } on ApiError {
      // the screen still offers a new request
    }
  }

  Future<void> _request() async {
    final l10n = AppLocalizations.of(context);
    final proof = await showReauthSheet(context);
    if (proof == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final id = await ref.read(privacyApiProvider).requestExport(proof);
      await _load(id: id);
    } on ApiError catch (e) {
      if (mounted) {
        showNcToast(
          context,
          privacyErrorMessage(l10n, e),
          kind: NcToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final file = await ref.read(privacyApiProvider).downloadExport(_job!);
      if (mounted) await shareReport(context, file, l10n.downloadMyData);
    } on ApiError catch (e) {
      if (mounted) {
        showNcToast(
          context,
          privacyErrorMessage(l10n, e),
          kind: NcToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final job = _job;
    final date = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    return ScreenGuard(
      child: Scaffold(
        backgroundColor: nc.surface,
        appBar: AppBar(title: Text(l10n.downloadMyData)),
        body: ListView(
          padding: EdgeInsets.all(nc.screenPadding),
          children: [
            Text(l10n.exportIntro),
            const SizedBox(height: NcSpace.cardGap),
            ProfileCard(
              colour: nc.primarySurface,
              child: Text(l10n.exportWhatsIncluded),
            ),
            const SizedBox(height: NcSpace.sectionGap),
            if (job != null && job.pending) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: NcSpace.inputGap),
              Text(l10n.exportPreparing, textAlign: TextAlign.center),
            ] else if (job != null && job.ready) ...[
              Text(
                l10n.exportReady(date.format(job.expiresAt!.toLocal())),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: NcSpace.buttonGap),
              Builder(
                builder: (context) => NcButton(
                  label: l10n.downloadAndShare,
                  icon: Icons.share_outlined,
                  loading: _busy,
                  onPressed: _download,
                ),
              ),
            ] else
              NcButton(
                label: l10n.requestExport,
                loading: _busy,
                onPressed: _request,
              ),
            const SizedBox(height: NcSpace.cardGap),
            Text(
              l10n.exportLimitNote,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Plain-language privacy notice (DPDP): what we collect, why, who processes
/// it, how long we keep it, your rights and the grievance contact. DRAFT
/// pending legal review (OQ-47); the full policy opens in the browser.
class PrivacyNoticeScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final config = ref.watch(appConfigProvider);
    final contact = ref.watch(supportInfoProvider).value?.$2.email;
    final sections = [
      (l10n.noticeCollectTitle, l10n.noticeCollectBody),
      (l10n.noticeWhyTitle, l10n.noticeWhyBody),
      (l10n.noticeNotCollectTitle, l10n.noticeNotCollectBody),
      (l10n.noticeProcessorsTitle, l10n.noticeProcessorsBody),
      (l10n.noticeRetentionTitle, l10n.noticeRetentionBody),
      (l10n.noticeRightsTitle, l10n.noticeRightsBody),
      (
        l10n.noticeGrievanceTitle,
        l10n.noticeGrievanceBody(contact ?? l10n.noticeGrievancePending),
      ),
    ];
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.privacyNotice)),
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          for (final (title, body) in sections) ...[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: NcSpace.xs),
            Text(body),
            const SizedBox(height: NcSpace.cardGap),
          ],
          OutlinedButton(
            onPressed: () => openLegalLink(context, config.privacyUrl),
            child: Text(l10n.readFullPolicy),
          ),
        ],
      ),
    );
  }
}

/// Account > Delete Account: what happens, the 30-day grace, the store
/// subscription reminder, confirmation and re-auth. Afterwards the user is
/// signed out on every device and this phone's data is wiped.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteState();
}

class _DeleteState extends ConsumerState<DeleteAccountScreen> {
  bool _understood = false;
  bool _busy = false;

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final proof = await showReauthSheet(context);
    if (proof == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final at = await ref.read(privacyApiProvider).requestDeletion(proof);
      if (!mounted) return;
      final date = DateFormat.yMMMd(Localizations.localeOf(context).toString())
          .format(at.toLocal());
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.deletionScheduledTitle),
          content: Text(l10n.deletionScheduledBody(date)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.okLabel),
            ),
          ],
        ),
      );
      await ref.read(authControllerProvider).signedOut();
    } on ApiError catch (e) {
      if (mounted) {
        showNcToast(
          context,
          privacyErrorMessage(l10n, e),
          kind: NcToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final manageUrl = ref.watch(subscriptionProvider).value?.manageUrl;
    return ScreenGuard(
      child: Scaffold(
        backgroundColor: nc.surface,
        appBar: AppBar(title: Text(l10n.deleteAccount)),
        body: ListView(
          padding: EdgeInsets.all(nc.screenPadding),
          children: [
            Text(
              l10n.deleteAccountIntro,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: NcSpace.buttonGap),
            for (final line in [
              l10n.deleteWhatGoes,
              l10n.deleteGrace,
              l10n.deleteKept,
              l10n.deleteSignedOut,
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: NcSpace.inputGap),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 6, color: nc.textSecondary),
                    const SizedBox(width: NcSpace.inputGap),
                    Expanded(child: Text(line)),
                  ],
                ),
              ),
            const SizedBox(height: NcSpace.cardGap),
            ProfileCard(
              colour: nc.errorSurface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.deleteSubscriptionWarning),
                  if (manageUrl != null && Uri.tryParse(manageUrl) != null)
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => launchUrl(
                        Uri.parse(manageUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Text(l10n.manageSubscription),
                    ),
                ],
              ),
            ),
            const SizedBox(height: NcSpace.cardGap),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _understood,
              onChanged: (v) => setState(() => _understood = v ?? false),
              title: Text(l10n.deleteConfirmCheck),
            ),
            const SizedBox(height: NcSpace.buttonGap),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: nc.error,
                minimumSize: const Size.fromHeight(NcSize.buttonHeight),
              ),
              onPressed: !_understood || _busy ? null : _delete,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.deleteAccountButton),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown after sign-in while a deletion is scheduled: cancel it, or keep it
/// and sign out.
class DeletionScheduledScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DeletionScheduledScreen> createState() => _ScheduledState();
}

class _ScheduledState extends ConsumerState<DeletionScheduledScreen> {
  bool _busy = false;

  Future<void> _cancel() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(privacyApiProvider).cancelDeletion();
      ref.invalidate(privacyStatusProvider);
      if (!mounted) return;
      showNcToast(context, l10n.deletionCancelled);
      context.go(Routes.home);
    } on ApiError catch (e) {
      if (mounted) {
        showNcToast(
          context,
          privacyErrorMessage(l10n, e),
          kind: NcToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final at = ref.watch(privacyStatusProvider).value?.deletionAt;
    final date = at == null
        ? ''
        : DateFormat.yMMMd(Localizations.localeOf(context).toString())
              .format(at.toLocal());
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: nc.surface,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(nc.screenPadding),
            child: Column(
              children: [
                const Spacer(),
                Icon(Icons.schedule, size: 64, color: nc.error),
                const SizedBox(height: NcSpace.cardGap),
                Text(
                  l10n.deletionPendingTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: NcSpace.inputGap),
                Text(
                  l10n.deletionPendingBody(date),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                NcButton(
                  label: l10n.cancelDeletion,
                  loading: _busy,
                  onPressed: _cancel,
                ),
                const SizedBox(height: NcSpace.inputGap),
                NcButton(
                  label: l10n.keepDeletionSignOut,
                  variant: NcButtonVariant.ghost,
                  onPressed: () => ref.read(authControllerProvider).signOut(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Re-consent gate: a new major version of the Terms or the Privacy Policy
/// must be accepted before the app can be used (doc 07 SEC-7.2).
class ReconsentScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ReconsentScreen> createState() => _ReconsentState();
}

class _ReconsentState extends ConsumerState<ReconsentScreen> {
  bool _busy = false;

  Future<void> _accept(List<PolicyUpdate> updates) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      for (final u in updates) {
        await ref
            .read(privacyApiProvider)
            .recordConsent(
              purpose: u.docType,
              policyVersion: u.currentVersion,
              granted: true,
            );
      }
      ref.invalidate(privacyStatusProvider);
      if (mounted) context.go(Routes.home);
    } on ApiError catch (e) {
      if (mounted) {
        showNcToast(
          context,
          privacyErrorMessage(l10n, e),
          kind: NcToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final updates =
        ref.watch(privacyStatusProvider).value?.policyUpdates ?? const [];
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: nc.surface,
        body: SafeArea(
          child: ListView(
            padding: EdgeInsets.all(nc.screenPadding),
            children: [
              const SizedBox(height: NcSpace.sectionGap),
              Icon(Icons.policy_outlined, size: 56, color: nc.primary),
              const SizedBox(height: NcSpace.cardGap),
              Text(
                l10n.reconsentTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: NcSpace.inputGap),
              Text(l10n.reconsentBody, textAlign: TextAlign.center),
              const SizedBox(height: NcSpace.sectionGap),
              for (final u in updates)
                Padding(
                  padding: const EdgeInsets.only(bottom: NcSpace.inputGap),
                  child: ProfileCard(
                    onTap: Uri.tryParse(u.url)?.scheme == 'https'
                        ? () => openLegalLink(context, Uri.parse(u.url))
                        : null,
                    child: Row(
                      children: [
                        const Icon(Icons.description_outlined),
                        const SizedBox(width: NcSpace.buttonGap),
                        Expanded(
                          child: Text(
                            '${_purposeTitle(l10n, u.docType)} '
                            '(${u.currentVersion})',
                          ),
                        ),
                        const Icon(Icons.open_in_new),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: NcSpace.sectionGap),
              NcButton(
                label: l10n.acceptAndContinue,
                loading: _busy,
                onPressed: updates.isEmpty ? null : () => _accept(updates),
              ),
              const SizedBox(height: NcSpace.inputGap),
              NcButton(
                label: l10n.logOut,
                variant: NcButtonVariant.ghost,
                onPressed: () => ref.read(authControllerProvider).signOut(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// At launch (Home): a scheduled deletion or a policy update takes over the
/// screen before anything else. Network errors are ignored (offline-first).
Future<void> checkPrivacyAtLaunch(BuildContext context, WidgetRef ref) async {
  try {
    final status = await ref.read(privacyStatusProvider.future);
    if (!context.mounted) return;
    if (status.deletionAt != null) {
      context.go(Routes.deletionScheduled);
    } else if (status.policyUpdates.isNotEmpty) {
      context.go(Routes.reconsent);
    }
  } on ApiError {
    return;
  }
}
