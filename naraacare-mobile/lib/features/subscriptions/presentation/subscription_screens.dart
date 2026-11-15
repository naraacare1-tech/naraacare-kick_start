import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/features/subscriptions/data/billing_data.dart';
import 'package:naraacare/features/subscriptions/subscription_providers.dart';
import 'package:naraacare/shared/widgets/legal_links.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';

/// "11 June 2026" (Figma).
String _longDate(BuildContext context, DateTime at) => DateFormat(
  'd MMMM y',
  Localizations.localeOf(context).toString(),
).format(at.toLocal());

/// "11 Jun 2026" (Figma Billing History).
String _shortDate(BuildContext context, DateTime at) => DateFormat(
  'd MMM y',
  Localizations.localeOf(context).toString(),
).format(at.toLocal());

/// "₹1899.00" (Figma Billing History); refunds get a minus sign.
String _amount(BillingHistoryItem i) =>
    '${i.type == 'refund' ? '−' : ''}'
    '${i.currency == 'INR' ? '₹' : '${i.currency} '}'
    '${i.amount.toStringAsFixed(2)}';

String _inr(double amount) => NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: amount == amount.roundToDouble() ? 0 : 2,
).format(amount);

/// Same day next month/year, clamped to the month's last day (31 Jan -> 28 Feb).
DateTime _addMonths(DateTime from, int months) {
  final month = from.month + months;
  final year = from.year + (month - 1) ~/ 12;
  final m = (month - 1) % 12 + 1;
  final day = from.day.clamp(1, DateUtils.getDaysInMonth(year, m));
  return DateTime(year, m, day);
}

String _productId({required bool yearly}) =>
    yearly ? 'star_yearly' : 'star_monthly';

/// The price shown for a STAR product: the store's localised price when the
/// store answered (OQ-06), else the server's INR display price (emulator,
/// store offline). Buying always goes through the store product.
String? _price(WidgetRef ref, String productId) {
  final store = ref.watch(storeProductsProvider).value?[productId];
  if (store != null) return store.price;
  final plan = ref.watch(planPricesProvider).value?[productId];
  return plan == null ? null : _inr(plan.displayPriceInr);
}

/// Yearly saving against 12 monthly payments, in percent (Figma: "SAVE 20%"
/// on the toggle, "SAVE 20.48%" on the yearly option).
double? _saving(WidgetRef ref) {
  final plans = ref.watch(planPricesProvider).value ?? const {};
  final monthly = plans['star_monthly']?.displayPriceInr;
  final yearly = plans['star_yearly']?.displayPriceInr;
  if (monthly == null || yearly == null || monthly <= 0) return null;
  final saving = (1 - yearly / (monthly * 12)) * 100;
  return saving > 0 ? saving : null;
}

String _percent(double value, {required bool exact}) => exact
    ? value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')
    : value.floor().toString();

/// Refreshes everything that depends on the tier after a purchase/restore.
void refreshTier(WidgetRef ref) => ref
  ..invalidate(subscriptionProvider)
  ..invalidate(billingHistoryProvider)
  ..invalidate(meProvider);

/// Opens the store's subscription page (OQ-07: cancelling and payment
/// methods are handled by the store, no custom forms).
Future<void> _openStore(BuildContext context, SubscriptionState s) async {
  final url = s.manageUrl;
  if (url == null) {
    showNcToast(
      context,
      AppLocalizations.of(context).storeUnavailable,
      kind: NcToastKind.error,
    );
    return;
  }
  await openLegalLink(context, Uri.parse(url));
}

// ------------------------------------------------------------ shared parts

class _Badge extends StatelessWidget {
  const new({
    required this.label,
    required this.colour,
    this.filled = false,
    this.background,
  });

  final String label;
  final Color colour;
  final bool filled;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? colour : background ?? nc.surface,
        borderRadius: BorderRadius.circular(
          filled ? NcRadius.xs : NcRadius.full,
        ),
        border: filled || background != null ? null : Border.all(color: colour),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NcSpace.inputGap,
          vertical: NcSpace.xs / 2,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: filled ? nc.surface : colour,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const new(this.label, {this.included = true, this.bold = false});

