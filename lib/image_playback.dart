import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'pixel_image.dart';
import 'my_utils.dart';

/// Playback state and commands for an animated image's displayed frame.
class ImagePlayback extends ChangeNotifier {
  int frameCount = 1;
  int frame = 0;
  bool playing = true;
  VoidCallback? _toggle;
  ValueChanged<int>? _step;
  ui.Image? _image;

  /// Notifies playback controls after a displayed frame changes.
  void changed() => notifyListeners();

  /// Pauses or resumes playback.
  void toggle() => _toggle?.call();

  /// Pauses and moves by [delta] frames, wrapping at either end.
  void step(int delta) => _step?.call(delta);

  /// Exports a snapshot of the displayed frame with its transparency.
  Future<Uint8List?> png() async {
    final image = _image?.clone();
    if (image == null) return null;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  void _release() {
    _toggle = null;
    _step = null;
    _image?.dispose();
    _image = null;
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }
}

class _FrameStream extends ImageStreamCompleter {
  void emit(ui.Image image) => setImage(ImageInfo(image: image));
}

class _FrameProvider extends ImageProvider<_FrameProvider> {
  _FrameProvider(this.stream);
  final _FrameStream stream;

  @override
  Future<_FrameProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    _FrameProvider key,
    ImageErrorListener handleError,
  ) => stream.setCompleter(this.stream);
}

/// Decodes only the current animation frame and supports pause and stepping.
class PlaybackImage extends StatefulWidget {
  const PlaybackImage({
    super.key,
    required this.bytes,
    required this.playback,
    required this.onPixel,
  });
  final Uint8List bytes;
  final ImagePlayback playback;
  final ValueChanged<String> onPixel;

  @override
  State<PlaybackImage> createState() => _PlaybackImageState();
}

class _PlaybackImageState extends State<PlaybackImage> {
  late final _FrameProvider _provider;
  ui.Codec? _codec;
  Timer? _timer;
  Future<void> _queue = Future.value();
  int _frame = -1;
  int _loops = 0;
  Duration _duration = const Duration(milliseconds: 100);
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _provider = _FrameProvider(_FrameStream());
    widget.playback._image?.dispose();
    widget.playback._image = null;
    widget.playback.frameCount = 1;
    widget.playback.frame = 0;
    widget.playback.playing = false;
    widget.playback._toggle = _toggle;
    widget.playback._step = _step;
    _queue = _load();
  }

  Future<void> _load() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      if (!mounted) {
        codec.dispose();
        return;
      }
      _codec = codec;
      widget.playback.frameCount = codec.frameCount;
      widget.playback.playing = codec.frameCount > 1;
      await _decode();
      _schedule();
    } catch (error, stack) {
      _decodeFailed(error, stack);
    }
  }

  void _decodeFailed(Object error, StackTrace stack) {
    if (!mounted) return;
    _timer?.cancel();
    setState(() => _failed = true);
    widget.playback.playing = false;
    widget.playback.changed();
    m.err('Animation decode failed: $error');
  }

  Future<void> _decode() async {
    final codec = _codec;
    if (!mounted || codec == null) return;
    final next = await codec.getNextFrame();
    if (!mounted) {
      next.image.dispose();
      return;
    }
    _frame = (_frame + 1) % codec.frameCount;
    _duration = next.duration > Duration.zero
        ? next.duration
        : const Duration(milliseconds: 100);
    final playback = widget.playback;
    playback._image?.dispose();
    playback._image = next.image.clone();
    playback.frame = _frame;
    _provider.stream.emit(next.image);
    playback.changed();
  }

  void _schedule() {
    _timer?.cancel();
    final codec = _codec;
    if (!mounted ||
        codec == null ||
        !widget.playback.playing ||
        codec.frameCount < 2) {
      return;
    }
    if (_frame == codec.frameCount - 1 &&
        codec.repetitionCount >= 0 &&
        _loops >= codec.repetitionCount) {
      widget.playback.playing = false;
      widget.playback.changed();
      return;
    }
    _timer = Timer(_duration, () {
      _queue = _queue
          .then<void>((_) async {
            if (!mounted || !widget.playback.playing) return;
            if (_frame == codec.frameCount - 1) _loops++;
            await _decode();
            _schedule();
          })
          .catchError(_decodeFailed);
    });
  }

  void _toggle() {
    widget.playback.playing = !widget.playback.playing;
    _loops = 0;
    widget.playback.changed();
    _schedule();
  }

  void _step(int delta) {
    _timer?.cancel();
    widget.playback.playing = false;
    widget.playback.changed();
    _queue = _queue
        .then<void>((_) async {
          if (!mounted || _codec == null) return;
          final target = (_frame + delta) % _codec!.frameCount;
          if (target <= _frame) {
            final codec = await ui.instantiateImageCodec(widget.bytes);
            if (!mounted) {
              codec.dispose();
              return;
            }
            _codec?.dispose();
            _codec = codec;
            _frame = -1;
          }
          while (mounted && _frame != target) {
            await _decode();
          }
        })
        .catchError(_decodeFailed);
  }

  @override
  void dispose() {
    _timer?.cancel();
    // An in-flight decoder finishes before its native codec is released.
    final codec = _codec;
    _queue.whenComplete(() => codec?.dispose());
    if (widget.playback._toggle == _toggle) widget.playback._release();
    PaintingBinding.instance.imageCache.evict(_provider);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _failed
      ? const Center(child: Text('Unable to display this image.'))
      : PixelImage(image: _provider, onPixel: widget.onPixel);
}
