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
import 'package:naraacare/features/hydration/presentation/hydration_card.dart';
import 'package:naraacare/features/nutrition/nutrition_providers.dart';
import 'package:naraacare/features/nutrition/presentation/widgets/nutrition_widgets.dart';
import 'package:naraacare/shared/widgets/nc_bottom_sheet.dart';
import 'package:naraacare/shared/widgets/nc_chip.dart';
import 'package:naraacare/shared/widgets/nc_star_badge.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';
import 'package:naraacare/shared/widgets/nc_update_badge.dart';
import 'package:naraacare/shared/widgets/nc_wheel_picker.dart';
import 'package:uuid/uuid.dart';

/// °C stored, °F shown when the user chose it (doc 06 section 1).
String temperatureLabel(double celsius, String unit) => unit == 'f'
    ? '${(celsius * 9 / 5 + 32).round()} °F'
    : '${celsius.toStringAsFixed(_decimals(celsius))} °C';

int _decimals(double c) => c == c.roundToDouble() ? 0 : 1;

// ------------------------------------------------------------------ H2 details

/// "On press" of the Water avatar: level, goal, food water and sweat.
Future<void> showHydrationDetails(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showNcBottomSheet<void>(
    context: context,
    title: l10n.todaysHydration,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final s = ref.watch(shownHydrationProvider).value;
        if (s == null) return const Center(child: CircularProgressIndicator());
        final text = Theme.of(context).textTheme;
        Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: NcSpace.xs),
          child: Row(
            children: [
              Expanded(child: Text(label, style: text.bodyMedium)),
              Text(value, style: text.titleSmall),
            ],
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(hydrationHeadline(l10n, s), style: text.titleLarge),
            const SizedBox(height: NcSpace.inputGap),
            LinearProgressIndicator(value: (s.levelPct / 100).clamp(0, 1)),
            const SizedBox(height: NcSpace.cardGap),
            row(l10n.tankLevel, l10n.levelPct(s.levelPct.round())),
            row(l10n.dailyGoal, '${litres(s.dailyGoalMl)} L'),
            row(l10n.drinksToday, '${litres(s.shownIntakeMl)} L'),
            row(l10n.waterFromFood, l10n.mlValue(s.foodWaterMl)),
            if (s.advanced)
              row(l10n.workoutSweat, l10n.mlValue(s.workoutSweatMl)),
            row(
              l10n.temperature,
              temperatureLabel(s.temperatureC, s.temperatureUnit),
            ),
            row(l10n.leftToDrinkLabel, '${litres(s.leftToDrinkMl)} L'),
          ],
        );
      },
    ),
  );
}

// ------------------------------------------------------------------ H3/H4 add

/// H3/H4 "Add water" | "Other drinks". Presets and a typed amount (digits
/// only, 1-3000 mL); other drinks show the user's tier (locked STAR drinks
/// open the upsell) and STAR custom drinks with an AI estimate.
Future<void> showAddIntakeSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showNcBottomSheet<void>(
    context: context,
    title: l10n.addIntakeTitle,
    builder: (context) => const _AddIntake(),
  );
}

class _AddIntake extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_AddIntake> createState() => _AddIntakeState();
}

class _AddIntakeState extends ConsumerState<_AddIntake> {
  static final Validator _amount = InputValidators.integer(min: 1, max: 3000);
  static const Validator _search = InputValidators.search;
  final _formKey = GlobalKey<FormState>();
  final _ml = TextEditingController();
  final _query = TextEditingController();
  int _tab = 0;
  int? _preset;
  DrinkOption? _drink;
  bool _saving = false;

  @override
  void dispose() {
    _ml.dispose();
    _query.dispose();
    super.dispose();
  }

  int? get _volume => _preset ?? int.tryParse(_ml.text);