  final String label;
  final bool included;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final faded = nc.textSecondary.withValues(alpha: 0.4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NcSpace.inputGap),
      child: Row(
        children: [
          Icon(
            included ? Icons.check_circle_outline : Icons.circle_outlined,
            size: NcSize.iconSmall,
            color: included ? nc.primary : faded,
          ),
          const SizedBox(width: NcSpace.buttonGap),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: included ? nc.textBody : faded,
                fontWeight: bold ? FontWeight.w700 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Price extends StatelessWidget {
  const new({required this.price, required this.suffix, this.colour});

  final String? price;
  final String suffix;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          price ?? '—',
          style: text.headlineMedium?.copyWith(color: colour ?? nc.textPrimary),
        ),
        const SizedBox(width: NcSpace.xs),
        Text(
          suffix,
          style: text.bodyMedium?.copyWith(color: colour ?? nc.textSecondary),
        ),
      ],
    );
  }
}

class _Bordered extends StatelessWidget {
  const new({
    required this.child,
    this.colour,
    this.width = 1,
    this.fill,
    this.padding = NcSpace.cardPadding,
  });

  final Widget child;
  final Color? colour;
  final double width;
  final Color? fill;
  final double padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(
      color: fill ?? context.nc.surface,
      borderRadius: BorderRadius.circular(NcRadius.l),
      border: Border.all(color: colour ?? context.nc.border, width: width),
    ),
    child: child,
  );
}

/// Label on the left, value on the right (bold).
class _InfoRow extends StatelessWidget {
  const new(this.label, this.value, {this.trailingIcon});

  final String label;
  final String value;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NcSpace.inputGap),
      child: Row(
        children: [
          Text(
            label,
            style: text.bodyMedium?.copyWith(color: nc.textSecondary),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: NcSpace.xs),
            Icon(trailingIcon, size: NcSize.iconSmall, color: nc.textSecondary),
          ],
          const SizedBox(width: NcSpace.buttonGap),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: text.bodyMedium?.copyWith(
                color: nc.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Centred pill button as in the Figma success/upgrade frames.
class _PillButton extends StatelessWidget {
  const new({required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, NcSize.buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: NcSpace.sectionGap),
        shape: const StadiumBorder(),
      ),
      child: busy
          ? SizedBox.square(
              dimension: NcSize.icon,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.nc.surface,
              ),
            )
          : Text(label),
    ),
  );
}

List<String> _standardFeatures(AppLocalizations l10n) => [
  l10n.featHydrationNutrition,
  l10n.featCareCircle,
  l10n.featBasicReports,
  l10n.featMeals4,
  l10n.featReferral30,
  l10n.featTicketSupport,
];

List<String> _starFeatures(AppLocalizations l10n) => [
  l10n.featEverythingStandard,
  l10n.featInsights,
  l10n.featRin,
  l10n.featCustomReports,
  l10n.featMeals8,
  l10n.featSleepAvatar,
  l10n.featBarcodeVoice,
  l10n.featPrioritySupport,
  l10n.featReferral50,
];

// ------------------------------------------------------------------ ST6/ST8

/// "My Subscriptions" (Figma "My subscriptions 1" for STANDARD, "4" for a
/// paid STAR plan). A reward/promo STAR has no store subscription to manage.
class SubscriptionScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final sub = ref.watch(subscriptionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.mySubscriptions)),
      backgroundColor: nc.surface,
      body: sub.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.subscriptionUnavailable)),
        data: (s) => s.isStar && s.status != null
            ? _StarPlan(state: s)
            : s.isStar
            ? _GrantedStar(state: s)
            : const _Plans(),
      ),
    );
  }
}

class _Plans extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_Plans> createState() => _PlansState();
}

