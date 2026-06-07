import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/account_display.dart' as account_display;
import '../app/room_display.dart' as room_display;
import '../app/room_forms.dart' as room_forms;
import '../app/room_members_filter.dart' as member_filter;
import '../app/rooms_controller.dart';
import '../config/app_config.dart';
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
const _sectionRadius = UiRadii.md;
const _rowRadius = UiRadii.md;

enum RoomManagementResultKind { updated, left, deleted }

class RoomManagementResult {
  const RoomManagementResult._({required this.kind, this.room});

  const RoomManagementResult.updated(RoomDetail room)
    : this._(kind: RoomManagementResultKind.updated, room: room);

  const RoomManagementResult.left()
    : this._(kind: RoomManagementResultKind.left);

  const RoomManagementResult.deleted()
    : this._(kind: RoomManagementResultKind.deleted);

  final RoomManagementResultKind kind;
  final RoomDetail? room;
}
