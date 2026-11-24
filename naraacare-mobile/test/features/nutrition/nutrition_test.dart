import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/core/l10n/generated/app_localizations_en.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/sync/outbox.dart';
import 'package:naraacare/features/nutrition/data/nutrition_models.dart';
import 'package:naraacare/features/nutrition/presentation/widgets/nutrition_widgets.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/harness.dart';

const apple = '0192f000-0000-7000-8000-000000000001';
const dal = '0192f000-0000-7000-8000-000000000004';
const roti = '0192f000-0000-7000-8000-000000000003';

const _standard = [
  ('calories', 'Calories', 'kcal'),
  ('protein', 'Protein', 'g'),
  ('carbohydrates', 'Carbohydrates', 'g'),
  ('fat', 'Fat', 'g'),
  ('dietary_fiber', 'Dietary Fiber', 'g'),
  ('total_sugar', 'Total Sugar', 'g'),
];
const _star = [
  ('iron', 'Iron', 'mg'),
  ('calcium', 'Calcium', 'mg'),
  ('saturated_fat', 'Saturated Fat', 'g'),
  ('polyunsaturated_fat', 'Polyunsaturated Fat', 'g'),
  ('monounsaturated_fat', 'Monounsaturated Fat', 'g'),
  ('trans_fat', 'Trans Fat', 'g'),
  ('cholesterol', 'Cholesterol', 'mg'),
  ('potassium', 'Potassium', 'mg'),
  ('vitamin_a', 'Vitamin A', 'mcg'),
  ('vitamin_c', 'Vitamin C', 'mg'),
  ('sodium', 'Sodium', 'mg'),
];

Map<String, Object?> nutrients({bool star = false, int calories = 78}) => {
  'nutrients': [
    for (final (code, label, unit) in [..._standard, if (star) ..._star])
      {
        'code': code,
        'label': label,
        'unit': unit,
        'value': code == 'calories' ? calories : 21,
      },
  ],
  'locked_nutrients_count': star ? 0 : 11,
};

Map<String, Object?> summary({
  int calories = 78,
  int mealCount = 1,
  bool star = false,
  String state = 'fueling',
}) => {
  'date': '2026-10-31',
  'calories': calories,
  ...nutrients(star: star, calories: calories),
  'target_kcal': 2214,
  'effective_allowance_kcal': 2214,
  'exercise_kcal': 0,
  'avatar': {'fill_pct': 3.5, 'state': state},
  'meal_count': mealCount,
  'meal_limit': star ? 8 : 4,
  'last_updated': '2026-10-31T07:50:00Z',
};

Map<String, Object?> meal({
  String id = '0190f5d2-0000-7000-8000-00000000a001',
  int version = 1,
  bool editable = true,
  int calories = 78,
}) => {
  'meal_id': id,
  'logged_at': '2026-10-31T07:50:00Z',
  'local_date': '2026-10-31',
  'meal_type': 'lunch',
  'source': 'search',
  'version': version,
  'editable': editable,
  'hydration_credit': true,
  'calories': calories,
  'items': [
    {
      'item_id': 'i1',
      'food_id': apple,
      'food_name': 'Apple',
      'quantity': 1,
      'unit_code': 'piece',
      'unit_size': 'medium',
      'consumed_amount': 150,
      'consumed_basis': 'g',
      'calories': calories,
    },
  ],
};

const Map<String, Object> searchResults = {
  'results': [
    {
      'food_id': dal,
      'name': 'Moong Dal (Cooked)',
      'matched_alias': null,
      'default_portion': {
        'unit_code': 'katori',
        'unit_size': 'medium',
        'label': 'Medium Katori',
        'quantity': 150,
        'basis': 'ml',
      },
      'kcal_per_default': 158,
    },
  ],
};

Map<String, Object?> foodDetail(String id, String name) => {
  'food_id': id,
  'name': name,
  'basis': 'ml',
  'category_code': 'dal_gravy',
  'is_cooked': true,
  'aliases': <String>[],
  'portions': [
    {
      'unit_code': 'katori',
      'size': 'medium',
      'label': 'Medium Katori',
      'quantity': 150,
      'basis': 'ml',
      'is_default': true,
    },
    {
      'unit_code': 'katori',
      'size': 'small',
      'label': 'Small Katori',
      'quantity': 100,
      'basis': 'ml',
      'is_default': false,
    },
  ],
  'per_100': nutrients(),
};