class _PlansState extends ConsumerState<_Plans> {
  bool _yearly = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final saving = _saving(ref);
    final suffix = _yearly ? l10n.perYearSuffix : l10n.perMonthSuffix;
    final label = text.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    );
    return ListView(
      padding: EdgeInsets.all(nc.screenPadding),
      children: [
        Center(
          child: _CycleToggle(
            yearly: _yearly,
            saving: saving,
            onChanged: (v) => setState(() => _yearly = v),
          ),
        ),
        const SizedBox(height: NcSpace.sectionGap),
        _Bordered(
          padding: NcSpace.cardPadding + NcSpace.inputGap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    l10n.planStandard,
                    style: label?.copyWith(color: nc.primary),
                  ),
                  const Spacer(),
                  _Badge(label: l10n.activeBadge, colour: nc.success),
                ],
              ),
              _Price(price: _inr(0), suffix: suffix),
              const SizedBox(height: NcSpace.inputGap),
              for (final f in _standardFeatures(l10n)) _Feature(f),
              _Feature(l10n.featRin, included: false),
              _Feature(l10n.featInsights, included: false),
              const SizedBox(height: NcSpace.cardGap),
              FilledButton(
                onPressed: null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(NcSize.buttonHeight),
                  disabledBackgroundColor: nc.inputFill,
                  disabledForegroundColor: nc.textBody,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(NcRadius.m),
                  ),
                ),
                child: Text(l10n.yourCurrentPlan),
              ),
            ],
          ),
        ),
        const SizedBox(height: NcSpace.cardGap),
        _Bordered(
          colour: nc.star,
          width: 1.5,
          padding: NcSpace.cardPadding + NcSpace.inputGap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(l10n.planStar, style: label?.copyWith(color: nc.star)),
                  const Spacer(),
                  _Badge(
                    label: l10n.recommendedBadge,
                    colour: nc.star,
                    filled: true,
                  ),
                ],
              ),
              _Price(
                price: _price(ref, _productId(yearly: _yearly)),
                suffix: suffix,
                colour: nc.star,
              ),
              const SizedBox(height: NcSpace.inputGap),
              for (final (i, f) in _starFeatures(l10n).indexed)
                _Feature(f, bold: i == 0),
              const SizedBox(height: NcSpace.cardGap),
              FilledButton(
                onPressed: () =>
                    context.push(Routes.upgradeToStar(yearly: _yearly)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(NcSize.buttonHeight),
                  backgroundColor: nc.star,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(NcRadius.m),
                  ),
                ),
                child: Text(l10n.upgradeToStar),
              ),
            ],
          ),
        ),
        const SizedBox(height: NcSpace.inputGap),
        // Required by both stores for subscriptions bought on another device.
        TextButton(
          onPressed: () async {
            await ref.read(iapServiceProvider).restore();
            refreshTier(ref);
          },
          child: Text(l10n.restorePurchases),
        ),
      ],
    );
  }
}

class _CycleToggle extends StatelessWidget {
  const new({
    required this.yearly,
    required this.saving,
    required this.onChanged,
  });

