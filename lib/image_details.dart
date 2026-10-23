import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter/painting.dart';

/// Capture metadata; absent tags are never replaced with file timestamps.
class ImageDetails {
  /// Creates optional capture information.
  const ImageDetails({this.dateTaken, this.location});
  final String? dateTaken;
  final String? location;
}

/// Converts validated EXIF degrees, minutes, and seconds to signed degrees.
double? gpsDegrees(
  List<double> values,
  String reference, {
  required bool latitude,
}) {
  if (values.length != 3 ||
      values.any((value) => !value.isFinite || value < 0)) {
    return null;
  }
  if (values[1] >= 60 || values[2] >= 60) return null;
  if (!(latitude ? ['N', 'S'] : ['E', 'W']).contains(reference)) return null;
  final degrees = values[0] + values[1] / 60 + values[2] / 3600;
  if (degrees > (latitude ? 90 : 180)) return null;
  return reference == 'S' || reference == 'W' ? -degrees : degrees;
}

/// Reads EXIF independently of image decoding, tolerating missing or damaged tags.
Future<ImageDetails> readImageDetails(Uint8List bytes) async {
  try {
    final tags = await readExifFromBytes(bytes, details: false);
    final date = tags['EXIF DateTimeOriginal']?.printable.trim();
    double? coordinate(String name, bool latitude) {
      final values = tags['GPS GPS$name']?.values.toList();
      if (values == null || values.any((value) => value is! Ratio)) return null;
      return gpsDegrees(
        values.cast<Ratio>().map((value) => value.toDouble()).toList(),
        tags['GPS GPS${name}Ref']?.printable.trim().toUpperCase() ?? '',
        latitude: latitude,
      );
    }

    final latitude = coordinate('Latitude', true);
    final longitude = coordinate('Longitude', false);
    return ImageDetails(
      dateTaken: date == null || date.isEmpty ? null : date,
      location: latitude == null || longitude == null
          ? null
          : '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
    );
  } catch (_) {
    return const ImageDetails();
  }
}

/// Samples straight RGBA pixels using coordinates within a centered fitted image.
String? pixelDescription(
  Uint8List rgba,
  Size imageSize,
  Size canvasSize,
  Offset position,
) {
  if (imageSize.isEmpty || canvasSize.isEmpty) return null;
  final fitted = applyBoxFit(BoxFit.contain, imageSize, canvasSize).destination;
  final rect = Alignment.center.inscribe(fitted, Offset.zero & canvasSize);
  if (!rect.contains(position)) return null;
  final column = ((position.dx - rect.left) * imageSize.width / rect.width)
      .floor();
  final row = ((position.dy - rect.top) * imageSize.height / rect.height)
      .floor();
  final offset = (row * imageSize.width.toInt() + column) * 4;
  if (offset < 0 || offset + 3 >= rgba.length) return null;
  final red = rgba[offset];
  final green = rgba[offset + 1];
  final blue = rgba[offset + 2];
  final hex = [red, green, blue]
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  return 'X:$column Y:$row · RGB($red, $green, $blue) · #$hex';
}
