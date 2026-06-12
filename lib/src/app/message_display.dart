import '../protocol/models.dart';
import 'file_display.dart';
import 'voice_message_display.dart' as voice_display;

enum MessageContentKind { sticker, voice, files, text }

const String kSystemMessageType = 'system';
const String kSystemEventRoomMemberJoined = 'room_member_joined';
const String kSystemEventRoomMemberLeft = 'room_member_left';
const String kSystemEventRoomMemberRemoved = 'room_member_removed';
const String kSystemEventLiveJoined = 'live_joined';
const String kSystemEventLiveLeft = 'live_left';
const String kSystemEventRoomRoleChanged = 'room_role_changed';

class SystemMessageEvent {
  const SystemMessageEvent({
    required this.event,
    required this.message,
    this.user,
    this.actor,
    this.target,
    this.fromRole,
    this.toRole,
  });

  final String event;
  final Message message;
  final UserSummary? user;
  final UserSummary? actor;
  final UserSummary? target;
  final String? fromRole;
  final String? toRole;

  UserSummary get subject => target ?? user ?? message.sender;
  bool get isRoleChange => event == kSystemEventRoomRoleChanged;
}

class MessageTextEdit {
  const MessageTextEdit({required this.text, required this.cursorOffset});

  final String text;
  final int cursorOffset;
}

class StickerMessageDraft {
  const StickerMessageDraft({
    required this.body,
    required this.type,
    required this.attachments,
  });

  final String body;
  final String type;
  final List<MessageAttachment> attachments;
}

Map<String, String> saveMessageDraft({
  required Map<String, String> drafts,
  required String? roomId,
  required String text,
}) {
  if (roomId == null) return drafts;
  return {...drafts, roomId: text};
}

Map<String, String> removeMessageDraft({
  required Map<String, String> drafts,
  required String? roomId,
}) {
  if (roomId == null || !drafts.containsKey(roomId)) return drafts;
  return {
    for (final entry in drafts.entries)
      if (entry.key != roomId) entry.key: entry.value,
  };
}

String messageDraftForRoom({
  required Map<String, String> drafts,
  required String roomId,
}) {
  return drafts[roomId] ?? '';
}

String formatMessageTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String formatChatTimestamp(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final date = DateTime(local.year, local.month, local.day);
  final dayDelta = today.difference(date).inDays;
  final time = formatMessageTime(local);

  if (dayDelta == 0) return time;
  if (dayDelta == 1) return '昨天 $time';
  if (dayDelta == 2) return '前天 $time';
  if (dayDelta >= 3 && dayDelta < 7) {
    return '${_weekdayLabel(local.weekday)} $time';
  }
  if (local.year == localNow.year) {
    return '${local.month}月${local.day}日 $time';
  }
  return '${local.year}年${local.month}月${local.day}日 $time';
}

String formatDetailedChatTimestamp(DateTime value) {
  final local = value.toLocal();
  final time = formatMessageTime(local);
  return '${local.year}年${local.month}月${local.day}日 '
      '${_weekdayLabel(local.weekday)} $time';
}

bool shouldShowChatTimestamp({
  required DateTime current,
  DateTime? previous,
  DateTime? now,
}) {
  if (previous == null) return true;
  final referenceNow = now ?? DateTime.now();
  return formatChatTimestamp(current, now: referenceNow) !=
      formatChatTimestamp(previous, now: referenceNow);
}

String _weekdayLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => '星期一',
    DateTime.tuesday => '星期二',
    DateTime.wednesday => '星期三',
    DateTime.thursday => '星期四',
    DateTime.friday => '星期五',
    DateTime.saturday => '星期六',
    DateTime.sunday => '星期日',
    _ => '星期日',
  };
}

MessageContentKind messageContentKind(Message message) {
  if (message.stickerAttachment != null) return MessageContentKind.sticker;
  if (voice_display.voiceMessageAttachment(message) != null) {
    return MessageContentKind.voice;
  }
  if (message.fileAttachments.isNotEmpty) return MessageContentKind.files;
  return MessageContentKind.text;
}

SystemMessageEvent? systemMessageEvent(Message message) {
  if (message.type != kSystemMessageType) return null;
  MessageAttachment? attachment;
  for (final candidate in message.attachments) {
    if (candidate.type == kSystemMessageType) {
      attachment = candidate;
      break;
    }
  }
  final event = attachment?.event?.trim();
  if (event == null || event.isEmpty) return null;
  final user = attachment?.user;
  final target = attachment?.target ?? user;
  return SystemMessageEvent(
    event: event,
    message: message,
    user: user,
    actor: attachment?.actor,
    target: target,
    fromRole: attachment?.fromRole,
    toRole: attachment?.toRole,
  );
}

String systemMessageRoleLabel(String? role) {
  return switch (role) {
    'owner' || 'creator' => '创建者',
    'admin' => '管理员',
    'member' => '成员',
    _ => '成员',
  };
}

String systemMessageRoleVerb(SystemMessageEvent event) {
  final fromRank = _roleRank(event.fromRole);
  final toRank = _roleRank(event.toRole);
  if (toRank > fromRank) return '晋升为';
  return '降职为';
}

bool systemMessageRoleChangeOmitsActor(SystemMessageEvent event) {
  return event.isRoleChange &&
      event.fromRole == 'owner' &&
      event.toRole == 'admin';
}

int _roleRank(String? role) {
  return switch (role) {
    'owner' || 'creator' => 3,
    'admin' => 2,
    'member' => 1,
    _ => 0,
  };
}

bool shouldShowFileAttachmentBody({
  required String body,
  required List<MessageAttachment> attachments,
}) {
  final trimmedBody = body.trim();
  if (trimmedBody.isEmpty) return false;
  if (attachments.length != 1) return true;
  return trimmedBody != fileAttachmentTitle(attachments[0]);
}

String stickerAttachmentTitle(MessageAttachment attachment) {
  final explicitName = attachment.name?.trim();
  if (explicitName != null && explicitName.isNotEmpty) return explicitName;
  return '表情';
}

String? messageDeliveryStatusText(Message message) {
  if (message.failed) return '发送失败';
  if (message.pending) return '发送中';
  return null;
}

String? outgoingTextMessageBody(String value) {
  final body = value.trimRight();
  return body.trim().isEmpty ? null : body;
}

StickerMessageDraft stickerMessageDraft(Sticker sticker) {
  return StickerMessageDraft(
    body: '[${sticker.name}]',
    type: 'sticker',
    attachments: [
      MessageAttachment(
        type: 'sticker',
        stickerId: sticker.id,
        name: sticker.name,
        asset: sticker.asset,
      ),
    ],
  );
}

MessageTextEdit insertMessageText({
  required String currentText,
  required String insertedText,
  required int? selectionStart,
  required int? selectionEnd,
}) {
  final length = currentText.length;
  final start = selectionStart == null
      ? length
      : selectionStart.clamp(0, length).toInt();
  final end = selectionEnd == null
      ? length
      : selectionEnd.clamp(0, length).toInt();
  final replaceStart = start < end ? start : end;
  final replaceEnd = start < end ? end : start;
  final nextText = currentText.replaceRange(
    replaceStart,
    replaceEnd,
    insertedText,
  );
  return MessageTextEdit(
    text: nextText,
    cursorOffset: replaceStart + insertedText.length,
  );
}
