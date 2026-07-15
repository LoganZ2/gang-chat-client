import 'dart:convert';

import 'package:client/src/app/managed_user_audio_settings.dart';
import 'package:client/src/protocol/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'managed audio store reads and writes the target cloud settings',
    () async {
      final requests = <http.Request>[];
      final api = GangApiClient(
        baseUrl: 'http://example.test/api/v1',
        accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
        httpClient: MockClient((request) async {
          requests.add(request);
          final settings = request.method == 'PATCH'
              ? jsonDecode(request.body) as Map<String, Object?>
              : <String, Object?>{
                  'default_audio_input_volume': 25,
                  'default_audio_output_volume': 75,
                  'live_mic_input_volume': 60,
                  'live_voice_output_volume': 70,
                  'live_screen_share_output_volume': 80,
                  'live_music_output_volume': 90,
                };
          return http.Response(jsonEncode({'audio_settings': settings}), 200);
        }),
      );
      final store = ManagedUserAudioSettingsStore(
        api: api,
        userId: 'target_user',
      );

      final stored = await store.read();
      await store.writeInputVolume(0.42);

      expect(stored.inputVolume, 0.25);
      expect(stored.outputVolume, 0.75);
      expect(requests.map((request) => request.url.path), [
        '/api/v1/users/target_user/audio-settings',
        '/api/v1/users/target_user/audio-settings',
      ]);
      expect(jsonDecode(requests.last.body), {
        'default_audio_input_volume': 42,
        'default_audio_output_volume': 75,
        'live_mic_input_volume': 60,
        'live_voice_output_volume': 70,
        'live_screen_share_output_volume': 80,
        'live_music_output_volume': 90,
      });
      api.close();
    },
  );
}
