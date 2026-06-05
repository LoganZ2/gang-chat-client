import 'dart:async';

import '../live/live_stream_client.dart';
import '../protocol/api_client.dart';

class RealtimeEvent {
  const RealtimeEvent({required this.type, required this.data});

  final String type;
  final Map<String, dynamic> data;
}

class RealtimeController {
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

  void Function()? onReconnect;

  Stream<RealtimeEvent> get events => _events.stream;

  Future<void> start() => _client.start();

  Future<void> stop() => _client.stop();

  void dispose() {
    unawaited(_sourceSubscription.cancel());
    _client.dispose();
    _events.close();
  }
}
