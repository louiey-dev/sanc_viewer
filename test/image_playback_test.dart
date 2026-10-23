import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanc_viewer/image_playback.dart';

import 'test_images.dart';

Future<void> settleDecoder(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue);
}

void main() {
  testWidgets(
    'Animation pauses, steps backwards, and exports displayed frame',
    (tester) async {
      final playback = ImagePlayback();
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackImage(
            bytes: twoFrameGif(),
            playback: playback,
            onPixel: (_) {},
          ),
        ),
      );
      await settleDecoder(
        tester,
        () =>
            playback.frameCount == 2 &&
            tester.widget<RawImage>(find.byType(RawImage)).image != null,
      );
      if (playback.playing) playback.toggle();
      final paused = playback.frame;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 10));
      expect(playback.frame, paused);
      playback.step(1);
      await settleDecoder(tester, () => playback.frame == (paused + 1) % 2);
      expect(playback.playing, isFalse);
      final expected = playback.frame == 0
          ? [255, 0, 0, 255]
          : [0, 0, 255, 255];
      await tester.runAsync(() async {
        final png = await playback.png();
        expect(png, isNotNull);
        final codec = await ui.instantiateImageCodec(png!);
        final frame = await codec.getNextFrame();
        final pixels = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        expect(pixels!.buffer.asUint8List(), expected);
        frame.image.dispose();
        codec.dispose();
      });
      playback.step(-1);
      await settleDecoder(tester, () => playback.frame == paused);
      playback.toggle();
      await settleDecoder(tester, () => playback.frame != paused);
      await tester.pumpWidget(const SizedBox());
      playback.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
