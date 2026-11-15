import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/care_circle/circle_providers.dart';
import 'package:naraacare/features/care_circle/data/circle_data.dart';
import 'package:naraacare/features/care_circle/data/realtime_client.dart';
import 'package:naraacare/features/care_circle/presentation/circle_widgets.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';

/// "Care Circle 6 / Messages": the circle chat (doc 04 section 2.9).
///
/// * New messages arrive over the realtime socket; the list also reloads
///   when the screen opens. Opening it marks the chat read.
/// * @mentions: typing "@" lists members; picking one inserts "@username"
///   and records the member's id. Only ids of members still named in the
///   text are sent; the server checks them again (MENTION_INVALID).
/// * Bodies are plain text (chatMessage validator, 2000 max) shown with
///   Text spans only: mentions are highlighted, never turned into links.
/// * Long-press your own message (any message, for admins) to delete it.
class CircleChatScreen extends ConsumerStatefulWidget {
  const new({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<CircleChatScreen> createState() => _CircleChatState();
}

class _CircleChatState extends ConsumerState<CircleChatScreen> {
  final _input = TextEditingController();
  final _mentions = <String, String>{}; // username -> user id
  List<ChatMessage> _messages = const [];
  List<CircleMember> _members = const [];
  bool _loading = true;
  bool _sending = false;
  String? _typingUser;
  Timer? _typingClear;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<RealtimeEvent>? _events;

  CircleApi get _api => ref.read(circleApiProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _events = ref.read(realtimeProvider).events.listen(_onEvent);
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    _typingClear?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.messages(widget.circleId),
        _api.members(widget.circleId),
      ]);
      if (!mounted) return;
      setState(() {
        _messages = results[0] as List<ChatMessage>;
        _members = [
          for (final m in results[1] as List<CircleMember>)
            if (m.status == MemberStatus.active) m,
        ];
        _loading = false;
      });
      unawaited(_api.markRead(widget.circleId).catchError((Object _) {}));
    } on Object {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onEvent(RealtimeEvent e) {
    if (e.circleId != widget.circleId || !mounted) return;
    switch (e.type) {
      case 'message.created':
        final json = e.data['message'];
        if (json is! Map<String, dynamic>) return;
        final message = ChatMessage.fromJson(json);
        if (_messages.any((m) => m.id == message.id)) return;
        setState(() => _messages = [message, ..._messages]);
        unawaited(_api.markRead(widget.circleId).catchError((Object _) {}));
      case 'message.deleted':
        final id = e.data['message_id'];
        setState(
          () => _messages = [
            for (final m in _messages)
              if (m.id == id)
                ChatMessage(
                  id: m.id,
                  at: m.at,
                  sender: m.sender,
                  body: null,
                  deleted: true,
                  mentions: const [],
                )
              else
                m,
          ],
        );
      case 'typing':
        final user = _members
            .where((m) => m.person.userId == e.data['user_id'])
            .map((m) => m.person.handle)
            .firstOrNull;
        if (user == null) return;
        _typingClear?.cancel();
        setState(() => _typingUser = user);
        _typingClear = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _typingUser = null);
        });
      case 'circle.changed':
        unawaited(_load());
    }
  }

  /// The "@prefix" being typed at the end of the text, if any.
  String? get _mentionQuery {
    final match = RegExp(r'(?:^|\s)@([a-z0-9._]{0,30})$')
        .firstMatch(_input.text);
    return match?.group(1);
  }

  void _onChanged(String _) {
    setState(() {});
    final now = DateTime.now();
    if (now.difference(_lastTypingSent) > const Duration(seconds: 3)) {
      _lastTypingSent = now;
      ref.read(realtimeProvider).typing(widget.circleId);
    }
  }

  void _pickMention(CircleMember m) {
    final username = m.person.username;
    if (username == null) return;
    final text = _input.text;
    final at = text.lastIndexOf('@');
    final next = '${text.substring(0, at)}@$username ';
    _mentions[username] = m.person.userId;
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() {});
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final body = InputValidators.normalise(_input.text);
    if (body.isEmpty || _sending) return;
    final error = InputValidators.chatMessage()(body);
    if (error != null) {
      showNcToast(context, l10n.messageNotAllowed, kind: NcToastKind.error);
      return;
    }
    final mentionIds = [
      for (final e in _mentions.entries)
        if (body.contains('@${e.key}')) e.value,
    ];
    setState(() => _sending = true);
    ChatMessage? sent;
    final ok = await runSocial(context, () async {
      sent = await _api.send(widget.circleId, body, mentionIds);
    });
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) {
        _input.clear();
        _mentions.clear();
        if (sent != null && !_messages.any((m) => m.id == sent!.id)) {
          _messages = [sent!, ..._messages];
        }
      }
    });
  }

  Future<void> _delete(ChatMessage m) async {
    final l10n = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.deleteMessageTitle),
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
    await runSocial(context, () => _api.deleteMessage(widget.circleId, m.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final me = ref.watch(meProvider).value?.userId ?? '';
    final detail = ref.watch(circleDetailProvider(widget.circleId)).value;
    final query = _mentionQuery;
    final suggestions = query == null
        ? const <CircleMember>[]
        : [
            for (final m in _members)
              if (m.person.userId != me &&
                  (m.person.username ?? '').startsWith(query))
                m,
          ];
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detail?.name ?? l10n.circleChat),
            if (detail != null)
              Text(
                _typingUser == null
                    ? l10n.membersCount(detail.memberCount)
                    : l10n.isTyping(_typingUser!),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                  ? Center(child: Text(l10n.noMessagesYet))
                  : ListView.builder(
                      reverse: true,
                      padding: EdgeInsets.all(nc.screenPadding),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        final mine = m.sender.userId == me;
                        return _Bubble(
                          message: m,
                          mine: mine,
                          me: me,
                          onLongPress:
                              !m.deleted && (mine || (detail?.isAdmin ?? false))
                              ? () => _delete(m)
                              : null,
                        );
                      },
                    ),
            ),
            if (suggestions.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: Material(
                  elevation: 2,
                  color: nc.surface,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final m in suggestions)
                        ListTile(
                          dense: true,
                          leading: PersonAvatar(person: m.person, size: 32),
                          title: Text(m.person.handle),
                          onTap: () => _pickMention(m),
                        ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                nc.screenPadding,
                NcSpace.inputGap,
                nc.screenPadding,
                nc.screenPadding,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: NcTextField(
                      controller: _input,
                      hint: l10n.typeHere,
                      // Empty is fine here (Send ignores it); the rules apply
                      // to anything typed.
                      validator: (v) => v.trim().isEmpty
                          ? null
                          : InputValidators.chatMessage()(v),
                      maxLength: 2000,
                      maxLines: 4,
                      minLines: 1,
                      onChanged: _onChanged,
                    ),
                  ),
                  IconButton.filled(
                    tooltip: l10n.send,
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const new({
    required this.message,
    required this.mine,
    required this.me,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool mine;
  final String me;
  final VoidCallback? onLongPress;

  /// Plain text with "@name" tokens highlighted (no links, no markup).
  List<TextSpan> _spans(String body, TextStyle base, TextStyle mention) {
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in RegExp('@[a-z0-9._]{3,30}').allMatches(body)) {
      if (m.start > last) {
        spans.add(TextSpan(text: body.substring(last, m.start), style: base));
      }
      spans.add(TextSpan(text: m.group(0), style: mention));
      last = m.end;
    }
    if (last < body.length) {
      spans.add(TextSpan(text: body.substring(last), style: base));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final text = Theme.of(context).textTheme;
    final base = text.bodyMedium!.copyWith(
      color: mine ? Colors.white : nc.textPrimary,
    );
    final mention = base.copyWith(fontWeight: FontWeight.w700);
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(message.at.toLocal()));
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.75,
          ),
          margin: const EdgeInsets.symmetric(vertical: NcSpace.xs),
          padding: const EdgeInsets.all(NcSpace.buttonGap),
          decoration: BoxDecoration(
            color: mine ? nc.primary : nc.inputFill,
            borderRadius: BorderRadius.circular(NcRadius.l),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Text(
                  message.sender.handle,
                  style: text.labelSmall?.copyWith(color: nc.primary),
                ),
              if (message.deleted || message.body == null)
                Text(
                  l10n.messageDeleted,
                  style: base.copyWith(fontStyle: FontStyle.italic),
                )
              else
                Text.rich(
                  TextSpan(children: _spans(message.body!, base, mention)),
                ),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  time,
                  style: text.labelSmall?.copyWith(
                    color: mine ? Colors.white70 : nc.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
