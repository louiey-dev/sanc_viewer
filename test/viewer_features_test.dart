import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanc_viewer/app_settings.dart';
import 'package:sanc_viewer/viewer_page.dart';
import 'package:sanc_viewer/viewer_support.dart';

import 'image_playback_test.dart' show settleDecoder;
import 'test_images.dart';

void main() {
  test(
    'Recent folders are deduplicated, capped and persisted with view options',
    () {
      final dir = Directory.systemTemp.createTempSync('sanc_recent_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/settings.json');
      final settings = AppSettings(file: file);
      for (var i = 0; i < 12; i++) {
        settings.rememberFolder('folder$i');
      }
      settings.rememberFolder('folder6');
      settings.update(thumbnails: true, checkerboard: false);
      final restored = AppSettings.read(file);
      expect(restored.recentFolders.length, 10);
      expect(restored.recentFolders.first, 'folder6');
      expect(
        restored.recentFolders.where((path) => path == 'folder6').length,
        1,
      );
      expect(restored.thumbnails, isTrue);
      expect(restored.checkerboard, isFalse);
      restored.clearRecentFolders();
      expect(AppSettings.read(file).recentFolders, isEmpty);
    },
  );

  test('Fit scale follows the constrained image dimension', () {
    expect(imageFitScale(const Size(400, 200), const Size(200, 200)), 0.5);
    expect(imageFitScale(const Size(200, 400), const Size(200, 200)), 0.5);
    expect(imageFitScale(const Size(100, 100), const Size(200, 300)), 2);
  });

  testWidgets(
    'Dropped folder, thumbnails, watcher, 100% zoom and context menu',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('sanc_features_');
      File('${dir.path}/aaa.gif').writeAsBytesSync(twoFrameGif());
      final first = File('${dir.path}/first.gif')
        ..writeAsBytesSync(twoFrameGif());
      final settings = AppSettings();
      settings.update(thumbnails: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appSettingsProvider.overrideWithValue(settings)],
          child: const MaterialApp(home: ViewerPage()),
        ),
      );
      final drop = tester.widget<DropTarget>(find.byType(DropTarget));
      drop.onDragDone!(
        DropDoneDetails(
          files: [DropItemDirectory(dir.path, [])],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await settleDecoder(
        tester,
        () =>
            find.text('first.gif').evaluate().isNotEmpty &&
            find.byType(InteractiveViewer).evaluate().isNotEmpty,
      );
      drop.onDragDone!(
        DropDoneDetails(
          files: [DropItemFile(first.path)],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await settleDecoder(
        tester,
        () =>
            settings.image != null &&
            settings.image!.endsWith('first.gif') &&
            find.byType(InteractiveViewer).evaluate().isNotEmpty,
      );
      expect(settings.recentFolders.first, dir.path);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image && widget.key.toString().contains('thumbnail-'),
        ),
        findsNWidgets(2),
      );
      await tester.tap(find.byTooltip('Show file list'));
      await tester.pump();
      expect(settings.thumbnails, isFalse);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image && widget.key.toString().contains('thumbnail-'),
        ),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Show thumbnails'));
      await tester.pump();
      expect(settings.thumbnails, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('zoom-percentage'))).data,
        '100%',
      );
      final matrix = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .clone();
      final second = File('${dir.path}/second.gif')
        ..writeAsBytesSync(twoFrameGif());
      await settleDecoder(
        tester,
        () => find.text('second.gif').evaluate().isNotEmpty,
      );
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value,
        matrix,
      );
      expect(
        settings.image!.replaceAll('\\', '/'),
        first.path.replaceAll('\\', '/'),
      );
      second.deleteSync();
      await settleDecoder(
        tester,
        () => find.text('second.gif').evaluate().isEmpty,
      );
      await tester.tap(find.text('first.gif'), buttons: 2);
      await tester.pumpAndSettle();
      expect(find.text('Copy file path'), findsOneWidget);
      expect(find.text('Open containing folder'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      dir.deleteSync(recursive: true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('F11 enters fullscreen and Escape restores the toolbar', (
    tester,
  ) async {
    var fullscreen = false;
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'setFullScreen') {
        fullscreen = (call.arguments as Map)['isFullScreen'] as bool;
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ViewerPage())),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(fullscreen, isTrue);
    expect(find.text('File'), findsNothing);
    expect(find.byTooltip('Exit fullscreen (Esc)'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(fullscreen, isFalse);
    expect(find.text('File'), findsOneWidget);
  });
}
