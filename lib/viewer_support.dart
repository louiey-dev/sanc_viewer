import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Converts a fitted image's transform scale into its original-pixel scale.
double imageFitScale(Size image, Size viewport) =>
    image.isEmpty || viewport.isEmpty
    ? 1
    : math.min(viewport.width / image.width, viewport.height / image.height);

/// Debounces directory events and releases the previous folder on navigation.
class FolderMonitor {
  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _timer;
  int _generation = 0;

  void watch(String path, VoidCallback onChange) {
    stop();
    final generation = _generation;
    try {
      _subscription = Directory(path).watch().listen((_) {
        if (generation != _generation) return;
        _timer?.cancel();
        _timer = Timer(const Duration(milliseconds: 300), () {
          if (generation == _generation) onChange();
        });
      }, onError: (Object _) {});
    } on FileSystemException catch (_) {
      // Some network filesystems do not support directory notifications.
    }
  }

  void stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _subscription?.cancel();
    _subscription = null;
  }
}

/// A neutral checkerboard makes transparent pixels visible in either theme.
class TransparencyGrid extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    const cell = 12.0;
    final light = Paint()..color = const Color(0xFFE8E8E8);
    final dark = Paint()..color = const Color(0xFFBEBEBE);
    canvas.drawRect(Offset.zero & size, light);
    for (var y = 0.0, row = 0; y < size.height; y += cell, row++) {
      for (var x = (row.isEven ? 0.0 : cell); x < size.width; x += cell * 2) {
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(TransparencyGrid oldDelegate) => false;
}
