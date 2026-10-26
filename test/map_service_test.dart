import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanc_viewer/app_settings.dart';
import 'package:sanc_viewer/main.dart';
import 'package:sanc_viewer/map_service.dart';

class _Launcher extends MapLauncher {
  final checked = <MapService>[];

  @override
  Future<bool> isAvailable(MapService service) async {
    checked.add(service);
    return service != MapService.naver;
  }
}

void main() {
  test('Map preference survives restart and unknown values use Google', () {
    final dir = Directory.systemTemp.createTempSync('sanc_maps_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/settings.json');
    final settings = AppSettings.read(file);
    expect(settings.mapService, MapService.google);
    settings.update(mapService: MapService.kakao);
    expect(AppSettings.read(file).mapService, MapService.kakao);
    file.writeAsStringSync('{"mapService":"unknown"}');
    expect(AppSettings.read(file).mapService, MapService.google);
  });

  test('Map URLs preserve latitude/longitude order and signed coordinates', () {
    const location = '-33.123456, 151.654321';
    final google = MapService.google.locationUrl(location);
    expect(google.queryParameters['api'], '1');
    expect(google.queryParameters['query'], '-33.123456,151.654321');
    final naver = MapService.naver.locationUrl(location);
    expect(naver.queryParameters['lat'], '-33.123456');
    expect(naver.queryParameters['lng'], '151.654321');
    expect(
      MapService.kakao.locationUrl(location).path,
      '/link/map/-33.123456,151.654321',
    );
    for (final service in MapService.values) {
      for (final invalid in ['NaN,1', '91,0', '0,181', 'bad', '1,2,3']) {
        expect(() => service.locationUrl(invalid), throwsFormatException);
      }
    }
  });

  testWidgets('Config checks all maps, disables unavailable maps and saves', (
    tester,
  ) async {
    final settings = AppSettings();
    final launcher = _Launcher();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(settings),
          mapLauncherProvider.overrideWithValue(launcher),
        ],
        child: const MyApp(),
      ),
    );
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Config'));
    await tester.pumpAndSettle();
    expect(launcher.checked, containsAll(MapService.values));
    expect(find.text('Available in browser'), findsNWidgets(2));
    final naver = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Naver Map'),
    );
    expect(naver.enabled, isFalse);
    await tester.ensureVisible(find.text('Kakao Map'));
    await tester.tap(find.text('Kakao Map'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(settings.mapService, MapService.kakao);
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Config'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Maps'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(settings.mapService, MapService.kakao);
    expect(tester.takeException(), isNull);
  });
}
