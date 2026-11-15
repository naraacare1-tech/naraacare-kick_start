import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/features/care_circle/circle_providers.dart';
import 'package:naraacare/features/care_circle/data/circle_data.dart';
import 'package:naraacare/features/care_circle/presentation/circle_widgets.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';

/// "Profile / Connections": My Connections (connected + Invites with
/// Connect / Decline) and Find People (username search + Suggested for
/// you). Requests go by username; the API hides blocked people both ways.
class ConnectionsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ConnectionsScreen> createState() => _ConnectionsState();
}

class _ConnectionsState extends ConsumerState<ConnectionsScreen> {
  List<SearchResult>? _results;
  final _requested = <String>{};
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
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
        final r = await ref.read(circleApiProvider).search(query);
        if (mounted) setState(() => _results = r);
      } on Object {
        if (mounted) setState(() => _results = const []);
      }
    });
  }

  Future<void> _connect(PersonCard p) async {
    final l10n = AppLocalizations.of(context);
    final username = p.username;
    if (username == null) return;
    final ok = await runSocial(
      context,
      () => ref.read(circleApiProvider).requestConnection(username),
      success: l10n.requestSent,
    );
    if (ok && mounted) {
      setState(() => _requested.add(p.userId));
      ref.invalidate(connectionsProvider);
    }
  }

  Future<void> _respond(Connection c, {required bool accept}) async {
    final ok = await runSocial(
      context,
      () => ref.read(circleApiProvider).respondConnection(c.id, accept: accept),
    );
    if (ok) ref.invalidate(connectionsProvider);
  }

  Widget _person(PersonCard p, {Widget? trailing, String? subtitle}) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: PersonAvatar(person: p),
        title: Text(p.displayName ?? p.handle),
        subtitle: Text(subtitle ?? (p.displayName == null ? '' : p.handle)),
        trailing: trailing,
      );

  Widget _connectButton(PersonCard p, ConnectionStatus state) {
    final l10n = AppLocalizations.of(context);
    if (state == ConnectionStatus.connected) {
      return Text(l10n.connected);
    }
    if (state == ConnectionStatus.outgoing || _requested.contains(p.userId)) {
      return Text(l10n.requested);
    }
    return OutlinedButton(
      onPressed: () => _connect(p),
      child: Text(l10n.connect),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final connections = ref.watch(connectionsProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: nc.surface,
        appBar: AppBar(
          title: Text(l10n.connections),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.myConnections),
              Tab(text: l10n.findPeople),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            connections.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(child: Text(l10n.circlesUnavailable)),
              data: (all) {
                final incoming = [
                  for (final c in all)
                    if (c.state == ConnectionStatus.incoming) c,
                ];
                final connected = [
                  for (final c in all)
                    if (c.state == ConnectionStatus.connected) c,
                ];
                return ListView(
                  padding: EdgeInsets.all(nc.screenPadding),
                  children: [
                    if (incoming.isNotEmpty) ...[
                      SectionHeader(l10n.invitesHeader),
                      for (final c in incoming)
                        _person(
                          c.person,
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              // The theme's full-width minimum would make
                              // this infinitely wide inside a list row and
                              // the screen would go blank.
                              FilledButton(
                                onPressed: () => _respond(c, accept: true),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                ),
                                child: Text(l10n.connect),
                              ),
                              TextButton(
                                onPressed: () => _respond(c, accept: false),
                                child: Text(l10n.decline),
                              ),
                            ],
                          ),
                        ),
                    ],
                    SectionHeader(l10n.connectedOnNaraaCare),
                    if (connected.isEmpty) Text(l10n.noConnectionsYet),
                    for (final c in connected) _person(c.person),
                  ],
                );
              },
            ),
            ListView(
              padding: EdgeInsets.all(nc.screenPadding),
              children: [
                NcTextField(
                  hint: l10n.searchByUsername,
                  prefixIcon: Icons.search,
                  validator: InputValidators.usernameSearch,
                  maxLength: 64,
                  onChanged: _onQuery,
                ),
                if (_results != null) ...[
                  SectionHeader(l10n.results),
                  if (_results!.isEmpty) Text(l10n.noResults),
                  for (final r in _results!)
                    _person(
                      r.person,
                      trailing: _connectButton(r.person, r.state),
                    ),
                ] else ...[
                  SectionHeader(l10n.suggestedForYou),
                  for (final p
                      in ref.watch(suggestionsProvider).value ??
                          const <PersonCard>[])
                    _person(
                      p,
                      trailing: _connectButton(p, ConnectionStatus.none),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
