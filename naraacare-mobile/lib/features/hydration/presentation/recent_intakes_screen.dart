import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/hydration/data/hydration_models.dart';
import 'package:naraacare/features/hydration/hydration_providers.dart';
import 'package:naraacare/shared/widgets/nc_bottom_sheet.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';

/// H5 "Recent Updates": today's drinks; only the last 2 (within 7 days) can
/// be edited or deleted (OQ-53, enforced by the server). A 409 replaces the
/// local copy with the server's (server wins).
class RecentIntakesScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final intakes = ref.watch(todaysIntakesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.recentUpdates)),
      backgroundColor: nc.surface,
      body: intakes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.hydrationUnavailable)),
        data: (items) => items.isEmpty
            ? Center(child: Text(l10n.noDrinksYet))
            : ListView(
                padding: EdgeInsets.all(nc.screenPadding),
                children: [
                  for (final i in items.reversed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.water_drop_outlined),
                      title: Text(
                        i.isSwipeDown
                            ? l10n.swipeDownEntry(-i.volumeMl)
                            : '${i.label} · ${l10n.mlValue(i.volumeMl)}',
                      ),
                      subtitle: Text(
                        MaterialLocalizations.of(context).formatTimeOfDay(
                          TimeOfDay.fromDateTime(i.loggedAt.toLocal()),
                        ),
                      ),
                      trailing: i.editable
                          ? IconButton(
                              tooltip: l10n.editEntry,
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _edit(context, ref, i),
                            )
                          : null,
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Intake intake) =>
      showNcBottomSheet<void>(
        context: context,
        title: AppLocalizations.of(context).editEntry,
        builder: (context) => _EditIntake(intake: intake),
      );
}

class _EditIntake extends ConsumerStatefulWidget {
  const new({required this.intake});

  final Intake intake;

  @override
  ConsumerState<_EditIntake> createState() => _EditIntakeState();
}

class _EditIntakeState extends ConsumerState<_EditIntake> {
  static final Validator _amount = InputValidators.integer(min: 1, max: 3000);
  final _formKey = GlobalKey<FormState>();
  late final _ml = TextEditingController(
    text: widget.intake.isSwipeDown ? '' : '${widget.intake.volumeMl}',
  );
  bool _busy = false;

  @override
  void dispose() {
    _ml.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work, String done) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await work();
      if (!mounted) return;
      ref
        ..invalidate(todaysIntakesProvider)
        ..invalidate(hydrationStatusProvider);
      Navigator.of(context).pop();
      showNcToast(context, done);
    } on ApiError catch (e) {
      if (!mounted) return;
      ref.invalidate(todaysIntakesProvider);
      showNcToast(context, switch (e.code) {
        'VERSION_CONFLICT' => l10n.changedElsewhere,
        'WATER_BELOW_ZERO' => l10n.waterBelowZero,
        _ => featureErrorMessage(l10n, e),
      }, kind: NcToastKind.error);
      if (e.code == 'VERSION_CONFLICT') Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final api = ref.read(hydrationApiProvider);
    final i = widget.intake;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!i.isSwipeDown) ...[
            NcTextField(
              controller: _ml,
              validator: _amount,
              maxLength: 4,
              label: l10n.amountMl,
              keyboardType: TextInputType.number,
              inputFormatters: [NcTextField.digitsOnly],
            ),
            const SizedBox(height: NcSpace.inputGap),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () {
                      if (!(_formKey.currentState?.validate() ?? false)) return;
                      unawaited(
                        _run(
                          () => api.updateIntake(
                            i.intakeId,
                            i.version,
                            volumeMl: int.parse(_ml.text),
                          ),
                          l10n.entryUpdated,
                        ),
                      );
                    },
              child: Text(l10n.saveChanges),
            ),
            const SizedBox(height: NcSpace.inputGap),
          ],
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: nc.error),
            onPressed: _busy
                ? null
                : () => _run(
                    () => api.deleteIntake(i.intakeId, i.version),
                    l10n.entryDeleted,
                  ),
            child: Text(l10n.deleteEntry),
          ),
        ],
      ),
    );
  }
}
