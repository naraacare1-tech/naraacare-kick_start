import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/nutrition/data/nutrition_models.dart';
import 'package:naraacare/features/nutrition/nutrition_providers.dart';
import 'package:naraacare/features/nutrition/presentation/widgets/nutrition_widgets.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_error_banner.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';
import 'package:speech_to_text/speech_to_text.dart';

// ---------------------------------------------------------------------------
// Voice (N5, STAR, OQ-43)

/// Speech-to-text on the device (platform recogniser; English (India) when
/// the phone has it, else the phone's language): only the text reaches the
/// app, never audio. An interface so tests need no mic. `onError` reports a
/// recogniser failure after listening started (no speech heard, no network,
/// microphone busy), so the screen stops "listening" and says so.
abstract interface class VoiceRecognizer {
  Future<bool> start(
    void Function(String words, {required bool done}) onWords, {
    void Function()? onError,
  });
  Future<void> stop();
}

class PlatformVoiceRecognizer implements VoiceRecognizer {
  final _speech = SpeechToText();
  bool _ready = false;
  void Function()? _onError;

  @override
  Future<bool> start(
    void Function(String words, {required bool done}) onWords, {
    void Function()? onError,
  }) async {
    _onError = onError;
    try {
      // initialize() asks for the microphone permission the first time; the
      // error listener can only be set once, so it forwards to _onError.
      _ready =
          _ready || await _speech.initialize(onError: (_) => _onError?.call());
      if (!_ready) return false;
      final locales = await _speech.locales();
      final indian = locales.any((l) => l.localeId == 'en_IN');
      await _speech.listen(
        onResult: (r) => onWords(r.recognizedWords, done: r.finalResult),
        listenOptions: SpeechListenOptions(
          localeId: indian ? 'en_IN' : null,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 4),
          cancelOnError: true,
        ),
      );
      return true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> stop() => _speech.stop();
}

final voiceRecognizerProvider = Provider<VoiceRecognizer>(
  (ref) => PlatformVoiceRecognizer(),
);

/// N5 "Nutrition Update" (voice): listen, show the transcript (editable,
/// freeText(300)), parse it on the server into food candidates, let the user
/// adjust them, then add them to the meal (source voice).
class VoiceMealScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<VoiceMealScreen> createState() => _VoiceMealScreenState();
}

class _VoiceMealScreenState extends ConsumerState<VoiceMealScreen> {
  final _form = GlobalKey<FormState>();
  final _transcript = TextEditingController();
  bool _listening = false;
  bool _busy = false;
  String? _error;
  VoiceParse? _parsed;
  List<MealItemDraft> _items = const [];

  static final Validator _transcriptValidator = InputValidators.freeText(
    max: 300,
  );

