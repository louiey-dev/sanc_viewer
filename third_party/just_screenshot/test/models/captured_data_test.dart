import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_screenshot/src/models/captured_data.dart';

void main() {
  group('CapturedData', () {
    test('creates instance with valid parameters', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final CapturedData data = CapturedData(
        width: 1920,
        height: 1080,
        bytes: bytes,
      );

      expect(data.width, equals(1920));
      expect(data.height, equals(1080));
      expect(data.bytes, equals(bytes));
    });

    test('assertion fails when width is zero', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
      expect(
        () => CapturedData(width: 0, height: 1080, bytes: bytes),
        throwsAssertionError,
      );
    });

    test('assertion fails when width is negative', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
      expect(
        () => CapturedData(width: -100, height: 1080, bytes: bytes),
        throwsAssertionError,
      );
    });

    test('assertion fails when height is zero', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
      expect(
        () => CapturedData(width: 1920, height: 0, bytes: bytes),
        throwsAssertionError,
      );
    });

    test('assertion fails when height is negative', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
      expect(
        () => CapturedData(width: 1920, height: -100, bytes: bytes),
        throwsAssertionError,
      );
    });

    test('assertion fails when bytes is empty', () {
      final Uint8List bytes = Uint8List(0);
      expect(
        () => CapturedData(width: 1920, height: 1080, bytes: bytes),
        throwsAssertionError,
      );
    });

    test('fromMap creates instance from valid map', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final Map<Object?, Object?> map = <Object?, Object?>{
        'width': 1920,
        'height': 1080,
        'bytes': bytes,
      };

      final CapturedData data = CapturedData.fromMap(map);

      expect(data.width, equals(1920));
      expect(data.height, equals(1080));
      expect(data.bytes, equals(bytes));
    });

    test('toMap creates valid map from instance', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final CapturedData data = CapturedData(
        width: 1920,
        height: 1080,
        bytes: bytes,
      );

      final Map<String, dynamic> map = data.toMap();

      expect(map['width'], equals(1920));
      expect(map['height'], equals(1080));
      expect(map['bytes'], equals(bytes));
    });

    test('equality comparison works correctly', () {
      final Uint8List bytes1 = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final Uint8List bytes2 = Uint8List.fromList(<int>[1, 2, 3, 4]);

      final CapturedData data1 = CapturedData(
        width: 1920,
        height: 1080,
        bytes: bytes1,
      );

      final CapturedData data2 = CapturedData(
        width: 1920,
        height: 1080,
        bytes: bytes2,
      );

      expect(data1, equals(data2));
    });

    test('inequality when dimensions differ', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

      final CapturedData data1 = CapturedData(
        width: 1920,
        height: 1080,
        bytes: bytes,
      );

      final CapturedData data2 = CapturedData(
        width: 1280,
        height: 720,
        bytes: bytes,
      );

      expect(data1, isNot(equals(data2)));
    });

    test('inequality when bytes differ', () {
      final Uint8List bytes1 = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final Uint8List bytes2 = Uint8List.fromList(<int>[5, 6, 7, 8]);

      final CapturedData data1 = CapturedData(
        width: 1920,
        height: 1080,
        bytes: bytes1,
      );

      final CapturedData data2 = CapturedData(
        width: 1920,
        height: 1080,
        bytes: bytes2,
      );

      expect(data1, isNot(equals(data2)));
    });

    test('hashCode is consistent with equality', () {
      final Uint8List bytes1 = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final Uint8List bytes2 = Uint8List.fromList(<int>[1, 2, 3, 4]);

      final CapturedData data1 = CapturedData(
        width: 1920,
        height: 1080,
        bytes: bytes1,
      );

      final CapturedData data2 = CapturedData(
        width: 1920,
        height: 1080,
        bytes: bytes2,
      );

      expect(data1.hashCode, equals(data2.hashCode));
    });

    test('toString includes dimensions and byte count', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final CapturedData data = CapturedData(
        width: 1920,
        height: 1080,
        bytes: bytes,
      );

      final String str = data.toString();

      expect(str, contains('1920'));
      expect(str, contains('1080'));
      expect(str, contains('4 bytes'));
    });
  });
}
