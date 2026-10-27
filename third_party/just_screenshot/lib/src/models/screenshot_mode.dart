/// Screenshot capture mode.
enum ScreenshotMode {
  /// Capture the entire screen.
  screen,

  /// Select and capture a specific region interactively.
  region,

  /// Click a visible window to capture its bounds.
  window,
}

/// Extension methods for [ScreenshotMode] serialization.
extension ScreenshotModeExtension on ScreenshotMode {
  /// Convert enum to string for method channel serialization.
  String toValue() {
    switch (this) {
      case ScreenshotMode.screen:
        return 'screen';
      case ScreenshotMode.region:
        return 'region';
      case ScreenshotMode.window:
        return 'window';
    }
  }

  /// Create [ScreenshotMode] from string value.
  static ScreenshotMode fromValue(String value) {
    switch (value) {
      case 'screen':
        return ScreenshotMode.screen;
      case 'region':
        return ScreenshotMode.region;
      case 'window':
        return ScreenshotMode.window;
      default:
        throw ArgumentError('Invalid ScreenshotMode value: $value');
    }
  }
}
