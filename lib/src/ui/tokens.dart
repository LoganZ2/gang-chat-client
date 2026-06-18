import 'package:flutter/material.dart';

const String kClientFontFamily = 'Microsoft YaHei';
const List<String> kClientFontFamilyFallback = ['Microsoft YaHei UI'];

abstract final class UiColors {
  static const background = Color(0xFF14171D);
  static const surfaceLow = Color(0xFF181C24);
  static const surface = Color(0xFF1F232C);
  static const surfaceRaised = Color(0xFF252A34);
  static const surfacePressed = Color(0xFF0F1115);
  static const selected = Color(0xFF1F2D27);
  static const border = Color(0xFF2A2F38);
  static const borderStrong = Color(0xFF3A424D);
  static const accentBorder = Color(0xFF355C49);
  static const selectedBorder = Color(0xFF3D705A);
  static const dangerBorder = Color(0xFF57343A);
  static const disabledSurface = Color(0xFF1A1D23);
  static const disabledBorder = Color(0xFF22262E);

  static const text = Color(0xFFECEFF1);
  static const textSecondary = Color(0xFFB0B8C0);
  static const textMuted = Color(0xFF6F7785);
  static const accent = Color(0xFF52A07C);
  static const violet = Color(0xFFB8A3FF);
  static const amber = Color(0xFFD4B675);
  static const danger = Color(0xFFE58383);

  static const presenceOnline = Color(0xFF52A07C);
  static const presenceOnlineSurface = Color(0xFF1F2D27);
  static const presenceOnlineBorder = Color(0xFF3D705A);
  static const presenceOffline = Color(0xFF8E96A6);
  static const presenceOfflineSurface = Color(0xFF222733);
  static const presenceOfflineBorder = Color(0xFF4A5263);
  static const presenceVoice = Color(0xFF7FFFD4);
  static const presenceVoiceSurface = Color(0xFF153A34);
  static const presenceVoiceBorder = Color(0xFF4AAE96);
}

abstract final class UiSpacing {
  static const xxs = 4.0;
  static const xs = 6.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
}

abstract final class UiRadii {
  static const sm = 4.0;
  static const md = 6.0;
  static const lg = 8.0;
}

abstract final class UiTypography {
  static const label = TextStyle(
    color: UiColors.textSecondary,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  static const body = TextStyle(
    color: UiColors.text,
    fontSize: 14,
    height: 1.35,
  );

  static const title = TextStyle(
    color: UiColors.text,
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );
}

ThemeData uiTheme() {
  return ThemeData(
    colorScheme: const ColorScheme.dark(
      primary: UiColors.accent,
      surface: UiColors.surfaceLow,
      error: UiColors.danger,
    ),
    fontFamily: kClientFontFamily,
    fontFamilyFallback: kClientFontFamilyFallback,
    scaffoldBackgroundColor: UiColors.background,
    // The app styles its own flat focus/hover/selected states (see the title
    // bar search field). Suppress Material's default interaction overlays so the
    // accent-tinted focus layer doesn't flash green on top of our own.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: UiColors.accent,
      selectionColor: UiColors.accent.withValues(alpha: 0.28),
      selectionHandleColor: UiColors.accent,
    ),
  );
}
