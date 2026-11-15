import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:naraacare/core/network/pinning.dart';
import 'package:naraacare/features/care_circle/data/circle_data.dart';

/// A server event (doc 04 section 2.9): message.created, message.deleted,
/// typing, circle.changed, notification. Unknown types are dropped.
class RealtimeEvent {
  const new({required this.type, required this.circleId, required this.data});

  final String type;
  final String? circleId;
  final Map<String, dynamic> data;
}

/// The circle WebSocket, kept open while a Care Circle screen listens.
///
/// * A single-use ticket from POST /realtime/ticket opens it, so the access
///   token never appears in a URL.
/// * The upgrade runs over an HttpClient so the server certificate is
///   checked against CERT_PINS before any frame is exchanged (same rule as
///   the REST client); `ws://` is allowed in dev only (AppConfig enforces).
/// * Pings every 30 s; on loss it reconnects with backoff (1 s .. 30 s).
/// * Incoming frames are parsed as JSON objects; message text is shown with
///   Text widgets only (no markup rendering).
class RealtimeClient {
  new({
    required this.api,
    required this.wsUrl,
    required this.pins,
    HttpClient Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final CircleApi api;
  final Uri wsUrl;
  final List<String> pins;
  final HttpClient Function() _httpClientFactory;

  static const _ping = Duration(seconds: 30);
  static const _maxBackoff = Duration(seconds: 30);

  final _events = StreamController<RealtimeEvent>.broadcast();
  WebSocket? _socket;
  Timer? _pingTimer;
  Timer? _retryTimer;
  int _attempt = 0;
  bool _closed = false;

  Stream<RealtimeEvent> get events => _events.stream;

  void start() => unawaited(_connect());

  Future<void> _connect() async {
    if (_closed) return;
    try {
      final ticket = await api.realtimeTicket();
      final socket = await _open(
        wsUrl.replace(queryParameters: {'ticket': ticket}),
      );
      if (_closed) {
        await socket.close();
        return;
      }
      _attempt = 0;
      _socket = socket;
      _pingTimer = Timer.periodic(
        _ping,
        (_) => socket.add(jsonEncode({'type': 'ping'})),
      );
      socket.listen(
        _onFrame,
        onDone: _scheduleRetry,
        onError: (Object _) => _scheduleRetry(),
        cancelOnError: true,
      );
    } on Object {
      _scheduleRetry();
    }
  }

  Future<WebSocket> _open(Uri uri) async {
    final secure = uri.scheme == 'wss';
    final client = _httpClientFactory()
      ..badCertificateCallback = (cert, host, port) => false;
    final httpUri = uri.replace(scheme: secure ? 'https' : 'http');
    final request = await client.openUrl('GET', httpUri);
    final key = base64.encode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    request.headers
      ..set(HttpHeaders.connectionHeader, 'Upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-WebSocket-Version', '13')
      ..set('Sec-WebSocket-Key', key);
    final response = await request.close();
    if (secure && !CertificatePinning.isPinned(response.certificate, pins)) {
      client.close(force: true);
      throw const HandshakeException('certificate not pinned');
    }
    if (response.statusCode != HttpStatus.switchingProtocols) {
      client.close(force: true);
      throw WebSocketException('handshake refused: ${response.statusCode}');
    }
    final socket = await response.detachSocket();
    return WebSocket.fromUpgradedSocket(socket, serverSide: false);
  }

  void _onFrame(Object? frame) {
    if (frame is! String || frame.length > 64 * 1024) return;
    final Object? json;
    try {
      json = jsonDecode(frame);
    } on FormatException {
      return;
    }
    if (json is! Map<String, dynamic>) return;
    final type = json['type'];
    if (type is! String || type == 'pong') return;
    _events.add(
      RealtimeEvent(
        type: type,
        circleId: json['circle_id'] as String?,
        data: json,
      ),
    );
  }

  /// Tell the circle's other members that this user is typing.
  void typing(String circleId) =>
      _socket?.add(jsonEncode({'type': 'typing', 'circle_id': circleId}));

  void _scheduleRetry() {
    _pingTimer?.cancel();
    _socket = null;
    if (_closed) return;
    final seconds = min(_maxBackoff.inSeconds, 1 << min(_attempt, 5));
    _attempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(
      Duration(seconds: seconds),
      () => unawaited(_connect()),
    );
  }

  Future<void> close() async {
    _closed = true;
    _pingTimer?.cancel();
    _retryTimer?.cancel();
    await _socket?.close();
    await _events.close();
  }
}
