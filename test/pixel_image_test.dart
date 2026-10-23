import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanc_viewer/pixel_image.dart';

class _Frames extends ImageStreamCompleter {
  void emit(ui.Image image) => setImage(ImageInfo(image: image));
}

class _Provider extends ImageProvider<_Provider> {
  _Provider(this.frames);
  final _Frames frames;

  @override
  Future<_Provider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    _Provider key,
    ImageErrorListener handleError,
  ) => stream.setCompleter(frames);
}

Future<ui.Image> _image(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint()..color = color);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(2, 2);
  } finally {
    picture.dispose();
  }
}

void main() {
  testWidgets('Pixel color follows animation frames without pointer movement', (
    tester,
  ) async {
    final frames = _Frames();
    var pixel = '';
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: PixelImage(
            image: _Provider(frames),
            onPixel: (value) => pixel = value,
          ),
        ),
      ),
    );
    final red = await tester.runAsync(() => _image(const Color(0xFFFF0000)));
    frames.emit(red!);
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (tester.widget<RawImage>(find.byType(RawImage)).image != null) break;
    }
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(tester.getCenter(find.byType(PixelImage)));
    await tester.pump();
    expect(pixel, contains('#FF0000'));
    final blue = await tester.runAsync(() => _image(const Color(0xFF0000FF)));
    frames.emit(blue!);
    for (
      var attempt = 0;
      attempt < 30 && !pixel.contains('#0000FF');
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(pixel, contains('#0000FF'));
    await pointer.moveTo(const Offset(-1, -1));
    await tester.pump();
    expect(pixel, 'Pixel —');
    await pointer.removePointer();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
