import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:just_screenshot/screenshot.dart';
import 'package:just_screenshot/screenshot_method_channel.dart';
import 'package:just_screenshot/screenshot_platform_interface.dart';

class MockScreenshotPlatform
    with MockPlatformInterfaceMixin
    implements ScreenshotPlatform {
  CapturedData? _mockResult;
  ScreenshotMode? _capturedMode;
  bool? _capturedIncludeCursor;
  int? _capturedDisplayId;

  void setMockResult(CapturedData? result) {
    _mockResult = result;
  }

  @override
  Future<CapturedData?> capture({
    required ScreenshotMode mode,
    bool includeCursor = false,
    int? displayId,
  }) async {
    _capturedMode = mode;
    _capturedIncludeCursor = includeCursor;
    _capturedDisplayId = displayId;
    return _mockResult;
  }

  ScreenshotMode? get capturedMode => _capturedMode;
  bool? get capturedIncludeCursor => _capturedIncludeCursor;
  int? get capturedDisplayId => _capturedDisplayId;
}

void main() {
  final ScreenshotPlatform initialPlatform = ScreenshotPlatform.instance;

  test('$MethodChannelScreenshot is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelScreenshot>());
  });

  group('Screenshot', () {
    late MockScreenshotPlatform fakePlatform;

    setUp(() {
      fakePlatform = MockScreenshotPlatform();
      ScreenshotPlatform.instance = fakePlatform;
    });

    tearDown(() {
      ScreenshotPlatform.instance = MethodChannelScreenshot();
    });

    test('capture delegates to platform with correct parameters', () async {
      final Uint8List mockBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final CapturedData mockData = CapturedData(
        width: 1920,
        height: 1080,
        bytes: mockBytes,
      );
      fakePlatform.setMockResult(mockData);

      final CapturedData? result = await Screenshot.instance.capture(
        mode: ScreenshotMode.screen,
        includeCursor: true,
        displayId: 0,
      );

      expect(fakePlatform.capturedMode, equals(ScreenshotMode.screen));
      expect(fakePlatform.capturedIncludeCursor, equals(true));
      expect(fakePlatform.capturedDisplayId, equals(0));
      expect(result, equals(mockData));
    });

    test('capture returns null when platform returns null', () async {
      fakePlatform.setMockResult(null);

      final CapturedData? result = await Screenshot.instance.capture(
        mode: ScreenshotMode.region,
      );

      expect(result, isNull);
    });

    test('capture with default parameters', () async {
      final Uint8List mockBytes = Uint8List.fromList(<int>[1, 2, 3]);
      final CapturedData mockData = CapturedData(
        width: 800,
        height: 600,
        bytes: mockBytes,
      );
      fakePlatform.setMockResult(mockData);

      await Screenshot.instance.capture(mode: ScreenshotMode.screen);

      expect(fakePlatform.capturedMode, equals(ScreenshotMode.screen));
      expect(fakePlatform.capturedIncludeCursor, equals(false));
      expect(fakePlatform.capturedDisplayId, isNull);
    });

    test('Screenshot uses singleton pattern', () {
      final Screenshot instance1 = Screenshot.instance;
      final Screenshot instance2 = Screenshot.instance;

      expect(identical(instance1, instance2), isTrue);
    });
  });
}
