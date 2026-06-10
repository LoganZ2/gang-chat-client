import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/account_display.dart' as account_display;
import '../app/room_display.dart' as room_display;
import '../app/room_forms.dart' as room_forms;
import '../app/room_invites.dart' as room_invites;
import '../app/room_join_requests.dart' as room_join_requests;
import '../app/room_members_filter.dart' as member_filter;
import '../app/rooms_controller.dart';
import '../app/sticker_management.dart';
import '../config/app_config.dart';
import '../protocol/api_client.dart';
import '../protocol/models.dart';
import '../shell/file_selection_service.dart';
import '../ui/avatar_crop_dialog.dart';
import '../ui/ui.dart';

part 'room_members_dialog.dart';
part 'room_settings_dialog.dart';
part 'room_members_components.dart';
part 'room_management_components.dart';

const _dialogMaxWidth = 680.0;
const _dialogMaxHeight = 700.0;
const _panelRadius = UiRadii.lg;
const _rowRadius = UiRadii.md;

enum RoomManagementResultKind { created, updated, left, deleted }

class RoomManagementResult {
  const RoomManagementResult._({required this.kind, this.room});

  const RoomManagementResult.created(RoomDetail room)
    : this._(kind: RoomManagementResultKind.created, room: room);

  const RoomManagementResult.updated(RoomDetail room)
    : this._(kind: RoomManagementResultKind.updated, room: room);

  const RoomManagementResult.left()
    : this._(kind: RoomManagementResultKind.left);

  const RoomManagementResult.deleted()
    : this._(kind: RoomManagementResultKind.deleted);

  final RoomManagementResultKind kind;
  final RoomDetail? room;
}
