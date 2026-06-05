class HomeSettingsPanePatch {
  const HomeSettingsPanePatch({
    required this.settingsOpen,
    required this.error,
  });

  final bool settingsOpen;
  final String? error;
}

class HomeFullScreenSharePatch {
  const HomeFullScreenSharePatch({required this.fullScreenShareIdentity});

  final String? fullScreenShareIdentity;
}

class HomeLivePanelPatch {
  const HomeLivePanelPatch({required this.livePanelOpen});

  final bool livePanelOpen;
}

class HomeSidebarLayoutPatch {
  const HomeSidebarLayoutPatch({
    required this.sidebarWidth,
    required this.sidebarCollapsed,
  });

  final double sidebarWidth;
  final bool sidebarCollapsed;
}

class HomeCurrentUserPatch<T> {
  const HomeCurrentUserPatch({required this.currentUser});

  final T currentUser;
}

enum HomeToastKind { error, success }

class HomeToastPatch {
  const HomeToastPatch({required this.message, required this.kind});

  final String? message;
  final HomeToastKind kind;
}

HomeSettingsPanePatch homeSettingsPaneToggled({required bool settingsOpen}) {
  return HomeSettingsPanePatch(settingsOpen: !settingsOpen, error: null);
}

HomeSettingsPanePatch? homeSettingsPaneClosed({required bool settingsOpen}) {
  if (!settingsOpen) return null;
  return const HomeSettingsPanePatch(settingsOpen: false, error: null);
}

HomeFullScreenSharePatch homeFullScreenShareEntered({
  required String identity,
}) {
  return HomeFullScreenSharePatch(fullScreenShareIdentity: identity);
}

HomeFullScreenSharePatch? homeFullScreenShareExited({
  required String? currentIdentity,
}) {
  if (currentIdentity == null) return null;
  return const HomeFullScreenSharePatch(fullScreenShareIdentity: null);
}

bool homeWindowControlsHiddenForFullScreenShare(String? identity) {
  return identity != null;
}

HomeLivePanelPatch? homeLivePanelExpanded({
  required bool currentLivePanelOpen,
}) {
  if (currentLivePanelOpen) return null;
  return const HomeLivePanelPatch(livePanelOpen: true);
}

HomeLivePanelPatch? homeLivePanelCollapsed({
  required bool currentLivePanelOpen,
}) {
  if (!currentLivePanelOpen) return null;
  return const HomeLivePanelPatch(livePanelOpen: false);
}

double homeSidebarMaxAllowedWidth({
  required double availableWidth,
  required double contentMinWidth,
  required double minWidth,
  required double maxWidth,
}) {
  return (availableWidth - contentMinWidth)
      .clamp(minWidth, maxWidth)
      .toDouble();
}

double homeSidebarVisibleWidth({
  required double sidebarWidth,
  required bool sidebarCollapsed,
  required double collapsedWidth,
  required double minWidth,
  required double maxWidth,
}) {
  if (sidebarCollapsed) return collapsedWidth;
  return sidebarWidth.clamp(minWidth, maxWidth).toDouble();
}

HomeSidebarLayoutPatch homeSidebarCollapsedToggled({
  required double sidebarWidth,
  required bool sidebarCollapsed,
}) {
  return HomeSidebarLayoutPatch(
    sidebarWidth: sidebarWidth,
    sidebarCollapsed: !sidebarCollapsed,
  );
}

HomeSidebarLayoutPatch? homeSidebarWidthDragged({
  required double sidebarWidth,
  required bool sidebarCollapsed,
  required double delta,
  required double minWidth,
  required double maxWidth,
}) {
  if (sidebarCollapsed) return null;
  final nextWidth = (sidebarWidth + delta).clamp(minWidth, maxWidth).toDouble();
  if ((nextWidth - sidebarWidth).abs() < 0.5) return null;
  return HomeSidebarLayoutPatch(
    sidebarWidth: nextWidth,
    sidebarCollapsed: false,
  );
}

HomeCurrentUserPatch<T> homeCurrentUserUpdated<T>(T user) {
  return HomeCurrentUserPatch<T>(currentUser: user);
}

HomeToastPatch homeToastShown({
  required String message,
  HomeToastKind kind = HomeToastKind.error,
}) {
  return HomeToastPatch(message: message, kind: kind);
}

HomeToastPatch? homeToastCleared({required String? currentMessage}) {
  if (currentMessage == null) return null;
  return const HomeToastPatch(message: null, kind: HomeToastKind.error);
}
