enum CloseBehavior { askEveryTime, minimizeToTray, exitProgram }

const defaultCloseBehavior = CloseBehavior.askEveryTime;

extension CloseBehaviorStorage on CloseBehavior {
  String get storageValue {
    return switch (this) {
      CloseBehavior.askEveryTime => 'ask_every_time',
      CloseBehavior.minimizeToTray => 'minimize_to_tray',
      CloseBehavior.exitProgram => 'exit_program',
    };
  }
}

CloseBehavior closeBehaviorFromStorageValue(String? value) {
  return switch (value) {
    'minimize_to_tray' => CloseBehavior.minimizeToTray,
    'exit_program' => CloseBehavior.exitProgram,
    _ => defaultCloseBehavior,
  };
}

String closeBehaviorLabel(CloseBehavior behavior) {
  return switch (behavior) {
    CloseBehavior.askEveryTime => '每次询问',
    CloseBehavior.minimizeToTray => '最小化到托盘',
    CloseBehavior.exitProgram => '直接退出程序',
  };
}

String closeBehaviorDescription(CloseBehavior behavior) {
  return switch (behavior) {
    CloseBehavior.askEveryTime => '关闭窗口时先询问本次要后台运行还是退出账号。',
    CloseBehavior.minimizeToTray => '关闭窗口时保留当前状态并在后台运行。',
    CloseBehavior.exitProgram => '关闭窗口时离开语音、退出账号并结束程序。',
  };
}

class CloseBehaviorStore {
  const CloseBehaviorStore();

  Future<CloseBehavior> read() {
    throw UnimplementedError('CloseBehaviorStore.read must be implemented.');
  }

  Future<void> write(CloseBehavior behavior) {
    throw UnimplementedError('CloseBehaviorStore.write must be implemented.');
  }
}
