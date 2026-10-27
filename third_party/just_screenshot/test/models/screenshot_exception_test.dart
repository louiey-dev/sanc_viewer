import 'package:flutter_test/flutter_test.dart';
import 'package:just_screenshot/src/models/screenshot_exception.dart';

void main() {
  group('ScreenshotException', () {
    test('constructor creates exception with code and message', () {
      const ScreenshotException exception = ScreenshotException(code: 'test_error', message: 'Test error message');

      expect(exception.code, 'test_error');
      expect(exception.message, 'Test error message');
      expect(exception.details, isNull);
    });

    test('constructor accepts optional details', () {
      const ScreenshotException exception = ScreenshotException(
        code: 'internal_error',
        message: 'Internal error occurred',
        details: 12345,
      );

      expect(exception.code, 'internal_error');
      expect(exception.message, 'Internal error occurred');
      expect(exception.details, 12345);
    });

    test('fromPlatformException creates exception from platform error', () {
      final ScreenshotException exception = ScreenshotException.fromPlatformException(
        code: 'cancelled',
        message: 'User cancelled',
        details: null,
      );

      expect(exception.code, 'cancelled');
      expect(exception.message, 'User cancelled');
      expect(exception.details, isNull);
    });

    test('fromPlatformException handles null message', () {
      final ScreenshotException exception = ScreenshotException.fromPlatformException(
        code: 'internal_error',
        message: null,
      );

      expect(exception.code, 'internal_error');
      expect(exception.message, 'Unknown error');
    });

    test('toString returns formatted string', () {
      const ScreenshotException exception = ScreenshotException(code: 'cancelled', message: 'User cancelled');

      expect(exception.toString(), 'ScreenshotException(cancelled: User cancelled)');
    });

    test('toString includes details when present', () {
      const ScreenshotException exception = ScreenshotException(
        code: 'internal_error',
        message: 'BitBlt failed',
        details: 5,
      );

      expect(exception.toString(), 'ScreenshotException(internal_error: BitBlt failed, details: 5)');
    });

    test('equality works correctly', () {
      const ScreenshotException exception1 = ScreenshotException(code: 'cancelled', message: 'User cancelled');
      const ScreenshotException exception2 = ScreenshotException(code: 'cancelled', message: 'User cancelled');
      const ScreenshotException exception3 = ScreenshotException(code: 'internal_error', message: 'Different error');

      expect(exception1, equals(exception2));
      expect(exception1, isNot(equals(exception3)));
    });

    test('hashCode is consistent', () {
      const ScreenshotException exception1 = ScreenshotException(code: 'cancelled', message: 'User cancelled');
      const ScreenshotException exception2 = ScreenshotException(code: 'cancelled', message: 'User cancelled');

      expect(exception1.hashCode, equals(exception2.hashCode));
    });

    test('error codes are as expected', () {
      // Test each error code defined in contracts
      const ScreenshotException cancelledError = ScreenshotException(
        code: 'cancelled',
        message: 'Screenshot capture cancelled by user',
      );
      const ScreenshotException notSupportedError = ScreenshotException(
        code: 'not_supported',
        message: 'Screenshot capture not supported on this platform',
      );
      const ScreenshotException internalError = ScreenshotException(
        code: 'internal_error',
        message: 'Internal error occurred',
      );
      const ScreenshotException invalidArgumentError = ScreenshotException(
        code: 'invalid_argument',
        message: 'Invalid argument provided',
      );

      expect(cancelledError.code, 'cancelled');
      expect(notSupportedError.code, 'not_supported');
      expect(internalError.code, 'internal_error');
      expect(invalidArgumentError.code, 'invalid_argument');
    });
  });
}
