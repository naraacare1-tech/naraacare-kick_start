/// Nutrition data as the API returns it (doc 04 section 2.4). Values are
/// already computed, tier-filtered and rounded by the server: the app does no
/// nutrition maths (doc 06 section 10).
library;

import 'package:flutter/foundation.dart' show immutable;

num _num(Object? value) => switch (value) {
  final num n => n,
  final String s => num.tryParse(s) ?? 0,
  _ => 0,
};

num? _numOrNull(Object? value) => value == null ? null : _num(value);

List<Map<String, dynamic>> _list(Object? value) =>
    (value as List? ?? const []).cast<Map<String, dynamic>>();

/// One nutrient line ("Protein 62 g"). [value] is null when unknown.
class NutrientValue {
  const new({
    required this.code,
    required this.label,
    required this.unit,
    required this.value,
  });

  factory fromJson(Map<String, dynamic> json) => NutrientValue(
    code: json['code'] as String,
    label: json['label'] as String,
    unit: json['unit'] as String,
    value: _numOrNull(json['value']),
  );

  final String code;
  final String label;
  final String unit;
  final num? value;
}

/// The nutrients the user's tier may see, plus how many are locked (STAR).
class NutrientView {
  const new({required this.nutrients, required this.lockedCount});

  factory fromJson(Map<String, dynamic> json) => NutrientView(
    nutrients: _list(json['nutrients']).map(NutrientValue.fromJson).toList(),
    lockedCount: (json['locked_nutrients_count'] as int?) ?? 0,
  );

  static const empty = NutrientView(nutrients: [], lockedCount: 0);

  final List<NutrientValue> nutrients;
  final int lockedCount;

  NutrientValue? operator [](String code) {
    for (final n in nutrients) {
      if (n.code == code) return n;
    }
    return null;
  }
}

/// Energy avatar (doc 06 section 2.8).
enum AvatarStateCode { empty, fueling, energized, goalMet, overfilled }

AvatarStateCode _avatarState(String? code) => switch (code) {
  'fueling' => AvatarStateCode.fueling,
  'energized' => AvatarStateCode.energized,
  'goal_met' => AvatarStateCode.goalMet,
  'overfilled' => AvatarStateCode.overfilled,
  _ => AvatarStateCode.empty,
};

class DailySummary {
  const new({
    required this.date,
    required this.calories,
    required this.view,
    required this.targetKcal,
    required this.allowanceKcal,
    required this.exerciseKcal,
    required this.fillPct,
    required this.state,
    required this.mealCount,
    required this.mealLimit,
    required this.lastUpdated,
  });

  factory fromJson(Map<String, dynamic> json) {
    final avatar = json['avatar'] as Map<String, dynamic>? ?? const {};
    return DailySummary(
      date: json['date'] as String,
      calories: _num(json['calories']).toInt(),
      view: NutrientView.fromJson(json),
      targetKcal: json['target_kcal'] as int?,
      allowanceKcal: json['effective_allowance_kcal'] as int?,
      exerciseKcal: (json['exercise_kcal'] as int?) ?? 0,
      fillPct: _num(avatar['fill_pct']).toDouble(),
      state: _avatarState(avatar['state'] as String?),
      mealCount: (json['meal_count'] as int?) ?? 0,
      mealLimit: (json['meal_limit'] as int?) ?? 4,
      lastUpdated: DateTime.tryParse('${json['last_updated']}'),
    );
  }

  final String date;
  final int calories;
  final NutrientView view;
  final int? targetKcal;
  final int? allowanceKcal;
  final int exerciseKcal;
  final double fillPct;
  final AvatarStateCode state;
  final int mealCount;
  final int mealLimit;
  final DateTime? lastUpdated;

  bool get limitReached => mealCount >= mealLimit;
}

@immutable
class Portion {
  const new({
    required this.unitCode,
    required this.size,
    required this.label,
    required this.quantity,
    required this.basis,
    required this.isDefault,
  });

  factory fromJson(Map<String, dynamic> json) => Portion(
    unitCode: json['unit_code'] as String,
    size: (json['size'] ?? json['unit_size']) as String,
    label: json['label'] as String,
    quantity: _num(json['quantity']),
    basis: json['basis'] as String,
    isDefault: (json['is_default'] as bool?) ?? false,
  );

  final String unitCode;
  final String size;
  final String label;
  final num quantity;
  final String basis;
  final bool isDefault;

  /// "Medium Katori (150 ml)".
  String get display {
    final amount = quantity == quantity.roundToDouble()
        ? quantity.toInt().toString()
        : quantity.toString();
    return '$label ($amount ${basis == 'ml' ? 'ml' : 'g'})';
  }

