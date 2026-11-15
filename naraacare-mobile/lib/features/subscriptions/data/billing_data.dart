import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:uuid/uuid.dart';

const starProductIds = {'star_monthly', 'star_yearly'};

/// GET /billing/subscription.
class SubscriptionState {
  const new({
    required this.tier,
    this.status,
    this.productId,
    this.period,
    this.periodEnd,
    this.autoRenew,
    this.manageUrl,
  });

  factory fromJson(Map<String, dynamic> json) => SubscriptionState(
    tier: json['tier'] as String,
    status: json['status'] as String?,
    productId: json['product_id'] as String?,
    period: json['period'] as String?,
    periodEnd: json['period_end'] == null
        ? null
        : DateTime.parse(json['period_end'] as String),
    autoRenew: json['auto_renew'] as bool?,
    manageUrl: json['manage_url'] as String?,
  );

  final String tier;
  final String? status;
  final String? productId;
  final String? period;
  final DateTime? periodEnd;
  final bool? autoRenew;
  final String? manageUrl;

  bool get isStar => tier == 'star';

  /// Auto-renew off but still inside the paid period (doc 06 section 9).
  bool get isCancelled => autoRenew == false && isStar;
}

/// One row of GET /billing/plans: the server's display price in INR, shown
/// when the store can't give its localised price (emulator, store offline).
class PlanPrice {
  const new({
    required this.productId,
    required this.period,
    required this.displayPriceInr,
  });

  factory fromJson(Map<String, dynamic> json) => PlanPrice(
    productId: json['product_id'] as String,
    period: json['period'] as String,
    displayPriceInr: (json['display_price_inr'] as num).toDouble(),
  );

  final String productId;
  final String period;
  final double displayPriceInr;
}

class BillingHistoryItem {
  const new({
    required this.date,
    required this.productId,
    required this.type,
    required this.amount,
    required this.currency,
  });

  factory fromJson(Map<String, dynamic> json) => BillingHistoryItem(
    date: DateTime.parse(json['date'] as String),
    productId: json['product_id'] as String,
    type: json['type'] as String,
    amount: (json['amount'] as num).toDouble(),
    currency: json['currency'] as String,
  );

  final DateTime date;
  final String productId;
  final String type;
  final double amount;
  final String currency;
}

class ReferralProgress {
  const new({
    required this.code,
    required this.link,
    required this.required,
    required this.qualified,
    required this.friends,
    this.rewardDays,
  });

  factory fromJson(Map<String, dynamic> json) => ReferralProgress(
    code: json['code'] as String,
    link: json['link'] as String,
    required: (json['required'] as num).toInt(),
    qualified: (json['qualified'] as num).toInt(),
    friends: [
      for (final f in (json['friends'] as List).cast<Map<String, dynamic>>())
        (
          display: f['display'] as String,
          activeDays: (f['active_days'] as num).toInt(),
          status: f['status'] as String,
        ),
    ],
    rewardDays: (json['reward_days'] as num?)?.toInt(),
  );

  final String code;
  final String link;
  final int required;
  final int qualified;
  final List<({String display, int activeDays, String status})> friends;
  final int? rewardDays;
}

/// Billing and referral endpoints (doc 04 section 2.12).
class BillingApi {
  const new(this.api);

  final ApiClient api;

  Future<Map<String, dynamic>> _map(Future<Object?> call) async =>
      (await call)! as Map<String, dynamic>;

  Future<SubscriptionState> subscription() async =>
      SubscriptionState.fromJson(await _map(api.get('billing/subscription')));

  /// This platform's STAR plans by product id.
  Future<Map<String, PlanPrice>> plans() async {
    final body = await _map(api.get('billing/plans'));
    final platform = Platform.isIOS ? 'ios' : 'android';
    return {
      for (final p in (body['plans'] as List).cast<Map<String, dynamic>>())
        if (p['platform'] == platform && p['tier'] == 'star')
          p['product_id'] as String: PlanPrice.fromJson(p),
    };
  }

  Future<List<BillingHistoryItem>> history() async {
    final body = await _map(api.get('billing/history', query: {'limit': 50}));
    return [
      for (final i in (body['items'] as List).cast<Map<String, dynamic>>())
        BillingHistoryItem.fromJson(i),
    ];
  }

  /// The server verifies with the store; the app finishes the purchase only
  /// after this returns. The idempotency key makes a retry safe.
  Future<void> verify({
    required String productId,
    required String serverVerificationData,
    required String idempotencyKey,
  }) => api.post(
    'billing/purchases/verify',
    body: {
      'platform': Platform.isIOS ? 'ios' : 'android',
      'product_id': productId,
      if (Platform.isIOS)
        'signed_transaction': serverVerificationData
      else
        'purchase_token': serverVerificationData,
    },
    options: Options(headers: {'Idempotency-Key': idempotencyKey}),
  );

  Future<ReferralProgress> referrals() async =>
      ReferralProgress.fromJson(await _map(api.get('referrals/me')));

  Future<void> attribute(String code, String installationId) => api.post(
    'referrals/attribute',
    body: {'code': code, 'installation_id': installationId},
  );
}

/// What a purchase attempt ended with.
enum PurchaseOutcome { verified, pending, cancelled, failed, unavailable }

/// The store purchase flow behind an interface (tests use a fake): the
/// store SDK gives the display prices; purchases are verified by the API
/// before `completePurchase` (doc 07 SEC-6.1).
abstract interface class IapService {
  Future<Map<String, ProductDetails>> products();
  Future<PurchaseOutcome> buy(ProductDetails product);
  Future<void> restore();
}

class StoreIapService implements IapService {
  new(this.api);

  final BillingApi api;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Completer<PurchaseOutcome>? _pending;

  void _listen() {
    _sub ??= _iap.purchaseStream.listen(_onPurchases);
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _finish(PurchaseOutcome.pending);
        case PurchaseStatus.canceled:
          _finish(PurchaseOutcome.cancelled);
        case PurchaseStatus.error:
          _finish(PurchaseOutcome.failed);
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          if (!starProductIds.contains(p.productID)) continue;
          try {
            await api.verify(
              productId: p.productID,
              serverVerificationData: p.verificationData.serverVerificationData,
              idempotencyKey: const Uuid().v5(
                Namespace.url.value,
                p.verificationData.serverVerificationData,
              ),
            );
            if (p.pendingCompletePurchase) await _iap.completePurchase(p);
            _finish(PurchaseOutcome.verified);
          } on Object {
            // Not completed: the store re-delivers it on the next launch.
            _finish(PurchaseOutcome.failed);
          }
      }
    }
  }

  void _finish(PurchaseOutcome outcome) {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(outcome);
  }

  @override
  Future<Map<String, ProductDetails>> products() async {
    _listen();
    if (!await _iap.isAvailable()) return const {};
    final response = await _iap.queryProductDetails(starProductIds);
    return {for (final p in response.productDetails) p.id: p};
  }

  @override
  Future<PurchaseOutcome> buy(ProductDetails product) async {
    _listen();
    if (!await _iap.isAvailable()) return PurchaseOutcome.unavailable;
    _pending = Completer<PurchaseOutcome>();
    final started = await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
    if (!started) _finish(PurchaseOutcome.failed);
    return await _pending!.future;
  }

  /// Stops listening to the store (provider disposal).
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  @override
  Future<void> restore() async {
    _listen();
    await _iap.restorePurchases();
  }
}
