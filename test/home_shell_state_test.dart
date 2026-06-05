import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/home_shell_state.dart';

void main() {
  test('home settings pane toggle flips open state and clears error', () {
    final opened = homeSettingsPaneToggled(settingsOpen: false);

    expect(opened.settingsOpen, isTrue);
    expect(opened.error, isNull);

    final closed = homeSettingsPaneToggled(settingsOpen: true);

    expect(closed.settingsOpen, isFalse);
    expect(closed.error, isNull);
  });

  test('home settings pane close is a no-op when already closed', () {
    expect(homeSettingsPaneClosed(settingsOpen: false), isNull);

    final closed = homeSettingsPaneClosed(settingsOpen: true);

    expect(closed?.settingsOpen, isFalse);
    expect(closed?.error, isNull);
  });

  test('home fullscreen share state tracks identity and window controls', () {
    final entered = homeFullScreenShareEntered(identity: 'user_1');

    expect(entered.fullScreenShareIdentity, 'user_1');
    expect(
      homeWindowControlsHiddenForFullScreenShare(
        entered.fullScreenShareIdentity,
      ),
      isTrue,
    );

    expect(homeFullScreenShareExited(currentIdentity: null), isNull);

    final exited = homeFullScreenShareExited(currentIdentity: 'user_1');

    expect(exited?.fullScreenShareIdentity, isNull);
    expect(
      homeWindowControlsHiddenForFullScreenShare(
        exited?.fullScreenShareIdentity,
      ),
      isFalse,
    );
  });

  test('home live panel state expands and collapses with no-op guards', () {
    final expanded = homeLivePanelExpanded(currentLivePanelOpen: false);

    expect(expanded?.livePanelOpen, isTrue);
    expect(homeLivePanelExpanded(currentLivePanelOpen: true), isNull);

    final collapsed = homeLivePanelCollapsed(currentLivePanelOpen: true);

    expect(collapsed?.livePanelOpen, isFalse);
    expect(homeLivePanelCollapsed(currentLivePanelOpen: false), isNull);
  });

  test('home sidebar layout computes visible width and drag patches', () {
    final maxAllowed = homeSidebarMaxAllowedWidth(
      availableWidth: 900,
      contentMinWidth: 240,
      minWidth: 288,
      maxWidth: 520,
    );

    expect(maxAllowed, 520);
    expect(
      homeSidebarVisibleWidth(
        sidebarWidth: 640,
        sidebarCollapsed: false,
        collapsedWidth: 64,
        minWidth: 288,
        maxWidth: maxAllowed,
      ),
      520,
    );
    expect(
      homeSidebarVisibleWidth(
        sidebarWidth: 320,
        sidebarCollapsed: true,
        collapsedWidth: 64,
        minWidth: 288,
        maxWidth: maxAllowed,
      ),
      64,
    );

    final toggled = homeSidebarCollapsedToggled(
      sidebarWidth: 320,
      sidebarCollapsed: false,
    );

    expect(toggled.sidebarWidth, 320);
    expect(toggled.sidebarCollapsed, isTrue);

    final dragged = homeSidebarWidthDragged(
      sidebarWidth: 320,
      sidebarCollapsed: false,
      delta: 300,
      minWidth: 288,
      maxWidth: maxAllowed,
    );

    expect(dragged?.sidebarWidth, 520);
    expect(dragged?.sidebarCollapsed, isFalse);
    expect(
      homeSidebarWidthDragged(
        sidebarWidth: 320,
        sidebarCollapsed: true,
        delta: 40,
        minWidth: 288,
        maxWidth: maxAllowed,
      ),
      isNull,
    );
  });

  test('home current user patch carries updated user value', () {
    final patch = homeCurrentUserUpdated('user_2');

    expect(patch.currentUser, 'user_2');
  });

  test('home toast state shows messages and clears with no-op guard', () {
    final shown = homeToastShown(message: 'Saved', kind: HomeToastKind.success);

    expect(shown.message, 'Saved');
    expect(shown.kind, HomeToastKind.success);

    final defaultShown = homeToastShown(message: 'Failed');

    expect(defaultShown.message, 'Failed');
    expect(defaultShown.kind, HomeToastKind.error);

    final cleared = homeToastCleared(currentMessage: shown.message);

    expect(cleared?.message, isNull);
    expect(cleared?.kind, HomeToastKind.error);
    expect(homeToastCleared(currentMessage: null), isNull);
  });
}