  @override
  bool operator ==(Object other) =>
      other is Portion && other.unitCode == unitCode && other.size == size;

  @override
  int get hashCode => Object.hash(unitCode, size);
}

class FoodSearchResult {
  const new({
    required this.foodId,
    required this.name,
    required this.matchedAlias,
    required this.defaultPortion,
    required this.kcalPerDefault,
  });

  factory fromJson(Map<String, dynamic> json) => FoodSearchResult(
    foodId: json['food_id'] as String,
    name: json['name'] as String,
    matchedAlias: json['matched_alias'] as String?,
    defaultPortion: json['default_portion'] is Map<String, dynamic>
        ? Portion.fromJson({
            ...json['default_portion'] as Map<String, dynamic>,
            'is_default': true,
          })
        : null,
    kcalPerDefault: _num(json['kcal_per_default']).toInt(),
  );

  final String foodId;
  final String name;
  final String? matchedAlias;
  final Portion? defaultPortion;
  final int kcalPerDefault;
}

class FoodDetail {
  const new({
    required this.foodId,
    required this.name,
    required this.portions,
    required this.per100,
    required this.basis,
  });

  factory fromJson(Map<String, dynamic> json) => FoodDetail(
    foodId: json['food_id'] as String,
    name: json['name'] as String,
    basis: json['basis'] as String,
    portions: _list(json['portions']).map(Portion.fromJson).toList(),
    per100: NutrientView.fromJson(json['per_100'] as Map<String, dynamic>),
  );

  final String foodId;
  final String name;
  final String basis;
  final List<Portion> portions;
  final NutrientView per100;

  Portion? get defaultPortion {
    for (final p in portions) {
      if (p.isDefault) return p;
    }
    return portions.isEmpty ? null : portions.first;
  }
}

/// An item on the Add Meal list (before saving). [calories] comes from the
/// server (search result, dry run) and is only shown, never computed here.
class MealItemDraft {
  const new({
    required this.foodId,
    required this.foodName,
    required this.quantity,
    required this.unitCode,
    required this.unitSize,
    required this.portionLabel,
    this.calories,
  });

  final String foodId;
  final String foodName;

  /// 0.25 .. 20 in steps of 0.25.
  final double quantity;
  final String unitCode;
  final String? unitSize;
  final String portionLabel;
  final int? calories;

  static const minQuantity = 0.25;
  static const maxQuantity = 20.0;
  static const step = 0.25;

  MealItemDraft copyWith({
    double? quantity,
    String? unitCode,
    String? unitSize,
    String? portionLabel,
    int? calories,
    bool clearCalories = false,
  }) => MealItemDraft(
    foodId: foodId,
    foodName: foodName,
    quantity: quantity ?? this.quantity,
    unitCode: unitCode ?? this.unitCode,
    unitSize: unitSize ?? this.unitSize,
    portionLabel: portionLabel ?? this.portionLabel,
    calories: clearCalories ? null : calories ?? this.calories,
  );

  Map<String, Object?> toJson() => {
    'food_id': foodId,
    'quantity': quantity,
    'unit_code': unitCode,
    'unit_size': ?unitSize,
  };
}

class MealItem {
  const new({
    required this.foodId,
    required this.foodName,
    required this.quantity,
    required this.unitCode,
    required this.unitSize,
    required this.calories,
  });

  factory fromJson(Map<String, dynamic> json) => MealItem(
    foodId: json['food_id'] as String,
    foodName: json['food_name'] as String,
    quantity: _num(json['quantity']).toDouble(),
    unitCode: json['unit_code'] as String,
    unitSize: json['unit_size'] as String?,
    calories: _num(json['calories']).toInt(),
  );

  final String foodId;
  final String foodName;
  final double quantity;
  final String unitCode;
  final String? unitSize;
  final int calories;
}

class Meal {
  const new({
    required this.mealId,
    required this.loggedAt,
    required this.localDate,
    required this.mealType,
    required this.source,
    required this.version,
    required this.editable,
    required this.calories,
    required this.items,
  });

  factory fromJson(Map<String, dynamic> json) => Meal(
    mealId: json['meal_id'] as String,
    loggedAt: DateTime.parse(json['logged_at'] as String),
    localDate: json['local_date'] as String,
    mealType: json['meal_type'] as String,
    source: json['source'] as String,
    version: json['version'] as int,
    editable: (json['editable'] as bool?) ?? false,
    calories: _num(json['calories']).toInt(),
    items: _list(json['items']).map(MealItem.fromJson).toList(),
  );

