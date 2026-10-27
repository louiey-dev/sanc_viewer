import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_screenshot/screenshot_method_channel.dart';
import 'package:just_screenshot/src/models/captured_data.dart';
import 'package:just_screenshot/src/models/screenshot_exception.dart';
import 'package:just_screenshot/src/models/screenshot_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelScreenshot', () {
    final MethodChannelScreenshot platform = MethodChannelScreenshot();
    const MethodChannel channel = MethodChannel('dev.flutter.screenshot');

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('capture sends correct parameters for screen mode', () async {
      final List<MethodCall> log = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        log.add(methodCall);
        return <String, dynamic>{
          'width': 1920,
          'height': 1080,
          'bytes': Uint8List.fromList(<int>[1, 2, 3, 4]),
        };
      });

      await platform.capture(mode: ScreenshotMode.screen, includeCursor: false);

      expect(log, hasLength(1));
      expect(log.first.method, equals('capture'));
      final Map<dynamic, dynamic> args = log.first.arguments as Map<dynamic, dynamic>;
      expect(args['mode'], equals('screen'));
      expect(args['includeCursor'], equals(false));
    });

    test('capture returns CapturedData on success', () async {
      final Uint8List mockBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        return <String, dynamic>{'width': 1920, 'height': 1080, 'bytes': mockBytes};
      });

      final CapturedData? result = await platform.capture(mode: ScreenshotMode.screen, includeCursor: true);

      expect(result, isNotNull);
      expect(result!.width, equals(1920));
      expect(result.height, equals(1080));
      expect(result.bytes, equals(mockBytes));
    });

    test('capture returns null when cancelled', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        return null;
      });

      final CapturedData? result = await platform.capture(mode: ScreenshotMode.screen);

      expect(result, isNull);
    });

    test('capture throws ScreenshotException on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        throw PlatformException(code: 'internal_error', message: 'BitBlt failed', details: 'GetLastError: 123');
      });

      expect(
        () => platform.capture(mode: ScreenshotMode.screen),
        throwsA(
          isA<ScreenshotException>()
              .having((ScreenshotException e) => e.code, 'code', 'internal_error')
              .having((ScreenshotException e) => e.message, 'message', 'BitBlt failed')
              .having((ScreenshotException e) => e.details, 'details', 'GetLastError: 123'),
        ),
      );
    });

    test('capture includes displayId when provided', () async {
      final List<MethodCall> log = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        log.add(methodCall);
        return <String, dynamic>{
          'width': 1920,
          'height': 1080,
          'bytes': Uint8List.fromList(<int>[1, 2, 3]),
        };
      });

      await platform.capture(mode: ScreenshotMode.screen, includeCursor: false, displayId: 1);

      final Map<dynamic, dynamic> args = log.first.arguments as Map<dynamic, dynamic>;
      expect(args['displayId'], equals(1));
    });

    test('capture omits displayId when not provided', () async {
      final List<MethodCall> log = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        log.add(methodCall);
        return <String, dynamic>{
          'width': 1920,
          'height': 1080,
          'bytes': Uint8List.fromList(<int>[1, 2, 3]),
        };
      });

      await platform.capture(mode: ScreenshotMode.screen);

      final Map<dynamic, dynamic> args = log.first.arguments as Map<dynamic, dynamic>;
      expect(args.containsKey('displayId'), isFalse);
    });

    test('capture with region mode sends correct parameters', () async {
      final List<MethodCall> log = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        log.add(methodCall);
        return null; // Simulate cancellation
      });

      await platform.capture(mode: ScreenshotMode.region, includeCursor: false);

      final Map<dynamic, dynamic> args = log.first.arguments as Map<dynamic, dynamic>;
      expect(args['mode'], equals('region'));
    });

    // T065: Test for region mode
    test('capture region mode sends correct mode parameter', () async {
      final List<MethodCall> log = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        log.add(methodCall);
        return <String, dynamic>{
          'width': 800,
          'height': 600,
          'bytes': Uint8List.fromList(<int>[5, 6, 7, 8]),
        };
      });

      final CapturedData? result = await platform.capture(mode: ScreenshotMode.region);

      expect(log, hasLength(1));
      expect(log.first.method, equals('capture'));
      final Map<dynamic, dynamic> args = log.first.arguments as Map<dynamic, dynamic>;
      expect(args['mode'], equals('region'));
      expect(result, isNotNull);
      expect(result!.width, equals(800));
      expect(result.height, equals(600));
    });

    // T066: Test for null return (cancellation)
    test('capture region returns null when user cancels selection', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        // User pressed ESC or right-clicked during region selection
        return null;
      });

      final CapturedData? result = await platform.capture(mode: ScreenshotMode.region);

      expect(result, isNull);
    });

    // T105: Test for PlatformException → ScreenshotException mapping
    test('capture maps cancelled PlatformException to ScreenshotException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        throw PlatformException(code: 'cancelled', message: 'User cancelled');
      });

      expect(
        () => platform.capture(mode: ScreenshotMode.region),
        throwsA(
          isA<ScreenshotException>()
              .having((ScreenshotException e) => e.code, 'code', 'cancelled')
              .having((ScreenshotException e) => e.message, 'message', 'User cancelled'),
        ),
      );
    });

    test('capture maps not_supported PlatformException to ScreenshotException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        throw PlatformException(code: 'not_supported', message: 'Not supported on this platform', details: 'Linux');
      });

      expect(
        () => platform.capture(mode: ScreenshotMode.screen),
        throwsA(
          isA<ScreenshotException>()
              .having((ScreenshotException e) => e.code, 'code', 'not_supported')
              .having((ScreenshotException e) => e.message, 'message', 'Not supported on this platform')
              .having((ScreenshotException e) => e.details, 'details', 'Linux'),
        ),
      );
    });

    test('capture maps invalid_argument PlatformException to ScreenshotException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        throw PlatformException(code: 'invalid_argument', message: 'Invalid mode parameter');
      });

      expect(
        () => platform.capture(mode: ScreenshotMode.screen),
        throwsA(
          isA<ScreenshotException>()
              .having((ScreenshotException e) => e.code, 'code', 'invalid_argument')
              .having((ScreenshotException e) => e.message, 'message', 'Invalid mode parameter'),
        ),
      );
    });

    // T106: Test for error code distinction (cancelled vs internal_error)
    test('cancelled error is distinct from internal_error', () async {
      // Cancelled error
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        throw PlatformException(code: 'cancelled', message: 'User cancelled');
      });

      try {
        await platform.capture(mode: ScreenshotMode.region);
        fail('Should have thrown ScreenshotException');
      } on ScreenshotException catch (e) {
        expect(e, isA<ScreenshotException>());
        final ScreenshotException exception = e;
        expect(exception.code, equals('cancelled'));
        expect(exception.code, isNot(equals('internal_error')));
      }

      // Internal error
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        throw PlatformException(code: 'internal_error', message: 'BitBlt failed', details: 123);
      });

      try {
        await platform.capture(mode: ScreenshotMode.screen);
        fail('Should have thrown ScreenshotException');
      } on ScreenshotException catch (e) {
        expect(e, isA<ScreenshotException>());
        final ScreenshotException exception = e;
        expect(exception.code, equals('internal_error'));
        expect(exception.code, isNot(equals('cancelled')));
        expect(exception.details, equals(123));
      }
    });
  });
}