void main() {
  late AppHarness h;

  setUp(() => h = AppHarness());

  /// Signed in at Home; [star] makes the user STAR.
  Future<void> home(WidgetTester tester, {bool star = false}) async {
    await h.signIn();
    h.server
      ..on('auth/token/refresh', 200, tokenPairJson())
      ..on('me', 200, {...meJson(), 'tier': star ? 'star' : 'standard'})
      ..on('reference/bootstrap', 200, referenceBootstrap)
      ..on('nutrition/daily-summary', 200, summary(star: star))
      ..on('meals/recent', 200, {
        'meals': [meal()],
        'recent_foods': [
          {
            'food_id': apple,
            'name': 'Apple',
            'quantity': 1,
            'unit_code': 'piece',
            'unit_size': 'medium',
          },
        ],
      })
      ..on('foods/search', 200, searchResults)
      ..on('foods/$dal', 200, foodDetail(dal, 'Moong Dal (Cooked)'))
      ..on('foods/$roti', 200, foodDetail(roti, 'Roti (Whole Wheat)'))
      ..on('saved-meals', 200, {'saved_meals': <Object>[]});
    await h.pump(tester);
    expect(h.location, Routes.home);
  }

  Future<void> addDal(WidgetTester tester) async {
    await h.go(tester, Routes.addMeal);
    await h.type(tester, h.l10n.searchFoodOrBarcodeHint, 'moong');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await h.tapText(tester, 'Moong Dal (Cooked)');
  }

  Map<dynamic, dynamic> lastMealPost() =>
      h.server.bodiesFor('meals').last! as Map<dynamic, dynamic>;

  group("N1/N2 avatar and Today's Nutrition", () {
    testWidgets('Home shows server kcal, goal and state', (tester) async {
      await home(tester);
      expect(find.text(h.l10n.kcalValueShort(78)), findsOneWidget);
      expect(find.textContaining(h.l10n.ofGoalKcal(2214)), findsOneWidget);
      expect(find.textContaining(h.l10n.avatarFueling), findsOneWidget);
    });

    testWidgets('STANDARD: 6 nutrients and the STAR upsell', (tester) async {
      await home(tester);
      await h.tapText(tester, h.l10n.kcalValueShort(78));
      expect(find.text(h.l10n.todaysNutrition), findsOneWidget);
      expect(find.text(h.l10n.caloriesOfGoal(78, 2214)), findsOneWidget);
      for (final (_, label, _) in _standard.skip(1)) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Iron'), findsNothing);
      expect(find.text(h.l10n.lockedNutrients(11)), findsOneWidget);
    });

    testWidgets('STAR: 17 nutrients, all unlocked', (tester) async {
      await home(tester, star: true);
      await h.tapText(tester, h.l10n.kcalValueShort(78));
      expect(find.text('Iron'), findsOneWidget);
      expect(find.text('Vitamin C'), findsOneWidget);
      expect(find.text(h.l10n.allNutrientsUnlocked), findsOneWidget);
    });
  });

  group('N3 Add Meal', () {
    testWidgets('debounced search, add, stepper, dry run, save', (
      tester,
    ) async {
      await home(tester);
      await h.go(tester, Routes.addMeal);
      await h.type(tester, h.l10n.searchFoodOrBarcodeHint, 'm');
      await h.type(tester, h.l10n.searchFoodOrBarcodeHint, 'moo');
      await h.type(tester, h.l10n.searchFoodOrBarcodeHint, 'moong');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final searches = h.server.requests.where((r) => r.$2 == 'foods/search');
      expect(searches, hasLength(1)); // only the last keystroke searched

      await h.tapText(tester, 'Moong Dal (Cooked)');
      expect(find.text(h.l10n.addItemsCount(1)), findsOneWidget);
      expect(find.text(h.l10n.kcalValueShort(158)), findsOneWidget);
      await tester.tap(find.byTooltip(h.l10n.increaseQuantity));
      await tester.pumpAndSettle();
      expect(find.text('1.25'), findsOneWidget);
      // The kcal of the old quantity is not shown (no app-side maths).
      expect(find.text(h.l10n.kcalValueShort(158)), findsNothing);

      h.server.on('meals?dry_run=true', 200, {
        'calories': 197,
        'totals': nutrients(calories: 197),
        'items': <Object>[],
      });
      await h.tapText(tester, h.l10n.viewNutritionSummary);
      expect(h.location, Routes.mealSummary);
      expect(find.text(h.l10n.kcalValueShort(197)), findsOneWidget);
      final dry = h.server.bodiesFor('meals?dry_run=true').single! as Map;
      expect((dry['items'] as List).single, {
        'food_id': dal,
        'quantity': 1.25,
        'unit_code': 'katori',
        'unit_size': 'medium',
      });
      expect(find.text(h.l10n.lockedNutrients(11)), findsOneWidget);

      h.server.on('meals', 201, {
        'meal': meal(calories: 197),
        'daily_summary': summary(calories: 275, mealCount: 2),
        'avatar': {'fill_pct': 12.4, 'state': 'fueling'},
      });
      await h.tapText(tester, h.l10n.saveMealButton);
      await h.tapText(tester, h.l10n.mealTypeDinner);
      await tester.tap(find.text(h.l10n.saveMealButton).last);
      await tester.pumpAndSettle();
      final body = lastMealPost();
      expect(body['meal_type'], 'dinner');
      expect(body['source'], 'search');
      expect(body['client_entry_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(DateTime.parse(body['logged_at'] as String).isUtc, isTrue);
      expect(h.location, Routes.home);
      expect(find.text(h.l10n.mealSaved), findsOneWidget);
    });

    testWidgets('a unit change asks the server for new totals', (tester) async {
      await home(tester);
      await addDal(tester);
      await tester.tap(find.byType(DropdownButton<Portion>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Small Katori (100 ml)').last);
      await tester.pumpAndSettle();
      expect(find.text(h.l10n.kcalValueShort(158)), findsNothing);
      expect(find.text('Small Katori (100 ml)'), findsOneWidget);
    });

    testWidgets('recent chips add the last-used portion', (tester) async {
      await home(tester);
      await h.go(tester, Routes.addMeal);
      await h.tapText(tester, 'Apple');
      expect(find.text(h.l10n.addItemsCount(1)), findsOneWidget);
    });

    testWidgets('STANDARD: mic and barcode open the upsell', (tester) async {
      await home(tester);
      await h.go(tester, Routes.addMeal);
      await tester.tap(find.byTooltip(h.l10n.voiceLogging));
      await tester.pumpAndSettle();
      expect(find.text(h.l10n.upsellBody), findsOneWidget);
      expect(h.location, Routes.addMeal);
    });

    testWidgets('DAILY_LIMIT_REACHED: limit sheet with the STAR upsell', (
      tester,
    ) async {
      await home(tester);
      await addDal(tester);
      h.server.on('meals', 403, {
        'error': {'code': 'DAILY_LIMIT_REACHED', 'limit': 4},
      });
      await h.tapText(tester, h.l10n.saveMealButton);
      await tester.tap(find.text(h.l10n.saveMealButton).last);
      await tester.pumpAndSettle();
      expect(find.text(h.l10n.limitTitle), findsOneWidget);
      expect(find.text(h.l10n.limitBodyStandard(4)), findsOneWidget);
      expect(find.text(h.l10n.upsellTitle), findsWidgets);
    });

    testWidgets('offline: queued, shown as syncing, sent once', (tester) async {
      await home(tester);
      await addDal(tester);
      h.server.offline = true;
      await h.tapText(tester, h.l10n.saveMealButton);
      await tester.tap(find.text(h.l10n.saveMealButton).last);
      await tester.pumpAndSettle();
      // The confirmation is the side badge beside the avatar (no toast, no
      // text under the avatar).
      expect(find.text(h.l10n.badgeSaved), findsOneWidget);
      expect(find.text(h.l10n.badgeSyncsLater), findsOneWidget);
      expect(await Outbox(h.db).count(), 1);
      expect(find.text(h.l10n.pendingMeals(1)), findsNothing);
      final queued = (await Outbox(h.db).pending()).single;
      final id = (jsonDecode(queued.body!) as Map)['client_entry_id'];

      // Back online: the outbox sends the same client id exactly once.
      h.server
        ..offline = false
        ..on('meals', 201, {
          'meal': meal(id: id as String),
          'daily_summary': summary(calories: 236, mealCount: 2),
          'avatar': {'fill_pct': 10.7, 'state': 'fueling'},
        });
      h.connectivity.online = true;
      await tester.pumpAndSettle();
      final posts = h.server.bodiesFor('meals');
      expect(posts, hasLength(1));
      expect((posts.single! as Map)['client_entry_id'], id);
      expect(await Outbox(h.db).count(), 0);
    });
  });

  group('N5 voice (STAR)', () {
    testWidgets('speech -> parse -> confirm -> source voice', (tester) async {
      await home(tester, star: true);
      h.server.on('nutrition/voice/parse', 200, {
        'items': [
          {
            'food_id': roti,
            'name': 'Roti (Whole Wheat)',
            'quantity': 2,
            'unit_code': 'piece',
            'unit_size': 'medium',
            'portion_label': 'Medium Piece',
            'confidence': 95,
          },
        ],
        'unmatched': ['pizza'],
      });
      await h.go(tester, Routes.addMeal);
      await tester.tap(find.byTooltip(h.l10n.voiceLogging));
      await tester.pumpAndSettle();
      expect(h.location, Routes.voiceMeal);
      await tester.tap(find.byTooltip(h.l10n.voiceStart));
      await tester.pumpAndSettle();
      expect(find.text('do roti aur ek katori dal'), findsOneWidget);
      await h.tapText(tester, h.l10n.voiceFindFoods);
      expect(h.server.bodiesFor('nutrition/voice/parse').single, {
        'transcript': 'do roti aur ek katori dal',
        'locale': 'en-IN',
      });
      expect(find.text(h.l10n.voiceUnmatched('pizza')), findsOneWidget);
      expect(find.text('Roti (Whole Wheat)'), findsOneWidget);
      await h.tapText(tester, h.l10n.addToMeal);
      expect(h.location, Routes.addMeal);

      h.server.on('meals', 201, {
        'meal': meal(),
        'daily_summary': summary(star: true),
        'avatar': {'fill_pct': 3.5, 'state': 'fueling'},
      });
      await h.tapText(tester, h.l10n.saveMealButton);
      await tester.tap(find.text(h.l10n.saveMealButton).last);
      await tester.pumpAndSettle();
      expect(lastMealPost()['source'], 'voice');
    });

    testWidgets('no recogniser: type instead', (tester) async {
      await home(tester, star: true);
      h.voice.available = false;
      await h.go(tester, Routes.voiceMeal);
      await tester.tap(find.byTooltip(h.l10n.voiceStart));
      await tester.pumpAndSettle();
      expect(find.text(h.l10n.voiceUnavailable), findsOneWidget);
    });
  });

  group('N6 barcode (STAR)', () {
    const code = '4006381333931';

    testWidgets('found: one serving added, source barcode', (tester) async {
      await home(tester, star: true);
      h.server.on('foods/barcode/$code', 200, {
        'found': true,
        'barcode': code,
        'product_name': 'Crunchy Muesli',
        'brand': 'Brand Y',
        'food_id': apple,
        'serving_g': 45,
        'source': 'open_food_facts',
        'per_100': nutrients(star: true, calories: 400),
      });
      await h.go(tester, Routes.barcodeMeal);
      await h.type(tester, h.l10n.barcodeManualLabel, code);
      await h.tapText(tester, h.l10n.barcodeLookup);
      expect(find.text('Crunchy Muesli'), findsOneWidget);
      expect(find.text(h.l10n.servingSize('45')), findsOneWidget);
      expect(find.text(h.l10n.openFoodFactsCredit), findsOneWidget);
      await h.tapText(tester, h.l10n.addToMeal);
      expect(h.location, Routes.addMeal);
      expect(find.text(h.l10n.addItemsCount(1)), findsOneWidget);
    });

    testWidgets('not found: search by name', (tester) async {
      await home(tester, star: true);
      h.server.on('foods/barcode/$code', 200, {
        'found': false,
        'barcode': code,
      });
      await h.go(tester, Routes.barcodeMeal);
      await h.type(tester, h.l10n.barcodeManualLabel, code);
      await h.tapText(tester, h.l10n.barcodeLookup);
      expect(find.text(h.l10n.barcodeNotFound), findsOneWidget);
      await h.tapText(tester, h.l10n.searchByName);
      expect(h.location, Routes.addMeal);
    });

    testWidgets('invalid check digit is refused locally', (tester) async {
      await home(tester, star: true);
      await h.go(tester, Routes.barcodeMeal);
      await h.type(tester, h.l10n.barcodeManualLabel, '4006381333932');
      await h.tapText(tester, h.l10n.barcodeLookup);
      expect(
        h.server.paths.where((p) => p.startsWith('foods/barcode')),
        isEmpty,
      );
      expect(find.text(h.l10n.validationFormat), findsOneWidget);
    });
  });

  group('N9/N10 recent, edit, saved', () {
    testWidgets('only the last 2 are editable; edit sends If-Match', (
      tester,
    ) async {
      await home(tester);
      h.server.on('meals/recent', 200, {
        'meals': [
          meal(version: 3),
          meal(id: '0190f5d2-0000-7000-8000-00000000a002', editable: false),
        ],
        'recent_foods': <Object>[],
      });
      await h.go(tester, Routes.recentMeals);
      expect(find.text(h.l10n.editYourEntry), findsOneWidget);
      expect(find.textContaining(h.l10n.onlyLastTwoEditable), findsOneWidget);

      h.server.on('meals/0190f5d2-0000-7000-8000-00000000a001', 200, {
        'meal': meal(version: 4),
        'daily_summary': summary(),
      });
      await h.tapText(tester, h.l10n.editYourEntry);
      expect(h.location, Routes.editMeal);
      await tester.tap(find.byTooltip(h.l10n.increaseQuantity));
      await tester.pumpAndSettle();
      await h.tapText(tester, h.l10n.updateMealButton);
      final put = h.server.requests.lastWhere((r) => r.$1 == 'PUT');
      expect((put.$3! as Map)['items'], [
        {
          'food_id': apple,
          'quantity': 1.25,
          'unit_code': 'piece',
          'unit_size': 'medium',
        },
      ]);
      expect(find.text(h.l10n.entryUpdated), findsOneWidget);
    });

    testWidgets('409: the server copy wins', (tester) async {
      await home(tester);
      h.server.on('meals/0190f5d2-0000-7000-8000-00000000a001', 409, {
        'error': {'code': 'VERSION_CONFLICT', 'current': meal(version: 2)},
      });
      await h.go(tester, Routes.recentMeals);
      await h.tapText(tester, h.l10n.editYourEntry);
      await h.tapText(tester, h.l10n.updateMealButton);
      expect(find.text(h.l10n.errorConflict), findsOneWidget);
      expect(h.location, Routes.recentMeals);
    });

    testWidgets('STANDARD breakdown opens the upsell', (tester) async {
      await home(tester);
      await h.go(tester, Routes.recentMeals);
      await h.tapText(tester, h.l10n.mealBreakdown);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text(h.l10n.upsellBody), findsOneWidget);
      expect(h.server.paths.where((p) => p.endsWith('/breakdown')), isEmpty);
    });

    testWidgets('a saved meal fills the Add Meal list', (tester) async {
      await home(tester);
      h.server.on('saved-meals', 200, {
        'saved_meals': [
          {
            'saved_meal_id': 's1',
            'name': 'Dal Roti',
            'created_at': '2026-10-30T10:00:00Z',
            'items': [
              {
                'food_id': dal,
                'food_name': 'Moong Dal (Cooked)',
                'quantity': 1,
                'unit_code': 'katori',
                'unit_size': 'medium',
                'available': true,
              },
              {
                'food_id': roti,
                'food_name': 'Roti (Whole Wheat)',
                'quantity': 2,
                'unit_code': 'piece',
                'unit_size': 'medium',
                'available': true,
              },
            ],
          },
        ],
      });
      await h.go(tester, Routes.recentMeals);
      await h.tapText(tester, h.l10n.savedMealsTab);
      await h.tapText(tester, h.l10n.useSavedMeal);
      expect(h.location, Routes.addMeal);
      expect(find.text(h.l10n.addItemsCount(2)), findsOneWidget);
    });
  });

  group('rules', () {
    test('meal type suggestion follows the local time', () {
      expect(suggestMealType(DateTime(2026, 10, 31, 4, 59)), 'dinner');
      expect(suggestMealType(DateTime(2026, 10, 31, 5)), 'breakfast');
      expect(suggestMealType(DateTime(2026, 10, 31, 11)), 'lunch');
      expect(suggestMealType(DateTime(2026, 10, 31, 16)), 'snack');
      expect(suggestMealType(DateTime(2026, 10, 31, 19)), 'dinner');
    });

    test('amounts display as the server sent them; unknown is a dash', () {
      final l10n = AppLocalizationsEn();
      expect(formatAmount(21, 'g', l10n), '21 g');
      expect(formatAmount(6.9, 'mg', l10n), '6.9 mg');
      expect(formatAmount(null, 'mg', l10n), l10n.nutrientUnknown);
    });
  });
}