  @override
  void dispose() {
    unawaited(ref.read(voiceRecognizerProvider).stop());
    _transcript.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final recognizer = ref.read(voiceRecognizerProvider);
    if (_listening) {
      await recognizer.stop();
      setState(() => _listening = false);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final ok = await recognizer.start(
      (words, {required done}) {
        if (!mounted) return;
        setState(() {
          _transcript.text = words.length > 300
              ? words.substring(0, 300)
              : words;
          if (done) _listening = false;
        });
      },
      onError: () {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _error = l10n.voiceDidNotHear;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _listening = ok;
      _error = ok ? null : l10n.voiceUnavailable;
    });
  }

  Future<void> _parse() async {
    if (!_form.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final parsed = await ref
          .read(nutritionApiProvider)
          .parseVoice(InputValidators.normalise(_transcript.text), 'en-IN');
      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        _items = [...parsed.items];
        if (parsed.items.isEmpty) _error = l10n.voiceNothingFound;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code == ApiError.upgradeRequired) {
        await showStarUpsell(context);
        return;
      }
      setState(() => _error = featureErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addToMeal() {
    ref.read(mealDraftProvider.notifier).addAll(_items, MealSource.voice);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final parsed = _parsed;
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.voiceTitle), backgroundColor: nc.surface),
      body: Form(
        key: _form,
        child: ListView(
          padding: EdgeInsets.all(nc.screenPadding),
          children: [
            Center(
              child: IconButton.filled(
                iconSize: NcSize.icon * 2,
                tooltip: _listening ? l10n.voiceStop : l10n.voiceStart,
                icon: Icon(_listening ? Icons.stop : Icons.mic),
                onPressed: _toggle,
              ),
            ),
            const SizedBox(height: NcSpace.inputGap),
            Text(
              _listening ? l10n.voiceListening : l10n.voiceTrySaying,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: nc.textSecondary),
            ),
            const SizedBox(height: NcSpace.cardGap),
            NcTextField(
              controller: _transcript,
              validator: _transcriptValidator,
              maxLength: 300,
              maxLines: 3,
              label: l10n.voiceTranscriptLabel,
              hint: l10n.voiceTranscriptHint,
            ),
            const SizedBox(height: NcSpace.inputGap),
            NcButton(
              label: l10n.voiceFindFoods,
              variant: NcButtonVariant.secondary,
              loading: _busy,
              onPressed: _parse,
            ),
            if (_error != null) ...[
              const SizedBox(height: NcSpace.inputGap),
              NcErrorBanner(message: _error!),
            ],
            if (parsed != null && parsed.unmatched.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: NcSpace.inputGap),
                child: Text(
                  l10n.voiceUnmatched(parsed.unmatched.join(', ')),
                  style: text.bodySmall?.copyWith(color: nc.textSecondary),
                ),
              ),
            if (_items.isNotEmpty) ...[
              const SizedBox(height: NcSpace.cardGap),
              Text(l10n.checkBeforeSaving, style: text.titleSmall),
              const SizedBox(height: NcSpace.inputGap),
              for (var i = 0; i < _items.length; i++)
                FoodItemRow(
                  key: ValueKey('voice-$i-${_items[i].foodId}'),
                  item: _items[i],
                  onChanged: (item) =>
                      setState(() => _items = [..._items]..[i] = item),
                  onRemove: () =>
                      setState(() => _items = [..._items]..removeAt(i)),
                ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: EdgeInsets.all(nc.screenPadding),
                child: NcButton(label: l10n.addToMeal, onPressed: _addToMeal),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Barcode (N6, STAR, OQ-44)

/// The camera view. Decoding happens on the device (mobile_scanner); only
/// the digits are sent. Replaceable in tests (no camera there).
typedef ScannerBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onCode,
);

final scannerBuilderProvider = Provider<ScannerBuilder>(
  (ref) =>
      (context, onCode) => MobileScanner(
        controller: MobileScannerController(
          formats: const [
            BarcodeFormat.ean13,
            BarcodeFormat.ean8,
            BarcodeFormat.upcA,
            BarcodeFormat.upcE,
          ],
        ),
        onDetect: (capture) {
          for (final b in capture.barcodes) {
            final value = b.rawValue;
            if (value != null) onCode(value);
          }
        },
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(NcSpace.cardPadding),
            child: Text(AppLocalizations.of(context).barcodePermission),
          ),
        ),
      ),
);

/// 8-14 digits with a valid GTIN check digit (the API rule, SafeBarcode).
ValidationError? validateBarcode(String value) {
  final digits = InputValidators.normalise(value);
  if (digits.isEmpty) return ValidationError.required;
  if (!RegExp(r'^\d{8,14}$').hasMatch(digits) ||
      !InputValidators.gtinValid(digits)) {
    return ValidationError.format;
  }
  return null;
}

/// N6 barcode: scan (or type the number), look the product up (our cache,
/// then Open Food Facts), add one serving to the meal (source barcode).
class BarcodeMealScreen extends ConsumerStatefulWidget {
  const new({super.key, this.initialCode});

  final String? initialCode;

  @override
  ConsumerState<BarcodeMealScreen> createState() => _BarcodeMealScreenState();
}

class _BarcodeMealScreenState extends ConsumerState<BarcodeMealScreen> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.initialCode);
  BarcodeResult? _result;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_lookup(widget.initialCode!));
      });
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _lookup(String raw) async {
    final code = InputValidators.normalise(raw);
    if (_busy || validateBarcode(code) != null || _result?.barcode == code) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _code.text = code;
    });
    try {
      final result = await ref.read(nutritionApiProvider).barcode(code);
      if (!mounted) return;
      setState(() {
        _result = result;
        if (!result.found) {
          _error = l10n.barcodeNotFound;
        } else if (result.foodId == null) {
          _error = l10n.barcodeNotLoggable;
        }
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code == ApiError.upgradeRequired) {
        await showStarUpsell(context);
        return;
      }
      setState(() => _error = featureErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addToMeal(BarcodeResult result) {
    final added = ref
        .read(mealDraftProvider.notifier)
        .add(
          MealItemDraft(
            foodId: result.foodId!,
            foodName: result.productName ?? result.barcode,
            quantity: 1,
            unitCode: 'serving',
            unitSize: 'standard',
            portionLabel: 'Serving',
          ),
          source: MealSource.barcode,
        );
    if (added) context.pop();
  }

  void _scanAnother() => setState(() {
    _result = null;
    _error = null;
    _code.clear();
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final result = _result;
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(
        title: Text(l10n.barcodeTitle),
        backgroundColor: nc.surface,
      ),
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          if (result == null)
            ClipRRect(
              borderRadius: BorderRadius.circular(NcRadius.l),
              child: SizedBox(
                height: NcSize.icon * 10,
                child: ref.watch(scannerBuilderProvider)(
                  context,
                  (code) => unawaited(_lookup(code)),
                ),
              ),
            ),
          const SizedBox(height: NcSpace.cardGap),
          Form(
            key: _form,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: NcTextField(
                    controller: _code,
                    validator: validateBarcode,
                    maxLength: 14,
                    label: l10n.barcodeManualLabel,
                    hint: l10n.barcodeManualHint,
                    keyboardType: TextInputType.number,
                    inputFormatters: [NcTextField.digitsOnly],
                    onSubmitted: (v) {
                      if (_form.currentState!.validate()) {
                        unawaited(_lookup(v));
                      }
                    },
                  ),
                ),
                const SizedBox(width: NcSpace.inputGap),
                Padding(
                  padding: const EdgeInsets.only(top: NcSpace.xs),
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_form.currentState!.validate()) {
                              unawaited(_lookup(_code.text));
                            }
                          },
                    child: Text(l10n.barcodeLookup),
                  ),
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            const SizedBox(height: NcSpace.inputGap),
            NcErrorBanner(
              message: _error!,
              actionLabel: l10n.searchByName,
              onAction: () => context.pushReplacement(Routes.addMeal),
            ),
          ],
          if (result != null && result.found) ...[
            const SizedBox(height: NcSpace.cardGap),
            Text(result.productName ?? '', style: text.titleMedium),
            if (result.brand != null)
              Text(result.brand!, style: TextStyle(color: nc.textSecondary)),
            if (result.servingG != null)
              Text(
                l10n.servingSize(formatQuantity(result.servingG!.toDouble())),
              ),
            const SizedBox(height: NcSpace.inputGap),
            Text(l10n.per100g, style: text.titleSmall),
            NutrientList(view: result.per100),
            UpsellCard(lockedCount: result.per100.lockedCount),
            const SizedBox(height: NcSpace.inputGap),
            Text(
              l10n.openFoodFactsCredit,
              style: text.bodySmall?.copyWith(color: nc.textSecondary),
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: NcSpace.cardGap),
            if (result.foodId != null)
              NcButton(
                label: l10n.addToMeal,
                onPressed: () => _addToMeal(result),
              ),
            const SizedBox(height: NcSpace.inputGap),
            NcButton(
              label: l10n.scanAnother,
              variant: NcButtonVariant.secondary,
              onPressed: _scanAnother,
            ),
          ],
        ],
      ),
    );
  }
}
