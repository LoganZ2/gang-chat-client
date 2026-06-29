import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/src/shell/local_auto_update_prompt_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('auto update prompt defaults to enabled', () async {
    const store = LocalAutoUpdatePromptStore();

    expect(await store.read(), isTrue);
  });

  test('auto update prompt persists as a local app-wide preference', () async {
    const store = LocalAutoUpdatePromptStore();

    await store.write(true);
    expect(await store.read(), isTrue);

    await store.write(false);
    expect(await store.read(), isFalse);
  });
}