  Future<void> _save(DrinkOption drink) async {
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false) && _preset == null) {
      return;
    }
    final volume = _volume;
    if (volume == null) return;
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(hydrationRepositoryProvider)
          .logIntake(
            drink: drink,
            volumeMl: volume,
            source: _preset != null ? 'preset' : 'manual',
          );
      if (!mounted) return;
      if (!result.queued) ref.invalidate(hydrationStatusProvider);
      ref.invalidate(todaysIntakesProvider);
      Navigator.of(context).pop();
      // Shown beside the avatar on Home, not as a toast over the button.
      ref
          .read(avatarUpdatesProvider.notifier)
          .post(
            UpdateTracker.water,
            result.queued ? l10n.badgeSaved : l10n.intakeAdded,
            offline: result.queued,
          );
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code == 'UPGRADE_REQUIRED') {
        unawaited(showStarUpsell(context));
      } else {
        showNcToast(
          context,
          featureErrorMessage(l10n, e),
          kind: NcToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalogue = ref.watch(drinkCatalogueProvider);
    return catalogue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Text(l10n.hydrationUnavailable),
      data: (c) {
        final water = c.drinks.firstWhere((d) => d.isWater);
        final q = _query.text.trim().toLowerCase();
        final others = [
          ...c.drinks.where((d) => !d.isWater),
          ...c.customDrinks,
        ].where((d) => q.isEmpty || d.label.toLowerCase().contains(q)).toList();
        final drink = _tab == 0 ? water : _drink;
        return Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 0, label: Text(l10n.waterTab)),
                  ButtonSegment(value: 1, label: Text(l10n.otherDrinksTab)),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              const SizedBox(height: NcSpace.cardGap),
              if (_tab == 1) ...[
                NcTextField(
                  controller: _query,
                  validator: (v) => v.trim().isEmpty ? null : _search(v),
                  maxLength: 64,
                  hint: l10n.searchDrinkHint,
                  prefixIcon: Icons.search,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: NcSpace.inputGap),
                Wrap(
                  spacing: NcSpace.inputGap,
                  runSpacing: NcSpace.inputGap,
                  children: [
                    for (final d in others)
                      NcChip(
                        label: d.label,
                        icon: d.locked ? Icons.lock_outline : null,
                        selected: _drink == d,
                        onTap: d.locked
                            ? () => showStarUpsell(context)
                            : () => setState(() => _drink = d),
                      ),
                    NcChip(
                      label: l10n.customDrink,
                      icon: Icons.add,
                      onTap: () => _customDrink(context),
                    ),
                  ],
                ),
                const SizedBox(height: NcSpace.cardGap),
              ],
              Wrap(
                spacing: NcSpace.inputGap,
                children: [
                  for (final ml in c.presetsMl)
                    NcChip(
                      label: l10n.mlValue(ml),
                      selected: _preset == ml,
                      onTap: () => setState(() {
                        _preset = _preset == ml ? null : ml;
                        _ml.clear();
                      }),
                    ),
                ],
              ),
              const SizedBox(height: NcSpace.inputGap),
              NcTextField(
                controller: _ml,
                validator: (v) => _preset != null ? null : _amount(v),
                maxLength: 4,
                label: l10n.amountMl,
                keyboardType: TextInputType.number,
                inputFormatters: [NcTextField.digitsOnly],
                onChanged: (_) => setState(() => _preset = null),
              ),
              const SizedBox(height: NcSpace.cardGap),
              FilledButton(
                onPressed: _saving || drink == null || _volume == null
                    ? null
                    : () => _save(drink),
                child: Text(l10n.addIntakeButton),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _customDrink(BuildContext context) async {
    if (!ref.read(isStarProvider)) {
      await showStarUpsell(context);
      return;
    }
    final saved = await showNcBottomSheet<DrinkOption>(
      context: context,
      title: AppLocalizations.of(context).customDrink,
      builder: (context) => const _CustomDrink(),
    );
    if (saved != null && mounted) {
      ref.invalidate(drinkCatalogueProvider);
      setState(() => _drink = saved);
    }
  }
}

/// STAR custom drink: name -> AI estimate (or the 0.85 default) -> the user
/// confirms or adjusts the factor -> saved for reuse.
class _CustomDrink extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_CustomDrink> createState() => _CustomDrinkState();
}

class _CustomDrinkState extends ConsumerState<_CustomDrink> {
  static final Validator _nameValidator = InputValidators.shortText(max: 60);
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  DrinkEstimate? _estimate;
  double _factor = 0.85;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await work();
    } on ApiError catch (e) {
      if (mounted) {
        showNcToast(
          context,
          featureErrorMessage(AppLocalizations.of(context), e),
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
    final api = ref.read(hydrationApiProvider);
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NcTextField(
            controller: _name,
            validator: _nameValidator,
            maxLength: 60,
            label: l10n.customDrinkName,
            hint: l10n.customDrinkHint,
          ),
          const SizedBox(height: NcSpace.inputGap),
          if (_estimate == null)
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final e = await api.estimate(_name.text.trim());
                      setState(() {
                        _estimate = e;
                        _factor = e.hydrationFactor;
                      });
                    }),
              child: Text(l10n.estimateFactor),
            )
          else ...[
            Text(
              _estimate!.source == 'ai'
                  ? l10n.estimateFromAi
                  : _estimate!.explanationCode == 'ai_consent_missing'
                  ? l10n.estimateNoConsent
                  : l10n.estimateDefault,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Slider(
              value: _factor,
              divisions: 20,
              label: l10n.factorPct((_factor * 100).round()),
              onChanged: (v) => setState(() => _factor = v),
            ),
            Text(
              l10n.factorExplain((_factor * 100).round()),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: NcSpace.inputGap),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final adjusted =
                          (_factor - _estimate!.hydrationFactor).abs() > 0.0005;
                      final saved = await api.saveCustomDrink(
                        _name.text.trim(),
                        _factor,
                        adjusted ? 'user' : _estimate!.source,
                      );
                      if (!context.mounted) return;
                      Navigator.of(context).pop(saved);
                    }),
              child: Text(l10n.saveCustomDrink),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ H6 STAR

/// "Water/Temperature & Gym": temperature wheel (15-40 °C, °F shown when
/// chosen) and workouts (6 types, presets 15/30/45/60 or 1-600 min). STAR;
/// STANDARD sees the upsell (OQ-04).
Future<void> showTemperatureActivitySheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showNcBottomSheet<void>(
    context: context,
    title: l10n.temperatureActivity,
    builder: (context) => const _TemperatureActivity(),
  );
}