  final String mealId;
  final DateTime loggedAt;
  final String localDate;
  final String mealType;
  final String source;
  final int version;
  final bool editable;
  final int calories;
  final List<MealItem> items;
}

class RecentFood {
  const new({
    required this.foodId,
    required this.name,
    required this.quantity,
    required this.unitCode,
    required this.unitSize,
  });

  factory fromJson(Map<String, dynamic> json) => RecentFood(
    foodId: json['food_id'] as String,
    name: json['name'] as String,
    quantity: _num(json['quantity']).toDouble(),
    unitCode: json['unit_code'] as String,
    unitSize: json['unit_size'] as String?,
  );

  final String foodId;
  final String name;
  final double quantity;
  final String unitCode;
  final String? unitSize;
}

class RecentMeals {
  const new({required this.meals, required this.foods});

  factory fromJson(Map<String, dynamic> json) => RecentMeals(
    meals: _list(json['meals']).map(Meal.fromJson).toList(),
    foods: _list(json['recent_foods']).map(RecentFood.fromJson).toList(),
  );

  final List<Meal> meals;
  final List<RecentFood> foods;
}

class SavedMeal {
  const new({required this.id, required this.name, required this.items});

  factory fromJson(Map<String, dynamic> json) => SavedMeal(
    id: json['saved_meal_id'] as String,
    name: json['name'] as String,
    items: _list(json['items'])
        .where((i) => i['available'] != false)
        .map(
          (i) => MealItemDraft(
            foodId: i['food_id'] as String,
            foodName: i['food_name'] as String,
            quantity: _num(i['quantity']).toDouble(),
            unitCode: i['unit_code'] as String,
            unitSize: i['unit_size'] as String?,
            portionLabel: '${i['unit_size'] ?? ''} ${i['unit_code']}'.trim(),
          ),
        )
        .toList(),
  );

  final String id;
  final String name;
  final List<MealItemDraft> items;
}

/// Dry run of a meal (View Nutrition Summary).
class MealPreview {
  const new({
    required this.calories,
    required this.totals,
    required this.itemCalories,
  });

  factory fromJson(Map<String, dynamic> json) => MealPreview(
    calories: _num(json['calories']).toInt(),
    totals: NutrientView.fromJson(json['totals'] as Map<String, dynamic>),
    itemCalories: [
      for (final i in _list(json['items'])) _num(i['calories']).toInt(),
    ],
  );

  final int calories;
  final NutrientView totals;
  final List<int> itemCalories;
}

class MealBreakdown {
  const new({required this.totals, required this.macroPct});

  factory fromJson(Map<String, dynamic> json) => MealBreakdown(
    totals: NutrientView.fromJson(json['totals'] as Map<String, dynamic>),
    macroPct: {
      for (final MapEntry(:key, :value)
          in (json['macro_pct'] as Map<String, dynamic>).entries)
        key: _num(value).toInt(),
    },
  );

  final NutrientView totals;
  final Map<String, int> macroPct;
}

class BarcodeResult {
  const new({
    required this.found,
    required this.barcode,
    this.productName,
    this.brand,
    this.foodId,
    this.servingG,
    this.per100 = NutrientView.empty,
  });

  factory fromJson(Map<String, dynamic> json) => BarcodeResult(
    found: json['found'] as bool,
    barcode: json['barcode'] as String,
    productName: json['product_name'] as String?,
    brand: json['brand'] as String?,
    foodId: json['food_id'] as String?,
    servingG: _numOrNull(json['serving_g']),
    per100: json['per_100'] is Map<String, dynamic>
        ? NutrientView.fromJson(json['per_100'] as Map<String, dynamic>)
        : NutrientView.empty,
  );

  final bool found;
  final String barcode;
  final String? productName;
  final String? brand;

  /// Null when the product cannot be logged (search manually instead).
  final String? foodId;
  final num? servingG;
  final NutrientView per100;
}

class VoiceParse {
  const new({required this.items, required this.unmatched});

  factory fromJson(Map<String, dynamic> json) => VoiceParse(
    items: [
      for (final i in _list(json['items']))
        MealItemDraft(
          foodId: i['food_id'] as String,
          foodName: i['name'] as String,
          quantity: _num(i['quantity']).toDouble(),
          unitCode: i['unit_code'] as String,
          unitSize: i['unit_size'] as String?,
          portionLabel: i['portion_label'] as String,
        ),
    ],
    unmatched: (json['unmatched'] as List? ?? const []).cast<String>(),
  );

  final List<MealItemDraft> items;
  final List<String> unmatched;
}
