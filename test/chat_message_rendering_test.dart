import 'package:client/src/app/composer_attachment_display.dart'
    as composer_attachment;
import 'package:client/src/app/message_display.dart' as message_display;
import 'package:client/src/app/sticker_display.dart' as sticker_display;
import 'package:client/src/app/voice_message_display.dart' as voice_display;
import 'package:client/src/config/app_config.dart';
import 'package:client/src/home/chat_pane.dart';
import 'package:client/src/protocol/models.dart';
import 'package:client/src/ui/app_config_scope.dart';
import 'package:client/src/ui/ui.dart' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('message timestamps toggle between brief and detailed labels', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final now = DateTime.now();
    final firstAt = now.subtract(const Duration(minutes: 5));
    final secondAt = now.subtract(const Duration(minutes: 3));
    final firstBrief = message_display.formatChatTimestamp(firstAt, now: now);
    final secondBrief = message_display.formatChatTimestamp(secondAt, now: now);
    final firstDetailed = message_display.formatDetailedChatTimestamp(firstAt);
    final secondDetailed = message_display.formatDetailedChatTimestamp(
      secondAt,
    );

    await tester.pumpWidget(
      _host(
        ChatPane(
          currentUser: _currentUser,
          roomCard: _roomCard,
          room: null,
          live: null,
          messages: [
            _message(type: 'text', body: 'hello', createdAt: firstAt),
            _message(
              type: 'text',
              body: 'world',
              createdAt: secondAt,
              clientMessageId: 'client_2',
            ),
          ],
          fileTransfers: const {},
          fileDownloads: const {},
          downloadActions: _downloadActions(),
          voicePlaybackActions: const ChatVoicePlaybackActions.disabled(),
          loading: false,
          error: null,
          sending: false,
          sendError: null,
          composerController: controller,
          composerPanelController: ui.ChatComposerController(),
          stickerPanel: const sticker_display.StickerPanelLoadState(),
          voiceState: const voice_display.VoiceRecorderState(),
          composerAttachments:
              const <composer_attachment.ComposerAttachmentView>[],
          fileActionHighlighted: false,
          onSubmit: (_) {},
          onSendSticker: (_) {},
          onLoadStickers: () {},
          onRefreshStickers: () {},
          onStickerSourceChanged: (_) {},
          onStartVoice: () {},
          onSendVoice: () {},
          onCancelVoice: () {},
          onPickFile: () {},
          onPasteFiles: () async => false,
          onRemoveAttachment: (_) {},
          onRetryAttachment: (_) {},
          onRetry: () {},
          onOpenLiveChannel: () {},
          onOpenRoomMembers: () {},
          onOpenRoomSettings: () {},
        ),
      ),
    );

    expect(find.text(firstBrief), findsOneWidget);
    expect(find.text(secondBrief), findsOneWidget);
    expect(find.text(firstDetailed), findsNothing);
    expect(find.text(secondDetailed), findsNothing);

    await tester.tap(find.text(firstBrief));
    await tester.pump();

    expect(find.text(firstDetailed), findsOneWidget);
    expect(find.text(secondDetailed), findsOneWidget);

    await tester.tap(find.text(firstDetailed));
    await tester.pump();

    expect(find.text(firstBrief), findsOneWidget);
    expect(find.text(secondBrief), findsOneWidget);
    expect(find.text(firstDetailed), findsNothing);
    expect(find.text(secondDetailed), findsNothing);
  });

  testWidgets('text message body is selectable for copy', (tester) async {
    await tester.pumpWidget(
      _host(
        MessageBubbleForTest(
          message: _message(type: 'text', body: 'copy this'),
          downloadActions: _downloadActions(),
        ),
      ),
    );

    expect(find.widgetWithText(SelectableText, 'copy this'), findsOneWidget);
  });

  testWidgets('pending message shows a spinner beside the 发送中 label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        MessageBubbleForTest(
          message: _message(type: 'text', body: 'sending soon', pending: true),
          outgoing: true,
          downloadActions: _downloadActions(),
        ),
      ),
    );

    expect(find.text('发送中'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('system role message renders below a centered timestamp', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final createdAt = DateTime.now().subtract(const Duration(minutes: 2));
    final brief = message_display.formatChatTimestamp(
      createdAt,
      now: DateTime.now(),
    );
    final detailed = message_display.formatDetailedChatTimestamp(createdAt);

    await tester.pumpWidget(
      _host(
        _chatPane(
          controller: controller,
          messages: [
            _message(
              type: 'system',
              body: '降职为管理员',
              createdAt: createdAt,
              attachments: const [
                MessageAttachment(
                  type: 'system',
                  event: message_display.kSystemEventRoomRoleChanged,
                  target: _systemTarget,
                  actor: _systemActor,
                  fromRole: 'owner',
                  toRole: 'admin',
                ),
              ],
            ),
          ],
        ),
      ),
    );

    expect(find.text(brief), findsOneWidget);
    expect(find.text('Logan'), findsOneWidget);
    expect(find.text('Owner'), findsNothing);
    expect(find.text('降职为'), findsOneWidget);
    expect(find.text('管理员'), findsOneWidget);

    await tester.tap(find.text(brief));
    await tester.pump();

    expect(find.text(detailed), findsOneWidget);
  });

  testWidgets('system and ordinary messages can share a timestamp divider', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final now = DateTime.now();
    final createdAt = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      5,
    );
    final brief = message_display.formatChatTimestamp(
      createdAt,
      now: DateTime.now(),
    );

    await tester.pumpWidget(
      _host(
        _chatPane(
          controller: controller,
          messages: [
            _message(
              type: 'system',
              body: '进入了语音频道',
              createdAt: createdAt,
              attachments: const [
                MessageAttachment(
                  type: 'system',
                  event: message_display.kSystemEventLiveJoined,
                  target: _systemTarget,
                ),
              ],
            ),
            _message(
              type: 'text',
              body: 'hello after live join',
              createdAt: createdAt.add(const Duration(seconds: 10)),
              clientMessageId: 'client_after_system',
            ),
          ],
        ),
      ),
    );

    expect(find.text(brief), findsOneWidget);
    expect(find.text('Logan'), findsWidgets);
    expect(find.text('进入了语音频道'), findsOneWidget);
    expect(find.text('hello after live join'), findsOneWidget);
  });

  testWidgets('sticker bubble exposes the sticker name only as a tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        MessageBubbleForTest(
          message: _message(
            type: 'sticker',
            body: '[表情] wave',
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

    expect(find.text('15"'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('voice-waveform'))).width,
      closeTo(
        voice_display.voiceWaveformWidth(const Duration(seconds: 15)),
        0.01,
      ),
    );
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

  testWidgets('voice waveform width follows attachment duration', (
    tester,
  ) async {
    Future<double> renderWidth(Duration duration) async {
      await tester.pumpWidget(
        _host(
          MessageBubbleForTest(
            message: _voiceMessage(duration: duration),
            downloadActions: _downloadActions(),
          ),
        ),
      );
      return tester.getSize(find.byKey(const ValueKey('voice-waveform'))).width;
    }

    final shortWidth = await renderWidth(const Duration(seconds: 3));
    final mediumWidth = await renderWidth(const Duration(seconds: 30));
    final longWidth = await renderWidth(const Duration(minutes: 5));

    expect(mediumWidth, greaterThan(shortWidth));
    expect(longWidth, greaterThan(mediumWidth));
    expect(longWidth, closeTo(voice_display.kVoiceWaveformMaxWidth, 0.01));
  });

  testWidgets('voice duration labels keep a consistent trailing gap', (
    tester,
  ) async {
    Future<double> renderTrailingGap(Duration duration, String label) async {
      await tester.pumpWidget(
        _host(
          MessageBubbleForTest(
            message: _voiceMessage(duration: duration),
            downloadActions: _downloadActions(),
          ),
        ),
      );
      final bodyRight = tester
          .getRect(find.byKey(const ValueKey('voice-body')))
          .right;
      final labelRight = tester.getRect(find.text(label)).right;
      return bodyRight - labelRight;
    }

    final secondsGap = await renderTrailingGap(
      const Duration(seconds: 2),
      '2"',
    );
    final minutesGap = await renderTrailingGap(
      const Duration(seconds: 65),
      '1\'05"',
    );

    expect(secondsGap, closeTo(minutesGap, 0.01));
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
        body: '[表情] wave',
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

Widget _chatPane({
  required TextEditingController controller,
  required List<Message> messages,
}) {
  return ChatPane(
    currentUser: _currentUser,
    roomCard: _roomCard,
    room: null,
    live: null,
    messages: messages,
    fileTransfers: const {},
    fileDownloads: const {},
    downloadActions: _downloadActions(),
    voicePlaybackActions: const ChatVoicePlaybackActions.disabled(),
    loading: false,
    error: null,
    sending: false,
    sendError: null,
    composerController: controller,
    composerPanelController: ui.ChatComposerController(),
    stickerPanel: const sticker_display.StickerPanelLoadState(),
    voiceState: const voice_display.VoiceRecorderState(),
    composerAttachments: const <composer_attachment.ComposerAttachmentView>[],
    fileActionHighlighted: false,
    onSubmit: (_) {},
    onSendSticker: (_) {},
    onLoadStickers: () {},
    onRefreshStickers: () {},
    onStickerSourceChanged: (_) {},
    onStartVoice: () {},
    onSendVoice: () {},
    onCancelVoice: () {},
    onPickFile: () {},
    onPasteFiles: () async => false,
    onRemoveAttachment: (_) {},
    onRetryAttachment: (_) {},
    onRetry: () {},
    onOpenLiveChannel: () {},
    onOpenRoomMembers: () {},
    onOpenRoomSettings: () {},
  );
}

Message _message({
  required String type,
  String body = '',
  List<MessageAttachment> attachments = const [],
  DateTime? createdAt,
  String clientMessageId = 'client_1',
  bool pending = false,
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
    clientMessageId: clientMessageId,
    type: type,
    body: body,
    createdAt: createdAt ?? DateTime.utc(2026, 6, 11),
    attachments: attachments,
    pending: pending,
  );
}

Message _voiceMessage({required Duration duration}) {
  return _message(
    type: 'audio',
    body: 'voice_1.m4a',
    attachments: [
      MessageAttachment(
        type: 'audio',
        name: 'voice_1.m4a',
        durationMs: duration.inMilliseconds,
        asset: const UploadedAsset(
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
}

const _currentUser = CurrentUser(
  id: 'current_user',
  uid: '1000000',
  username: 'me',
  displayName: 'Me',
  bio: '',
  gender: 'secret',
  email: null,
  emailPublic: false,
  phoneNumber: null,
  phoneNumberPublic: false,
  avatarUrl: null,
  defaultAvatarKey: 'blue-3',
  isSuperuser: false,
  createdAt: null,
);

const _systemTarget = UserSummary(
  id: 'user_target',
  username: 'logan',
  displayName: 'Logan',
  avatarUrl: null,
  defaultAvatarKey: 'green-2',
);

const _systemActor = UserSummary(
  id: 'user_actor',
  username: 'owner',
  displayName: 'Owner',
  avatarUrl: null,
  defaultAvatarKey: 'blue-3',
);

final _roomCard = RoomCard(
  id: 'room_1',
  name: 'Test room',
  avatarUrl: null,
  defaultAvatarKey: 'room-1',
  memberCount: 2,
  liveParticipantCount: 0,
  liveAvatarPreview: const [],
  lastMessage: null,
  unreadCount: 0,
  updatedAt: DateTime(2026, 6, 12),
);

ChatFileDownloadActions _downloadActions() {
  return ChatFileDownloadActions(
    onDownload: (_, _, _, _) {},
    onPause: (_) {},
    onResume: (_) {},
    onCancel: (_) {},
    onDismiss: (_) {},
  );
}