  final bool yearly;
  final double? saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    Widget segment({required bool value, required Widget child}) {
      final selected = value == yearly;
      return Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(NcRadius.full),
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minWidth: 132),
            padding: const EdgeInsets.symmetric(
              horizontal: NcSpace.cardGap,
              vertical: NcSpace.inputGap,
            ),
            decoration: BoxDecoration(
              color: selected ? nc.primary : null,
              borderRadius: BorderRadius.circular(NcRadius.full),
            ),
            child: DefaultTextStyle.merge(
              style: text.bodyMedium?.copyWith(
                color: selected ? nc.surface : nc.textSecondary,
              ),
              textAlign: TextAlign.center,
              child: child,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(NcSpace.xs),
      decoration: BoxDecoration(
        color: nc.inputFill,
        borderRadius: BorderRadius.circular(NcRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment(value: false, child: Text(l10n.planMonthly)),
          segment(
            value: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(l10n.planYearly),
                if (saving != null) ...[
                  const SizedBox(width: NcSpace.xs),
                  Text(
                    l10n.saveBadge(_percent(saving!, exact: false)),
                    style: text.labelSmall?.copyWith(
                      color: yearly ? nc.surface : nc.success,
                      fontWeight: FontWeight.w700,
                      fontSize: NcTypeScale.footnote - 2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StarPlan extends ConsumerWidget {
  const new({required this.state});

  final SubscriptionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final yearly = state.period == 'yearly';
    final end = state.periodEnd;
    return ListView(
      padding: EdgeInsets.all(nc.screenPadding),
      children: [
        _Bordered(
          colour: nc.star,
          width: 1.5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.currentPlan,
                style: text.bodySmall?.copyWith(color: nc.textSecondary),
              ),
              Row(
                children: [
                  Text(l10n.starPlan, style: text.titleLarge),
                  const Spacer(),
                  _Badge(
                    label: state.isCancelled
                        ? l10n.subscriptionCancelled
                        : l10n.activeBadge,
                    colour: state.isCancelled ? nc.error : nc.success,
                  ),
                ],
              ),
              const SizedBox(height: NcSpace.inputGap),
              _Price(
                price: _price(
                  ref,
                  state.productId ?? _productId(yearly: yearly),
                ),
                suffix: yearly ? l10n.perYearSuffix : l10n.perMonthSuffix,
                colour: nc.star,
              ),
              const Divider(height: NcSpace.cardGap * 2),
              _InfoRow(
                l10n.billingCycle,
                yearly ? l10n.planYearly : l10n.planMonthly,
              ),
              if (end != null)
                _InfoRow(
                  state.isCancelled
                      ? l10n.accessUntilLabel
                      : l10n.nextBillingDate,
                  _longDate(context, end),
                ),
              _InfoRow(
                l10n.autoRenewal,
                state.isCancelled ? l10n.autoRenewalOff : l10n.autoRenewalOn,
              ),
              if (state.status == 'in_grace') ...[
                const SizedBox(height: NcSpace.inputGap),
                Text(
                  l10n.paymentIssue,
                  style: text.bodySmall?.copyWith(color: nc.error),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: NcSpace.sectionGap),
        Text(l10n.planIncludes, style: text.titleMedium),
        const SizedBox(height: NcSpace.inputGap),
        for (final f in _starFeatures(l10n)) _Feature(f),
        const SizedBox(height: NcSpace.sectionGap),
        Text(l10n.subscriptionActions, style: text.titleMedium),
        const SizedBox(height: NcSpace.inputGap),
        _Bordered(
          padding: 0,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(l10n.billingHistory),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.billingHistory),
              ),
              if (state.manageUrl != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.credit_card_outlined),
                  title: Text(l10n.updatePaymentMethod),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openStore(context, state),
                ),
              ],
              if (!state.isCancelled) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.cancel_outlined, color: nc.error),
                  title: Text(
                    l10n.cancelSubscription,
                    style: TextStyle(color: nc.error),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.cancelSubscription),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _GrantedStar extends StatelessWidget {
  const new({required this.state});

  final SubscriptionState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    return ListView(
      padding: EdgeInsets.all(nc.screenPadding),
      children: [
        _Bordered(
          colour: nc.star,
          width: 1.5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    l10n.starPlan,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  _Badge(label: l10n.activeBadge, colour: nc.success),
                ],
              ),
              const SizedBox(height: NcSpace.inputGap),
              Text(l10n.starFromReward),
            ],
          ),
        ),
        const SizedBox(height: NcSpace.sectionGap),
        Text(l10n.planIncludes, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: NcSpace.inputGap),
        for (final f in _starFeatures(l10n)) _Feature(f),
      ],
    );
  }
}

// ---------------------------------------------------------------------- ST7

/// "Upgrade to STAR" (Figma "My subscriptions 2"): the plan card, the billing
/// cycle choice with start/renewal dates, then the store purchase sheet.
class UpgradeScreen extends ConsumerStatefulWidget {
  const new({this.yearly = false, super.key});

  final bool yearly;

  @override
  ConsumerState<UpgradeScreen> createState() => _UpgradeState();
}

class _UpgradeState extends ConsumerState<UpgradeScreen> {
  late bool _yearly = widget.yearly;
  bool _busy = false;

  Future<void> _subscribe() async {
    final l10n = AppLocalizations.of(context);
    final ProductDetails? product;
    try {
      product = (await ref.read(
        storeProductsProvider.future,
      ))[_productId(yearly: _yearly)];
    } on Object {
      if (mounted) {
        showNcToast(context, l10n.storeUnavailable, kind: NcToastKind.error);
      }
      return;
    }
    if (!mounted) return;
    if (product == null) {
      showNcToast(context, l10n.storeUnavailable, kind: NcToastKind.error);
      return;
    }
    setState(() => _busy = true);
    final outcome = await ref.read(iapServiceProvider).buy(product);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case PurchaseOutcome.verified:
        refreshTier(ref);
        context.pushReplacement(Routes.purchaseSuccess);
      case PurchaseOutcome.pending:
        showNcToast(context, l10n.purchasePending, kind: NcToastKind.info);
      case PurchaseOutcome.cancelled:
        break;
      case PurchaseOutcome.unavailable:
        showNcToast(context, l10n.storeUnavailable, kind: NcToastKind.error);
      case PurchaseOutcome.failed:
        showNcToast(context, l10n.purchaseFailed, kind: NcToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final monthly = _price(ref, 'star_monthly');
    final yearly = _price(ref, 'star_yearly');
    final saving = _saving(ref);
    final today = DateUtils.dateOnly(DateTime.now());
    final details = Column(
      children: [
        const SizedBox(height: NcSpace.inputGap),
        _Bordered(
          padding: NcSpace.buttonGap,
          child: _InfoRow(l10n.startsToday, _longDate(context, today)),
        ),
        const SizedBox(height: NcSpace.inputGap),
        _Bordered(
          padding: NcSpace.buttonGap,
          child: _InfoRow(
            l10n.renewsOnLabel,
            _longDate(context, _addMonths(today, _yearly ? 12 : 1)),
          ),
        ),
        const SizedBox(height: NcSpace.inputGap),
        _Bordered(
          padding: NcSpace.buttonGap,
          child: _InfoRow(l10n.paymentVia, l10n.paymentViaStores),
        ),
      ],
    );

    Widget option({
      required bool value,
      required String title,
      required String subtitle,
      Widget? badge,
    }) {
      final selected = value == _yearly;
      return Semantics(
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(NcRadius.l),
          onTap: () => setState(() => _yearly = value),
          child: _Bordered(
            colour: selected ? nc.primary : null,
            width: selected ? 1.5 : 1,
            fill: selected ? nc.inputFill : null,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: NcSpace.inputGap),
                            badge,
                          ],
                        ],
                      ),
                      Text(
                        subtitle,
                        style: text.bodySmall?.copyWith(
                          color: nc.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? nc.primary : nc.textSecondary,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.upgradeToStar)),
      backgroundColor: nc.surface,
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          Container(
            padding: const EdgeInsets.all(NcSpace.cardPadding * 1.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(NcRadius.l),
              gradient: LinearGradient(
                colors: [nc.starGradientStart, nc.starGradientEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.starPlan,
                  style: text.titleMedium?.copyWith(color: nc.surface),
                ),
                const SizedBox(height: NcSpace.inputGap),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      (_yearly ? yearly : monthly) ?? '—',
                      style: text.headlineLarge?.copyWith(
                        color: nc.surface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _yearly ? l10n.perYearSuffix : l10n.perMonthSuffix,
                      style: text.bodyLarge?.copyWith(color: nc.surface),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: NcSpace.sectionGap),
          Text(l10n.billingCycle, style: text.titleMedium),
          const SizedBox(height: NcSpace.buttonGap),
          option(
            value: false,
            title: l10n.planMonthly,
            subtitle: monthly == null ? '—' : l10n.pricePerMonthShort(monthly),
          ),
          if (!_yearly) details,
          const SizedBox(height: NcSpace.inputGap),
          option(
            value: true,
            title: l10n.planYearly,
            subtitle: yearly == null ? '—' : l10n.pricePerYearShort(yearly),
            badge: saving == null
                ? null
                : _Badge(
                    label: l10n.saveBadge(_percent(saving, exact: true)),
                    colour: nc.success,
                    background: nc.successSurface,
                  ),
          ),
          if (_yearly) details,
          const SizedBox(height: NcSpace.sectionGap),
          Container(
            padding: const EdgeInsets.all(NcSpace.cardPadding),
            decoration: BoxDecoration(
              color: nc.primarySurface,
              borderRadius: BorderRadius.circular(NcRadius.m),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: NcSize.iconSmall,
                  color: nc.primary,
                ),
                const SizedBox(width: NcSpace.buttonGap),
                Expanded(child: Text(l10n.chargedThroughStore)),
              ],
            ),
          ),
          const SizedBox(height: NcSpace.sectionGap),
          _PillButton(
            label: l10n.confirmSubscribe,
            busy: _busy,
            onPressed: _subscribe,
          ),
        ],
      ),
    );
  }
}

/// "You're now on STAR plan." (Figma "My subscriptions 3").
class PurchaseSuccessScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final sub = ref.watch(subscriptionProvider).value;
    final yearly = sub?.period == 'yearly';
    final end = sub?.periodEnd;
    return Scaffold(
      backgroundColor: nc.surface,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(nc.screenPadding),
          children: [
            const SizedBox(height: NcSpace.sectionGap),
            Center(
              child: Container(
                padding: const EdgeInsets.all(NcSpace.cardGap),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: nc.successSurface.withValues(alpha: 0.5),
                ),
                child: Container(
                  padding: const EdgeInsets.all(NcSpace.cardGap),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: nc.successSurface,
                  ),
                  child: Icon(
                    Icons.verified_outlined,
                    color: nc.success,
                    size: NcSize.icon * 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: NcSpace.cardGap),
            Text(
              l10n.nowOnStar,
              style: text.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: NcSpace.inputGap),
            Text(
              l10n.nowOnStarBody,
              style: text.bodyMedium?.copyWith(color: nc.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: NcSpace.sectionGap),
            _Bordered(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.currentPlanCaps,
                              style: text.labelSmall?.copyWith(
                                color: nc.textSecondary,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(l10n.starPlan, style: text.titleMedium),
                          ],
                        ),
                      ),
                      _Badge(label: l10n.activeBadge, colour: nc.success),
                    ],
                  ),
                  const Divider(height: NcSpace.cardGap * 2),
                  _InfoRow(yearly ? l10n.annualPrice : l10n.monthlyPrice, () {
                    final price = _price(
                      ref,
                      sub?.productId ?? _productId(yearly: yearly),
                    );
                    if (price == null) return '—';
                    return yearly
                        ? l10n.pricePerYearShort(price)
                        : l10n.pricePerMonthShort(price);
                  }()),
                  if (end != null)
                    _InfoRow(l10n.nextBillingDate, _longDate(context, end)),
                  _InfoRow(
                    l10n.autoRenewal,
                    sub?.autoRenew == false
                        ? l10n.autoRenewalOff
                        : l10n.autoRenewalOn,
                    trailingIcon: Icons.info_outline,
                  ),
                  const SizedBox(height: NcSpace.inputGap),
                  Container(
                    padding: const EdgeInsets.all(NcSpace.buttonGap),
                    decoration: BoxDecoration(
                      color: nc.inputFill,
                      borderRadius: BorderRadius.circular(NcRadius.s),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.mail_outline,
                          size: NcSize.iconSmall,
                          color: nc.textSecondary,
                        ),
                        const SizedBox(width: NcSpace.inputGap),
                        Expanded(
                          child: Text(
                            l10n.receiptSent,
                            style: text.bodySmall?.copyWith(
                              color: nc.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: NcSpace.sectionGap),
            _PillButton(
              label: l10n.goToSubscriptions,
              onPressed: () => context.go(Routes.subscriptions),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Billing History" (Figma "My subscriptions 5"); receipts themselves come
/// from the stores by email.
class BillingHistoryScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final history = ref.watch(billingHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.billingHistory)),
      backgroundColor: nc.surface,
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.subscriptionUnavailable)),
        data: (items) => items.isEmpty
            ? Center(child: Text(l10n.noBillingHistory))
            : ListView(
                padding: EdgeInsets.all(nc.screenPadding),
                children: [
                  for (final i in items) ...[
                    _Bordered(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _shortDate(context, i.date),
                                  style: text.titleSmall,
                                ),
                                const SizedBox(height: NcSpace.xs),
                                Text(
                                  i.productId == 'star_yearly'
                                      ? l10n.planNameYearly
                                      : l10n.planNameMonthly,
                                  style: text.bodySmall?.copyWith(
                                    color: nc.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_amount(i), style: text.titleSmall),
                              const SizedBox(height: NcSpace.xs),
                              _Badge(
                                label: i.type == 'refund'
                                    ? l10n.refundedBadge
                                    : l10n.paidBadge,
                                colour: i.type == 'refund'
                                    ? nc.error
                                    : nc.success,
                                background: i.type == 'refund'
                                    ? nc.errorSurface
                                    : nc.successSurface,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: NcSpace.buttonGap),
                  ],
                  const SizedBox(height: NcSpace.inputGap),
                  Text(
                    l10n.receiptsByEmail,
                    style: text.bodySmall?.copyWith(color: nc.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );
  }
}

/// "Cancel Subscription" (Figma "My subscriptions 6"). Cancelling happens in
/// the store (OQ-07); when the user comes back, the subscription is
/// re-read and, once auto-renew is off, "Subscription Cancelled" is shown.
class CancelSubscriptionScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<CancelSubscriptionScreen> createState() => _CancelState();
}

class _CancelState extends ConsumerState<CancelSubscriptionScreen> {
  late final AppLifecycleListener _lifecycle;
  bool _inStore = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _onResume() async {
    if (!_inStore) return;
    _inStore = false;
    ref.invalidate(subscriptionProvider);
    final SubscriptionState s;
    try {
      s = await ref.read(subscriptionProvider.future);
    } on Object {
      return;
    }
    if (mounted && s.isCancelled) {
      context.pushReplacement(Routes.subscriptionCancelled);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final s = ref.watch(subscriptionProvider).value;
    final yearly = s?.period == 'yearly';
    final end = s?.periodEnd;
    Widget bullet(String line) => Padding(
      padding: const EdgeInsets.symmetric(vertical: NcSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: NcSpace.xs),
            child: Icon(Icons.circle, size: NcSpace.inputGap, color: nc.star),
          ),
          const SizedBox(width: NcSpace.buttonGap),
          Expanded(child: Text(line)),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cancelSubscription)),
      backgroundColor: nc.surface,
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          _Bordered(
            colour: nc.star,
            width: 1.5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.currentPlan,
                  style: text.bodySmall?.copyWith(color: nc.textSecondary),
                ),
                Text(l10n.starPlan, style: text.titleLarge),
                const SizedBox(height: NcSpace.inputGap),
                _Price(
                  price: _price(
                    ref,
                    s?.productId ?? _productId(yearly: yearly),
                  ),
                  suffix: yearly ? l10n.perYearSuffix : l10n.perMonthSuffix,
                  colour: nc.star,
                ),
                if (end != null) ...[
                  const Divider(height: NcSpace.cardGap * 2),
                  _InfoRow(l10n.nextBillingDate, _longDate(context, end)),
                ],
              ],
            ),
          ),
          const SizedBox(height: NcSpace.sectionGap),
          Text(l10n.ifYouCancel, style: text.titleMedium),
          const SizedBox(height: NcSpace.inputGap),
          bullet(
            end == null
                ? l10n.cancelAccessTillPeriodEnd
                : l10n.cancelAccessTill(_longDate(context, end)),
          ),
          bullet(l10n.cancelAutoRenewOff),
          bullet(l10n.cancelNoCharge),
          const SizedBox(height: NcSpace.cardGap),
          Text(
            l10n.cancelUpgradeBack,
            style: text.bodyMedium?.copyWith(color: nc.textSecondary),
          ),
          const SizedBox(height: NcSpace.sectionGap),
          OutlinedButton(
            onPressed: s == null
                ? null
                : () async {
                    _inStore = true;
                    await _openStore(context, s);
                  },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(NcSize.buttonHeight),
              foregroundColor: nc.error,
              side: BorderSide(color: nc.error),
              shape: const StadiumBorder(),
            ),
            child: Text(l10n.cancelSubscription),
          ),
          const SizedBox(height: NcSpace.inputGap),
          Text(
            l10n.cancelInStore,
            style: text.bodySmall?.copyWith(color: nc.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: NcSpace.cardGap),
          FilledButton(
            onPressed: () => context.pop(),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(NcSize.buttonHeight),
              shape: const StadiumBorder(),
            ),
            child: Text(l10n.stayOnStar),
          ),
        ],
      ),
    );
  }
}

