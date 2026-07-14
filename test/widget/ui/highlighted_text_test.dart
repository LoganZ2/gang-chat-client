import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/ui/highlighted_text.dart';
import 'package:client/src/ui/tokens.dart';

void main() {
  testWidgets('highlights all case-insensitive query matches', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: HighlightedText(
          text: 'Alpha beta alpha',
          query: 'ALPHA',
          style: UiTypography.body,
        ),
      ),
    );

    expect(find.text('Alpha beta alpha'), findsOneWidget);

    final text = tester.widget<Text>(find.text('Alpha beta alpha'));
    final span = text.textSpan! as TextSpan;
    final highlighted = span.children!
        .where((child) => (child as TextSpan).style?.color == UiColors.accent)
        .toList();

    expect(highlighted, hasLength(2));
  });

  testWidgets('uses plain text when query does not match', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: HighlightedText(
          text: 'Alpha beta',
          query: 'gamma',
          style: UiTypography.body,
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('Alpha beta'));
    expect(text.data, 'Alpha beta');
    expect(text.textSpan, isNull);
  });
}
