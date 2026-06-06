import 'dart:async';

import '../live/live_stream_client.dart';
import '../protocol/api_client.dart';

class RealtimeEvent {
  const RealtimeEvent({required this.type, required this.data});

  final String type;
  final Map<String, dynamic> data;
}

abstract class RealtimeService {
  void Function()? onReconnect;

  Stream<RealtimeEvent> get events;

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
    _client.onReconnect = () => onReconnect?.call();
    _sourceSubscription = _client.events.listen((event) {
      if (_events.isClosed) return;
      _events.add(RealtimeEvent(type: event.type, data: event.data));
    });
  }

  final LiveStreamClient _client;
  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();
  late final StreamSubscription<LiveEvent> _sourceSubscription;

  @override
  void Function()? onReconnect;

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  @override
  Future<void> start() => _client.start();

  @override
  Future<void> stop() => _client.stop();

  @override
  void dispose() {
    unawaited(_sourceSubscription.cancel());
    _client.dispose();
    _events.close();
  }
}
