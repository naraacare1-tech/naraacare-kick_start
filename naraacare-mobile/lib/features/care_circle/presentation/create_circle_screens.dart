import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/care_circle/circle_providers.dart';
import 'package:naraacare/features/care_circle/data/circle_data.dart';
import 'package:naraacare/features/care_circle/presentation/circle_widgets.dart';
import 'package:naraacare/features/nutrition/nutrition_providers.dart';
import 'package:naraacare/features/nutrition/presentation/widgets/nutrition_widgets.dart';
import 'package:naraacare/shared/widgets/nc_star_badge.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';

/// The circle being created: its name and the people picked so far.
class CircleDraft {
  const new({this.name = '', this.invitees = const {}});

  final String name;
  final Set<String> invitees;
}

class CircleDraftNotifier extends Notifier<CircleDraft> {
  @override
  CircleDraft build() => const CircleDraft();

  void start() => state = const CircleDraft();
  void name(String value) =>
      state = CircleDraft(name: value, invitees: state.invitees);
  void toggle(String userId) => state = CircleDraft(
    name: state.name,
    invitees: state.invitees.contains(userId)
        ? ({...state.invitees}..remove(userId))
        : {...state.invitees, userId},
  );
}

final NotifierProvider<CircleDraftNotifier, CircleDraft> circleDraftProvider =
    NotifierProvider<CircleDraftNotifier, CircleDraft>(CircleDraftNotifier.new);

// ------------------------------------------------------------ Care Circle 2

/// "Create a Circle": the circle name (SafeShortText50 on the API).
class CreateCircleScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<CreateCircleScreen> createState() => _CreateCircleState();
}

