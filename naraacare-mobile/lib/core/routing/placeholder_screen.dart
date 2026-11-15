import 'package:flutter/material.dart';
import 'package:naraacare/core/theme/app_theme.dart';

/// Stand-in for screens built in later sessions (S07 auth/onboarding, S08+
/// tabs). Only routing is real here.
class PlaceholderScreen extends StatelessWidget {
  const new({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(context.nc.screenPadding),
          child: Center(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
      ),
    );
  }
}
