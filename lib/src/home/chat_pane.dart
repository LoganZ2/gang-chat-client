import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../app/file_display.dart' as file_display;
import '../app/file_transfer_state.dart';
import '../app/media_cache_controller.dart';
import '../app/composer_attachment_display.dart' as composer_attachment;
import '../app/live_display.dart' as live_display;
import '../app/message_display.dart' as message_display;
import '../app/room_display.dart' as room_display;
import '../app/sticker_display.dart' as sticker_display;
import '../app/voice_message_display.dart' as voice_display;
import '../protocol/models.dart';
import '../ui/ui.dart';
import 'cached_media_image.dart';
import 'room_profile_card.dart';

part 'chat_header.dart';
part 'chat_messages.dart';
part 'chat_composer_dock.dart';
part 'chat_profile_card.dart';
part 'chat_image_preview.dart';

const _chatHeaderHeight = 111.0;
const _chatHorizontalPadding = 18.0;
const _chatFloatingEdgeInset = 14.0;
const _chatHeaderHorizontalInset = _chatFloatingEdgeInset;
const _chatHeaderVisualTopInset = _chatHeaderHorizontalInset;
const _chatHeaderBottomInset = 16.0;
const _headerSurfaceHoverLift = 3.0;
const _headerSurfaceBaseDepth = 5.0;
const _liveHeaderCardHeight = 70.0;
const _headerActionButtonSize = 31.0;
const _headerActionGap = 0.0;
const _messageMaxWidth = 560.0;
// Breathing room below the last message before the composer row begins.
const _messageListBottomInset = 14.0;
const _composerHorizontalInset = _chatFloatingEdgeInset;
const _composerBottomInset = _chatFloatingEdgeInset;
const _outgoingBubble = Color(0xFF1F352B);
const _incomingBubble = UiColors.surface;

class ChatPane extends StatelessWidget {
  const ChatPane({
    super.key,
    required this.currentUser,
    required this.roomCard,
    required this.room,
    required this.live,
    required this.messages,
    required this.fileTransfers,
    required this.fileDownloads,
    required this.downloadActions,
    required this.voicePlaybackActions,
    required this.imagePreviewActions,
    required this.loading,
    required this.error,
    required this.sending,
    required this.sendError,
    required this.composerController,
    required this.composerPanelController,
    required this.stickerPanel,
    required this.voiceState,
    required this.composerAttachments,
    required this.fileActionHighlighted,
    required this.onSubmit,
    required this.onSendSticker,
    required this.onLoadStickers,
    required this.onRefreshStickers,
    required this.onStickerSourceChanged,
    required this.onStartVoice,
    required this.onSendVoice,
    required this.onCancelVoice,
    required this.onPickFile,
    required this.onPasteFiles,
    required this.onRemoveAttachment,
    required this.onRetryAttachment,
    required this.onRetry,
    required this.onOpenLiveChannel,
    required this.onOpenRoomMembers,
    required this.onOpenRoomSettings,
    this.onResolveSenderProfile,
    this.onResolveRoomProfile,
    this.onEnterProfileRoom,
    this.senderProfileActionBuilder,
    this.composerDropKey,
  });

  final CurrentUser currentUser;
  final RoomCard? roomCard;
  final RoomDetail? room;
  final LiveState? live;
  final List<Message> messages;
  final Map<String, FileTransferState> fileTransfers;
  final Map<String, FileTransferState> fileDownloads;
  final ChatFileDownloadActions downloadActions;
  final ChatVoicePlaybackActions voicePlaybackActions;
  final ChatImagePreviewActions imagePreviewActions;
  final bool loading;
  final String? error;
  final bool sending;
  final String? sendError;
  final TextEditingController composerController;
  final ChatComposerController composerPanelController;
  final sticker_display.StickerPanelLoadState stickerPanel;
  final voice_display.VoiceRecorderState voiceState;
  final List<composer_attachment.ComposerAttachmentView> composerAttachments;
  final bool fileActionHighlighted;
  final ValueChanged<String> onSubmit;
  final ValueChanged<Sticker> onSendSticker;
  final VoidCallback onLoadStickers;
  final VoidCallback onRefreshStickers;
  final ValueChanged<sticker_display.StickerPanelSource> onStickerSourceChanged;
  final VoidCallback onStartVoice;
  final VoidCallback onSendVoice;
  final VoidCallback onCancelVoice;
  final VoidCallback onPickFile;
  final Future<bool> Function() onPasteFiles;
  final ValueChanged<String> onRemoveAttachment;
  final ValueChanged<String> onRetryAttachment;
  final VoidCallback onRetry;
  final VoidCallback onOpenLiveChannel;
  final VoidCallback onOpenRoomMembers;
  final VoidCallback onOpenRoomSettings;

