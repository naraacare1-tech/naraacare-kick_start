import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/features/profile/data/reference_data.dart';
import 'package:naraacare/features/profile/profile_providers.dart';

/// Weight goal picker: only the goals the API allows for the user's BMI
/// ([allowed]; null while unknown), labelled from the reference data.
class GoalDropdown extends ConsumerWidget {
  const new({
    required this.allowed,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<String>? allowed;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final reference = ref.watch(referenceDataProvider).value;
    final goals = [
      for (final goal in reference?.weightGoals ?? const <RefItem>[])
        if (allowed?.contains(goal.code) ?? false) goal,
    ];
    return DropdownButtonFormField<String>(
      initialValue: goals.any((g) => g.code == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: l10n.goalLabel),
      hint: Text(l10n.goalHint),
      items: [
        for (final goal in goals)
          DropdownMenuItem(value: goal.code, child: Text(goal.label)),
      ],
      onChanged: goals.isEmpty ? null : onChanged,
    );
  }
}
