import 'dart:convert';

import 'package:client/src/app/settings_controller.dart';
import 'package:client/src/protocol/api_client.dart';
import 'package:client/src/protocol/sticker_pack_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'managed settings controller routes account operations to target APIs',
    () async {
      final requests = <http.Request>[];
      final target = <String, Object?>{
        'id': 'target_user',
        'uid': '1000042',
        'username': 'target',
        'display_name': 'Target',
        'bio': '',
        'gender': 'secret',
        'email': 'target@example.test',
        'email_verified': true,
        'email_public': false,
        'phone_number_public': false,
        'avatar_url': null,
        'default_avatar_key': 'blue-3',
        'is_superuser': false,
        'language': 'zh-Hans',
      };
      final api = GangApiClient(
        baseUrl: 'http://example.test/api/v1',
        accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/sessions')) {
            return http.Response(jsonEncode([]), 200);
          }
          if (request.url.path.endsWith('/password')) {
            return http.Response(jsonEncode({'ok': true}), 200);
          }
          return http.Response(jsonEncode({'user': target}), 200);
        }),
      );
      final controller = SettingsController(
        api: api,
        apiBaseUrl: 'http://example.test/api/v1',
        stickerPackStore: const StickerPackStore(),
        managedUserId: 'target_user',
      );

      await controller.loadAccount();
      await controller.loadSessions();
      await controller.updateAccount(
        email: 'changed-target@example.test',
        language: 'en',
        emailVerificationToken: 'verified-token',
      );
      await controller.changePassword(
        currentPassword: '',
        newPassword: 'new password',
      );
      await controller.setManagedAccountSuspended(true);
      await controller.setManagedAccountSuspended(false);
      await controller.deleteMyAccount();

      expect(requests.map((request) => request.url.path), [
        '/api/v1/users/target_user/settings',
        '/api/v1/users/target_user/sessions',
        '/api/v1/users/target_user/settings',
        '/api/v1/users/target_user/password',
        '/api/v1/users/target_user/settings',
        '/api/v1/users/target_user/settings',
        '/api/v1/users/target_user/account',
      ]);
      expect(jsonDecode(requests[2].body), {
        'email': 'changed-target@example.test',
        'email_verified': true,
        'language': 'en',
      });
      expect(jsonDecode(requests[3].body), {'new_password': 'new password'});
      expect(jsonDecode(requests[4].body), {'status': 'suspended'});
      expect(jsonDecode(requests[5].body), {'status': 'active'});
      expect(jsonDecode(requests[6].body), {'confirm': true});
      api.close();
    },
  );
}