class _TemperatureActivity extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_TemperatureActivity> createState() =>
      _TemperatureActivityState();
}

class _TemperatureActivityState extends ConsumerState<_TemperatureActivity> {
  static final Validator _minutes = InputValidators.integer(min: 1, max: 600);
  static final List<double> _temps = [
    for (var t = 150; t <= 400; t += 5) t / 10,
  ];
  final _custom = TextEditingController();
  double? _temp;
  String _type = 'walking';
  int? _preset = 30;
  bool _busy = false;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  Future<void> _saveTemperature(double c) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final status = await ref.read(hydrationApiProvider).setTemperature(c);
      if (!mounted) return;
      ref.invalidate(hydrationStatusProvider);
      showNcToast(
        context,
        l10n.temperatureSaved(temperatureLabel(c, status.temperatureUnit)),
      );
    } on ApiError catch (e) {
      if (mounted) _error(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveWorkout() async {
    final l10n = AppLocalizations.of(context);
    final minutes = _preset ?? int.tryParse(_custom.text);
    if (minutes == null || _minutes('$minutes') != null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(hydrationApiProvider)
          .logWorkout(
            clientEntryId: const Uuid().v7(),
            workoutType: _type,
            durationMin: minutes,
            performedAt: DateTime.now(),
          );
      if (!mounted) return;
      ref
        ..invalidate(hydrationStatusProvider)
        ..invalidate(todaysWorkoutsProvider)
        // The workout raises today's calorie allowance (doc 06 section 2.7).
        ..invalidate(dailySummaryProvider);
      showNcToast(context, l10n.workoutSaved);
    } on ApiError catch (e) {
      if (mounted) _error(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _error(ApiError e) {
    if (e.code == 'UPGRADE_REQUIRED') {
      unawaited(showStarUpsell(context));
      return;
    }
    showNcToast(
      context,
      featureErrorMessage(AppLocalizations.of(context), e),
      kind: NcToastKind.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    if (!ref.watch(isStarProvider)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const NcStarBadge(),
          const SizedBox(height: NcSpace.inputGap),
          Text(l10n.temperatureActivityUpsell, textAlign: TextAlign.center),
          const SizedBox(height: NcSpace.cardGap),
          FilledButton(
            onPressed: () => showStarUpsell(context),
            child: Text(l10n.upsellTitle),
          ),
        ],
      );
    }
    final status = ref.watch(hydrationStatusProvider).value;
    final unit = status?.temperatureUnit ?? 'c';
    final current = _temp ?? status?.temperatureC ?? 25;
    final selected = _temps.reduce(
      (a, b) => (a - current).abs() <= (b - current).abs() ? a : b,
    );
    final workouts = ref.watch(todaysWorkoutsProvider).value ?? const [];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.temperature, style: text.titleSmall),
        NcWheelPicker<double>(
          values: _temps,
          selected: selected,
          onChanged: (v) => setState(() => _temp = v),
          labelOf: (v) => temperatureLabel(v, unit),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _saveTemperature(selected),
          child: Text(l10n.saveTemperature),
        ),
        const SizedBox(height: NcSpace.sectionGap),
        Text(l10n.activity, style: text.titleSmall),
        const SizedBox(height: NcSpace.inputGap),
        Wrap(
          spacing: NcSpace.inputGap,
          runSpacing: NcSpace.inputGap,
          children: [
            for (final t in workoutTypes)
              NcChip(
                label: workoutLabel(l10n, t),
                selected: _type == t,
                onTap: () => setState(() => _type = t),
              ),
          ],
        ),
        const SizedBox(height: NcSpace.cardGap),
        Wrap(
          spacing: NcSpace.inputGap,
          children: [
            for (final m in const [15, 30, 45, 60])
              NcChip(
                label: l10n.minutesValue(m),
                selected: _preset == m,
                onTap: () => setState(() {
                  _preset = m;
                  _custom.clear();
                }),
              ),
          ],
        ),
        const SizedBox(height: NcSpace.inputGap),
        NcTextField(
          controller: _custom,
          validator: (v) => _preset != null ? null : _minutes(v),
          maxLength: 3,
          label: l10n.customMinutes,
          keyboardType: TextInputType.number,
          inputFormatters: [NcTextField.digitsOnly],
          onChanged: (_) => setState(() => _preset = null),
        ),
        const SizedBox(height: NcSpace.inputGap),
        FilledButton(
          onPressed: _busy ? null : _saveWorkout,
          child: Text(l10n.saveWorkout),
        ),
        for (final w in workouts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${w.label} · ${l10n.minutesValue(w.durationMin)}'),
            subtitle: Text(
              '${l10n.mlValue(w.sweatMl.round())} · '
              '${l10n.kcalValueShort(w.kcal)}',
            ),
            trailing: w.editable
                ? IconButton(
                    tooltip: l10n.removeItem,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      try {
                        await ref
                            .read(hydrationApiProvider)
                            .deleteWorkout(w.workoutId, w.version);
                        ref
                          ..invalidate(todaysWorkoutsProvider)
                          ..invalidate(hydrationStatusProvider)
                          ..invalidate(dailySummaryProvider);
                      } on ApiError catch (e) {
                        if (mounted) _error(e);
                      }
                    },
                  )
                : null,
          ),
      ],
    );
  }
}

