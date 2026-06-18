import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/ui/ui.dart';

void main() {
  test('avatarFallbackColor maps known keys and falls back to blue', () {
    expect(avatarFallbackColor('blue-3'), const Color(0xFF526C9F));
    expect(normalizeAvatarPresetKey('room-1'), 'blue-3');
    expect(avatarFallbackColor('room-1'), const Color(0xFF526C9F));
    expect(avatarFallbackColor('graphite-2'), const Color(0xFF5B5D63));
    expect(avatarFallbackColor('missing'), const Color(0xFF526C9F));
  });
}
