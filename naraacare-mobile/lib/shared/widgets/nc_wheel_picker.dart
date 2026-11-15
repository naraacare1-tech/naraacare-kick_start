import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// Wheel of fixed values (height ruler, temperature, time; Figma pickers).
/// Values come from a closed list, so no free text is ever typed here.
class NcWheelPicker<T> extends StatelessWidget {
  const new({
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.labelOf,
    super.key,
    this.itemExtent = 40,
    this.height = 200,
  });

  final List<T> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T value) labelOf;
  final double itemExtent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final index = values.indexOf(selected);
    return SizedBox(
      height: height,
      child: CupertinoPicker.builder(
        itemExtent: itemExtent,
        scrollController: FixedExtentScrollController(
          initialItem: index < 0 ? 0 : index,
        ),
        selectionOverlay: DecoratedBox(
          decoration: BoxDecoration(
            color: nc.primarySurface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(NcRadius.s),
          ),
        ),
        onSelectedItemChanged: (i) => onChanged(values[i]),
        childCount: values.length,
        itemBuilder: (context, i) => Center(
          child: Text(
            labelOf(values[i]),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }
}
