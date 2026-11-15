import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/features/subscriptions/data/billing_data.dart';

final billingApiProvider = Provider<BillingApi>(
  (ref) => BillingApi(ref.watch(apiClientProvider)),
);

final iapServiceProvider = Provider<IapService>((ref) {
  final service = StoreIapService(ref.watch(billingApiProvider));
  ref.onDispose(service.dispose);
  return service;
});

final subscriptionProvider = FutureProvider<SubscriptionState>(
  (ref) => ref.watch(billingApiProvider).subscription(),
);

/// Store products with the store's localised prices (OQ-06).
final storeProductsProvider = FutureProvider<Map<String, ProductDetails>>(
  (ref) => ref.watch(iapServiceProvider).products(),
);

final planPricesProvider = FutureProvider<Map<String, PlanPrice>>(
  (ref) => ref.watch(billingApiProvider).plans(),
);

final billingHistoryProvider = FutureProvider<List<BillingHistoryItem>>(
  (ref) => ref.watch(billingApiProvider).history(),
);

final referralProgressProvider = FutureProvider<ReferralProgress>(
  (ref) => ref.watch(billingApiProvider).referrals(),
);
