import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sanc_viewer/main.dart';
import 'package:sanc_viewer/app_settings.dart';
import 'package:sanc_viewer/map_service.dart';

class _MapLauncher extends MapLauncher {
  @override
  Future<bool> isAvailable(MapService service) async => false;
}

void main() {
  testWidgets('Toolbar folds and restores its saved visibility', (
    tester,
  ) async {
    final settings = AppSettings();
    Widget app() => ProviderScope(
      overrides: [appSettingsProvider.overrideWithValue(settings)],
      child: const MyApp(),
    );
    await tester.pumpWidget(app());
    await tester.tap(find.byTooltip('Hide toolbar'));
    await tester.pumpAndSettle();
    expect(find.text('File'), findsNothing);
    expect(settings.toolbar, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('File'), findsNothing);
    await tester.tap(find.byTooltip('Show toolbar'));
    await tester.pumpAndSettle();
    expect(find.text('File'), findsOneWidget);
    expect(settings.toolbar, isTrue);
  });

  testWidgets(
    'File association menu invokes Windows registration',
    (tester) async {
      const channel = MethodChannel('sanc_viewer/file_associations');
      var registrations = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'register');
        registrations++;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [mapLauncherProvider.overrideWithValue(_MapLauncher())],
          child: const MyApp(),
        ),
      );
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
      expect(find.text('File associations'), findsNothing);
      await tester.tap(find.text('Config'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('File associations'));
      await tester.pumpAndSettle();
      expect(registrations, 1);
      expect(find.textContaining('Image formats registered.'), findsOneWidget);
    },
    skip: !Platform.isWindows,
  );

  testWidgets('Sidebar resizes within bounds and retains width when folded', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapLauncherProvider.overrideWithValue(_MapLauncher())],
        child: const MyApp(),
      ),
    );
    final sidebar = find.byKey(const ValueKey('explorer-sidebar'));
    final handle = find.byKey(const ValueKey('sidebar-resize-handle'));
    expect(tester.getSize(sidebar).width, 236);
    await tester.drag(handle, const Offset(80, 0));
    await tester.pumpAndSettle();
    final resizedWidth = tester.getSize(sidebar).width;
    expect(resizedWidth, greaterThan(236));
    await tester.tap(find.byTooltip('Hide sidebar'));
    await tester.pumpAndSettle();
    expect(handle, findsNothing);
    await tester.tap(find.byTooltip('Show sidebar'));
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, resizedWidth);
    await tester.drag(handle, const Offset(1000, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, 472);
    await tester.drag(handle, const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Appearance switches between dark and light', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapLauncherProvider.overrideWithValue(_MapLauncher())],
        child: const MyApp(),
      ),
    );
    expect(find.byTooltip('Switch to dark mode'), findsNothing);
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(find.text('Dark mode'), findsNothing);
    await tester.tap(find.text('Config'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark mode'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Config'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light mode'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.light,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Empty viewer and sidebar toggle', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapLauncherProvider.overrideWithValue(_MapLauncher())],
        child: const MyApp(),
      ),
    );
    expect(find.text('A clear view of every detail.'), findsOneWidget);
    expect(find.text('EXPLORER'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Hide sidebar'));
    await tester.pumpAndSettle();
    expect(find.text('EXPLORER'), findsNothing);
    await tester.tap(find.byTooltip('Show sidebar'));
    await tester.pumpAndSettle();
    expect(find.text('EXPLORER'), findsOneWidget);
  });

  testWidgets('Viewer fits a narrow window', (tester) async {
    tester.view.physicalSize = const Size(420, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapLauncherProvider.overrideWithValue(_MapLauncher())],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A clear view of every detail.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
