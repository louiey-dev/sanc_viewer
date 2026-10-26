import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

enum MapService {
  google('Google Maps'),
  naver('Naver Map'),
  kakao('Kakao Map');

  const MapService(this.label);
  final String label;

  Uri locationUrl(String location) {
    final coordinates = location.split(',').map((part) => part.trim()).toList();
    if (coordinates.length != 2) {
      throw const FormatException('Invalid location');
    }
    final latitude = double.tryParse(coordinates[0]);
    final longitude = double.tryParse(coordinates[1]);
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      throw const FormatException('Invalid location');
    }
    return switch (this) {
      MapService.google => Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': coordinates.join(','),
      }),
      MapService.naver => Uri.https('map.naver.com', '/', {
        'lat': coordinates[0],
        'lng': coordinates[1],
        'dlevel': '12',
      }),
      MapService.kakao => Uri.https(
        'map.kakao.com',
        '/link/map/${coordinates.join(',')}',
      ),
    };
  }
}

final mapLauncherProvider = Provider<MapLauncher>((ref) => MapLauncher());

class MapLauncher {
  Future<bool> isAvailable(MapService service) async {
    try {
      return await canLaunchUrl(
        service.locationUrl('0,0'),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      return false;
    }
  }

  Future<bool> open(MapService service, String location) async {
    try {
      return await launchUrl(
        service.locationUrl(location),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
