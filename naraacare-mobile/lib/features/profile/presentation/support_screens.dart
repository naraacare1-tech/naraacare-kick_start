import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/security/system_prompt.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/profile/data/profile_tab_api.dart';
import 'package:naraacare/features/profile/presentation/streak_screens.dart';
import 'package:naraacare/features/profile/profile_tab_providers.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';
import 'package:url_launcher/url_launcher.dart';

const int _maxScreenshotBytes = 10 * 1024 * 1024;

String supportErrorMessage(AppLocalizations l10n, ApiError e) =>
    switch (e.code) {
      'SUPPORT_LIMIT_REACHED' => l10n.supportLimitReached,
      'UPLOAD_INVALID' => l10n.uploadInvalid,
      _ => featureErrorMessage(l10n, e),
    };

/// Figma "Profile/ Settings/ Help 1": the Help & support menu.
class HelpSupportScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    Widget item(IconData icon, String label, String route) => Padding(
      padding: const EdgeInsets.only(bottom: NcSpace.buttonGap),
      child: ProfileCard(
        onTap: () => context.push(route),
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
      appBar: AppBar(title: Text(l10n.helpSupport)),
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          item(Icons.help_outline, l10n.faqsLong, Routes.faqs),
          item(
            Icons.chat_bubble_outline,
            l10n.contactSupport,
            Routes.contactSupport,
          ),
          item(
            Icons.report_gmailerrorred_outlined,
            l10n.reportProblem,
            Routes.reportProblem,
          ),
          item(
            Icons.lightbulb_outline,
            l10n.requestFeature,
            Routes.requestFeature,
          ),
          item(
            Icons.menu_book_outlined,
            l10n.gettingStartedGuide,
            Routes.guide,
          ),
        ],
      ),
    );
  }
}

/// Figma "Help 2": FAQs with a search box (filtered on the device; the list
/// is small and static).
class FaqsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<FaqsScreen> createState() => _FaqsState();
}

class _FaqsState extends ConsumerState<FaqsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final info = ref.watch(supportInfoProvider);
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.faqs)),
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          NcTextField(
            validator: (v) => v.isEmpty ? null : InputValidators.search(v),
            maxLength: 64,
            hint: l10n.searchQuestions,
            prefixIcon: Icons.search,
            onChanged: (v) => setState(
              () => _query = InputValidators.search(v) == null ? v.trim() : '',
            ),
          ),
          const SizedBox(height: NcSpace.cardGap),
          ...info.when(
            loading: () => [const Center(child: CircularProgressIndicator())],
            error: (_, _) => [Center(child: Text(l10n.loadFailed))],
            data: (data) {
              final q = _query.toLowerCase();
              final items = data.$1.where(
                (f) =>
                    q.isEmpty ||
                    f.question.toLowerCase().contains(q) ||
                    f.answer.toLowerCase().contains(q),
              );
              if (items.isEmpty) return [Text(l10n.noFaqMatch)];
              return [
                for (final f in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: NcSpace.inputGap),
                    child: Card(
                      elevation: 0,
                      color: nc.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(NcRadius.l),
                        side: BorderSide(color: nc.inputFill),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        shape: const Border(),
                        title: Text(f.question),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          NcSpace.cardPadding,
                          0,
                          NcSpace.cardPadding,
                          NcSpace.cardPadding,
                        ),
                        children: [Text(f.answer)],
                      ),
                    ),
                  ),
              ];
            },
          ),
        ],
      ),
    );
  }
}

/// Figma "Help 4": email support for everyone; the phone line for STAR
/// (the server only sends the number to STAR users).
class ContactSupportScreen extends ConsumerWidget {
  const new({super.key});

