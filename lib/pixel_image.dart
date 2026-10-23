import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'image_details.dart';

/// Displays and samples the same decoded frame, including animated images.
class PixelImage extends StatefulWidget {
  /// Creates a frame-synchronized image and pixel inspector.
  const PixelImage({super.key, required this.image, required this.onPixel});

  final ImageProvider image;
  final ValueChanged<String> onPixel;

  @override
  State<PixelImage> createState() => _PixelImageState();
}

class _PixelImageState extends State<PixelImage> {
  final _surfaceKey = GlobalKey();
  ImageStream? _stream;
  late final ImageStreamListener _listener;
  ImageInfo? _frame;
  ByteData? _pixels;
  Offset? _pointer;
  int _generation = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _listener = ImageStreamListener(
      _receiveFrame,
      onError: (Object error, StackTrace? stack) {
        if (mounted) setState(() => _failed = true);
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(PixelImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) _resolve();
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    ++_generation;
    _stream?.removeListener(_listener);
    _frame?.dispose();
    _frame = null;
    _pixels = null;
    _failed = false;
    _stream = stream;
    stream.addListener(_listener);
  }

  Future<void> _receiveFrame(ImageInfo frame, bool synchronousCall) async {
    final generation = ++_generation;
    ByteData? pixels;
    try {
      pixels = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
    } catch (_) {
      pixels = null;
    }
    if (!mounted || generation != _generation) {
      frame.dispose();
      return;
    }
    final previous = _frame;
    setState(() {
      _frame = frame;
      _pixels = pixels;
      _failed = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previous?.dispose();
      if (mounted && generation == _generation) _sample();
    });
  }

  void _sample() {
    final surface =
        _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    final pixels = _pixels;
    final frame = _frame;
    if (_pointer == null || surface == null || frame == null) {
      widget.onPixel('Pixel —');
      return;
    }
    if (pixels == null) {
      widget.onPixel('Pixel: Not available (pixel reading unsupported)');
      return;
    }
    widget.onPixel(
      pixelDescription(
            pixels.buffer.asUint8List(
              pixels.offsetInBytes,
              pixels.lengthInBytes,
            ),
            Size(frame.image.width.toDouble(), frame.image.height.toDouble()),
            surface.size,
            surface.globalToLocal(_pointer!),
          ) ??
          'Pixel —',
    );
  }

  @override
  void dispose() {
    ++_generation;
    _stream?.removeListener(_listener);
    _frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    key: _surfaceKey,
    onHover: (event) {
      _pointer = event.position;
      _sample();
    },
    onExit: (_) {
      _pointer = null;
      widget.onPixel('Pixel —');
    },
    child: SizedBox.expand(
      child: _failed
          ? const Center(child: Text('Unable to display this image.'))
          : RawImage(image: _frame?.image, fit: BoxFit.contain),
    ),
  );
}
