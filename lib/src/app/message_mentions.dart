import '../protocol/models.dart';
import 'room_display.dart' as room_display;
import 'room_members_filter.dart' as member_filter;

const int defaultMessageMentionOptionLimit = 8;

class MessageMentionQuery {
  const MessageMentionQuery({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;
}

class MessageMentionRange {
  const MessageMentionRange({required this.start, required this.end});

  final int start;
  final int end;
}

class MessageMentionOption {
  const MessageMentionOption({
    required this.member,
    required this.label,
    required this.roleLabel,
  });

  final RoomMember member;
  final String label;
  final String roleLabel;
}

MessageMentionQuery? activeMessageMentionQuery({
  required String text,
  required int cursorOffset,
}) {
  if (cursorOffset < 0 || cursorOffset > text.length) return null;
  var atIndex = -1;
  for (var index = cursorOffset - 1; index >= 0; index--) {
    final codeUnit = text.codeUnitAt(index);
    if (text[index] == '@') {
      atIndex = index;
      break;
    }
    if (_isMentionTerminator(codeUnit)) break;
  }
  if (atIndex < 0) return null;
  final query = text.substring(atIndex + 1, cursorOffset);
  if (query.contains('@') || query.contains('\n') || query.contains('\r')) {
    return null;
  }
  if (_looksLikeEmailAddress(text, atIndex: atIndex, end: cursorOffset)) {
    return null;
  }
  return MessageMentionQuery(start: atIndex, end: cursorOffset, query: query);
}

List<MessageMentionRange> messageMentionRanges(String text) {
  final ranges = <MessageMentionRange>[];
  var index = 0;
  while (index < text.length) {
    final atIndex = text.indexOf('@', index);
    if (atIndex < 0) break;
    var end = atIndex + 1;
    while (end < text.length && !_isMentionTerminator(text.codeUnitAt(end))) {
      if (text[end] == '@') break;
      end++;
    }
    if (_looksLikeEmailAddress(text, atIndex: atIndex, end: end)) {
      index = end <= atIndex ? atIndex + 1 : end;
      continue;
    }
    if (end > atIndex + 1) {
      ranges.add(MessageMentionRange(start: atIndex, end: end));
    }
    index = end <= atIndex ? atIndex + 1 : end;
  }
  return ranges;
}

List<MessageMentionOption> messageMentionOptions({
  required Iterable<RoomMember> members,
  required String query,
  required String? ownerUserId,
  String? excludedUserId,
  int limit = defaultMessageMentionOptionLimit,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final ranked = <_RankedMentionOption>[];
  for (final member in members) {
    if (excludedUserId != null && member.user.id == excludedUserId) {
      continue;
    }
    final label = member_filter.roomMemberDisplayName(member).trim();
    if (label.isEmpty) continue;
    final rank = _mentionSearchRank(member, label, normalizedQuery);
    if (rank == null) continue;
    ranked.add(
      _RankedMentionOption(
        option: MessageMentionOption(
          member: member,
          label: label,
          roleLabel: room_display.roomRoleLabel(
            member.user,
            ownerUserId: ownerUserId,
          ),
        ),
        rank: rank,
        roleRank: member_filter.roomMemberRoleRank(
          member,
          ownerUserId: ownerUserId,
        ),
      ),
    );
  }
  ranked.sort((a, b) {
    final rankCompare = a.rank.compareTo(b.rank);
    if (rankCompare != 0) return rankCompare;
    final roleCompare = a.roleRank.compareTo(b.roleRank);
    if (roleCompare != 0) return roleCompare;
    return a.option.label.toLowerCase().compareTo(b.option.label.toLowerCase());
  });
  return ranked.take(limit).map((entry) => entry.option).toList();
}

String messageMentionInsertText(MessageMentionOption option) =>
    '@${option.label} ';

int? _mentionSearchRank(
  RoomMember member,
  String label,
  String normalizedQuery,
) {
  if (normalizedQuery.isEmpty) return 100;
  final candidates =
      <String>{
            label,
            member.roomDisplayName ?? '',
            member.remarkName ?? '',
            member.user.roomDisplayName ?? '',
            member.user.displayName,
            member.user.username,
            member.user.uid ?? '',
            member.user.id,
          }
          .where((value) => value.trim().isNotEmpty)
          .map((value) => value.toLowerCase())
          .toList();
  var bestRank = 1 << 30;
  for (final candidate in candidates) {
    if (candidate == normalizedQuery) {
      bestRank = bestRank < 0 ? bestRank : 0;
    } else if (candidate.startsWith(normalizedQuery)) {
      bestRank = bestRank < 1 ? bestRank : 1;
    } else if (candidate.contains(normalizedQuery)) {
      bestRank = bestRank < 2 ? bestRank : 2;
    }
  }
  return bestRank == 1 << 30 ? null : bestRank;
}

bool _isMentionTerminator(int codeUnit) =>
    codeUnit <= 0x20 || codeUnit == 0x3000;

bool _looksLikeEmailAddress(
  String text, {
  required int atIndex,
  required int end,
}) {
  if (atIndex <= 0 || end <= atIndex + 1 || end > text.length) return false;
  final domain = text.substring(atIndex + 1, end);
  if (!domain.contains('.')) return false;
  if (domain.startsWith('.') || domain.endsWith('.')) return false;
  if (!domain.codeUnits.every(_isEmailDomainCodeUnit)) return false;

  var localStart = atIndex - 1;
  while (localStart >= 0 &&
      _isEmailLocalCodeUnit(text.codeUnitAt(localStart))) {
    localStart--;
  }
  localStart++;
  if (localStart >= atIndex) return false;
  final local = text.substring(localStart, atIndex);
  return local.isNotEmpty &&
      !local.startsWith('.') &&
      !local.endsWith('.') &&
      local.codeUnits.every(_isEmailLocalCodeUnit);
}

bool _isEmailLocalCodeUnit(int codeUnit) {
  return _isAsciiLetterOrDigit(codeUnit) ||
      codeUnit == 0x2e ||
      codeUnit == 0x5f ||
      codeUnit == 0x25 ||
      codeUnit == 0x2b ||
      codeUnit == 0x2d;
}

bool _isEmailDomainCodeUnit(int codeUnit) {
  return _isAsciiLetterOrDigit(codeUnit) ||
      codeUnit == 0x2e ||
      codeUnit == 0x2d;
}

bool _isAsciiLetterOrDigit(int codeUnit) {
  return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7a);
}

class _RankedMentionOption {
  const _RankedMentionOption({
    required this.option,
    required this.rank,
    required this.roleRank,
  });

  final MessageMentionOption option;
  final int rank;
  final int roleRank;
}
