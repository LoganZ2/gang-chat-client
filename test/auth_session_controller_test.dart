import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/auth_session_controller.dart';
import 'package:client/src/auth/auth_client.dart';
import 'package:client/src/auth/token_store.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test(
    'AuthSessionController notifies listeners without Flutter notifier',
    () async {
      final store = _FakeTokenStore();
      final controller = AuthSessionController(
        tokenStore: store,
        apiBaseUrl: 'https://api.example.test',
      );
      var notifications = 0;
      void listener() => notifications += 1;

      controller.addListener(listener);

      await controller.acceptSession(_session);
      expect(notifications, 1);
      expect(controller.session, _session);
      expect(store.refreshToken, 'refresh_1');
      expect(store.apiBaseUrl, 'https://api.example.test');

      final loggedOut = controller.beginLogout();
      expect(loggedOut, _session);
      expect(notifications, 2);
      expect(controller.session, isNull);

      controller.removeListener(listener);
      await controller.acceptSession(_session);
      expect(notifications, 2);
      controller.dispose();
    },
  );
}

class _FakeTokenStore extends TokenStore {
  String? refreshToken;
  String? apiBaseUrl;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> writeApiBaseUrl(String baseUrl) async {
    apiBaseUrl = baseUrl;
  }

  @override
  Future<void> clearRefreshToken() async {
    refreshToken = null;
  }
}

final _session = AuthSession(
  accessToken: 'access_1',
  refreshToken: 'refresh_1',
  accessTokenExpiresAt: DateTime.now().add(const Duration(days: 1)),
  user: CurrentUser(
    id: 'user_1',
    uid: '1001',
    username: 'alice',
    displayName: 'Alice',
    bio: '',
    gender: 'secret',
    email: 'alice@example.test',
    emailPublic: false,
    phoneNumber: null,
    phoneNumberPublic: false,
    avatarUrl: null,
    defaultAvatarKey: 'blue-3',
    isSuperuser: false,
    createdAt: DateTime.utc(2026, 6, 1),
  ),
);
