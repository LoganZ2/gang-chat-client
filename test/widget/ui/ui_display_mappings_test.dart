import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/room_members_filter.dart';
import 'package:client/src/ui/ui.dart';

void main() {
  test('fileIconForMime maps common mime families', () {
    expect(fileIconForMime('image/png'), Icons.image_outlined);
    expect(fileIconForMime('application/pdf'), Icons.picture_as_pdf_outlined);
    expect(fileIconForMime('application/zip'), Icons.folder_zip_outlined);
    expect(
      fileIconForMime('application/octet-stream'),
      Icons.insert_drive_file_outlined,
    );
  });

  test('roomMemberPresenceIcon maps presence states', () {
    expect(roomMemberPresenceIcon(RoomMemberPresence.live), Icons.call);
    expect(roomMemberPresenceIcon(RoomMemberPresence.online), Icons.circle);
    expect(
      roomMemberPresenceIcon(RoomMemberPresence.offline),
      Icons.circle_outlined,
    );
  });

  testWidgets('PresencePill maps presence tones to unified colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            PresencePill(label: '语音', tone: PresencePillTone.voice),
            PresencePill(label: '在线', tone: PresencePillTone.online),
            PresencePill(label: '离线', tone: PresencePillTone.offline),
          ],
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('语音')).style?.color,
      UiColors.presenceVoice,
    );
    expect(
      tester.widget<Text>(find.text('在线')).style?.color,
      UiColors.presenceOnline,
    );
    expect(
      tester.widget<Text>(find.text('离线')).style?.color,
      UiColors.presenceOffline,
    );
  });

  testWidgets('RoleBadge maps role labels to blue yellow orange red colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            RoleBadge(label: '成员'),
            RoleBadge(label: '管理员'),
            RoleBadge(label: '创建者'),
            RoleBadge(label: '超级用户'),
          ],
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('成员')).style?.color,
      UiColors.roleMember,
    );
    expect(
      tester.widget<Text>(find.text('管理员')).style?.color,
      UiColors.roleAdmin,
    );
    expect(
      tester.widget<Text>(find.text('创建者')).style?.color,
      UiColors.roleCreator,
    );
    expect(
      tester.widget<Text>(find.text('超级用户')).style?.color,
      UiColors.roleSuperuser,
    );
  });

  test('genderMark normalizes common gender values', () {
    expect(genderMark('M')?.symbol, '♂');
    expect(genderMark('woman')?.symbol, '♀');
    expect(genderMark('unknown'), isNull);
  });
}