/// "Subscription Cancelled" (Figma "My subscriptions 7").
class SubscriptionCancelledScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final end = ref.watch(subscriptionProvider).value?.periodEnd;
    return Scaffold(
      backgroundColor: nc.surface,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(nc.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(NcSpace.cardGap),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: nc.errorSurface,
                  ),
                  child: Icon(
                    Icons.event_busy_outlined,
                    color: nc.error,
                    size: NcSize.icon * 1.5,
                  ),
                ),
              ),
              const SizedBox(height: NcSpace.cardGap),
              Text(
                l10n.subscriptionCancelled,
                style: text.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: NcSpace.inputGap),
              Text(l10n.subscriptionCancelledBody, textAlign: TextAlign.center),
              if (end != null) ...[
                const SizedBox(height: NcSpace.inputGap),
                Text(
                  l10n.cancelledAccessTill(_longDate(context, end)),
                  style: text.bodyMedium?.copyWith(color: nc.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              _PillButton(
                label: l10n.goToSubscriptions,
                onPressed: () => context.go(Routes.subscriptions),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ referral

/// "Refer 5 Friends": code, link (copied to the clipboard), progress n/5,
/// friends' active days, and the reward (30 days STANDARD / 50 days STAR).
class ReferFriendsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final progress = ref.watch(referralProgressProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.referFriend)),
      backgroundColor: nc.surface,
      body: progress.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.subscriptionUnavailable)),
        data: (p) => ListView(
          padding: EdgeInsets.all(nc.screenPadding),
          children: [
            Text(l10n.referTitle, style: text.headlineSmall),
            const SizedBox(height: NcSpace.inputGap),
            Text(l10n.referBody),
            const SizedBox(height: NcSpace.cardGap),
            Card(
              elevation: 0,
              color: nc.primarySurface,
              child: ListTile(
                title: Text(p.code, style: text.titleLarge),
                subtitle: Text(p.link),
                trailing: IconButton(
                  tooltip: l10n.copyLink,
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: p.link));
                    if (context.mounted) {
                      showNcToast(context, l10n.linkCopied);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: NcSpace.cardGap),
            Text(
              l10n.referProgress(p.qualified, p.required),
              style: text.titleSmall,
            ),
            const SizedBox(height: NcSpace.xs),
            LinearProgressIndicator(
              value: (p.qualified / p.required).clamp(0, 1),
            ),
            if (p.rewardDays != null) ...[
              const SizedBox(height: NcSpace.inputGap),
              Text(
                l10n.referRewardGranted(p.rewardDays!),
                style: text.bodyMedium?.copyWith(color: nc.success),
              ),
            ],
            const SizedBox(height: NcSpace.cardGap),
            for (final f in p.friends)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text(f.display.characters.first)),
                title: Text(f.display),
                subtitle: Text(
                  f.status == 'qualified'
                      ? l10n.friendQualified
                      : f.status == 'disqualified'
                      ? l10n.friendNotQualified
                      : l10n.friendActiveDays(f.activeDays),
                ),
              ),
            const SizedBox(height: NcSpace.cardGap),
            Text(
              l10n.referRules,
              style: text.bodySmall?.copyWith(color: nc.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
