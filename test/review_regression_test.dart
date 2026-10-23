import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanc_viewer/app_settings.dart';
import 'package:sanc_viewer/image_playback.dart';
import 'package:sanc_viewer/viewer_page.dart';
import 'package:window_manager/window_manager.dart';
import 'test_images.dart';

class _Capture extends Fake implements ScreenCapturer {
  _Capture(this.result, {this.fail = false});
  final CapturedData? result;
  final bool fail;
  int clipboardReads = 0;

  @override
  Future<CapturedData?> capture({
    CaptureMode mode = CaptureMode.region,
    String? imagePath,
    bool copyToClipboard = true,
    bool silent = true,
  }) async {
    expect(copyToClipboard, isFalse);
    if (fail) throw PlatformException(code: 'CAPTURE_FAILED');
    return result;
  }

  @override
  Future<Uint8List?> readImageFromClipboard() async {
    clipboardReads++;
    return twoFrameGif();
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

void main() {
  for (final outcome in ['cancel', 'failure', 'success']) {
    testWidgets('Capture $outcome never uses an old clipboard image', (
      tester,
    ) async {
      final captured = outcome == 'success'
          ? CapturedData(
              imageWidth: 1,
              imageHeight: 1,
              imageBytes: twoFrameGif(),
            )
          : null;
      final capture = _Capture(captured, fail: outcome == 'failure');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [screenCapturerProvider.overrideWithValue(capture)],
          child: const MaterialApp(home: ViewerPage()),
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      // File result retries run on the widget test clock.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pump();
      expect(capture.clipboardReads, 0);
      expect(
        find.text('Capture ready. Use Save to export the PNG.'),
        outcome == 'success' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Capture failed. Please try again.'),
        outcome == 'failure' ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(PlaybackImage),
        outcome == 'success' ? findsOneWidget : findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

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
