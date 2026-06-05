enum ChatComposerPanel { stickers, voice, file, tools }

class ChatComposerPanelPatch {
  const ChatComposerPanelPatch({
    required this.openPanel,
    required this.shouldLoadStickers,
  });

  final ChatComposerPanel? openPanel;
  final bool shouldLoadStickers;
}

class ChatComposerInputHeightPatch {
  const ChatComposerInputHeightPatch({required this.inputHeight});

  final double inputHeight;
}

ChatComposerPanelPatch chatComposerPanelToggled({
  required ChatComposerPanel? currentPanel,
  required ChatComposerPanel panel,
}) {
  final opening = currentPanel != panel;
  return ChatComposerPanelPatch(
    openPanel: opening ? panel : null,
    shouldLoadStickers: opening && panel == ChatComposerPanel.stickers,
  );
}

ChatComposerPanelPatch? chatComposerPanelClosed({
  required ChatComposerPanel? currentPanel,
}) {
  if (currentPanel == null) return null;
  return const ChatComposerPanelPatch(
    openPanel: null,
    shouldLoadStickers: false,
  );
}

ChatComposerPanelPatch chatComposerPanelResetForRoomChange() {
  return const ChatComposerPanelPatch(
    openPanel: null,
    shouldLoadStickers: false,
  );
}

ChatComposerInputHeightPatch? chatComposerInputHeightMeasured({
  required double currentHeight,
  required double measuredHeight,
  double threshold = 0.5,
}) {
  if ((currentHeight - measuredHeight).abs() < threshold) return null;
  return ChatComposerInputHeightPatch(inputHeight: measuredHeight);
}
