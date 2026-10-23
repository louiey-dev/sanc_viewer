import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanc_viewer/viewer_page.dart';

class _Picker extends FileSelectorPlatform {
  _Picker(this.folder);
  final String folder;

  @override
  Future<String?> getDirectoryPathWithOptions(
    FileDialogOptions options,
  ) async => folder;
}

void main() {
  testWidgets(
    'Explorer filters unsupported files and navigates into empty folders',
    (tester) async {
      final folder = Directory.systemTemp.createTempSync('sanc_explorer_');
      final original = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _Picker(folder.path);
      addTearDown(() {
        FileSelectorPlatform.instance = original;
        folder.deleteSync(recursive: true);
      });
      File('${folder.path}/notes.txt').writeAsStringSync('notes');
      File('${folder.path}/other.bin').writeAsBytesSync([1, 2]);
      Directory('${folder.path}/empty').createSync();
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ViewerPage())),
      );
      await tester.tap(find.text('Open folder'));
      for (
        var attempt = 0;
        attempt < 30 && find.text('empty').evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.text('notes.txt'), findsNothing);
      expect(find.text('other.bin'), findsNothing);
      expect(find.text('empty'), findsOneWidget);
      expect(find.text('0 / 0'), findsOneWidget);
      await tester.tap(find.text('empty'));
      for (
        var attempt = 0;
        attempt < 30 && find.text('This folder is empty.').evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.text('This folder is empty.'), findsOneWidget);
      expect(find.text('Parent folder'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
