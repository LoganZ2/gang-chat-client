import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/account_state.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('accountLoadStarted preserves user and clears error', () {
    final user = _user(id: 'user_1');
    final patch = accountLoadStarted(user: user);

    expect(patch.user, user);
    expect(patch.loading, isTrue);
    expect(patch.accountError, isNull);
  });

  test('accountLoadSucceeded stores user and clears busy state', () {
    final user = _user(id: 'user_2');
    final patch = accountLoadSucceeded(user: user);

    expect(patch.user, user);
    expect(patch.loading, isFalse);
    expect(patch.accountError, isNull);
  });

  test('accountLoadCancelled preserves existing feedback', () {
    final user = _user(id: 'user_1');
    final patch = accountLoadCancelled(
      user: user,
      accountError: 'previous error',
    );

    expect(patch.user, user);
    expect(patch.loading, isFalse);
    expect(patch.accountError, 'previous error');
  });

  test('accountLoadFailed preserves user and reports error', () {
    final user = _user(id: 'user_1');
    final patch = accountLoadFailed(user: user, failure: 'load failed');

    expect(patch.user, user);
    expect(patch.loading, isFalse);
    expect(patch.accountError, 'load failed');
  });
}

CurrentUser _user({required String id}) {
  return CurrentUser(
    id: id,
    uid: '1001',
    username: 'logan',
    displayName: 'Logan',
    bio: '',
    gender: 'secret',
    email: 'logan@example.test',
    emailPublic: false,
    phoneNumber: null,
    phoneNumberPublic: false,
    avatarUrl: null,
    defaultAvatarKey: 'blue-3',
    isSuperuser: false,
    createdAt: DateTime(2026, 6, 4),
  );
}
