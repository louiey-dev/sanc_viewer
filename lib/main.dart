import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import 'viewer_page.dart';
import 'app_theme.dart';
import 'app_settings.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings.load();
  try {
    await windowManager.ensureInitialized();
    await windowManager.setAsFrameless();
    final windowOptions = WindowOptions(
      size: settings.windowSize,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: true,
    );
    await windowManager.waitUntilReadyToShow(windowOptions);
    if (settings.windowMaximized) await windowManager.maximize();
    await windowManager.show();
    await windowManager.focus();
  } catch (_) {}
  runApp(
    ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(settings),
        startupImageProvider.overrideWithValue(
          arguments.isEmpty ? null : arguments.first,
        ),
      ],
      child: const MyApp(),
    ),
  );
}

final _router = GoRouter(
  routes: [GoRoute(path: '/', builder: (context, state) => const ViewerPage())],
);

/// Application theme and navigation for Sanc Viewer.
class MyApp extends ConsumerWidget {
  /// Creates the image viewer application.
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Sanc Viewer',
    debugShowCheckedModeBanner: false,
    routerConfig: _router,
    themeMode: ref.watch(themeModeProvider),
    theme: viewerTheme(Brightness.light),
    darkTheme: viewerTheme(Brightness.dark),
  );
}
