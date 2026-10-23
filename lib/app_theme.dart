import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_settings.dart';

/// Selected appearance for the current session.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// Controls application appearance.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() =>
      ref.read(appSettingsProvider).dark ? ThemeMode.dark : ThemeMode.light;

  /// Switches between light and dark appearance.
  void toggle() {
    setMode(state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);
  }

  void setMode(ThemeMode mode) {
    state = mode;
    ref.read(appSettingsProvider).update(dark: state == ThemeMode.dark);
  }
}

/// Creates the viewer palette for a given brightness.
ThemeData viewerTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF147D73),
      brightness: brightness,
      surface: dark ? const Color(0xFF20262D) : const Color(0xFFFAFBFC),
    ),
    scaffoldBackgroundColor: dark
        ? const Color(0xFF171C22)
        : const Color(0xFFF0F2F5),
    dividerColor: dark ? const Color(0xFF353E48) : const Color(0xFFE2E6EB),
    visualDensity: VisualDensity.compact,
  );
}
