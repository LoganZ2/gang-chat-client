import 'package:flutter/foundation.dart';

String clientSystemName(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.fuchsia => 'Fuchsia',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
  };
}

String gangChatClientUserAgent(TargetPlatform platform) {
  return 'GangChat Client (${clientSystemName(platform)})';
}

String currentGangChatClientUserAgent() {
  return gangChatClientUserAgent(defaultTargetPlatform);
}
