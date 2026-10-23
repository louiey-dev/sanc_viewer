import 'dart:io';
import 'dart:ui' as ui;

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
import 'pixel_image.dart';
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

  XFile? get _current => _files.isEmpty ? null : _files[_index];

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appSettingsProvider);
    _sidebarWidth = settings.sidebarWidth;
    _toolbarVisible = settings.toolbar;
    _isMaximized = settings.windowMaximized;
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
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

  Future<void> _loadFolder(String folder, {String? selectedPath}) async {
    final request = ++_folderRequest;
    try {
      final entries = await Directory(folder).list(followLinks: false).toList();
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
      final selected = images.indexWhere((file) => file.path == selectedPath);
      ++_request;
      setState(() {
        _folder = folder;
        _entries = entries;
        _files = images;
        _index = selected < 0 ? 0 : selected;
        _bytes = null;
        _dimensions = null;
        _details = const ImageDetails();
        _pixel.value = 'Pixel —';
        _error = null;
        _loading = false;
      });
      ref.read(appSettingsProvider).update(folder: folder, clearImage: true);
      if (images.isNotEmpty) await _select(_index);
    } catch (_) {
      if (request == _folderRequest) _folderError();
    }
  }

  Widget _entryTile(FileSystemEntity entry) {
    final directory = entry is Directory;
    final imageIndex = _files.indexWhere((file) => file.path == entry.path);
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: ListTile(
        selected: imageIndex >= 0 && imageIndex == _index,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(
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
    final bytes = _bytes;
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
          body: SafeArea(
            child: Column(
              children: [
                _titleBar(),
                if (_toolbarVisible) _toolbar(sidebar),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Row(
                      children: [
                        if (sidebar && constraints.maxWidth >= 640) ...[
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
                _statusBar(),
              ],
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
            onPressed: _bytes == null
                ? null
                : () => _transform.value = Matrix4.identity(),
            icon: Icon(Icons.fit_screen_rounded, size: 20),
            label: Text('Fit'),
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
                        leading: Icon(Icons.image_outlined, size: 20),
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
        ? InteractiveViewer(
            transformationController: _transform,
            minScale: 0.25,
            maxScale: 8,
            onInteractionUpdate: (_) => _pixel.value = 'Pixel —',
            child: PixelImage(
              key: ValueKey(_bytes),
              image: MemoryImage(_bytes!),
              onPixel: (value) => _pixel.value = value,
            ),
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
