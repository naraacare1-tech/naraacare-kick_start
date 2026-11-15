import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/onboarding/presentation/step_saver.dart';
import 'package:naraacare/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:naraacare/features/profile/profile_providers.dart';

/// O6 (Figma "Onboarding 6"): the three body types as plain-T-shirt figures
/// (Figma Avatars "3 body types", `assets/avatars/<sex>_body_<code>.webp`) in a
/// carousel: the centred one is the choice, its neighbours are smaller and
/// faded; swipe or tap a neighbour to rotate it to the centre ("rotation
/// based on thumb swipe or click"). Its name is repeated in the info text.
class Step6BodyTypeScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<Step6BodyTypeScreen> createState() => _Step6State();
}

class _Step6State extends ConsumerState<Step6BodyTypeScreen>
    with StepSaver<Step6BodyTypeScreen> {
  @override
  int get step => 6;

  late String? _bodyType = draft.bodyType;
  PageController? _pages;

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_bodyType == null) return;
    draft.bodyType = _bodyType;
    await saveAndContinue({'body_type': _bodyType});
  }

  /// The carousel starts on the saved choice, else the middle type, which is
  /// then the choice until the user rotates to another one.
  PageController _controller(List<String> codes) {
    final existing = _pages;
    if (existing != null) return existing;
    final saved = codes.indexOf(_bodyType ?? '');
    final start = saved >= 0 ? saved : codes.length ~/ 2;
    _bodyType = codes[start];
    return _pages = PageController(initialPage: start, viewportFraction: 0.56);
  }

  String _asset(String code) =>
      'assets/avatars/${draft.sex == 'female' ? 'female' : 'male'}_body_'
      '$code.webp';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final reference = ref.watch(referenceDataProvider).value;
    final types = reference?.bodyTypes ?? const [];
    final pages = types.isEmpty
        ? null
        : _controller([for (final t in types) t.code]);
    return OnboardingScaffold(
      step: step,
      title: l10n.step6Title,
      why: _bodyType == null || reference == null
          ? l10n.step6Why
          : '${l10n.step6Why} '
                '${l10n.bodyTypeChosen(reference.label(types, _bodyType))}',
      busy: busy,
      error: error,
      onBack: goBack,
      onNext: _bodyType == null ? null : _next,
      child: pages == null
          ? const SizedBox(
              height: NcSize.icon * 12,
              child: Center(child: CircularProgressIndicator()),
            )
          : SizedBox(
              height: NcSize.icon * 18,
              child: PageView.builder(
                controller: pages,
                itemCount: types.length,
                onPageChanged: (i) => setState(() => _bodyType = types[i].code),
                itemBuilder: (context, i) {
                  final type = types[i];
                  final chosen = _bodyType == type.code;
                  return AnimatedBuilder(
                    animation: pages,
                    builder: (context, child) {
                      // 1 in the centre, smaller and faded further out.
                      final page =
                          pages.hasClients && pages.position.haveDimensions
                          ? pages.page ?? i.toDouble()
                          : pages.initialPage.toDouble();
                      final away = math.min(1, (page - i).abs()).toDouble();
                      return Opacity(
                        opacity: 1 - 0.55 * away,
                        child: Transform.scale(
                          scale: 1 - 0.18 * away,
                          child: child,
                        ),
                      );
                    },
                    child: Semantics(
                      button: true,
                      selected: chosen,
                      label: type.label,
                      child: GestureDetector(
                        onTap: () => pages.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: NcSpace.xs,
                                ),
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  // The art has a white background (Figma).
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(
                                    NcRadius.l,
                                  ),
                                  border: Border.all(
                                    color: chosen ? nc.primary : nc.border,
                                    width: chosen ? 2 : 1,
                                  ),
                                ),
                                child: Image.asset(
                                  _asset(type.code),
                                  fit: BoxFit.contain,
                                  excludeFromSemantics: true,
                                ),
                              ),
                            ),
                            const SizedBox(height: NcSpace.inputGap),
                            Text(
                              type.label.split(' (').first,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: chosen ? nc.primary : null),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
