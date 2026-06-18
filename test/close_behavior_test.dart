import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/src/app/close_behavior.dart';
import 'package:client/src/shell/local_close_behavior_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('close behavior defaults to asking every time', () async {
    const store = LocalCloseBehaviorStore();

    expect(await store.read(), CloseBehavior.askEveryTime);
  });

  test('close behavior persists as a local app-wide preference', () async {
    const store = LocalCloseBehaviorStore();

    await store.write(CloseBehavior.minimizeToTray);
    expect(await store.read(), CloseBehavior.minimizeToTray);

    await store.write(CloseBehavior.exitProgram);
    expect(await store.read(), CloseBehavior.exitProgram);
  });

  test('unknown stored close behavior falls back to asking every time', () {
    expect(
      closeBehaviorFromStorageValue('older-client-value'),
      defaultCloseBehavior,
    );
  });
}
