import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/ui/ui.dart' as ui;

void main() {
  testWidgets(
    'segmented control badge follows content instead of segment edge',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(640, 120);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: ui.uiTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                child: ui.SegmentedControl<int>(
                  expanded: true,
                  value: 1,
                  onChanged: (_) {},
                  segments: const [
                    ui.Segment(value: 0, label: 'Members'),
                    ui.Segment(
                      value: 1,
                      label: 'New Members',
                      icon: Icons.person_add_alt_1,
                      showBadge: true,
                      badgeKey: ValueKey('new-members-tab-badge'),
                    ),
                    ui.Segment(value: 2, label: 'Blacklist'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final badgeRect = tester.getRect(
        find.byKey(const ValueKey('new-members-tab-badge')),
      );
      final labelRect = tester.getRect(find.text('New Members'));
      final segmentRect = tester.getRect(
        find.ancestor(
          of: find.text('New Members'),
          matching: find.byType(ui.PressableSurface),
        ),
      );

      expect(badgeRect.center.dx, greaterThan(labelRect.right - 2));
      expect(badgeRect.center.dx, lessThan(labelRect.right + 12));
      expect(badgeRect.center.dy, lessThan(labelRect.center.dy));
      expect(segmentRect.right - badgeRect.right, greaterThan(16));
    },
  );
}