String workoutLabel(AppLocalizations l10n, String code) => switch (code) {
  'walking' => l10n.workoutWalking,
  'gym' => l10n.workoutGym,
  'cycling' => l10n.workoutCycling,
  'swimming' => l10n.workoutSwimming,
  'running' => l10n.workoutRunning,
  _ => l10n.workoutTrekking,
};

// ------------------------------------------------------------------ H7 info

/// "Water/Info" with the corrected swipe copy (OQ-20) and disclaimers.
Future<void> showHydrationInfo(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showNcBottomSheet<void>(
    context: context,
    title: l10n.hydrationInfo,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      final nc = context.nc;
      Widget section(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: NcSpace.cardGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleSmall),
            const SizedBox(height: NcSpace.xs),
            Text(body, style: text.bodyMedium?.copyWith(color: nc.textBody)),
          ],
        ),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section(l10n.hydrationInfoGoalTitle, l10n.hydrationInfoGoalBody),
          section(l10n.hydrationInfoTankTitle, l10n.hydrationInfoTankBody),
          section(
            l10n.hydrationInfoLoggingTitle,
            l10n.hydrationInfoLoggingBody,
          ),
          section(l10n.infoNoteTitle, l10n.hydrationInfoNoteBody),
        ],
      );
    },
  );
}
