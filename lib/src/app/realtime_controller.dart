import 'dart:async';

import '../live/live_stream_client.dart';
import '../protocol/api_client.dart';

class RealtimeEvent {
  const RealtimeEvent({required this.type, required this.data});

  final String type;
  final Map<String, dynamic> data;
}

enum RealtimeConnectionStatus { connecting, connected, reconnecting, offline }

abstract class RealtimeService {
  void Function()? onReconnect;

  Stream<RealtimeEvent> get events;

  RealtimeConnectionStatus get status;

  Stream<RealtimeConnectionStatus> get statusChanges;

  Future<void> start();

  Future<void> stop();

  void dispose();
}

class RealtimeController implements RealtimeService {
  RealtimeController({
    required String apiBaseUrl,
    required AccessTokenProvider accessTokenProvider,
  }) : _client = LiveStreamClient(
         apiBaseUrl: apiBaseUrl,
         accessTokenProvider: accessTokenProvider,
       ) {
    _status = _connectionStatusFromStreamStatus(_client.status);
    _client.addListener(_handleClientStatusChanged);
    _client.onReconnect = () => onReconnect?.call();
    _sourceSubscription = _client.events.listen((event) {
      if (_events.isClosed) return;
      _events.add(RealtimeEvent(type: event.type, data: event.data));
    });
  }

  final LiveStreamClient _client;
  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();
  final StreamController<RealtimeConnectionStatus> _statusChanges =
      StreamController<RealtimeConnectionStatus>.broadcast();
  late final StreamSubscription<LiveEvent> _sourceSubscription;
  late RealtimeConnectionStatus _status;

  @override
  void Function()? onReconnect;

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  @override
  RealtimeConnectionStatus get status => _status;

  @override
  Stream<RealtimeConnectionStatus> get statusChanges => _statusChanges.stream;

  @override
  Future<void> start() => _client.start();

  @override
  Future<void> stop() => _client.stop();

  void _handleClientStatusChanged() {
    final next = _connectionStatusFromStreamStatus(_client.status);
    if (_status == next) return;
    _status = next;
    if (!_statusChanges.isClosed) _statusChanges.add(next);
  }

  @override
  void dispose() {
    _client.removeListener(_handleClientStatusChanged);
    unawaited(_sourceSubscription.cancel());
    _client.dispose();
    _events.close();
    _statusChanges.close();
  }
}

RealtimeConnectionStatus _connectionStatusFromStreamStatus(
  StreamStatus status,
) {
  return switch (status) {
    StreamStatus.connecting => RealtimeConnectionStatus.connecting,
    StreamStatus.connected => RealtimeConnectionStatus.connected,
    StreamStatus.reconnecting => RealtimeConnectionStatus.reconnecting,
    StreamStatus.offline => RealtimeConnectionStatus.offline,
  };
}
