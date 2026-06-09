import 'package:client/src/app/voice_message_display.dart' as voice_display;
import 'package:client/src/ui/ui.dart';
import 'package:client/src/home/chat_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 360, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('idle voice panel shows a plain mic trigger, no raised surface', (
    tester,
  ) async {
    var started = 0;
    await tester.pumpWidget(
      _host(
        VoicePanelForTest(
          state: const voice_display.VoiceRecorderState(),
          onStart: () => started++,
          onSend: () {},
          onCancel: () {},
        ),
      ),
    );

    expect(find.text('点击录音'), findsOneWidget);
    // Plain IconButton, not a PressableSurface circle.
    expect(find.byType(IconButton), findsOneWidget);
    expect(find.byType(PressableSurface), findsNothing);

    await tester.tap(find.byIcon(Icons.mic_none));
    expect(started, 1);
  });

  testWidgets('recording panel shows a live timer and send/cancel', (
    tester,
  ) async {
    var sent = 0;
    var cancelled = 0;
    await tester.pumpWidget(
      _host(
        VoicePanelForTest(
          state: voice_display.voiceRecordingTicked(
            voice_display.voiceRecordingStarted(),
            const Duration(seconds: 7),
          ),
          onStart: () {},
          onSend: () => sent++,
          onCancel: () => cancelled++,
        ),
      ),
    );

    expect(find.text('0:07'), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.tap(find.byIcon(Icons.delete_outline));
    expect(sent, 1);
    expect(cancelled, 1);
  });

  testWidgets('review panel keeps the clip duration and a send action', (
    tester,
  ) async {
    final review = voice_display.voiceRecordingStopped(
      state: voice_display.voiceRecordingStarted(),
      path: '/tmp/voice.m4a',
      elapsed: const Duration(seconds: 12),
    );
    await tester.pumpWidget(
      _host(
        VoicePanelForTest(
          state: review,
          onStart: () {},
          onSend: () {},
          onCancel: () {},
        ),
      ),
    );

    expect(find.text('0:12'), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.text('点击发送或取消'), findsOneWidget);
  });
}
