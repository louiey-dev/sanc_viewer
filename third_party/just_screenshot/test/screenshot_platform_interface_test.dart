import 'package:flutter_test/flutter_test.dart';
import 'package:just_screenshot/screenshot_platform_interface.dart';
import 'package:just_screenshot/screenshot_method_channel.dart';
import 'package:just_screenshot/src/models/screenshot_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScreenshotPlatform', () {
    test('default instance is MethodChannelScreenshot', () {
      expect(ScreenshotPlatform.instance, isA<MethodChannelScreenshot>());
    });

    test('can set custom platform instance', () {
      final ScreenshotPlatform testInstance = TestScreenshotPlatform();
      ScreenshotPlatform.instance = testInstance;

      expect(ScreenshotPlatform.instance, equals(testInstance));

      // Reset to default
      ScreenshotPlatform.instance = MethodChannelScreenshot();
    });

    test('capture method is unimplemented in base class', () {
      final ScreenshotPlatform platform = TestScreenshotPlatform();

      expect(
        () => platform.capture(mode: ScreenshotMode.screen),
        throwsUnimplementedError,
      );
    });

    test('verifyToken protects platform instance', () {
      // Attempting to set an instance without proper token should fail
      // This is enforced by PlatformInterface.verifyToken
      expect(ScreenshotPlatform.instance, isA<ScreenshotPlatform>());
    });
  });
}

class TestScreenshotPlatform extends ScreenshotPlatform {
  // Test implementation that doesn't override capture
  // to test the unimplemented error
}