  /// Resolves a richer profile for a message sender on demand (gender, common
  /// rooms). The hover card calls this lazily; when null it shows just the
  /// lightweight summary carried by the message.
  final Future<UserSummary> Function(UserSummary sender)?
  onResolveSenderProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterProfileRoom;
  final UserProfileActionBuilder? senderProfileActionBuilder;
  final Key? composerDropKey;

  @override
  Widget build(BuildContext context) {
    final title = _roomTitle(room, roomCard);
    final avatarUrl = room?.avatarUrl ?? roomCard?.avatarUrl;
    final defaultAvatarKey =
        room?.defaultAvatarKey ??
        roomCard?.defaultAvatarKey ??
        kDefaultAvatarPresetKey;
    final liveParticipantCount =
        live?.participantCount ??
        room?.live.participantCount ??
        roomCard?.liveParticipantCount;
    final roomReady = room != null;
    final stageKey = ValueKey(
      'message-stage-${room?.id ?? roomCard?.id ?? 'none'}',
    );

    return ColoredBox(
      color: UiColors.background,
      child: Column(
        children: [
          _RoomHeader(
            title: title,
            avatarUrl: avatarUrl,
            defaultAvatarKey: defaultAvatarKey,
            memberCount: room?.memberCount ?? roomCard?.memberCount,
            onlineMemberCount:
                room?.onlineMemberCount ?? roomCard?.onlineMemberCount,
            liveParticipantCount: liveParticipantCount,
            onLivePressed: onOpenLiveChannel,
            onMembersPressed: onOpenRoomMembers,
            onSettingsPressed: onOpenRoomSettings,
          ),
          Expanded(
            child: _MessageStage(
              key: stageKey,
              roomId: room?.id ?? roomCard?.id,
              currentUser: currentUser,
              ownerUserId: room?.createdBy?.id,
              roomReady: roomReady,
              loading: loading,
              error: error,
              messages: messages,
              fileTransfers: fileTransfers,
              fileDownloads: fileDownloads,
              live: live,
              downloadActions: downloadActions,
              voicePlaybackActions: voicePlaybackActions,
              imagePreviewActions: imagePreviewActions,
              onRetry: onRetry,
              bottomInset: _messageListBottomInset,
              onResolveSenderProfile: onResolveSenderProfile,
              onResolveRoomProfile: onResolveRoomProfile,
              onEnterProfileRoom: onEnterProfileRoom,
              senderProfileActionBuilder: senderProfileActionBuilder,
            ),
          ),
          if (roomReady)
            SelectionContainer.disabled(
              // The composer's text field drives its own selection and its
              // panels (sticker grid, voice) are scrollable but not meant to
              // be selectable. Detach it from the app-wide SelectionArea so
              // showing/hiding a panel mid-selection can't trip the
              // scrollable-selection assertion.
              child: _ComposerDock(
                controller: composerController,
                composerController: composerPanelController,
                sending: sending,
                sendError: sendError,
                stickerPanel: stickerPanel,
                voiceState: voiceState,
                attachments: composerAttachments,
                fileActionHighlighted: fileActionHighlighted,
                onSubmit: onSubmit,
                onSendSticker: onSendSticker,
                onOpenStickers: onLoadStickers,
                onRefreshStickers: onRefreshStickers,
                onStickerSourceChanged: onStickerSourceChanged,
                onStartVoice: onStartVoice,
                onSendVoice: onSendVoice,
                onCancelVoice: onCancelVoice,
                onPickFile: onPickFile,
                onPasteFiles: onPasteFiles,
                onRemoveAttachment: onRemoveAttachment,
                onRetryAttachment: onRetryAttachment,
                dropKey: composerDropKey,
              ),
            ),
        ],
      ),
    );
  }
}

String _roomTitle(RoomDetail? room, RoomCard? card) {
  final detailRemark = room?.remarkName?.trim();
  if (detailRemark != null && detailRemark.isNotEmpty) return detailRemark;
  final detailTitle = room?.name.trim();
  if (detailTitle != null && detailTitle.isNotEmpty) return detailTitle;
  final cardTitle = card?.displayName.trim();
  if (cardTitle != null && cardTitle.isNotEmpty) return cardTitle;
  return '聊天';
}
