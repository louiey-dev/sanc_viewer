import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'map_service.dart';

/// In-memory by default so widget tests never change the user's settings.
final appSettingsProvider = Provider<AppSettings>((ref) => AppSettings());

class AppSettings {
  AppSettings({this.file});

  final File? file;
  Map<String, dynamic> _values = {};

  static AppSettings load() {
    final base =
        Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return AppSettings.read(File('$base/SancViewer/settings.json'));
  }

  factory AppSettings.read(File file) {
    final settings = AppSettings(file: file);
    try {
      settings._values = Map<String, dynamic>.from(
        jsonDecode(file.readAsStringSync()) as Map,
      );
    } catch (_) {
      // Missing or damaged settings use the normal defaults.
    }
    return settings;
  }

  bool get thumbnails => _values['thumbnails'] == true;
  bool get checkerboard => _values['checkerboard'] != false;
  List<String> get recentFolders => (_values['recentFolders'] is List
      ? (_values['recentFolders'] as List).whereType<String>().take(10).toList()
      : <String>[]);

  void rememberFolder(String folder) {
    final previous = recentFolders.where(
      (item) => Platform.isWindows
          ? item.toLowerCase() != folder.toLowerCase()
          : item != folder,
    );
    _values['recentFolders'] = [folder, ...previous].take(10).toList();
    update();
  }

  void clearRecentFolders() {
    _values['recentFolders'] = <String>[];
    update();
  }

  bool get dark => _values['dark'] == true;
  MapService get mapService => MapService.values.firstWhere(
    (service) => service.name == _values['mapService'],
    orElse: () => MapService.google,
  );
  bool get windowMaximized => _values['windowMaximized'] == true;
  Size? get windowSize {
    final width = _values['windowWidth'];
    final height = _values['windowHeight'];
    if (width is! num ||
        height is! num ||
        !width.isFinite ||
        !height.isFinite ||
        width < 320 ||
        height < 240) {
      return null;
    }
    return Size(width.toDouble(), height.toDouble());
  }

  bool get toolbar =>
      _values['toolbar'] is bool ? _values['toolbar'] as bool : true;
  bool get sidebar =>
      _values['sidebar'] is bool ? _values['sidebar'] as bool : true;
  double get sidebarWidth {
    final value = _values['sidebarWidth'];
    return value is num && value.isFinite && value >= 200
        ? value.toDouble()
        : 236;
  }

  String? get folder =>
      _values['folder'] is String ? _values['folder'] as String : null;
  String? get image =>
      _values['image'] is String ? _values['image'] as String : null;

  void update({
    MapService? mapService,
    bool? dark,
    bool? thumbnails,
    bool? checkerboard,
    Size? windowSize,
    bool? windowMaximized,
    bool? sidebar,
    bool? toolbar,
    double? sidebarWidth,
    String? folder,
    String? image,
    bool clearImage = false,
  }) {
    if (mapService != null) _values['mapService'] = mapService.name;
    if (thumbnails != null) _values['thumbnails'] = thumbnails;
    if (checkerboard != null) _values['checkerboard'] = checkerboard;
    if (dark != null) _values['dark'] = dark;
    if (windowSize != null &&
        windowSize.width.isFinite &&
        windowSize.height.isFinite &&
        windowSize.width >= 320 &&
        windowSize.height >= 240) {
      _values['windowWidth'] = windowSize.width;
      _values['windowHeight'] = windowSize.height;
    }
    if (windowMaximized != null) _values['windowMaximized'] = windowMaximized;
    if (sidebar != null) _values['sidebar'] = sidebar;
    if (toolbar != null) _values['toolbar'] = toolbar;
    if (sidebarWidth != null) _values['sidebarWidth'] = sidebarWidth;
    if (folder != null) _values['folder'] = folder;
    if (clearImage) _values.remove('image');
    if (image != null) _values['image'] = image;
    try {
      final target = file;
      if (target == null) return;
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(jsonEncode(_values), flush: true);
    } on FileSystemException catch (_) {
      // A read-only settings directory must not prevent viewing images.
    }
  }
}
