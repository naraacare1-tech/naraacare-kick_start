import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/utils/logger.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/onboarding/presentation/onboarding_draft.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/shared/widgets/nc_status_screen.dart';

/// O7 "Generating your health profile…": completes onboarding with the
/// consents, then stores the chosen avatar and display units.
class GeneratingScreen extends ConsumerStatefulWidget {
  const new({required this.consents, super.key});

  final List<Map<String, Object?>> consents;

  @override
  ConsumerState<GeneratingScreen> createState() => _GeneratingScreenState();
}

class _GeneratingScreenState extends ConsumerState<GeneratingScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    // After the first frame: _complete reads inherited widgets (l10n).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_complete());
    });
  }

  Future<void> _complete() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _error = null);
    final api = ref.read(profileApiProvider);
    final draft = ref.read(onboardingDraftProvider);
    try {
      await api.complete(widget.consents);
    } on ApiError catch (e) {
      // Completed already (a retry after a lost response) counts as done.
      if (e.code != 'ONBOARDING_ALREADY_COMPLETED') {
        if (mounted) setState(() => _error = featureErrorMessage(l10n, e));
        return;
      }
    }
    // Best effort: neither blocks the user, both can be changed in Settings.
    try {
      if (draft.sex != null && draft.bodyType != null) {
        await api.patchProfile({'avatar_code': draft.avatarCode()});
      }
      final me = await api.me();
      await api.putSettings({
        ...me.settings..remove('sleep_goal_min'),
        'height_unit': draft.feetInches ? 'ft_in' : 'cm',
        'weight_unit': draft.pounds ? 'lb' : 'kg',
      });
    } on ApiError catch (e) {
      log.info('onboarding_preferences_failed', {'code': e.code});
    }
    if (mounted) context.go(Routes.onboardingSaved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NcStatusScreen(
      title: l10n.generatingTitle,
      body: _error,
      busy: _error == null,
      actionLabel: _error == null ? null : l10n.actionRetry,
      onAction: _complete,
    );
  }
}

/// O7 "Final page": Saved Details, then Home after a moment.
class SavedScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends ConsumerState<SavedScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 2), () {
      ref.invalidate(meProvider);
      unawaited(ref.read(authControllerProvider).onboardingCompleted());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NcStatusScreen(title: l10n.savedTitle, body: l10n.savedBody);
  }
}
