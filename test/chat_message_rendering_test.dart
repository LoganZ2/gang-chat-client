import 'package:client/src/app/message_display.dart' as message_display;
import 'package:client/src/config/app_config.dart';
import 'package:client/src/home/chat_pane.dart';
import 'package:client/src/protocol/models.dart';
import 'package:client/src/ui/app_config_scope.dart';
import 'package:client/src/ui/ui.dart' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sticker bubble exposes the sticker name only as a tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        MessageBubbleForTest(
          message: _message(
            type: 'sticker',
            body: '[wave]',
            attachments: const [
              MessageAttachment(
                type: 'sticker',
                name: 'wave',
                asset: UploadedAsset(
                  id: 'asset_sticker',
                  url: '/stickers/wave.webp',
                  thumbnailUrl: '/stickers/wave-thumb.webp',
                  mimeType: 'image/webp',
                ),
              ),
            ],
          ),
          downloadActions: _downloadActions(),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('wave'), findsNothing);
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'wave');
  });

  testWidgets('image file attachment renders a resolved preview image', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        MessageBubbleForTest(
          message: _message(
            type: 'file',
            body: 'photo.png',
            attachments: const [
              MessageAttachment(
                type: 'file',
                name: 'photo.png',
                asset: UploadedAsset(
                  id: 'asset_photo',
                  url: '/uploads/photo.png',
                  thumbnailUrl: '/uploads/photo-thumb.png',
                  mimeType: 'image/png',
                  filename: 'photo.png',
                  sizeBytes: 2048,
                  width: 1600,
                  height: 900,
                ),
              ),
            ],
          ),
          downloadActions: _downloadActions(),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
    expect(image.image, isA<NetworkImage>());
    expect(
      (image.image as NetworkImage).url,
      'https://assets.test/uploads/photo-thumb.png',
    );
    expect(tester.getSize(find.byType(Image)), const Size(320, 180));
  });

  testWidgets('non-image file attachment keeps the file tile without preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        MessageBubbleForTest(
          message: _message(
            type: 'file',
            body: 'report.pdf',
            attachments: const [
              MessageAttachment(
                type: 'file',
                name: 'report.pdf',
                asset: UploadedAsset(
                  id: 'asset_report',
                  url: '/uploads/report.pdf',
                  thumbnailUrl: null,
                  mimeType: 'application/pdf',
                  filename: 'report.pdf',
                  sizeBytes: 2048,
                ),
              ),
            ],
          ),
          downloadActions: _downloadActions(),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(find.byTooltip('report.pdf'), findsOneWidget);
  });

  testWidgets('voice attachment renders a playable waveform bubble', (
    tester,
  ) async {
    final toggles = <String>[];
    final message = _message(
      type: 'audio',
      body: 'voice_1.m4a',
      attachments: const [
        MessageAttachment(
          type: 'audio',
          name: 'voice_1.m4a',
          durationMs: 15000,
          asset: UploadedAsset(
            id: 'asset_voice',
            url: '/uploads/voice_1.m4a',
            thumbnailUrl: null,
            mimeType: 'audio/mp4',
            filename: 'voice_1.m4a',
            sizeBytes: 4096,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      _host(
        MessageBubbleForTest(
          message: message,
          downloadActions: _downloadActions(),
          voicePlaybackActions: ChatVoicePlaybackActions(
            activeMessageId: null,
            onToggle: (messageId, resolvedUrl) {
              toggles.add('$messageId|$resolvedUrl');
            },
          ),
        ),
      ),
    );

    expect(find.text('15s'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.audio_file_outlined), findsNothing);
    expect(find.byTooltip('voice_1.m4a'), findsNothing);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    expect(toggles, ['client_1|https://assets.test/uploads/voice_1.m4a']);

    await tester.pumpWidget(
      _host(
        MessageBubbleForTest(
          message: message,
          downloadActions: _downloadActions(),
          voicePlaybackActions: ChatVoicePlaybackActions(
            activeMessageId: 'client_1',
            onToggle: (messageId, resolvedUrl) {
              toggles.add('$messageId|$resolvedUrl');
            },
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
  });

  testWidgets('attachment bubbles keep sender and time outside the bubble', (
    tester,
  ) async {
    final messages = [
      _message(
        type: 'file',
        body: 'report.pdf',
        attachments: const [
          MessageAttachment(
            type: 'file',
            name: 'report.pdf',
            asset: UploadedAsset(
              id: 'asset_report',
              url: '/uploads/report.pdf',
              thumbnailUrl: null,
              mimeType: 'application/pdf',
              filename: 'report.pdf',
              sizeBytes: 2048,
            ),
          ),
        ],
      ),
      _message(
        type: 'audio',
        body: 'voice_1.m4a',
        attachments: const [
          MessageAttachment(
            type: 'audio',
            name: 'voice_1.m4a',
            durationMs: 15000,
            asset: UploadedAsset(
              id: 'asset_voice',
              url: '/uploads/voice_1.m4a',
              thumbnailUrl: null,
              mimeType: 'audio/mp4',
              filename: 'voice_1.m4a',
              sizeBytes: 4096,
            ),
          ),
        ],
      ),
      _message(
        type: 'sticker',
        body: '[wave]',
        attachments: const [
          MessageAttachment(
            type: 'sticker',
            name: 'wave',
            asset: UploadedAsset(
              id: 'asset_sticker',
              url: '/stickers/wave.webp',
              thumbnailUrl: '/stickers/wave-thumb.webp',
              mimeType: 'image/webp',
            ),
          ),
        ],
      ),
    ];

    for (final message in messages) {
      await tester.pumpWidget(
        _host(
          MessageBubbleForTest(
            message: message,
            downloadActions: _downloadActions(),
          ),
        ),
      );

      expect(find.text('Logan'), findsNothing);
      expect(
        find.text(message_display.formatMessageTime(message.createdAt)),
        findsNothing,
      );
    }
  });
}

Widget _host(Widget child) {
  return MaterialApp(
    theme: ui.uiTheme(),
    home: AppConfigScope(
      config: const AppConfig(
        apiBaseUrl: 'https://api.test/api/v1',
        assetBaseUrl: 'https://assets.test',
      ),
      child: Scaffold(
        body: Center(child: SizedBox(width: 600, child: child)),
      ),
    ),
  );
}

Message _message({
  required String type,
  required String body,
  required List<MessageAttachment> attachments,
}) {
  return Message(
    id: 'message_1',
    roomId: 'room_1',
    sender: const UserSummary(
      id: 'user_1',
      username: 'logan',
      displayName: 'Logan',
      avatarUrl: null,
      defaultAvatarKey: 'blue-3',
    ),
    clientMessageId: 'client_1',
    type: type,
    body: body,
    createdAt: DateTime.utc(2026, 6, 11),
    attachments: attachments,
  );
}

ChatFileDownloadActions _downloadActions() {
  return ChatFileDownloadActions(
    onDownload: (_, _, _, _) {},
    onPause: (_) {},
    onResume: (_) {},
    onCancel: (_) {},
    onDismiss: (_) {},
  );
}
