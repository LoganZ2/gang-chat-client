import 'package:shared_preferences/shared_preferences.dart';

import '../app/close_behavior.dart';

class LocalCloseBehaviorStore extends CloseBehaviorStore {
  const LocalCloseBehaviorStore();

  static const _closeBehaviorKey = 'gang.closeBehavior';

  @override
  Future<CloseBehavior> read() async {
    final prefs = await SharedPreferences.getInstance();
    return closeBehaviorFromStorageValue(prefs.getString(_closeBehaviorKey));
  }

  @override
  Future<void> write(CloseBehavior behavior) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_closeBehaviorKey, behavior.storageValue);
  }
}
