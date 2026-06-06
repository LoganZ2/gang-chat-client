import 'package:flutter/material.dart';

import '../app/audio_device_store.dart';
import '../app/authenticated_app_context.dart';
import '../app/live_session_controller.dart';
import '../app/realtime_controller.dart';
import '../shell/secure_audio_device_store.dart';
import 'home_shell.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.app,
    this.audioDeviceStore = const SecureAudioDeviceStore(),
    this.liveSessionController,
    this.realtime,
  });

  final AuthenticatedAppContext app;
  final AudioDeviceStore audioDeviceStore;
  final LiveSessionController? liveSessionController;
  final RealtimeService? realtime;

  @override
  Widget build(BuildContext context) {
    return HomeShell(
      app: app,
      audioDeviceStore: audioDeviceStore,
      liveSessionController: liveSessionController,
      realtime: realtime,
    );
  }
}
