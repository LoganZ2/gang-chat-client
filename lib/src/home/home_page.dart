import 'package:flutter/material.dart';

import '../app/audio_device_store.dart';
import '../app/authenticated_app_context.dart';
import '../app/close_behavior.dart';
import '../app/language_preference.dart';
import '../app/live_session_controller.dart';
import '../app/realtime_controller.dart';
import '../app/settings_about.dart';
import '../shell/local_auto_update_prompt_store.dart';
import '../shell/local_close_behavior_store.dart';
import '../shell/desktop_window_controller.dart';
import '../shell/local_audio_device_store.dart';
import '../shell/local_language_preference_store.dart';
import 'home_shell.dart';

class HomePage extends StatelessWidget {
  HomePage({
    super.key,
    required this.app,
    this.audioDeviceStore = const LocalAudioDeviceStore(),
    this.liveSessionController,
    this.realtime,
    this.closeBehaviorStore = const LocalCloseBehaviorStore(),
    this.languageStore = const LocalLanguagePreferenceStore(),
    this.autoUpdatePromptStore = const LocalAutoUpdatePromptStore(),
    DesktopWindowController? windowController,
  }) : windowController = windowController ?? DesktopWindowController();

  final AuthenticatedAppContext app;
  final AudioDeviceStore audioDeviceStore;
  final LiveSessionController? liveSessionController;
  final RealtimeService? realtime;
  final CloseBehaviorStore closeBehaviorStore;
  final LanguagePreferenceStore languageStore;
  final AutoUpdatePromptStore autoUpdatePromptStore;
  final DesktopWindowController windowController;

  @override
  Widget build(BuildContext context) {
    return HomeShell(
      app: app,
      audioDeviceStore: audioDeviceStore,
      liveSessionController: liveSessionController,
      realtime: realtime,
      closeBehaviorStore: closeBehaviorStore,
      languageStore: languageStore,
      autoUpdatePromptStore: autoUpdatePromptStore,
      windowController: windowController,
    );
  }
}
