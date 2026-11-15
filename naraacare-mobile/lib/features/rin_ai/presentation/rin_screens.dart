import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/care_circle/presentation/circle_widgets.dart';
import 'package:naraacare/features/hydration/hydration_providers.dart';
import 'package:naraacare/features/nutrition/nutrition_providers.dart';
import 'package:naraacare/features/nutrition/presentation/widgets/nutrition_widgets.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/features/rin_ai/data/rin_data.dart';
import 'package:naraacare/features/rin_ai/rin_providers.dart';
import 'package:naraacare/shared/widgets/nc_bottom_sheet.dart';
import 'package:naraacare/shared/widgets/nc_star_badge.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';

String rinErrorMessage(AppLocalizations l10n, ApiError e) => switch (e.code) {
  'MONTHLY_LIMIT_REACHED' || 'DAILY_LIMIT_REACHED' => l10n.rinLimitReached,
  'SERVICE_UNAVAILABLE' || 'RIN_UNAVAILABLE' => l10n.rinResting,
  'ACTION_EXPIRED' => l10n.rinActionExpired,
  'ACTION_RESOLVED' => l10n.rinActionResolved,
  _ => featureErrorMessage(l10n, e),
};

// ------------------------------------------------------------ Rin AI tab

/// The Rin AI tab: STANDARD sees "Unlock Rin AI" (Figma Rin AI-1); STAR gets
/// a new chat (Figma Rin AI/Start).
class RinTabScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(isStarProvider) ? const RinChatScreen() : const _RinLocked();
}

