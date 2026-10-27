import 'package:flutter_test/flutter_test.dart';
import 'package:just_screenshot/src/models/screenshot_mode.dart';

void main() {
  group('ScreenshotMode', () {
    test('toValue returns correct string for screen mode', () {
      const ScreenshotMode mode = ScreenshotMode.screen;
      expect(mode.toValue(), equals('screen'));
    });

    test('toValue returns correct string for region mode', () {
      const ScreenshotMode mode = ScreenshotMode.region;
      expect(mode.toValue(), equals('region'));
    });

    test('fromValue creates correct mode from screen string', () {
      final ScreenshotMode mode = ScreenshotModeExtension.fromValue('screen');
      expect(mode, equals(ScreenshotMode.screen));
    });

    test('fromValue creates correct mode from region string', () {
      final ScreenshotMode mode = ScreenshotModeExtension.fromValue('region');
      expect(mode, equals(ScreenshotMode.region));
    });

    test('fromValue throws ArgumentError for invalid value', () {
      expect(
        () => ScreenshotModeExtension.fromValue('invalid'),
        throwsArgumentError,
      );
    });

    test('enum values are correctly defined', () {
      expect(ScreenshotMode.values.length, equals(2));
      expect(ScreenshotMode.values, contains(ScreenshotMode.screen));
      expect(ScreenshotMode.values, contains(ScreenshotMode.region));
    });
  });
}
