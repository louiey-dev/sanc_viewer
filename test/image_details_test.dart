import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanc_viewer/image_details.dart';

void main() {
  for (final endian in [Endian.little, Endian.big]) {
    test('Reads GPS from JPEG EXIF with $endian byte order', () async {
      final tiff = Uint8List(128);
      final data = ByteData.sublistView(tiff);
      tiff.setRange(0, 2, endian == Endian.little ? [73, 73] : [77, 77]);
      data.setUint16(2, 42, endian);
      data.setUint32(4, 8, endian);
      data.setUint16(8, 1, endian);
      data.setUint16(10, 0x8825, endian);
      data.setUint16(12, 4, endian);
      data.setUint32(14, 1, endian);
      data.setUint32(18, 26, endian);
      data.setUint16(26, 4, endian);
      for (var index = 0; index < 4; index++) {
        final offset = 28 + index * 12;
        final reference = index.isEven;
        data.setUint16(offset, index + 1, endian);
        data.setUint16(offset + 2, reference ? 2 : 5, endian);
        data.setUint32(offset + 4, reference ? 2 : 3, endian);
        if (reference) {
          tiff[offset + 8] = index == 0 ? 78 : 87;
        } else {
          data.setUint32(offset + 8, index == 1 ? 80 : 104, endian);
        }
      }
      final components = [37, 30, 0, 122, 15, 0];
      for (var index = 0; index < components.length; index++) {
        data.setUint32(80 + index * 8, components[index], endian);
        data.setUint32(84 + index * 8, 1, endian);
      }
      final jpeg = Uint8List.fromList([
        0xFF,
        0xD8,
        0xFF,
        0xE1,
        0,
        136,
        69,
        120,
        105,
        102,
        0,
        0,
        ...tiff,
        0xFF,
        0xD9,
      ]);
      final details = await readImageDetails(jpeg);
      expect(details.location, '37.500000, -122.250000');
    });
  }

  test('Reads original capture time from a TIFF EXIF directory', () async {
    final bytes = Uint8List(64);
    final data = ByteData.sublistView(bytes);
    bytes.setRange(0, 4, [73, 73, 42, 0]);
    data.setUint32(4, 8, Endian.little);
    data.setUint16(8, 1, Endian.little);
    data.setUint16(10, 0x8769, Endian.little);
    data.setUint16(12, 4, Endian.little);
    data.setUint32(14, 1, Endian.little);
    data.setUint32(18, 26, Endian.little);
    data.setUint16(26, 1, Endian.little);
    data.setUint16(28, 0x9003, Endian.little);
    data.setUint16(30, 2, Endian.little);
    data.setUint32(32, 20, Endian.little);
    data.setUint32(36, 44, Endian.little);
    bytes.setRange(44, 63, '2026:10:23 12:34:56'.codeUnits);
    final details = await readImageDetails(bytes);
    expect(details.dateTaken, '2026:10:23 12:34:56');
    expect(details.location, isNull);
  });

  test('GPS validates coordinates and hemisphere', () {
    expect(gpsDegrees([37, 30, 0], 'N', latitude: true), 37.5);
    expect(gpsDegrees([122, 15, 0], 'W', latitude: false), -122.25);
    expect(gpsDegrees([0, 0, 0], 'S', latitude: true), 0);
    expect(gpsDegrees([91, 0, 0], 'N', latitude: true), isNull);
    expect(gpsDegrees([30, 60, 0], 'N', latitude: true), isNull);
    expect(gpsDegrees([30, 0, double.infinity], 'N', latitude: true), isNull);
    expect(gpsDegrees([30, 0, 0], '', latitude: true), isNull);
  });

  test('Fitted pixel coordinates exclude letterboxing and preserve RGBA', () {
    final bytes = Uint8List.fromList([255, 0, 0, 255, 0, 128, 255, 128]);
    expect(
      pixelDescription(
        bytes,
        const Size(2, 1),
        const Size(200, 200),
        const Offset(150, 100),
      ),
      'X:1 Y:0 · RGB(0, 128, 255) · #0080FF',
    );
    expect(
      pixelDescription(
        bytes,
        const Size(2, 1),
        const Size(200, 200),
        const Offset(10, 20),
      ),
      isNull,
    );
    expect(
      pixelDescription(
        bytes,
        const Size(2, 1),
        const Size(200, 200),
        const Offset(200, 100),
      ),
      isNull,
    );
  });

  test('Missing or malformed EXIF leaves fields absent', () async {
    final details = await readImageDetails(Uint8List.fromList([1, 2, 3]));
    expect(details.dateTaken, isNull);
    expect(details.location, isNull);
  });
}