class _CreateCircleState extends ConsumerState<CreateCircleScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.createCircleTitleShort)),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: EdgeInsets.all(nc.screenPadding),
            children: [
              NcTextField(
                controller: _name,
                label: l10n.circleName,
                hint: l10n.circleNameHint,
                helper: l10n.circleNameHelper,
                validator: InputValidators.shortText(max: 50),
                maxLength: 50,
                autofocus: true,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: NcSpace.sectionGap),
              FilledButton(
                onPressed: () {
                  if (!(_form.currentState?.validate() ?? false)) return;
                  ref
                      .read(circleDraftProvider.notifier)
                      .name(InputValidators.normalise(_name.text));
                  unawaited(context.push(Routes.createCircleMembers));
                },
                child: Text(l10n.next),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------- Care Circle 3.1-3.3

/// "Add Members": People on NaraaCare (connections, or a username search)
/// and Invite Link. While creating, picks go into the draft; for an
/// existing circle ([circleId]) they are invited at once.
class AddMembersScreen extends ConsumerStatefulWidget {
  const new({super.key, this.circleId});

  final String? circleId;

  @override
  ConsumerState<AddMembersScreen> createState() => _AddMembersState();
}

class _AddMembersState extends ConsumerState<AddMembersScreen> {
  final _search = TextEditingController();
  final _picked = <String>{};
  List<SearchResult>? _results;
  Timer? _debounce;
  bool _busy = false;

  bool get _creating => widget.circleId == null;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    final query = InputValidators.normalise(value).replaceFirst('@', '');
    if (query.length < 3 || InputValidators.usernameSearch(query) != null) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await ref.read(circleApiProvider).search(query);
        if (mounted) setState(() => _results = results);
      } on Object {
        if (mounted) setState(() => _results = const []);
      }
    });
  }

  bool _isPicked(String userId) => _creating
      ? ref.read(circleDraftProvider).invitees.contains(userId)
      : _picked.contains(userId);

  void _toggle(String userId) => setState(() {
    if (_creating) {
      ref.read(circleDraftProvider.notifier).toggle(userId);
    } else if (!_picked.remove(userId)) {
      _picked.add(userId);
    }
  });

  Future<void> _invite() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final ok = await runSocial(
      context,
      () => ref
          .read(circleApiProvider)
          .inviteMembers(widget.circleId!, _picked.toList()),
      success: l10n.invitesSent,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(circleMembersProvider(widget.circleId!));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    ref.watch(circleDraftProvider);
    final count = _creating
        ? ref.watch(circleDraftProvider).invitees.length
        : _picked.length;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: nc.surface,
        appBar: AppBar(
          title: Text(l10n.addMembers),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.peopleOnNaraaCare),
              Tab(text: l10n.inviteLink),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _peopleTab(context, l10n, nc, count),
              _InviteLinkTab(circleId: widget.circleId),
            ],
          ),
        ),
      ),
    );
  }

  Widget _peopleTab(
    BuildContext context,
    AppLocalizations l10n,
    NcTheme nc,
    int count,
  ) {
    final connections = ref.watch(connectionsProvider).value ?? const [];
    final connected = [
      for (final c in connections)
        if (c.state == ConnectionStatus.connected) c.person,
    ];
    final people = _results == null
        ? connected
        : [for (final r in _results!) r.person];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(nc.screenPadding),
            children: [
              NcTextField(
                controller: _search,
                hint: l10n.searchByUsername,
                prefixIcon: Icons.search,
                validator: InputValidators.usernameSearch,
                maxLength: 64,
                onChanged: _onQuery,
              ),
              SectionHeader(
                _results == null ? l10n.connectedOnNaraaCare : l10n.results,
              ),
              if (people.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(NcSpace.cardPadding),
                  child: Text(
                    _results == null ? l10n.noConnectionsYet : l10n.noResults,
                    style: TextStyle(color: nc.textSecondary),
                  ),
                ),
              for (final p in people)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PersonAvatar(person: p),
                  title: Text(p.displayName ?? p.handle),
                  subtitle: p.displayName == null ? null : Text(p.handle),
                  trailing: Icon(
                    _isPicked(p.userId)
                        ? Icons.check_circle
                        : Icons.add_circle_outline,
                    color: nc.primary,
                  ),
                  onTap: () => _toggle(p.userId),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.all(nc.screenPadding),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy
                  ? null
                  : _creating
                  ? () => context.push(Routes.createCircleShares)
                  : count == 0
                  ? null
                  : _invite,
              child: Text(
                _creating
                    ? (count == 0 ? l10n.skip : l10n.nextWithCount(count))
                    : l10n.inviteCount(count),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InviteLinkTab extends ConsumerStatefulWidget {
  const new({required this.circleId});

  final String? circleId;

  @override
  ConsumerState<_InviteLinkTab> createState() => _InviteLinkTabState();
}

class _InviteLinkTabState extends ConsumerState<_InviteLinkTab> {
  bool _busy = false;

  Future<void> _copy() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    String? url;
    await runSocial(context, () async {
      url = await ref
          .read(circleApiProvider)
          .createInviteLink(widget.circleId!);
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (url != null) {
      await Clipboard.setData(ClipboardData(text: url!));
      if (mounted) showNcToast(context, l10n.inviteLinkCopied);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.all(nc.screenPadding),
      child: Column(
        children: [
          const SizedBox(height: NcSpace.sectionGap),
          CircleAvatar(
            radius: 40,
            backgroundColor: nc.primarySurface,
            child: Icon(Icons.link, size: 40, color: nc.primary),
          ),
          const SizedBox(height: NcSpace.cardGap),
          Text(l10n.invitePeopleTitle, style: text.titleMedium),
          const SizedBox(height: NcSpace.inputGap),
          Text(
            widget.circleId == null
                ? l10n.inviteLinkAfterCreate
                : l10n.invitePeopleBody,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: nc.textSecondary),
          ),
          const Spacer(),
          if (widget.circleId != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _copy,
                icon: const Icon(Icons.copy),
                label: Text(l10n.copyInviteLink),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ Care Circle 4

/// Why the share picker is open.
enum ShareMode { create, accept, update }

/// "Share with" + circle name: at least one avatar (Figma note), sleep only on
/// STAR (the API checks both sharer and viewer).
class ShareAvatarsScreen extends ConsumerStatefulWidget {
  const new({
    required this.mode,
    super.key,
    this.circleId,
    this.circleName,
    this.initial = const {},
  });

  final ShareMode mode;
  final String? circleId;
  final String? circleName;
  final Set<AvatarType> initial;

  @override
  ConsumerState<ShareAvatarsScreen> createState() => _ShareAvatarsState();
}

class _ShareAvatarsState extends ConsumerState<ShareAvatarsScreen> {
  late final Set<AvatarType> _shares = {...widget.initial};
  bool _busy = false;

  Future<void> _save() async {
    final api = ref.read(circleApiProvider);
    setState(() => _busy = true);
    String? goTo;
    final ok = await runSocial(context, () async {
      switch (widget.mode) {
        case ShareMode.create:
          final draft = ref.read(circleDraftProvider);
          final circle = await api.createCircle(
            name: draft.name,
            inviteeIds: draft.invitees.toList(),
            shares: _shares,
          );
          goTo = Routes.circle(circle.id);
        case ShareMode.accept:
          await api.acceptInvite(widget.circleId!, _shares);
          goTo = Routes.circle(widget.circleId!);
        case ShareMode.update:
          await api.updateShares(widget.circleId!, _shares);
      }
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    ref
      ..invalidate(circlesProvider)
      ..invalidate(circleInvitesProvider);
    if (widget.circleId != null) {
      ref.invalidate(circleDetailProvider(widget.circleId!));
    }
    if (goTo != null) {
      context.go(Routes.careCircle);
      unawaited(context.push(goTo!));
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final star = ref.watch(isStarProvider);
    final name = widget.circleName ?? ref.watch(circleDraftProvider).name;
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(title: Text(l10n.shareWith(name))),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(nc.screenPadding),
          children: [
            Text(
              l10n.chooseShares,
              style: text.bodyMedium?.copyWith(color: nc.textSecondary),
            ),
            const SizedBox(height: NcSpace.cardGap),
            for (final type in AvatarType.values)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Text(
                  avatarEmoji(type),
                  style: const TextStyle(fontSize: 24),
                ),
                title: Row(
                  children: [
                    Text(avatarLabel(l10n, type)),
                    if (type == AvatarType.sleep) ...[
                      const SizedBox(width: NcSpace.inputGap),
                      const NcStarBadge(),
                    ],
                  ],
                ),
                value: _shares.contains(type),
                onChanged: type == AvatarType.sleep && !star
                    ? null
                    : (on) => setState(
                        () => on ? _shares.add(type) : _shares.remove(type),
                      ),
              ),
            if (!star) ...[
              const SizedBox(height: NcSpace.cardGap),
              Card(
                elevation: 0,
                color: nc.primarySurface,
                child: Padding(
                  padding: const EdgeInsets.all(NcSpace.cardPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.whyStar, style: text.titleSmall),
                      const SizedBox(height: NcSpace.xs),
                      Text(l10n.whyStarBody, style: text.bodySmall),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => showStarUpsell(context),
                          child: Text(l10n.upgrade),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: NcSpace.cardGap),
            Text(
              l10n.changeSharesLater,
              style: text.bodySmall?.copyWith(color: nc.textSecondary),
            ),
            const SizedBox(height: NcSpace.sectionGap),
            FilledButton(
              onPressed: _shares.isEmpty || _busy ? null : _save,
              child: Text(switch (widget.mode) {
                ShareMode.create => l10n.createCircleButton,
                ShareMode.accept => l10n.joinCircle,
                ShareMode.update => l10n.save,
              }),
            ),
          ],
        ),
      ),
    );
  }
}
