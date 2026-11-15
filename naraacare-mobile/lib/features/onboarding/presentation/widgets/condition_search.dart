import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/profile/data/reference_data.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/shared/widgets/nc_chip.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';

/// Medical condition / allergy picker (O4): a local search over the
/// reference list; only codes are sent, the search text never leaves the
/// device (doc 02 O4). At most 20 codes (API limit).
class ConditionSearch extends ConsumerStatefulWidget {
  const new({required this.selected, required this.onChanged, super.key});

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  static const maxSelected = 20;

  @override
  ConsumerState<ConditionSearch> createState() => _ConditionSearchState();
}

/// The search box sits inside the step's form: empty is fine (nothing to
/// filter); anything typed must pass the search rules.
ValidationError? _optionalSearch(String value) =>
    value.trim().isEmpty ? null : InputValidators.search(value);

class _ConditionSearchState extends ConsumerState<ConditionSearch> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _toggle(String code) {
    // A condition and "none" never go together.
    final next = [...widget.selected]..remove('none');
    if (!next.remove(code)) {
      if (next.length >= ConditionSearch.maxSelected) return;
      next.add(code);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final all = ref.watch(referenceDataProvider).value?.medicalConditions;
    final raw = _query.text;
    final query = InputValidators.search(raw) == null
        ? InputValidators.normalise(raw).toLowerCase()
        : '';
    // The reference list also has a 'none' entry; the app's own None chip
    // (empty selection) stands for it, so it is not shown twice.
    final matches = [
      for (final item in all ?? const <RefItem>[])
        if (item.code != 'none' &&
            (query.isEmpty || item.label.toLowerCase().contains(query)))
          item,
    ];
    final noneSelected = widget.selected.every((code) => code == 'none');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.conditionsLabel,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: NcSpace.inputGap),
        NcTextField(
          controller: _query,
          validator: _optionalSearch,
          maxLength: 64,
          hint: l10n.conditionsHint,
          prefixIcon: Icons.search,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: NcSpace.inputGap),
        if (all == null)
          const Center(child: CircularProgressIndicator())
        else
          Wrap(
            spacing: NcSpace.inputGap,
            runSpacing: NcSpace.inputGap,
            children: [
              NcChip(
                label: l10n.conditionsNone,
                selected: noneSelected,
                onTap: () => widget.onChanged(const []),
              ),
              for (final item in matches.take(30))
                NcChip(
                  label: item.label,
                  selected: widget.selected.contains(item.code),
                  onTap: () => _toggle(item.code),
                ),
            ],
          ),
      ],
    );
  }
}
