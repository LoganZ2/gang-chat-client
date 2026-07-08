export '../protocol/server_time_header.dart' show gangServerTimeHeader;

typedef ServerClockListener = void Function();

class ServerClock {
  ServerClock({
    DateTime Function()? localNow,
    Duration Function()? monotonicNow,
  }) : _localNow = localNow ?? DateTime.now,
       _monotonicNow = monotonicNow;

  final DateTime Function() _localNow;
  final Duration Function()? _monotonicNow;
  final Stopwatch _stopwatch = Stopwatch()..start();
  final Set<ServerClockListener> _listeners = <ServerClockListener>{};
  DateTime? _serverBaseTime;
  Duration? _monotonicBaseTime;
  Duration? _requestRoundTrip;

  DateTime now() {
    final serverBaseTime = _serverBaseTime;
    final monotonicBaseTime = _monotonicBaseTime;
    if (serverBaseTime == null || monotonicBaseTime == null) {
      return _localNow();
    }
    return serverBaseTime.add(_elapsed() - monotonicBaseTime);
  }

  Duration? get requestRoundTrip => _requestRoundTrip;

  bool updateFromHeader(String? value) {
    final serverTime = parseServerTimeHeader(value);
    if (serverTime == null) return false;
    _serverBaseTime = serverTime;
    _monotonicBaseTime = _elapsed();
    _notifyListeners();
    return true;
  }

  bool updateRequestRoundTrip(Duration value) {
    if (value < Duration.zero) return false;
    _requestRoundTrip = value;
    _notifyListeners();
    return true;
  }

  void _notifyListeners() {
    for (final listener in List<ServerClockListener>.of(_listeners)) {
      listener();
    }
  }

  void addListener(ServerClockListener listener) {
    _listeners.add(listener);
  }

  void removeListener(ServerClockListener listener) {
    _listeners.remove(listener);
  }

  void dispose() {
    _listeners.clear();
    _stopwatch.stop();
  }

  Duration _elapsed() => _monotonicNow?.call() ?? _stopwatch.elapsed;
}

DateTime? parseServerTimeHeader(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  return DateTime.tryParse(normalized)?.toUtc();
}
