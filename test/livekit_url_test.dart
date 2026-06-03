import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/live/livekit_url.dart';

void main() {
  test('rewrites loopback LiveKit host when API host is remote', () {
    expect(
      resolveLiveKitServerUrl(
        serverUrl: 'http://127.0.0.1:7880',
        apiBaseUrl: 'http://64.90.4.129:21116/api/v1',
      ),
      'ws://64.90.4.129:7880',
    );
  });

  test('keeps loopback LiveKit host for a local API', () {
    expect(
      resolveLiveKitServerUrl(
        serverUrl: 'http://127.0.0.1:7880',
        apiBaseUrl: 'http://localhost:21116/api/v1',
      ),
      'ws://127.0.0.1:7880',
    );
  });

  test('keeps already-public LiveKit host', () {
    expect(
      resolveLiveKitServerUrl(
        serverUrl: 'wss://voice.example.com',
        apiBaseUrl: 'http://64.90.4.129:21116/api/v1',
      ),
      'wss://voice.example.com',
    );
  });

  test('normalizes public HTTP LiveKit URL to WebSocket scheme', () {
    expect(
      resolveLiveKitServerUrl(
        serverUrl: 'http://64.90.4.129:7880',
        apiBaseUrl: 'http://64.90.4.129:21116/api/v1',
      ),
      'ws://64.90.4.129:7880',
    );
  });

  test('normalizes HTTPS LiveKit URL to secure WebSocket scheme', () {
    expect(
      resolveLiveKitServerUrl(
        serverUrl: 'https://voice.example.com',
        apiBaseUrl: 'https://api.example.com/api/v1',
      ),
      'wss://voice.example.com',
    );
  });
}
