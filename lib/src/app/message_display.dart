import '../protocol/models.dart';
import 'file_display.dart';

enum MessageContentKind { sticker, files, text }

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

MessageContentKind messageContentKind(Message message) {
  if (message.stickerAttachment != null) return MessageContentKind.sticker;
  if (message.fileAttachments.isNotEmpty) return MessageContentKind.files;
  return MessageContentKind.text;
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
