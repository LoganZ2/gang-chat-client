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

  test('genderMark normalizes common gender values', () {
    expect(genderMark('M')?.symbol, '♂');
    expect(genderMark('woman')?.symbol, '♀');
    expect(genderMark('unknown'), isNull);
  });
}
