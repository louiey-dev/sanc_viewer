import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanc_viewer/app_settings.dart';

void main() {
  test('Window size survives maximization and rejects invalid dimensions', () {
    final directory = Directory.systemTemp.createTempSync('sanc_window_test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/settings.json');
    final settings = AppSettings.read(file);
    expect(settings.windowSize, isNull);
    settings.update(windowSize: const Size(1024, 768));
    settings.update(windowMaximized: true);
    final restored = AppSettings.read(file);
    expect(restored.windowSize, const Size(1024, 768));
    expect(restored.windowMaximized, isTrue);
    restored.update(windowSize: const Size(0, 0));
    expect(AppSettings.read(file).windowSize, const Size(1024, 768));
    file.writeAsStringSync('{"windowWidth":"bad","windowHeight":-1}');
    expect(AppSettings.read(file).windowSize, isNull);
  });

  test('Settings survive reload including empty-folder selection', () {
    final directory = Directory.systemTemp.createTempSync('sanc_settings_test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/settings.json');
    final settings = AppSettings.read(file);
    settings.update(
      dark: true,
      sidebar: false,
      sidebarWidth: 310,
      folder: 'C:/사진',
      image: 'C:/사진/image.png',
    );
    final restored = AppSettings.read(file);
    expect(restored.dark, isTrue);
    expect(restored.sidebar, isFalse);
    expect(restored.sidebarWidth, 310);
    expect(restored.folder, 'C:/사진');
    expect(restored.image, 'C:/사진/image.png');
    restored.update(folder: 'C:/empty', clearImage: true);
    expect(AppSettings.read(file).image, isNull);
    expect(AppSettings.read(file).folder, 'C:/empty');
  });

  test('Damaged settings fall back to defaults', () {
    final directory = Directory.systemTemp.createTempSync('sanc_settings_test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/settings.json')
      ..writeAsStringSync('{');
    final settings = AppSettings.read(file);
    expect(settings.dark, isFalse);
    expect(settings.sidebar, isTrue);
    expect(settings.sidebarWidth, 236);
    expect(settings.folder, isNull);
  });
}