  Future<void> _open(BuildContext context, Uri uri) async {
    final l10n = AppLocalizations.of(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      opened = false;
    }
    if (!opened && context.mounted) {
      showNcToast(context, l10n.couldNotOpenApp, kind: NcToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final info = ref.watch(supportInfoProvider);
    final small = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: nc.textSecondary);
    Widget card({
      required IconData icon,
      required Color colour,
      required String title,
      required String body,
      String? note,
      String? action,
      VoidCallback? onAction,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: NcSpace.cardGap),
      child: ProfileCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(NcSpace.inputGap),
              decoration: BoxDecoration(
                color: colour.withAlpha(36),
                borderRadius: BorderRadius.circular(NcRadius.s),
              ),
              child: Icon(icon, color: colour),
            ),
            const SizedBox(height: NcSpace.buttonGap),
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            Text(body),
            if (note != null) Text(note, style: small),
            if (action != null)
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: onAction,
                child: Text('$action →'),
              ),
          ],
        ),
      ),
    );
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.contactSupport)),
      body: info.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.loadFailed)),
        data: (data) {
          final contact = data.$2;
          return ListView(
            padding: EdgeInsets.all(nc.screenPadding),
            children: [
              card(
                icon: Icons.mail_outline,
                colour: nc.primary,
                title: l10n.emailSupport,
                body: l10n.emailSupportBody,
                note: contact.emailResponse,
                action: l10n.sendAnEmail,
                onAction: () =>
                    _open(context, Uri(scheme: 'mailto', path: contact.email)),
              ),
              if (contact.phone != null)
                card(
                  icon: Icons.call_outlined,
                  colour: nc.error,
                  title: l10n.callUs,
                  body: l10n.callUsBody,
                  note: contact.phoneHours,
                  action: contact.phone,
                  onAction: () => _open(
                    context,
                    Uri(
                      scheme: 'tel',
                      path: contact.phone!.replaceAll(' ', ''),
                    ),
                  ),
                )
              else if (contact.phoneRequiresStar)
                card(
                  icon: Icons.call_outlined,
                  colour: nc.star,
                  title: l10n.callUs,
                  body: l10n.callUsStarOnly,
                  action: l10n.upgradeButton,
                  onAction: () => context.push(Routes.subscriptions),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Figma "Help 5": category, description and an optional screenshot. The
/// server checks the image, re-encodes it and removes its metadata.
class ReportProblemScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ReportProblemScreen> createState() => _ProblemState();
}

class _ProblemState extends ConsumerState<ReportProblemScreen> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  String _category = 'app_crash';
  Screenshot? _shot;
  bool _busy = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final l10n = AppLocalizations.of(context);
    final file = await SystemPrompt.guard(
      () => ImagePicker().pickImage(source: ImageSource.gallery),
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final lower = file.name.toLowerCase();
    final png = lower.endsWith('.png');
    final jpg = lower.endsWith('.jpg') || lower.endsWith('.jpeg');
    if (!mounted) return;
    if ((!png && !jpg) || bytes.length > _maxScreenshotBytes) {
      showNcToast(context, l10n.uploadInvalid, kind: NcToastKind.error);
      return;
    }
    // The picker's own file name is never sent: a fixed safe name instead.
    setState(
      () => _shot = Screenshot(
        bytes: bytes,
        name: png ? 'screenshot.png' : 'screenshot.jpg',
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final ref0 = await ref
          .read(profileTabApiProvider)
          .reportProblem(
            category: _category,
            description: _description.text.trim(),
            screenshot: _shot,
          );
      if (!mounted) return;
      showNcToast(context, l10n.ticketSent(ref0));
      context.pop();
    } on ApiError catch (e) {
      if (mounted) {
        showNcToast(
          context,
          supportErrorMessage(l10n, e),
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
    final label = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: nc.textSecondary);
    final categories = [
      ('app_crash', Icons.sync_problem, l10n.catAppCrash),
      ('data_sync', Icons.sync, l10n.catDataSync),
      ('billing', Icons.credit_card, l10n.catBilling),
      ('device_link', Icons.watch_outlined, l10n.catDeviceLink),
      ('account', Icons.person_outline, l10n.catAccount),
      ('other', Icons.more_horiz, l10n.catOther),
    ];
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.reportProblem)),
      body: Form(
        key: _form,
        child: ListView(
          padding: EdgeInsets.all(nc.screenPadding),
          children: [
            Text(l10n.issueCategory, style: label),
            const SizedBox(height: NcSpace.inputGap),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: NcSpace.inputGap,
              crossAxisSpacing: NcSpace.inputGap,
              childAspectRatio: 2.4,
              children: [
                for (final (code, icon, text) in categories)
                  ProfileCard(
                    colour: code == _category ? nc.primarySurface : null,
                    onTap: () => setState(() => _category = code),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          color: nc.primary,
                          size: NcSize.iconSmall + 4,
                        ),
                        Text(
                          text,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: NcSpace.cardGap),
            Text(l10n.problemDescription, style: label),
            const SizedBox(height: NcSpace.inputGap),
            NcTextField(
              controller: _description,
              validator: InputValidators.freeText(max: 2000),
              maxLength: 2000,
              maxLines: 6,
              minLines: 4,
              hint: l10n.tellUsWhatHappened,
            ),
            const SizedBox(height: NcSpace.cardGap),
            Text(l10n.uploadScreenshotOptional, style: label),
            const SizedBox(height: NcSpace.inputGap),
            ProfileCard(
              colour: nc.inputFill,
              onTap: _busy ? null : _pick,
              child: _shot == null
                  ? Column(
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color: nc.textSecondary,
                        ),
                        const SizedBox(height: NcSpace.xs),
                        Text(l10n.tapToUpload),
                        Text(
                          l10n.uploadLimits,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(NcRadius.s),
                          child: Image.memory(
                            _shot!.bytes,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: NcSpace.buttonGap),
                        Expanded(child: Text(l10n.screenshotAttached)),
                        IconButton(
                          tooltip: l10n.remove,
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _shot = null),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: NcSpace.sectionGap),
            NcButton(
              label: l10n.submitReport,
              loading: _busy,
              onPressed: _submit,
            ),
            const SizedBox(height: NcSpace.inputGap),
            Text(
              l10n.responseTime,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Figma "Help 6": what to add and how it helps.
class RequestFeatureScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<RequestFeatureScreen> createState() => _FeatureState();
}

class _FeatureState extends ConsumerState<RequestFeatureScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _benefit = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _benefit.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(profileTabApiProvider)
          .requestFeature(
            title: _title.text.trim(),
            benefit: _benefit.text.trim(),
          );
      if (!mounted) return;
      showNcToast(context, l10n.featureRequestSent);
      context.pop();
    } on ApiError catch (e) {
      if (mounted) {
        showNcToast(
          context,
          supportErrorMessage(l10n, e),
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
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.requestFeature)),
      body: Form(
        key: _form,
        child: ListView(
          padding: EdgeInsets.all(nc.screenPadding),
          children: [
            NcTextField(
              controller: _title,
              label: l10n.whatShouldWeAdd,
              hint: l10n.featureTitleHint,
              validator: InputValidators.shortText(max: 120),
              maxLength: 120,
            ),
            const SizedBox(height: NcSpace.cardGap),
            NcTextField(
              controller: _benefit,
              label: l10n.howWouldThisHelp,
              hint: l10n.tellUsWhatHappened,
              validator: InputValidators.freeText(max: 1000),
              maxLength: 1000,
              maxLines: 6,
              minLines: 4,
            ),
            const SizedBox(height: NcSpace.sectionGap),
            NcButton(
              label: l10n.sendRequest,
              loading: _busy,
              onPressed: _submit,
            ),
            const SizedBox(height: NcSpace.inputGap),
            Text(
              l10n.featureRequestNote,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Figma "Help 7" (frame without content yet): the getting-started steps.
class GuideScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final steps = [
      (Icons.water_drop_outlined, l10n.guideWaterTitle, l10n.guideWaterBody),
      (Icons.restaurant_outlined, l10n.guideMealTitle, l10n.guideMealBody),
      (Icons.bedtime_outlined, l10n.guideSleepTitle, l10n.guideSleepBody),
      (
        Icons.local_fire_department_outlined,
        l10n.guideStreakTitle,
        l10n.guideStreakBody,
      ),
      (Icons.diversity_3_outlined, l10n.guideCircleTitle, l10n.guideCircleBody),
      (Icons.description_outlined, l10n.guideReportTitle, l10n.guideReportBody),
    ];
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.guide)),
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          for (final (i, (icon, title, body)) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: NcSpace.buttonGap),
              child: ProfileCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: nc.primarySurface,
                      child: Icon(icon, color: nc.primary),
                    ),
                    const SizedBox(width: NcSpace.buttonGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1}. $title',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: NcSpace.xs),
                          Text(body),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Data sources and services credited on the Licenses page (doc 03): the
/// Open Food Facts database (ODbL) and the nutrition references.
void registerDataSourceLicenses() {
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks(
        ['Open Food Facts'],
        '''
Product data from Open Food Facts (https://world.openfoodfacts.org), available under the Open Database License (ODbL) v1.0. Individual contents are available under the Database Contents License.''',
      ),
    ),
  );
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks(
        ['NaraaCare nutrition references'],
        '''
Food composition values are based on published national food composition tables and dietary reference values for India. Targets in NaraaCare are estimates for general wellness, not medical advice.''',
      ),
    ),
  );
}
