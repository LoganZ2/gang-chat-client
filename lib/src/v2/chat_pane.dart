import 'package:flutter/material.dart';

import '../app/file_display.dart' as file_display;
import '../app/file_transfer_state.dart';
import '../app/message_display.dart' as message_display;
import '../protocol/models.dart';
import '../ui/ui.dart';

part 'chat_header.dart';
part 'chat_messages.dart';
part 'chat_composer_dock.dart';

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
const _selectedLiveHeaderBackground = Color(0xFF1B2F27);
const _composerStickerIcons = [
  Icons.sentiment_satisfied_alt,
  Icons.waving_hand_outlined,
  Icons.auto_awesome,
  Icons.local_fire_department_outlined,
  Icons.coffee_outlined,
  Icons.celebration_outlined,
  Icons.favorite_border,
  Icons.lightbulb_outline,
  Icons.bolt_outlined,
  Icons.nightlight_round,
  Icons.public_outlined,
  Icons.workspace_premium_outlined,
];
const _composerStickerLabels = [
  'Smile',
  'Wave',
  'Spark',
  'Fire',
  'Coffee',
  'Party',
  'Heart',
  'Idea',
  'Fast',
  'Night',
  'World',
  'Win',
];
const _composerStickerColors = [
  UiColors.accent,
  UiColors.violet,
  UiColors.amber,
  UiColors.danger,
];

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
    required this.onSubmit,
    required this.onRetry,
    required this.onOpenLiveChannel,
    required this.onOpenRoomMembers,
    required this.onOpenRoomSettings,
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
  final ValueChanged<String> onSubmit;
  final VoidCallback onRetry;
  final VoidCallback onOpenLiveChannel;
  final VoidCallback onOpenRoomMembers;
  final VoidCallback onOpenRoomSettings;

  @override
  Widget build(BuildContext context) {
    final title = _roomTitle(room, roomCard);
    final avatarUrl = room?.avatarUrl ?? roomCard?.avatarUrl;
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
                    onSubmit: onSubmit,
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
  return 'Chat';
}