class _Feature extends StatelessWidget {
  const new({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: NcSpace.buttonGap),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(NcRadius.m),
      side: BorderSide(color: context.nc.inputFill),
    ),
    child: ListTile(
      leading: Icon(icon, color: color),
      title: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}

List<Widget> _features(AppLocalizations l10n) => [
  _Feature(
    icon: Icons.forum_outlined,
    text: l10n.rinFeatureChat,
    color: const Color(0xFF34AFF0),
  ),
  _Feature(
    icon: Icons.restaurant_outlined,
    text: l10n.rinFeatureLog,
    color: const Color(0xFFE53935),
  ),
  _Feature(
    icon: Icons.lightbulb_outline,
    text: l10n.rinFeatureTips,
    color: const Color(0xFFB8762E),
  ),
  _Feature(
    icon: Icons.notifications_active_outlined,
    text: l10n.rinFeatureAvatar,
    color: const Color(0xFFE79FE0),
  ),
];

class _RinLocked extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: nc.surface,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(nc.screenPadding),
          children: [
            const SizedBox(height: NcSpace.sectionGap),
            Icon(Icons.auto_awesome, size: 56, color: nc.textPrimary),
            const SizedBox(height: NcSpace.cardGap),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(l10n.unlockRin, style: text.headlineSmall),
                const SizedBox(width: NcSpace.inputGap),
                const NcStarBadge(),
              ],
            ),
            const SizedBox(height: NcSpace.inputGap),
            Text(
              l10n.unlockRinBody,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: nc.textSecondary),
            ),
            const SizedBox(height: NcSpace.sectionGap),
            ..._features(l10n),
            const SizedBox(height: NcSpace.cardGap),
            FilledButton.icon(
              onPressed: () => showStarUpsell(context),
              icon: const Icon(Icons.star),
              label: Text(l10n.upgradeToStar),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ chat

/// "Rin AI/Start" and "Rin AI/Conversation": suggestions when empty, then the
/// chat. Replies stream in (text appears as it arrives) and are replaced by
/// the stored plain text when done. A meal or drink Rin proposes shows as a
/// card: Add to Avatar logs it, Edit adjusts the amounts first, Not Now
/// dismisses it. Every screen carries the medical disclaimer.
class RinChatScreen extends ConsumerStatefulWidget {
  const new({super.key, this.conversationId});

  final String? conversationId;

  @override
  ConsumerState<RinChatScreen> createState() => _RinChatState();
}

class _Turn {
  new({required this.fromUser, required this.text, this.action});

  final bool fromUser;
  String text;
  RinAction? action;
}

class _RinChatState extends ConsumerState<RinChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <_Turn>[];
  String? _conversationId;
  bool _busy = false;
  bool _loading = false;

  RinApi get _api => ref.read(rinApiProvider);

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    if (_conversationId != null) unawaited(_load());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final messages = await _api.messages(_conversationId!);
      if (!mounted) return;
      setState(() {
        _turns
          ..clear()
          ..addAll([
            for (final m in messages.reversed)
              _Turn(fromUser: m.fromUser, text: m.text, action: m.action),
          ]);
      });
    } on ApiError catch (e) {
      if (mounted) _toast(rinErrorMessage(AppLocalizations.of(context), e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String message, {bool error = true}) => showNcToast(
    context,
    message,
    kind: error ? NcToastKind.error : NcToastKind.success,
  );

  Future<void> _send(String raw) async {
    final l10n = AppLocalizations.of(context);
    final text = InputValidators.normalise(raw);
    if (text.isEmpty || _busy) return;
    if (InputValidators.chatMessage()(text) != null) {
      _toast(l10n.messageNotAllowed);
      return;
    }
    setState(() => _busy = true);
    try {
      _conversationId ??= await _api.createConversation();
      final reply = _Turn(fromUser: false, text: '');
      setState(() {
        _turns.addAll([_Turn(fromUser: true, text: text), reply]);
        _input.clear();
      });
      await for (final e in _api.send(_conversationId!, text)) {
        if (!mounted) return;
        switch (e.type) {
          case 'delta':
            setState(() => reply.text += (e.data['text'] as String?) ?? '');
          case 'action':
            setState(() => reply.action = RinAction.fromJson(e.data));
          case 'done':
            final done = e.data['text'] as String?;
            setState(() {
              if (done != null) reply.text = done;
              if (e.data['duplicate'] == true) _turns.remove(reply);
            });
            ref.invalidate(rinUsageProvider);
          case 'error':
            setState(() => reply.text = l10n.rinResting);
        }
      }
    } on ApiError catch (e) {
      if (!mounted) return;
      if (_turns.isNotEmpty && _turns.last.text.isEmpty) {
        setState(_turns.removeLast);
      }
      if (e.code == 'CONSENT_REQUIRED') {
        if (_turns.isNotEmpty && _turns.last.fromUser) {
          setState(_turns.removeLast);
        }
        if (await _askConsent() && mounted) unawaited(_send(text));
      } else {
        _toast(rinErrorMessage(l10n, e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Rin needs the ai_processing consent (OQ-37): ask once, record it.
  Future<bool> _askConsent() async {
    final l10n = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.rinConsentTitle),
        content: Text(l10n.rinConsentBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l10n.notNow),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l10n.allow),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return false;
    try {
      await _api.grantAiConsent();
      return true;
    } on ApiError catch (e) {
      if (mounted) _toast(rinErrorMessage(l10n, e));
      return false;
    }
  }

  Future<void> _accept(_Turn turn, {List<Map<String, Object?>>? items}) async {
    final l10n = AppLocalizations.of(context);
    final action = turn.action!;
    try {
      await _api.accept(action.id, items: items);
      if (!mounted) return;
      setState(() => turn.action = action.withStatus('accepted'));
      ref
        ..invalidate(dailySummaryProvider)
        ..invalidate(hydrationStatusProvider);
      _toast(l10n.rinAdded, error: false);
    } on ApiError catch (e) {
      if (mounted) _toast(rinErrorMessage(l10n, e));
    }
  }

  Future<void> _dismiss(_Turn turn) async {
    final action = turn.action!;
    try {
      await _api.dismiss(action.id);
      if (mounted) setState(() => turn.action = action.withStatus('dismissed'));
    } on ApiError catch (e) {
      if (mounted) _toast(rinErrorMessage(AppLocalizations.of(context), e));
    }
  }

  Future<void> _edit(_Turn turn) async {
    final items = await showNcBottomSheet<List<Map<String, Object?>>>(
      context: context,
      title: AppLocalizations.of(context).rinEditTitle,
      builder: (_) => _EditItems(action: turn.action!),
    );
    if (items != null && mounted) await _accept(turn, items: items);
  }

  Future<void> _menu() async {
    final l10n = AppLocalizations.of(context);
    final choice = await showNcBottomSheet<String>(
      context: context,
      title: l10n.rinAi,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.search),
            title: Text(l10n.rinSearchHistory),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(sheet).pop('search'),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text(l10n.rinHelp),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(sheet).pop('help'),
          ),
          if (_conversationId != null)
            ListTile(
              leading: Icon(Icons.delete_outline, color: context.nc.error),
              title: Text(
                l10n.rinDeleteChat,
                style: TextStyle(color: context.nc.error),
              ),
              onTap: () => Navigator.of(sheet).pop('delete'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'search':
        unawaited(context.push(Routes.rinSearch));
      case 'help':
        unawaited(context.push(Routes.rinHelp));
      case 'delete':
        await _delete();
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.rinDeleteTitle),
        content: Text(l10n.rinDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await _api.deleteConversation(_conversationId!);
      if (!mounted) return;
      _toast(l10n.rinDeleted, error: false);
      if (widget.conversationId != null) {
        context.pop();
      } else {
        setState(() {
          _turns.clear();
          _conversationId = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) _toast(rinErrorMessage(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final usage = ref.watch(rinUsageProvider).value;
    final limited = (usage?.usedPct ?? 0) >= 100;
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(
        automaticallyImplyLeading: widget.conversationId != null,
        title: Text(l10n.rinAi),
        actions: [
          IconButton(
            tooltip: l10n.moreOptions,
            icon: const Icon(Icons.more_vert),
            onPressed: _menu,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (usage != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: nc.screenPadding),
                child: Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: usage.usedPct / 100,
                        backgroundColor: nc.inputFill,
                        color: limited ? nc.error : nc.primary,
                      ),
                    ),
                    const SizedBox(width: NcSpace.inputGap),
                    Text(
                      // One decimal below 10 % so each reply visibly moves
                      // the bar (one short reply is about 0.2 %).
                      l10n.rinUsage(
                        usage.usedPct < 10
                            ? usage.usedPct.toStringAsFixed(1)
                            : usage.usedPct.round().toString(),
                      ),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _turns.isEmpty
                  ? _Start(onPick: _send)
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: EdgeInsets.all(nc.screenPadding),
                      itemCount: _turns.length,
                      itemBuilder: (context, i) {
                        final turn = _turns[_turns.length - 1 - i];
                        return _RinBubble(
                          turn: turn,
                          onAccept: () => _accept(turn),
                          onEdit: () => _edit(turn),
                          onDismiss: () => _dismiss(turn),
                        );
                      },
                    ),
            ),
            if (limited)
              Padding(
                padding: const EdgeInsets.all(NcSpace.inputGap),
                child: Text(
                  l10n.rinLimitReached,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: nc.error),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                nc.screenPadding,
                NcSpace.xs,
                nc.screenPadding,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: NcTextField(
                      controller: _input,
                      hint: l10n.typeHere,
                      enabled: !limited,
                      validator: (v) => v.trim().isEmpty
                          ? null
                          : InputValidators.chatMessage()(v),
                      maxLength: 2000,
                      maxLines: 4,
                      minLines: 1,
                    ),
                  ),
                  IconButton.filled(
                    tooltip: l10n.send,
                    onPressed: _busy || limited
                        ? null
                        : () => _send(_input.text),
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NcSpace.cardGap,
                NcSpace.xs,
                NcSpace.cardGap,
                NcSpace.inputGap,
              ),
              child: Text(
                l10n.rinDisclaimer,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: nc.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Start extends ConsumerWidget {
  const new({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final name = (ref.watch(meProvider).value?.profile.fullName ?? '')
        .split(' ')
        .first;
    final suggestions = [
      (Icons.description_outlined, l10n.rinSuggestToday),
      (Icons.restaurant_outlined, l10n.rinSuggestDinner),
      (Icons.battery_alert_outlined, l10n.rinSuggestTired),
      (Icons.water_drop_outlined, l10n.rinSuggestWater),
    ];
    return ListView(
      padding: EdgeInsets.all(nc.screenPadding),
      children: [
        const SizedBox(height: NcSpace.sectionGap),
        Text(
          name.isEmpty ? l10n.rinHi : l10n.rinHiName(name),
          textAlign: TextAlign.center,
          style: text.headlineSmall,
        ),
        const SizedBox(height: NcSpace.inputGap),
        Text(
          l10n.rinIntro,
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: nc.textSecondary),
        ),
        const SizedBox(height: NcSpace.sectionGap),
        for (final (icon, label) in suggestions)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: NcSpace.buttonGap),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NcRadius.m),
              side: BorderSide(color: nc.inputFill),
            ),
            child: ListTile(
              leading: Icon(icon, color: nc.primary),
              title: Text(label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onPick(label),
            ),
          ),
      ],
    );
  }
}

class _RinBubble extends StatelessWidget {
  const new({
    required this.turn,
    required this.onAccept,
    required this.onEdit,
    required this.onDismiss,
  });

  final _Turn turn;
  final VoidCallback onAccept;
  final VoidCallback onEdit;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final mine = turn.fromUser;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(vertical: NcSpace.xs),
        padding: const EdgeInsets.all(NcSpace.buttonGap),
        decoration: BoxDecoration(
          color: mine ? nc.primary : nc.surface,
          borderRadius: BorderRadius.circular(NcRadius.l),
          border: mine ? null : Border.all(color: nc.inputFill),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (turn.text.isEmpty)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                turn.text,
                style: text.bodyMedium?.copyWith(
                  color: mine ? Colors.white : nc.textPrimary,
                ),
              ),
            if (turn.action != null)
              _ActionCard(
                action: turn.action!,
                onAccept: onAccept,
                onEdit: onEdit,
                onDismiss: onDismiss,
              ),
          ],
        ),
      ),
    );
  }
}

/// The meal / drink estimate card (Figma "Rin AI/Actions").
class _ActionCard extends StatelessWidget {
  const new({
    required this.action,
    required this.onAccept,
    required this.onEdit,
    required this.onDismiss,
  });

  final RinAction action;
  final VoidCallback onAccept;
  final VoidCallback onEdit;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final meal = action.kind == 'meal';
    return Container(
      margin: const EdgeInsets.only(top: NcSpace.inputGap),
      padding: const EdgeInsets.all(NcSpace.buttonGap),
      decoration: BoxDecoration(
        color: nc.primarySurface,
        borderRadius: BorderRadius.circular(NcRadius.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meal) ...[
            for (final i in action.items)
              Text(
                '${i['food_name']} · '
                '${l10n.kcalValueShort((i['calories'] as num?)?.toInt() ?? 0)}',
                style: text.bodySmall,
              ),
            const SizedBox(height: NcSpace.xs),
            Text(
              l10n.rinMealTotals(
                action.total('calories'),
                action.total('protein'),
                action.total('carbohydrates'),
                action.total('fat'),
              ),
              style: text.bodyMedium,
            ),
          ] else
            Text(
              l10n.rinDrinkCard(
                l10n.mlValue(
                  (action.payload['volume_ml'] as num?)?.toInt() ?? 0,
                ),
                '${action.payload['drink_code']}',
              ),
              style: text.bodyMedium,
            ),
          const SizedBox(height: NcSpace.inputGap),
          switch (action.status) {
            'accepted' => Text(
              l10n.rinAdded,
              style: TextStyle(color: nc.success),
            ),
            'dismissed' => Text(
              l10n.rinNotAdded,
              style: TextStyle(color: nc.textSecondary),
            ),
            'expired' => Text(
              l10n.rinActionExpired,
              style: TextStyle(color: nc.textSecondary),
            ),
            _ => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.rinAddQuestion, style: text.bodySmall),
                const SizedBox(height: NcSpace.xs),
                FilledButton(
                  onPressed: onAccept,
                  child: Text(l10n.rinAddToAvatar),
                ),
                Row(
                  children: [
                    if (meal)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onEdit,
                          child: Text(l10n.edit),
                        ),
                      ),
                    if (meal) const SizedBox(width: NcSpace.inputGap),
                    Expanded(
                      child: TextButton(
                        onPressed: onDismiss,
                        child: Text(l10n.notNow),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          },
        ],
      ),
    );
  }
}

/// Edit: adjust each item's amount (or remove it) before adding.
class _EditItems extends StatefulWidget {
  const new({required this.action});

  final RinAction action;

  @override
  State<_EditItems> createState() => _EditItemsState();
}

class _EditItemsState extends State<_EditItems> {
  late final List<Map<String, dynamic>> _items = [
    for (final i in widget.action.items) {...i},
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final i in _items)
          ListTile(
            title: Text('${i['food_name']}'),
            subtitle: Text('${i['portion_label'] ?? i['unit_code']}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l10n.less,
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() {
                    final q = (i['quantity'] as num).toDouble() - 0.5;
                    if (q <= 0) {
                      _items.remove(i);
                    } else {
                      i['quantity'] = q;
                    }
                  }),
                ),
                Text('${i['quantity']}'),
                IconButton(
                  tooltip: l10n.more,
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(
                    () => i['quantity'] =
                        ((i['quantity'] as num).toDouble() + 0.5).clamp(
                          0.5,
                          20,
                        ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(NcSpace.cardPadding),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _items.isEmpty
                  ? null
                  : () => Navigator.of(context).pop([
                      for (final i in _items)
                        {
                          'food_id': i['food_id'],
                          'quantity': i['quantity'],
                          'unit_code': i['unit_code'],
                          'unit_size': i['unit_size'],
                        },
                    ]),
              child: Text(l10n.rinAddToAvatar),
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ search, help

/// "Search in Rin AI": past chats, filtered by text (title or prompts).
class RinSearchScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<RinSearchScreen> createState() => _RinSearchState();
}

class _RinSearchState extends ConsumerState<RinSearchScreen> {
  List<RinConversation>? _items;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    unawaited(_run(null));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _run(String? query) async {
    try {
      final items = await ref.read(rinApiProvider).conversations(query: query);
      if (mounted) setState(() => _items = items);
    } on ApiError catch (e) {
      if (mounted) {
        showNcToast(
          context,
          rinErrorMessage(AppLocalizations.of(context), e),
          kind: NcToastKind.error,
        );
        setState(() => _items = const []);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.rinSearchTitle)),
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          NcTextField(
            hint: l10n.rinSearchHint,
            prefixIcon: Icons.search,
            validator: (v) =>
                v.trim().isEmpty ? null : InputValidators.search(v),
            maxLength: 64,
            onChanged: (v) {
              _debounce?.cancel();
              final q = InputValidators.normalise(v);
              if (q.isNotEmpty && InputValidators.search(q) != null) return;
              _debounce = Timer(
                const Duration(milliseconds: 350),
                () => _run(q.isEmpty ? null : q),
              );
            },
          ),
          SectionHeader(l10n.rinConversations),
          if (_items == null)
            const Center(child: CircularProgressIndicator())
          else if (_items!.isEmpty)
            Text(l10n.noResults)
          else
            for (final c in _items!)
              Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: NcSpace.inputGap),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(NcRadius.m),
                  side: BorderSide(color: nc.inputFill),
                ),
                child: ListTile(
                  title: Text(
                    c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    timeAgo(l10n, c.lastAt),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  onTap: () => context.push(Routes.rinConversation(c.id)),
                ),
              ),
        ],
      ),
    );
  }
}

/// "Rin AI help": what Rin does, the disclaimer, and clearing Rin's memory.
class RinHelpScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.rinHelpTitle)),
      body: ListView(
        padding: EdgeInsets.all(nc.screenPadding),
        children: [
          Text(
            l10n.aboutRin,
            textAlign: TextAlign.center,
            style: text.headlineSmall,
          ),
          const SizedBox(height: NcSpace.inputGap),
          Text(
            l10n.aboutRinBody,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: nc.textSecondary),
          ),
          const SizedBox(height: NcSpace.sectionGap),
          ..._features(l10n),
          const SizedBox(height: NcSpace.cardGap),
          Container(
            padding: const EdgeInsets.all(NcSpace.buttonGap),
            decoration: BoxDecoration(
              color: nc.primarySurface,
              borderRadius: BorderRadius.circular(NcRadius.m),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: nc.star),
                const SizedBox(width: NcSpace.inputGap),
                Expanded(child: Text(l10n.rinDisclaimer)),
              ],
            ),
          ),
          const SizedBox(height: NcSpace.sectionGap),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                await ref.read(rinApiProvider).deleteMemory();
                if (context.mounted) {
                  showNcToast(context, l10n.rinMemoryCleared);
                }
              } on ApiError catch (e) {
                if (context.mounted) {
                  showNcToast(
                    context,
                    rinErrorMessage(l10n, e),
                    kind: NcToastKind.error,
                  );
                }
              }
            },
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text(l10n.rinClearMemory),
          ),
        ],
      ),
    );
  }
}
