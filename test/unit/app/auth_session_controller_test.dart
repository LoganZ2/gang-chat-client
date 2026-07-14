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

  test('transient access refresh failure keeps the active session', () async {
    final store = _FakeTokenStore();
    final client = _FakeAuthClient(
      onRefresh: (_) async => throw StateError('offline'),
    );
    final controller = AuthSessionController(
      tokenStore: store,
      apiBaseUrl: 'https://api.example.test',
      authClientFactory: (_) => client,
    );

    await controller.acceptSession(_session);

    await expectLater(
      controller.accessToken(forceRefresh: true),
      throwsA(isA<StateError>()),
    );
    expect(controller.session, _session);
    expect(store.refreshToken, 'refresh_1');
    expect(store.clearCount, 0);

    controller.dispose();
  });

  test('unauthorized access refresh clears the active session', () async {
    final store = _FakeTokenStore();
    final client = _FakeAuthClient(
      onRefresh: (_) async => throw AuthException(
        'session expired',
        statusCode: 401,
        code: 'unauthorized',
      ),
    );
    final controller = AuthSessionController(
      tokenStore: store,
      apiBaseUrl: 'https://api.example.test',
      authClientFactory: (_) => client,
    );

    await controller.acceptSession(_session);

    await expectLater(
      controller.accessToken(forceRefresh: true),
      throwsA(isA<AuthException>()),
    );
    expect(controller.session, isNull);
    expect(store.refreshToken, isNull);
    expect(store.clearCount, 1);

    controller.dispose();
  });

  test(
    'rotated refresh token write failure keeps the in-memory session',
    () async {
      final store = _FakeTokenStore();
      final client = _FakeAuthClient(onRefresh: (_) async => _rotatedSession);
      final controller = AuthSessionController(
        tokenStore: store,
        apiBaseUrl: 'https://api.example.test',
        authClientFactory: (_) => client,
      );

      await controller.acceptSession(_session);
      store.failWrites = true;

      final accessToken = await controller.accessToken(forceRefresh: true);

      expect(accessToken, 'access_2');
      expect(controller.session, _rotatedSession);
      expect(store.refreshToken, 'refresh_1');
      expect(store.clearCount, 0);

      controller.dispose();
    },
  );

  test('transient restore failure keeps the stored refresh token', () async {
    final store = _FakeTokenStore(refreshToken: 'stored_refresh');
    final client = _FakeAuthClient(
      onRefresh: (_) async => throw StateError('offline'),
    );
    final controller = AuthSessionController(
      tokenStore: store,
      apiBaseUrl: 'https://api.example.test',
      authClientFactory: (_) => client,
    );

    final result = await controller.restoreSession();

    expect(result.status, AuthRestoreStatus.refreshFailed);
    expect(controller.session, isNull);
    expect(store.refreshToken, 'stored_refresh');
    expect(store.clearCount, 0);

    controller.dispose();
  });

  test(
    'unauthorized restore failure clears the stored refresh token',
    () async {
      final store = _FakeTokenStore(refreshToken: 'stored_refresh');
      final client = _FakeAuthClient(
        onRefresh: (_) async => throw AuthException(
          'session expired',
          statusCode: 401,
          code: 'unauthorized',
        ),
      );
      final controller = AuthSessionController(
        tokenStore: store,
        apiBaseUrl: 'https://api.example.test',
        authClientFactory: (_) => client,
      );

      final result = await controller.restoreSession();

      expect(result.status, AuthRestoreStatus.refreshFailed);
      expect(controller.session, isNull);
      expect(store.refreshToken, isNull);
      expect(store.clearCount, 1);

      controller.dispose();
    },
  );
}

class _FakeTokenStore extends TokenStore {
  _FakeTokenStore({this.refreshToken});

  String? refreshToken;
  String? apiBaseUrl;
  int clearCount = 0;
  bool failWrites = false;

  @override
  Future<String?> readRefreshToken() async {
    return refreshToken;
  }

  @override
  Future<void> writeRefreshToken(String refreshToken) async {
    if (failWrites) throw StateError('keychain unavailable');
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> writeApiBaseUrl(String baseUrl) async {
    apiBaseUrl = baseUrl;
  }

  @override
  Future<void> clearRefreshToken() async {
    clearCount += 1;
    refreshToken = null;
  }
}

class _FakeAuthClient extends AuthClient {
  _FakeAuthClient({this.onRefresh}) : super(baseUrl: 'https://unused.test');

  final Future<AuthSession> Function(String refreshToken)? onRefresh;

  @override
  Future<AuthSession> refresh(String refreshToken) {
    final refresh = onRefresh;
    if (refresh == null) return super.refresh(refreshToken);
    return refresh(refreshToken);
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

final _rotatedSession = AuthSession(
  accessToken: 'access_2',
  refreshToken: 'refresh_2',
  accessTokenExpiresAt: DateTime.now().add(const Duration(days: 1)),
  user: _session.user,
);
