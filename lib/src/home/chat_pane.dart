import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/file_display.dart' as file_display;
import '../app/file_transfer_state.dart';
import '../app/message_display.dart' as message_display;
import '../app/room_display.dart' as room_display;
import '../app/sticker_display.dart' as sticker_display;
import '../app/voice_message_display.dart' as voice_display;
import '../protocol/models.dart';
import '../ui/ui.dart';

part 'chat_header.dart';
part 'chat_messages.dart';
part 'chat_composer_dock.dart';
part 'chat_profile_card.dart';

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
const _composerOverlayInset = 112.0;
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
    required this.loading,
    required this.error,
    required this.sending,
    required this.sendError,
    required this.composerController,
    required this.stickerPanel,
    required this.voiceState,
    required this.onSubmit,
    required this.onSendSticker,
    required this.onLoadStickers,
    required this.onRefreshStickers,
    required this.onStickerSourceChanged,
    required this.onStartVoice,
    required this.onSendVoice,
    required this.onCancelVoice,
    required this.onRetry,
    required this.onOpenLiveChannel,
    required this.onOpenRoomMembers,
    required this.onOpenRoomSettings,
    this.onResolveSenderProfile,
  });

  final CurrentUser currentUser;
  final RoomCard? roomCard;
  final RoomDetail? room;
  final LiveState? live;
  final List<Message> messages;
  final Map<String, FileTransferState> fileTransfers;
  final bool loading;
  final String? error;
  final bool sending;
  final String? sendError;
  final TextEditingController composerController;
  final sticker_display.StickerPanelLoadState stickerPanel;
  final voice_display.VoiceRecorderState voiceState;
  final ValueChanged<String> onSubmit;
  final ValueChanged<Sticker> onSendSticker;
  final VoidCallback onLoadStickers;
  final VoidCallback onRefreshStickers;
  final ValueChanged<sticker_display.StickerPanelSource> onStickerSourceChanged;
  final VoidCallback onStartVoice;
  final VoidCallback onSendVoice;
  final VoidCallback onCancelVoice;
  final VoidCallback onRetry;
  final VoidCallback onOpenLiveChannel;
  final VoidCallback onOpenRoomMembers;
  final VoidCallback onOpenRoomSettings;

  /// Resolves a richer profile for a message sender on demand (gender, common
  /// rooms). The hover card calls this lazily; when null it shows just the
  /// lightweight summary carried by the message.
  final Future<UserSummary> Function(UserSummary sender)?
  onResolveSenderProfile;

  @override
  Widget build(BuildContext context) {
    final title = _roomTitle(room, roomCard);
    final avatarUrl = room?.avatarUrl ?? roomCard?.avatarUrl;
    final defaultAvatarKey =
        room?.defaultAvatarKey ?? roomCard?.defaultAvatarKey ?? 'room-1';
    final liveParticipantCount =
        live?.participantCount ??
        room?.live.participantCount ??
        roomCard?.liveParticipantCount;

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
            loading: loading,
            onLivePressed: onOpenLiveChannel,
            onMembersPressed: onOpenRoomMembers,
            onSettingsPressed: onOpenRoomSettings,
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _MessageStage(
                    currentUserId: currentUser.id,
                    roomReady: room != null,
                    loading: loading,
                    error: error,
                    messages: messages,
                    fileTransfers: fileTransfers,
                    onRetry: onRetry,
                    onResolveSenderProfile: onResolveSenderProfile,
                  ),
                ),
                Positioned(
                  left: _composerHorizontalInset,
                  right: _composerHorizontalInset,
                  bottom: _composerBottomInset,
                  child: _ComposerDock(
                    controller: composerController,
                    sending: sending,
                    sendError: sendError,
                    stickerPanel: stickerPanel,
                    voiceState: voiceState,
                    onSubmit: onSubmit,
                    onSendSticker: onSendSticker,
                    onOpenStickers: onLoadStickers,
                    onRefreshStickers: onRefreshStickers,
                    onStickerSourceChanged: onStickerSourceChanged,
                    onStartVoice: onStartVoice,
                    onSendVoice: onSendVoice,
                    onCancelVoice: onCancelVoice,
                  ),
                ),
              ],
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
