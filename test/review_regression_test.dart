import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_screenshot/screenshot.dart' as native_capture;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanc_viewer/app_settings.dart';
import 'package:sanc_viewer/image_playback.dart';
import 'package:sanc_viewer/viewer_page.dart';
import 'package:window_manager/window_manager.dart';
import 'test_images.dart';

class _Capture extends Fake implements native_capture.Screenshot {
  _Capture(this.result, {this.fail = false});
  native_capture.CapturedData? result;
  bool fail;
  int calls = 0;
  native_capture.ScreenshotMode? mode;

  @override
  Future<native_capture.CapturedData?> capture({
    required native_capture.ScreenshotMode mode,
    bool includeCursor = false,
    int? displayId,
  }) async {
    calls++;
    this.mode = mode;
    if (fail) throw PlatformException(code: 'CAPTURE_FAILED');
    return result;
  }
}

Future<void> spin(WidgetTester tester, [int times = 40]) async {
  for (var i = 0; i < times; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> pumpCapture(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

void main() {
  const windowChannel = MethodChannel('window_manager');
  for (final outcome in ['screen', 'region', 'window', 'cancel', 'failure']) {
    testWidgets('Native capture $outcome updates the viewer', (tester) async {
      final events = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        (call) async {
          events.add(call.method);
          return call.method.startsWith('is') ? false : true;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowChannel,
          null,
        ),
      );
      final successful =
          outcome == 'screen' || outcome == 'region' || outcome == 'window';
      final capture = _Capture(
        successful
            ? native_capture.CapturedData(
                width: 1,
                height: 1,
                bytes: twoFrameGif(),
              )
            : null,
        fail: outcome == 'failure',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [desktopScreenshotProvider.overrideWithValue(capture)],
          child: const MaterialApp(home: ViewerPage()),
        ),
      );
      if (outcome == 'screen' || outcome == 'window') {
        await tester.tap(find.text('Capture'));
        await tester.pump();
        await tester.tap(
          find.text(
          outcome == 'screen' ? 'Capture screen' : 'Capture window',
          ),
        );
      } else {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
      await pumpCapture(tester);
      expect(capture.calls, 1);
      expect(capture.mode, switch (outcome) {
        'screen' => native_capture.ScreenshotMode.screen,
        'window' => native_capture.ScreenshotMode.window,
        _ => native_capture.ScreenshotMode.region,
      });
      expect(events, contains('minimize'));
      expect(events, contains('show'));
      expect(find.text('Save'), successful ? findsOneWidget : findsNothing);
      expect(
        find.byType(PlaybackImage),
        successful ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Capture failed. Please try again.'),
        outcome == 'failure' ? findsOneWidget : findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('A cancelled capture allows another capture', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async => call.method.startsWith('is') ? false : true,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        null,
      ),
    );
    final capture = _Capture(null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [desktopScreenshotProvider.overrideWithValue(capture)],
        child: const MaterialApp(home: ViewerPage()),
      ),
    );
    Future<void> trigger() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await pumpCapture(tester);
    }

    await trigger();
    expect(capture.calls, 1);
    capture.result = native_capture.CapturedData(
      width: 1,
      height: 1,
      bytes: twoFrameGif(),
    );
    await trigger();
    expect(capture.calls, 2);
    expect(find.text('Save'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets('A completed non-looping GIF can be replayed', (tester) async {
    final bytes = twoFrameGif().toList()..removeRange(19, 38);
    final playback = ImagePlayback();
    await tester.pumpWidget(
      MaterialApp(
        home: PlaybackImage(
          bytes: Uint8List.fromList(bytes),
          playback: playback,
          onPixel: (_) {},
        ),
      ),
    );
    await spin(tester);
    expect(playback.frameCount, 2);
    expect(playback.frame, 1);
    expect(playback.playing, isFalse);
    playback.toggle();
    final restarted = playback.playing;
    for (var i = 0; i < 30 && playback.frame != 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      await tester.pump();
    }
    expect(
      playback.frame,
      0,
      reason: 'Replay must start with the first frame.',
    );
    await spin(tester);
    expect(playback.frame, 1);
    expect(playback.playing, isFalse);
    await tester.pumpWidget(const SizedBox());
    playback.dispose();
    expect(
      restarted,
      isTrue,
      reason: 'Play should restart a finished animation.',
    );
  });
  testWidgets('Refresh does not revert a newer user selection', (tester) async {
    final dir = Directory.systemTemp.createTempSync('sanc_review_refresh_');
    final a = File('${dir.path}/a.gif')..writeAsBytesSync(twoFrameGif());
    File('${dir.path}/b.gif').writeAsBytesSync(twoFrameGif());
    final settings = AppSettings()..update(folder: dir.path, image: a.path);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appSettingsProvider.overrideWithValue(settings)],
        child: const MaterialApp(home: ViewerPage()),
      ),
    );
    await spin(tester);
    final state = tester.state(find.byType(ViewerPage)) as WindowListener;
    state.onWindowFocus();
    final tile = find.ancestor(
      of: find.text('b.gif'),
      matching: find.byType(ListTile),
    );
    tester.widget<ListTile>(tile).onTap!();
    await spin(tester);
    final selected = settings.image;
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    dir.deleteSync(recursive: true);
    expect(
      selected,
      endsWith('b.gif'),
      reason: 'Async refresh must preserve the newer user selection.',
    );
  });
}
