import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/chat_composer_state.dart';

void main() {
  test('chat composer panel toggle opens and closes the same panel', () {
    final opened = chatComposerPanelToggled(
      currentPanel: null,
      panel: ChatComposerPanel.tools,
    );

    expect(opened.openPanel, ChatComposerPanel.tools);
    expect(opened.shouldLoadStickers, isFalse);

    final closed = chatComposerPanelToggled(
      currentPanel: ChatComposerPanel.tools,
      panel: ChatComposerPanel.tools,
    );

    expect(closed.openPanel, isNull);
    expect(closed.shouldLoadStickers, isFalse);
  });

  test('chat composer sticker panel open requests sticker loading', () {
    final opened = chatComposerPanelToggled(
      currentPanel: null,
      panel: ChatComposerPanel.stickers,
    );

    expect(opened.openPanel, ChatComposerPanel.stickers);
    expect(opened.shouldLoadStickers, isTrue);

    final switched = chatComposerPanelToggled(
      currentPanel: ChatComposerPanel.tools,
      panel: ChatComposerPanel.stickers,
    );

    expect(switched.openPanel, ChatComposerPanel.stickers);
    expect(switched.shouldLoadStickers, isTrue);
  });

  test('chat composer close and room reset clear open panel', () {
    expect(chatComposerPanelClosed(currentPanel: null), isNull);

    final closed = chatComposerPanelClosed(
      currentPanel: ChatComposerPanel.stickers,
    );

    expect(closed?.openPanel, isNull);
    expect(closed?.shouldLoadStickers, isFalse);

    final reset = chatComposerPanelResetForRoomChange();

    expect(reset.openPanel, isNull);
    expect(reset.shouldLoadStickers, isFalse);
  });

  test('chat composer input height patch ignores sub-threshold changes', () {
    expect(
      chatComposerInputHeightMeasured(currentHeight: 76, measuredHeight: 76.25),
      isNull,
    );

    final patch = chatComposerInputHeightMeasured(
      currentHeight: 76,
      measuredHeight: 84,
    );

    expect(patch?.inputHeight, 84);
  });
}
