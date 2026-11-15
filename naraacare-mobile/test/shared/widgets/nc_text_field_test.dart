import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';

import '../../helpers/harness.dart';
import '../../security/payloads.dart';

void main() {
  final payloads = loadPayloads();
  // A spread of the list (tags, encodings, templates, control characters).
  final sample = [for (var i = 0; i < payloads.length; i += 18) payloads[i]];

  final fields = <String, Validator>{
    'name': InputValidators.name,
    'email': InputValidators.email,
    'shortText': InputValidators.shortText(max: 120),
    'freeText': InputValidators.freeText(max: 2000),
    'chatMessage': InputValidators.chatMessage(),
    'search': InputValidators.search,
  };

  for (final MapEntry(key: label, value: validator) in fields.entries) {
    testWidgets('$label field rejects payloads without echoing them', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(
        themed(
          Form(
            key: formKey,
            child: NcTextField(
              controller: controller,
              validator: validator,
              maxLength: 4000,
              label: label,
            ),
          ),
        ),
      );
      for (final payload in sample) {
        controller.text = payload;
        expect(formKey.currentState!.validate(), isFalse, reason: payload);
        await tester.pump();
        final errors = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .where((t) => t.isNotEmpty && t != label);
        for (final text in errors) {
          if (payload.trim().length >= 4) {
            expect(text.contains(payload.trim()), isFalse, reason: payload);
          }
        }
      }
    });
  }

  testWidgets('valid input passes and shows no error', (tester) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      themed(
        Form(
          key: formKey,
          child: NcTextField(
            controller: TextEditingController(text: 'Priya Sharma'),
            validator: InputValidators.name,
            maxLength: 100,
          ),
        ),
      ),
    );
    expect(formKey.currentState!.validate(), isTrue);
  });

  testWidgets('maxLength is enforced while typing', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      themed(
        NcTextField(
          controller: controller,
          validator: InputValidators.otp,
          maxLength: 6,
          inputFormatters: [NcTextField.digitsOnly],
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), '12a34567890');
    expect(controller.text, '123456');
  });

  testWidgets('secret fields hide text and disable suggestions', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        const NcTextField(
          validator: InputValidators.passwordLogin,
          maxLength: 128,
          secret: true,
        ),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);
    expect(field.enableSuggestions, isFalse);
    expect(field.autocorrect, isFalse);
    expect(field.enableIMEPersonalizedLearning, isFalse);
    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();
    final shown = tester.widget<TextField>(find.byType(TextField));
    expect(shown.obscureText, isFalse);
  });

  testWidgets('username formatter lower-cases and drops other characters', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      themed(
        NcTextField(
          controller: controller,
          validator: InputValidators.username,
          maxLength: 30,
          inputFormatters: NcTextField.username,
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Priya.S <x>');
    expect(controller.text, 'priya.sx');
  });
}
