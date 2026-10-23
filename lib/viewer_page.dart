import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_clipboard/image_clipboard.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'app_info.dart';
import 'app_settings.dart';
import 'app_theme.dart';
import 'image_details.dart';
import 'image_playback.dart';
import 'viewer_support.dart';
import 'my_utils.dart';

final _sidebarProvider = NotifierProvider<_Sidebar, bool>(_Sidebar.new);
final startupImageProvider = Provider<String?>((ref) => null);

class _Sidebar extends Notifier<bool> {
  @override
  bool build() => ref.read(appSettingsProvider).sidebar;

  void toggle() {
    state = !state;
    ref.read(appSettingsProvider).update(sidebar: state);
  }
}

/// Main viewer with a collapsible explorer and image information strip.
class ViewerPage extends ConsumerStatefulWidget {
  /// Creates the viewer page.
  const ViewerPage({super.key});

  @override
  ConsumerState<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends ConsumerState<ViewerPage> with WindowListener {
  final _transform = TransformationController();
  double _sidebarWidth = 236;
  List<XFile> _files = [];
  List<FileSystemEntity> _entries = [];
  String? _folder;
  int _folderRequest = 0;
  int _index = 0;
  int _request = 0;
  Uint8List? _bytes;
  Size? _dimensions;
  ImageDetails _details = const ImageDetails();
  final _pixel = ValueNotifier<String>('Pixel —');
  bool _loading = false;
  String? _error;
  bool _hasCapture = false;
  bool _isMaximized = false;
  bool _toolbarVisible = true;
  bool _thumbnails = false;
  bool _checkerboard = true;
  bool _fullScreen = false;
  bool _dragging = false;
  bool _restoring = true;
  bool _openingFolder = false;
  final _folderMonitor = FolderMonitor();
  final _playback = ImagePlayback();
  Size _viewport = Size.zero;
  int _viewportRevision = 0;
  String? _selectedStamp;

  XFile? get _current => _files.isEmpty ? null : _files[_index];

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appSettingsProvider);
    _sidebarWidth = settings.sidebarWidth;
    _toolbarVisible = settings.toolbar;
    _isMaximized = settings.windowMaximized;
    _thumbnails = settings.thumbnails;
    _checkerboard = settings.checkerboard;
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_restoring) return;
      _restoring = false;
      final startupImage = ref.read(startupImageProvider);
      if (startupImage != null && _isImage(startupImage)) {
        final file = File(startupImage).absolute;
        if (await file.exists() && mounted) {
          await _loadFolder(file.parent.path, selectedPath: file.path);
          return;
        }
      }
      final folder = settings.folder;
      if (folder != null && await Directory(folder).exists() && mounted) {
        await _loadFolder(folder, selectedPath: settings.image);
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _folderMonitor.stop();
    _playback.dispose();
    _transform.dispose();
    _pixel.dispose();
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (!mounted) return;
    setState(() => _isMaximized = true);
    ref.read(appSettingsProvider).update(windowMaximized: true);
  }

  @override
  void onWindowUnmaximize() {
    if (!mounted) return;
    setState(() => _isMaximized = false);
    ref.read(appSettingsProvider).update(windowMaximized: false);
  }

  @override
  void onWindowResized() => _saveWindowSize();

  Future<void> _saveWindowSize() async {
    try {
      if (!mounted ||
          await windowManager.isMaximized() ||
          await windowManager.isMinimized() ||
          await windowManager.isFullScreen()) {
        return;
      }
      final size = await windowManager.getSize();
      if (!mounted || _isMaximized) return;
      ref.read(appSettingsProvider).update(windowSize: size);
    } catch (_) {
      // Window APIs may be unavailable outside the desktop runner.
    }
  }

  @override
  void onWindowFocus() => _refreshFolder();

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _fullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _fullScreen = false);
  }

  Future<void> _toggleFullScreen({bool exit = false}) async {
    try {
      final next = exit ? false : !_fullScreen;
      await windowManager.setFullScreen(next);
      if (mounted) setState(() => _fullScreen = next);
    } catch (error) {
      m.err('Fullscreen failed: $error');
    }
  }

  void _refreshFolder() {
    final folder = _folder;
    if (mounted && folder != null && !_openingFolder) {
      unawaited(
        _loadFolder(folder, selectedPath: _current?.path, refresh: true),
      );
    }
  }

  Future<void> _openDropped(List<String> paths) async {
    _restoring = false;
    for (final path in paths) {
      if (await Directory(path).exists()) {
        if (mounted) await _loadFolder(path);
        return;
      }
      if (_isImage(path) && await File(path).exists()) {
        if (mounted) {
          await _loadFolder(File(path).parent.path, selectedPath: path);
        }
        return;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drop a supported image or folder.')),
      );
    }
  }

  void _fit() => _transform.value = Matrix4.identity();

  void _actualSize() {
    final image = _dimensions;
    if (image == null || _viewport.isEmpty) return;
    final scale =
        1 /
        (imageFitScale(image, _viewport) * View.of(context).devicePixelRatio);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        (_viewport.width - _viewport.width * scale) / 2,
        (_viewport.height - _viewport.height * scale) / 2,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _setThumbnails(bool value) {
    setState(() => _thumbnails = value);
    ref.read(appSettingsProvider).update(thumbnails: value);
  }

  Widget _thumbnail(String path) => SizedBox(
    width: 48,
    height: 48,
    child: Image.file(
      File(path),
      key: ValueKey('thumbnail-$path-$_folderRequest'),
      cacheWidth: 96,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) =>
          const Icon(Icons.broken_image_outlined),
    ),
  );

  Future<void> _showContextMenu(Offset position, {String? path}) async {
    final target = path ?? _current?.path;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlay.globalToLocal(position);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        local & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        if (path != null)
          const PopupMenuItem(value: 'open', child: Text('Open')),
        if (_bytes != null && (path == null || _samePath(path, _current?.path)))
          const PopupMenuItem(value: 'copy', child: Text('Copy image')),
        if (target != null) ...[
          const PopupMenuItem(value: 'path', child: Text('Copy file path')),
          const PopupMenuItem(
            value: 'folder',
            child: Text('Open containing folder'),
          ),
        ],
        const PopupMenuItem(value: 'fit', child: Text('Fit to window')),
        const PopupMenuItem(value: 'actual', child: Text('Actual size (100%)')),
        const PopupMenuItem(
          value: 'fullscreen',
          child: Text('Toggle fullscreen'),
        ),
      ],
    );
    if (!mounted) return;
    try {
      switch (action) {
        case 'open':
          if (target != null) await _openDropped([target]);
        case 'copy':
          await _copyImage();
        case 'path':
          if (target != null) {
            await Clipboard.setData(ClipboardData(text: target));
          }
        case 'folder':
          if (target != null &&
              !await launchUrl(
                Uri.directory(File(target).parent.path),
                mode: LaunchMode.externalApplication,
              )) {
            throw StateError('Could not open the folder');
          }
        case 'fit':
          _fit();
        case 'actual':
          _actualSize();
        case 'fullscreen':
          await _toggleFullScreen();
      }
    } catch (error) {
      m.err('Context action failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not complete the selected action.'),
          ),
        );
      }
    }
  }

  Future<void> _saveFrame() async {
    try {
      final bytes = await _playback.png();
      if (bytes == null || !mounted) return;
      final location = await getSaveLocation(
        suggestedName: 'frame_${_playback.frame + 1}.png',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PNG image', extensions: ['png']),
        ],
      );
      if (location != null) {
        await File(location.path).writeAsBytes(bytes, flush: true);
      }
    } catch (error) {
      m.err('Save frame failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the current frame.')),
        );
      }
    }
  }

  Future<void> _open() async {
    try {
      final files = await openFiles(
        acceptedTypeGroups: [
          XTypeGroup(
            label: 'Images',
            extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'ico'],
          ),
        ],
      );
      if (!mounted || files.isEmpty) return;
      if (!kIsWeb) {
        await _loadFolder(
          File(files.first.path).parent.path,
          selectedPath: files.first.path,
        );
        return;
      }
      files.sort(
        (first, second) =>
            first.name.toLowerCase().compareTo(second.name.toLowerCase()),
      );
      setState(() {
        _files = files;
        _index = 0;
      });
      await _select(0);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open the file picker. Please try again.'),
        ),
      );
    }
  }

  Future<void> _associateFiles() async {
    try {
      await const MethodChannel(
        'sanc_viewer/file_associations',
      ).invokeMethod<void>('register');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Image formats registered. Select Sanc Viewer in Windows Default apps to finish.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is PlatformException
                ? error.message ?? 'Could not register image formats.'
                : 'Could not register image formats.',
          ),
        ),
      );
    }
  }

  bool _isImage(String path) => [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'ico',
  ].contains(path.split('.').last.toLowerCase());

  String _name(String path) => path.replaceAll('\\', '/').split('/').last;

  bool _samePath(String first, String? second) {
    if (second == null) return false;
    String normalized(String path) {
      final value = File(path).absolute.uri.normalizePath().toFilePath();
      return Platform.isWindows ? value.toLowerCase() : value;
    }

    return normalized(first) == normalized(second);
  }

  Future<void> _openFolder() async {
    try {
      final folder = await getDirectoryPath();
      if (!mounted || folder == null) return;
      await _loadFolder(folder);
    } catch (_) {
      _folderError();
    }
  }

  void _folderError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not read this folder. Check access permissions.'),
      ),
    );
  }

  Future<void> _loadFolder(
    String folder, {
    String? selectedPath,
    bool refresh = false,
  }) async {
    _restoring = false;
    if (!refresh) {
      _openingFolder = true;
      _folderMonitor.stop();
    }
    final request = ++_folderRequest;
    try {
      final entries =
          (await Directory(folder).list(followLinks: false).toList())
              .where(
                (entry) =>
                    entry is Directory ||
                    (entry is File && _isImage(entry.path)),
              )
              .toList();
      entries.sort((first, second) {
        if ((first is Directory) != (second is Directory)) {
          return first is Directory ? -1 : 1;
        }
        return _name(
          first.path,
        ).toLowerCase().compareTo(_name(second.path).toLowerCase());
      });
      if (!mounted || request != _folderRequest) return;
      final images = entries
          .whereType<File>()
          .where((file) => _isImage(file.path))
          .map((file) => XFile(file.path))
          .toList();
      final selected = images.indexWhere(
        (file) => _samePath(file.path, selectedPath),
      );
      final currentPath = _current?.path;
      String? stamp;
      if (selected >= 0) {
        final stat = await File(images[selected].path).stat();
        stamp = '${stat.modified.microsecondsSinceEpoch}:${stat.size}';
      }
      if (!mounted || request != _folderRequest) return;
      final preserve =
          refresh &&
          (_hasCapture ||
              (selected >= 0 &&
                  _samePath(images[selected].path, currentPath) &&
                  stamp == _selectedStamp &&
                  _bytes != null));
      if (refresh && _thumbnails) {
        for (final file in images) {
          await ResizeImage.resizeIfNeeded(
            96,
            null,
            FileImage(File(file.path)),
          ).evict();
        }
      }
      if (!mounted || request != _folderRequest) return;
      if (!preserve) ++_request;
      setState(() {
        _folder = folder;
        _entries = entries;
        _files = images;
        _index = selected < 0 ? 0 : selected;
        if (!preserve) {
          _bytes = null;
          _dimensions = null;
          _details = const ImageDetails();
          _pixel.value = 'Pixel ?';
          _error = null;
          _loading = false;
          _hasCapture = false;
        }
      });
      final settings = ref.read(appSettingsProvider);
      if (!refresh) {
        settings.rememberFolder(folder);
        _folderMonitor.watch(folder, _refreshFolder);
      }
      if (!preserve) {
        settings.update(folder: folder, clearImage: true);
        if (images.isNotEmpty) await _select(_index);
      }
    } catch (_) {
      if (mounted && request == _folderRequest) {
        if (!refresh) {
          _folderError();
          if (_folder != null) _folderMonitor.watch(_folder!, _refreshFolder);
        }
      }
    } finally {
      if (!refresh && request == _folderRequest) _openingFolder = false;
    }
  }

  Widget _entryTile(FileSystemEntity entry) {
    final directory = entry is Directory;
    final imageIndex = _files.indexWhere(
      (file) => _samePath(file.path, entry.path),
    );
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(details.globalPosition, path: entry.path),
      child: Padding(
        padding: EdgeInsets.only(bottom: 4),
        child: ListTile(
          selected: imageIndex >= 0 && imageIndex == _index,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          leading: _thumbnails && imageIndex >= 0
              ? _thumbnail(entry.path)
              : Icon(
                  directory
                      ? Icons.folder_outlined
                      : imageIndex >= 0
                      ? Icons.image_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 20,
                ),
          title: Text(
            _name(entry.path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12),
          ),
          onTap: directory
              ? () => _loadFolder(entry.path)
              : imageIndex >= 0
              ? () => _select(imageIndex)
              : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('This file is not a supported image.'),
                    ),
                  );
                },
        ),
      ),
    );
  }

  Future<void> _select(int index) async {
    if (index < 0 || index >= _files.length) return;
    final request = ++_request;
    final file = _files[index];
    ref.read(appSettingsProvider).update(image: file.path);
    setState(() {
      _index = index;
      _loading = true;
      _error = null;
      _bytes = null;
      _dimensions = null;
      _hasCapture = false;
      _details = const ImageDetails();
      _pixel.value = 'Pixel —';
    });
    try {
      final bytes = await file.readAsBytes();
      final stat = await File(file.path).stat();
      final codec = await ui.instantiateImageCodec(bytes);
      late final Size dimensions;
      try {
        final frame = await codec.getNextFrame();
        dimensions = Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (!mounted || request != _request) return;
      _transform.value = Matrix4.identity();
      setState(() {
        _bytes = bytes;
        _selectedStamp = '${stat.modified.microsecondsSinceEpoch}:${stat.size}';
        _dimensions = dimensions;
        _pixel.value = 'Pixel —';
        _loading = false;
      });
      final details = await compute(readImageDetails, bytes);
      if (!mounted || request != _request) return;
      setState(() => _details = details);
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error =
            'This image could not be decoded.\nTry a different image or format.';
      });
    }
  }

  Future<void> _capture(CaptureMode mode) async {
    final temporaryPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'sanc_capture_${DateTime.now().microsecondsSinceEpoch}.png';
    CapturedData? captured;
    Object? captureError;
    try {
      captured = await screenCapturer.capture(
        mode: mode,
        imagePath: temporaryPath,
        copyToClipboard: false,
        silent: false,
      );
    } catch (error) {
      captureError = error;
    }
    try {
      Uint8List? bytes = captured?.imageBytes;
      final temporaryFile = File(temporaryPath);
      for (var attempt = 0; bytes == null && attempt < 5; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        if (temporaryFile.existsSync()) {
          bytes = await temporaryFile.readAsBytes();
        }
        if (bytes == null) {
          try {
            bytes = await screenCapturer.readImageFromClipboard();
          } catch (error) {
            captureError ??= error;
          }
        }
      }
      if (!mounted) return;
      if (bytes == null) {
        m.err('Capture failed: $captureError');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Capture failed. Please try again.')),
        );
        return;
      }
      final decoded = await ui.instantiateImageCodec(bytes);
      final frame = await decoded.getNextFrame();
      final dimensions = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      decoded.dispose();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _dimensions = dimensions;
        _hasCapture = true;
        _error = null;
        _loading = false;
        _pixel.value = 'Pixel —';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Capture ready. Use Save to export the PNG.'),
        ),
      );
    } catch (error) {
      m.err('Capture result processing failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capture failed. Please try again.')),
      );
    } finally {
      final temporaryFile = File(temporaryPath);
      if (temporaryFile.existsSync()) await temporaryFile.delete();
    }
  }

  Future<void> _copyImage() async {
    final bytes = await _playback.png() ?? _bytes;
    if (!mounted) return;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open an image before copying.')),
      );
      return;
    }
    final temporaryPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'sanc_clipboard_${DateTime.now().microsecondsSinceEpoch}.png';
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      late final Uint8List pngBytes;
      try {
        final frame = await codec.getNextFrame();
        try {
          final pngData = await frame.image.toByteData(
            format: Platform.isWindows
                ? ui.ImageByteFormat.rawStraightRgba
                : ui.ImageByteFormat.png,
          );
          if (pngData == null) throw StateError('Could not encode image');
          pngBytes = pngData.buffer.asUint8List();
          if (Platform.isWindows) {
            await const MethodChannel(
              'sanc_viewer/clipboard',
            ).invokeMethod<void>('copyImage', {
              'width': frame.image.width,
              'height': frame.image.height,
              'rgba': pngBytes,
            });
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      if (!Platform.isWindows) {
        await File(temporaryPath).writeAsBytes(pngBytes, flush: true);
        await ImageClipboard().copyImage(temporaryPath);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image copied to clipboard.')),
      );
    } catch (error) {
      m.err('Copy image failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not copy the image.')),
      );
    } finally {
      final temporaryFile = File(temporaryPath);
      if (temporaryFile.existsSync()) await temporaryFile.delete();
    }
  }

  Future<void> _saveCapture() async {
    if (!_hasCapture || _bytes == null) return;
    try {
      final now = DateTime.now();
      String twoDigits(int value) => value.toString().padLeft(2, '0');
      final fileName =
          'sanc_viewer_${now.year}${twoDigits(now.month)}'
          '${twoDigits(now.day)}_${twoDigits(now.hour)}${twoDigits(now.minute)}'
          '${twoDigits(now.second)}.png';
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          XTypeGroup(label: 'PNG image', extensions: ['png']),
        ],
      );
      if (location == null) return;
      await File(location.path).writeAsBytes(_bytes!, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved capture to ${location.path}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the capture.')),
      );
    }
  }

  void _showInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About sanc_viewer'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appName),
            SizedBox(height: 8),
            Text('Version $appVersion (build $appBuildNumber)'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sidebar = ref.watch(_sidebarProvider);
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyO, control: true): _open,
        SingleActivator(LogicalKeyboardKey.f11): _toggleFullScreen,
        SingleActivator(LogicalKeyboardKey.escape): () {
          if (_fullScreen) _toggleFullScreen(exit: true);
        },
        SingleActivator(LogicalKeyboardKey.digit1, control: true): _actualSize,
        SingleActivator(LogicalKeyboardKey.digit0, control: true): _fit,
        SingleActivator(LogicalKeyboardKey.space): () {
          if (_playback.frameCount > 1) _playback.toggle();
        },
        SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _select(_index - 1),
        SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _select(_index + 1),
        SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveCapture,
        SingleActivator(
          LogicalKeyboardKey.keyC,
          control: true,
          shift: true,
        ): () =>
            _capture(CaptureMode.region),
        SingleActivator(LogicalKeyboardKey.keyC, control: true): _copyImage,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (details) {
              setState(() => _dragging = false);
              unawaited(
                _openDropped(details.files.map((file) => file.path).toList()),
              );
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: _dragging
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      )
                    : null,
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    if (!_fullScreen) _titleBar(),
                    if (_toolbarVisible && !_fullScreen) _toolbar(sidebar),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => Row(
                          children: [
                            if (sidebar &&
                                !_fullScreen &&
                                constraints.maxWidth >= 640) ...[
                              _sidebar(
                                _sidebarWidth.clamp(
                                  200,
                                  _maxSidebarWidth(constraints.maxWidth),
                                ),
                              ),
                              _sidebarResizeHandle(constraints.maxWidth),
                            ],
                            Expanded(child: _canvas()),
                          ],
                        ),
                      ),
                    ),
                    if (!_fullScreen) _statusBar(),
                    if (_fullScreen)
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: 'Exit fullscreen (Esc)',
                          onPressed: () => _toggleFullScreen(exit: true),
                          icon: const Icon(Icons.fullscreen_exit),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _titleBar() => Container(
    height: 44,
    color: Theme.of(context).colorScheme.surface,
    padding: const EdgeInsets.only(left: 12, right: 8),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          if (constraints.maxWidth >= 560) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.filter_frames_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Text(
              'sanc',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 4),
            Text(
              'viewer',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 20),
          ],
          if (constraints.maxWidth >= 560)
            Expanded(
              child: DragToMoveArea(
                child: Tooltip(
                  message: _current?.path ?? 'No image selected',
                  child: Text(
                    _current?.path ?? 'Your images, a little closer.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 4),
          IconButton(
            tooltip: _toolbarVisible ? 'Hide toolbar' : 'Show toolbar',
            onPressed: () {
              setState(() => _toolbarVisible = !_toolbarVisible);
              ref.read(appSettingsProvider).update(toolbar: _toolbarVisible);
            },
            icon: Icon(
              _toolbarVisible ? Icons.expand_less : Icons.expand_more,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: 'Minimize',
            onPressed: windowManager.minimize,
            icon: const Icon(Icons.remove, size: 16),
          ),
          IconButton(
            tooltip: _isMaximized ? 'Restore' : 'Maximize',
            onPressed: () async {
              if (_isMaximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
            icon: Icon(
              _isMaximized ? Icons.filter_none : Icons.crop_square,
              size: 16,
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: windowManager.close,
            icon: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    ),
  );

  Widget _toolbar(bool sidebar) => Container(
    height: 58,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.symmetric(
        horizontal: BorderSide(color: Theme.of(context).dividerColor),
      ),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            tooltip: sidebar ? 'Hide sidebar' : 'Show sidebar',
            onPressed: () => ref.read(_sidebarProvider.notifier).toggle(),
            icon: Icon(Icons.view_sidebar_outlined, size: 20),
          ),
          SizedBox(width: 8),
          MenuAnchor(
            menuChildren: [
              if (!kIsWeb)
                MenuItemButton(
                  onPressed: _openFolder,
                  child: Text('Open folder…'),
                ),
              MenuItemButton(
                onPressed: _open,
                child: Text('Open images…    Ctrl+O'),
              ),
              SubmenuButton(
                menuChildren: [
                  if (ref.watch(appSettingsProvider).recentFolders.isEmpty)
                    const MenuItemButton(child: Text('No recent folders')),
                  for (final path
                      in ref.watch(appSettingsProvider).recentFolders)
                    MenuItemButton(
                      onPressed: () => _loadFolder(path),
                      child: Text(path),
                    ),
                  const Divider(),
                  MenuItemButton(
                    onPressed: () {
                      setState(
                        () =>
                            ref.read(appSettingsProvider).clearRecentFolders(),
                      );
                    },
                    child: const Text('Clear recent folders'),
                  ),
                ],
                child: const Text('Recent folders'),
              ),
              const Divider(),
              SubmenuButton(
                menuChildren: [
                  for (final thumbnails in [false, true])
                    MenuItemButton(
                      leadingIcon: Icon(
                        _thumbnails == thumbnails
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      onPressed: () {
                        _setThumbnails(thumbnails);
                      },
                      child: Text(thumbnails ? 'Thumbnails' : 'Files'),
                    ),
                ],
                child: const Text('Sidebar view'),
              ),
              MenuItemButton(
                leadingIcon: Icon(
                  _checkerboard
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                ),
                onPressed: () {
                  setState(() => _checkerboard = !_checkerboard);
                  ref
                      .read(appSettingsProvider)
                      .update(checkerboard: _checkerboard);
                },
                child: const Text('Transparency checkerboard'),
              ),
              MenuItemButton(
                onPressed: _toggleFullScreen,
                child: const Text('Fullscreen    F11'),
              ),
              const Divider(),
              if (Platform.isWindows)
                MenuItemButton(
                  leadingIcon: const Icon(Icons.link),
                  onPressed: _associateFiles,
                  child: const Text('File associations'),
                ),
              MenuItemButton(
                leadingIcon: Icon(
                  ref.watch(themeModeProvider) == ThemeMode.light
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                onPressed: () => ref
                    .read(themeModeProvider.notifier)
                    .setMode(ThemeMode.light),
                child: const Text('Light mode'),
              ),
              MenuItemButton(
                leadingIcon: Icon(
                  ref.watch(themeModeProvider) == ThemeMode.dark
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                onPressed: () => ref
                    .read(themeModeProvider.notifier)
                    .setMode(ThemeMode.dark),
                child: const Text('Dark mode'),
              ),
              const Divider(),
              MenuItemButton(onPressed: _showInfo, child: const Text('Info')),
            ],
            builder: (context, controller, child) => TextButton.icon(
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              icon: Icon(Icons.folder_open_rounded, size: 19),
              label: Text('File'),
            ),
          ),
          SizedBox(height: 22, child: VerticalDivider(width: 28)),
          IconButton(
            tooltip: 'Previous image',
            onPressed: _index > 0 ? () => _select(_index - 1) : null,
            icon: Icon(Icons.chevron_left_rounded),
          ),
          SizedBox(
            width: 62,
            child: Text(
              _files.isEmpty ? '0 / 0' : '${_index + 1} / ${_files.length}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: 'Next image',
            onPressed: _index + 1 < _files.length
                ? () => _select(_index + 1)
                : null,
            icon: Icon(Icons.chevron_right_rounded),
          ),
          SizedBox(height: 22, child: VerticalDivider(width: 28)),
          TextButton.icon(
            onPressed: _bytes == null ? null : _fit,
            icon: Icon(Icons.fit_screen_rounded, size: 20),
            label: Text('Fit'),
          ),
          TextButton(
            onPressed: _bytes == null ? null : _actualSize,
            child: const Text('100%'),
          ),
          ListenableBuilder(
            listenable: _transform,
            builder: (context, child) {
              final scale = _dimensions == null
                  ? 1.0
                  : imageFitScale(_dimensions!, _viewport) *
                        View.of(context).devicePixelRatio *
                        _transform.value.getMaxScaleOnAxis();
              return SizedBox(
                width: 64,
                child: Text(
                  _bytes == null ? '?' : '${(scale * 100).toStringAsFixed(0)}%',
                  key: const ValueKey('zoom-percentage'),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
          ListenableBuilder(
            listenable: _playback,
            builder: (context, child) =>
                _bytes == null || _playback.frameCount < 2
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous frame',
                        onPressed: () => _playback.step(-1),
                        icon: const Icon(Icons.skip_previous),
                      ),
                      IconButton(
                        tooltip: _playback.playing
                            ? 'Pause animation'
                            : 'Play animation',
                        onPressed: _playback.toggle,
                        icon: Icon(
                          _playback.playing ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                      Text('${_playback.frame + 1}/${_playback.frameCount}'),
                      IconButton(
                        tooltip: 'Next frame',
                        onPressed: () => _playback.step(1),
                        icon: const Icon(Icons.skip_next),
                      ),
                      IconButton(
                        tooltip: 'Save current frame',
                        onPressed: _saveFrame,
                        icon: const Icon(Icons.save_alt),
                      ),
                    ],
                  ),
          ),
          SizedBox(width: 12),
          Tooltip(
            message: 'Capture region, screen, or window',
            child: MenuAnchor(
              menuChildren: [
                MenuItemButton(
                  onPressed: () => _capture(CaptureMode.region),
                  child: Text('Capture region'),
                ),
                MenuItemButton(
                  onPressed: () => _capture(CaptureMode.window),
                  child: Text('Capture window'),
                ),
                MenuItemButton(
                  onPressed: () => _capture(CaptureMode.screen),
                  child: Text('Capture screen'),
                ),
              ],
              builder: (context, controller, child) => OutlinedButton.icon(
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                icon: Icon(Icons.crop_free_rounded, size: 18),
                label: Text('Capture'),
              ),
            ),
          ),
          if (_hasCapture) ...[
            SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _saveCapture,
              icon: Icon(Icons.save_alt_rounded, size: 18),
              label: Text('Save'),
            ),
          ],
        ],
      ),
    ),
  );

  double _maxSidebarWidth(double availableWidth) =>
      (availableWidth - 328).clamp(200, 480);

  Widget _sidebarResizeHandle(double availableWidth) => MouseRegion(
    cursor: SystemMouseCursors.resizeLeftRight,
    child: GestureDetector(
      key: const ValueKey('sidebar-resize-handle'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (_) =>
          ref.read(appSettingsProvider).update(sidebarWidth: _sidebarWidth),
      onHorizontalDragUpdate: (details) {
        final maximum = _maxSidebarWidth(availableWidth);
        setState(() {
          _sidebarWidth = (_sidebarWidth.clamp(200, maximum) + details.delta.dx)
              .clamp(200, maximum);
        });
      },
      child: Tooltip(
        message: 'Drag to resize sidebar',
        child: SizedBox(
          width: 8,
          height: double.infinity,
          child: Center(
            child: Container(
              width: 2,
              height: 28,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _sidebar(double width) {
    final path = _current?.path.replaceAll('\\', '/');
    final folder =
        _folder ??
        (path != null && path.contains('/')
            ? path.substring(0, path.lastIndexOf('/'))
            : 'No folder selected');
    return Container(
      key: const ValueKey('explorer-sidebar'),
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'EXPLORER',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.7,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _thumbnails ? 'Show file list' : 'Show thumbnails',
                  onPressed: () => _setThumbnails(!_thumbnails),
                  icon: Icon(
                    _thumbnails
                        ? Icons.view_list_outlined
                        : Icons.grid_view_outlined,
                    size: 18,
                  ),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  padding: EdgeInsets.zero,
                ),
                Text(
                  '${_folder == null ? _files.length : _entries.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: folder,
                    child: Text(
                      folder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 18),
          if (_folder != null)
            ListTile(
              dense: true,
              leading: Icon(Icons.drive_folder_upload_outlined, size: 18),
              title: Text('Parent folder', style: TextStyle(fontSize: 12)),
              onTap: Directory(_folder!).parent.path == _folder
                  ? null
                  : () => _loadFolder(Directory(_folder!).parent.path),
            ),
          Expanded(
            child: _folder != null
                ? _entries.isEmpty
                      ? Center(child: Text('This folder is empty.'))
                      : ListView.builder(
                          itemCount: _entries.length,
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          itemBuilder: (context, index) =>
                              _entryTile(_entries[index]),
                        )
                : _files.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Opened images will appear here.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _files.length,
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    itemBuilder: (context, index) => Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        selected: _index == index,
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        leading: _thumbnails
                            ? _thumbnail(_files[index].path)
                            : Icon(Icons.image_outlined, size: 20),
                        title: Text(
                          _files[index].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12),
                        ),
                        onTap: () => _select(index),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: kIsWeb ? _open : _openFolder,
              icon: Icon(Icons.add, size: 16),
              label: Text(kIsWeb ? 'Open images' : 'Open folder'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _canvas() => Padding(
    padding: EdgeInsets.all(24),
    child: _loading
        ? Center(child: CircularProgressIndicator(strokeWidth: 2))
        : _bytes != null
        ? LayoutBuilder(
            builder: (context, constraints) {
              final viewport = constraints.biggest;
              if (_viewport != viewport) {
                _viewport = viewport;
                final revision = ++_viewportRevision;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && revision == _viewportRevision) setState(() {});
                });
              }
              final fitted = _dimensions == null
                  ? Size.zero
                  : applyBoxFit(
                      BoxFit.contain,
                      _dimensions!,
                      viewport,
                    ).destination;
              return GestureDetector(
                onSecondaryTapDown: (details) =>
                    _showContextMenu(details.globalPosition),
                child: InteractiveViewer(
                  transformationController: _transform,
                  minScale: 0.00001,
                  maxScale: 256,
                  onInteractionUpdate: (_) => _pixel.value = 'Pixel ?',
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_checkerboard)
                        Center(
                          child: SizedBox(
                            width: fitted.width,
                            height: fitted.height,
                            child: CustomPaint(painter: TransparencyGrid()),
                          ),
                        ),
                      PlaybackImage(
                        key: ValueKey(_bytes),
                        bytes: _bytes!,
                        playback: _playback,
                        onPixel: (value) => _pixel.value = value,
                      ),
                    ],
                  ),
                ),
              );
            },
          )
        : Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Icon(
                      _error == null
                          ? Icons.landscape_outlined
                          : Icons.broken_image_outlined,
                      size: 36,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  SizedBox(height: 24),
                  Text(
                    _error == null
                        ? 'A clear view of every detail.'
                        : 'Unable to open image',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.6,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    _error ?? 'Open an image and make yourself at home.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                  SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _open,
                    icon: Icon(Icons.folder_open_rounded, size: 18),
                    label: Text('Open images'),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'JPG  ·  PNG  ·  WEBP  ·  BMP  ·  GIF',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
  );

  Widget _statusBar() => Container(
    height: 38,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          _detail(
            Icons.photo_size_select_large_outlined,
            _dimensions == null
                ? 'Dimensions —'
                : '${_dimensions!.width.toInt()} × ${_dimensions!.height.toInt()} px',
          ),
          _detail(
            Icons.data_usage_outlined,
            _bytes == null
                ? 'Size —'
                : '${(_bytes!.length / 1024).toStringAsFixed(1)} KB',
          ),
          _detail(
            Icons.image_outlined,
            _current == null
                ? 'Format —'
                : _current!.name.split('.').last.toUpperCase(),
          ),
          ValueListenableBuilder<String>(
            valueListenable: _pixel,
            builder: (context, value, child) =>
                _detail(Icons.colorize_outlined, value),
          ),
          _detail(
            Icons.schedule_outlined,
            'Date taken: ${_details.dateTaken ?? 'Not available'}',
          ),
          if (_details.location == null)
            _detail(Icons.location_on_outlined, 'Location: Not available')
          else
            Tooltip(
              message: 'Open in Google Maps',
              child: TextButton.icon(
                onPressed: _openLocation,
                icon: const Icon(Icons.location_on_outlined, size: 14),
                label: Text(
                  'Location: ${_details.location}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _openLocation() async {
    final location = _details.location;
    if (location == null) return;
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': location,
    });
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open Google Maps. Please check your browser.'),
      ),
    );
  }

  Widget _detail(IconData icon, String text) => Padding(
    padding: EdgeInsets.only(right: 24),
    child: Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        SizedBox(width: 7),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
