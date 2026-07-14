import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:client/src/ui/ui.dart' as ui;

void main() {
  test('uiTheme uses Microsoft YaHei for client text', () {
    final theme = ui.uiTheme();

    expect(theme.textTheme.bodyMedium?.fontFamily, ui.kClientFontFamily);
    expect(
      theme.textTheme.bodyMedium?.fontFamilyFallback,
      ui.kClientFontFamilyFallback,
    );
    expect(theme.primaryTextTheme.bodyMedium?.fontFamily, ui.kClientFontFamily);
    expect(ui.UiTypography.label.fontWeight, FontWeight.w500);
    expect(ui.UiTypography.title.fontWeight, FontWeight.w600);
  });
}
