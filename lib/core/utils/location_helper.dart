import 'dart:convert';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class GeoLocation {
  final double latitude;
  final double longitude;
  final String? name;

  const GeoLocation({
    required this.latitude,
    required this.longitude,
    this.name,
  });

  Map<String, dynamic> toMap() {
    return {
      'lat': latitude,
      'lng': longitude,
      if (name != null) 'name': name,
    };
  }

  @override
  String toString() {
    if (name != null && name!.isNotEmpty) {
      return '$name (${latitude.toStringAsFixed(2)}, ${longitude.toStringAsFixed(2)})';
    }
    return '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
  }
}

class LocationHelper {
  // Default reference location (Visayas / Bacolod area matching default auth coordinates 10.123, 122.345)
  static const GeoLocation defaultLocation = GeoLocation(
    latitude: 10.123,
    longitude: 122.345,
    name: 'Bacolod / Visayas Area',
  );

  // Popular reference locations for quick filtering and selection
  static const List<GeoLocation> presetLocations = [
    GeoLocation(latitude: 10.123, longitude: 122.345, name: 'Bacolod Area (Default)'),
    GeoLocation(latitude: 10.6765, longitude: 122.9509, name: 'Bacolod City'),
    GeoLocation(latitude: 10.7202, longitude: 122.5621, name: 'Iloilo City (~45 km)'),
    GeoLocation(latitude: 10.3157, longitude: 123.8854, name: 'Cebu City (~115 km)'),
    GeoLocation(latitude: 9.3068, longitude: 123.3054, name: 'Dumaguete City (~130 km)'),
    GeoLocation(latitude: 14.5995, longitude: 120.9842, name: 'Metro Manila (~500 km)'),
    GeoLocation(latitude: 14.6760, longitude: 121.0437, name: 'Quezon City (~505 km)'),
    GeoLocation(latitude: 7.1907, longitude: 125.4504, name: 'Davao City (~450 km)'),
    GeoLocation(latitude: 8.4542, longitude: 124.6319, name: 'Cagayan de Oro (~260 km)'),
    GeoLocation(latitude: 16.4023, longitude: 120.5960, name: 'Baguio City (~690 km)'),
  ];

  /// Parses latitude and longitude from various formats:
  /// - GeoLocation
  /// - GeoPoint
  /// - Map: {'lat': 10.12, 'lng': 122.34} or {'latitude': ..., 'longitude': ...}
  /// - String: "10.123, 122.345" or city names like "Cebu", "Bacolod", "Manila"
  static GeoLocation? parseCoordinates(dynamic data) {
    if (data == null) return null;

    if (data is GeoLocation) return data;

    if (data is GeoPoint) {
      return GeoLocation(
        latitude: data.latitude,
        longitude: data.longitude,
      );
    }

    if (data is Map) {
      final latRaw = data['lat'] ?? data['latitude'] ?? data['latVal'];
      final lngRaw = data['lng'] ?? data['lon'] ?? data['longitude'] ?? data['lngVal'];
      final nameRaw = data['name'] ?? data['city'] ?? data['address'];

      final lat = (latRaw is num) ? latRaw.toDouble() : double.tryParse(latRaw?.toString() ?? '');
      final lng = (lngRaw is num) ? lngRaw.toDouble() : double.tryParse(lngRaw?.toString() ?? '');

      if (lat != null && lng != null) {
        return GeoLocation(
          latitude: lat,
          longitude: lng,
          name: nameRaw?.toString(),
        );
      }
    }

    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isEmpty) return null;

      // 1. Try comma-separated: "10.123, 122.345"
      if (trimmed.contains(',')) {
        final parts = trimmed.split(',');
        if (parts.length >= 2) {
          final lat = double.tryParse(parts[0].trim());
          final lng = double.tryParse(parts[1].trim());
          if (lat != null && lng != null) {
            final name = parts.length > 2 ? parts[2].trim() : null;
            return GeoLocation(latitude: lat, longitude: lng, name: name);
          }
        }
      }

      // 2. Try space-separated if two numbers
      final spaceParts = trimmed.split(RegExp(r'\s+'));
      if (spaceParts.length == 2) {
        final lat = double.tryParse(spaceParts[0]);
        final lng = double.tryParse(spaceParts[1]);
        if (lat != null && lng != null) {
          return GeoLocation(latitude: lat, longitude: lng);
        }
      }

      // 3. Match against known Philippine & global city names
      final lower = trimmed.toLowerCase();

      if (lower.contains('bacolod')) {
        return const GeoLocation(latitude: 10.6765, longitude: 122.9509, name: 'Bacolod City');
      }
      if (lower.contains('iloilo')) {
        return const GeoLocation(latitude: 10.7202, longitude: 122.5621, name: 'Iloilo City');
      }
      if (lower.contains('cebu')) {
        return const GeoLocation(latitude: 10.3157, longitude: 123.8854, name: 'Cebu City');
      }
      if (lower.contains('manila') || lower.contains('makati') || lower.contains('taguig') || lower.contains('pasig')) {
        return const GeoLocation(latitude: 14.5995, longitude: 120.9842, name: 'Metro Manila');
      }
      if (lower.contains('davao')) {
        return const GeoLocation(latitude: 7.1907, longitude: 125.4504, name: 'Davao City');
      }
      if (lower.contains('dumaguete')) {
        return const GeoLocation(latitude: 9.3068, longitude: 123.3054, name: 'Dumaguete City');
      }
      if (lower.contains('cagayan')) {
        return const GeoLocation(latitude: 8.4542, longitude: 124.6319, name: 'Cagayan de Oro');
      }
      if (lower.contains('baguio')) {
        return const GeoLocation(latitude: 16.4023, longitude: 120.5960, name: 'Baguio City');
      }

      for (final preset in presetLocations) {
        final presetName = (preset.name ?? '').toLowerCase();
        if (presetName == lower || presetName.contains(lower)) {
          return GeoLocation(
            latitude: preset.latitude,
            longitude: preset.longitude,
            name: preset.name,
          );
        }
      }
      if (lower.contains('iloilo')) {
        return const GeoLocation(latitude: 10.7202, longitude: 122.5621, name: 'Iloilo City');
      }
      if (lower.contains('cebu')) {
        return const GeoLocation(latitude: 10.3157, longitude: 123.8854, name: 'Cebu City');
      }
      if (lower.contains('manila') || lower.contains('makati') || lower.contains('taguig') || lower.contains('pasig')) {
        return const GeoLocation(latitude: 14.5995, longitude: 120.9842, name: 'Metro Manila');
      }
      if (lower.contains('davao')) {
        return const GeoLocation(latitude: 7.1907, longitude: 125.4504, name: 'Davao City');
      }
      if (lower.contains('dumaguete')) {
        return const GeoLocation(latitude: 9.3068, longitude: 123.3054, name: 'Dumaguete City');
      }
      if (lower.contains('cagayan')) {
        return const GeoLocation(latitude: 8.4542, longitude: 124.6319, name: 'Cagayan de Oro');
      }
      if (lower.contains('baguio')) {
        return const GeoLocation(latitude: 16.4023, longitude: 120.5960, name: 'Baguio City');
      }
    }

    return null;
  }

  /// Calculates real-world spherical distance in kilometers using the Haversine formula.
  static double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusKm = 6371.0;
    final dLat = (lat2 - lat1) * (pi / 180.0);
    final dLon = (lon2 - lon1) * (pi / 180.0);
    final rLat1 = lat1 * (pi / 180.0);
    final rLat2 = lat2 * (pi / 180.0);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(rLat1) * cos(rLat2) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  /// Calculates distance in km between two flexible location representations.
  static double? getDistanceBetween(dynamic locationA, dynamic locationB) {
    final locA = parseCoordinates(locationA);
    final locB = parseCoordinates(locationB);

    if (locA == null || locB == null) return null;
    return calculateDistance(locA.latitude, locA.longitude, locB.latitude, locB.longitude);
  }

  /// Extracts coordinates from item document data with intelligent fallbacks:
  /// 1. Direct 'latitude' and 'longitude' or 'lat' and 'lng'
  /// 2. 'location' field (Map, String, or GeoPoint)
  /// 3. Returns null if coordinates cannot be extracted
  static GeoLocation? extractItemCoordinates(Map<String, dynamic> itemData) {
    // Check direct lat/lng fields
    final latRaw = itemData['latitude'] ?? itemData['lat'];
    final lngRaw = itemData['longitude'] ?? itemData['lng'];
    if (latRaw != null && lngRaw != null) {
      final lat = (latRaw is num) ? latRaw.toDouble() : double.tryParse(latRaw.toString());
      final lng = (lngRaw is num) ? lngRaw.toDouble() : double.tryParse(lngRaw.toString());
      if (lat != null && lng != null) {
        return GeoLocation(
          latitude: lat,
          longitude: lng,
          name: itemData['location'] is String ? itemData['location'] : null,
        );
      }
    }

    // Check location field
    if (itemData['location'] != null) {
      return parseCoordinates(itemData['location']);
    }

    return null;
  }

  /// Formats raw distance in km to clean, user-friendly text:
  /// - e.g. "Nearby (< 100m)", "450 m away", "2.5 km away"
  static String formatDistance(double? km) {
    if (km == null) return 'Distance unknown';
    if (km < 0.1) return 'Nearby (< 100m)';
    if (km < 1.0) return '${(km * 1000).round()} m away';
    return '${km.toStringAsFixed(1)} km away';
  }

  /// Formats location field into human-readable text for display in profiles, cards, and headers.
  static String formatLocationDisplay(dynamic locationData, {String fallback = 'Location not specified'}) {
    if (locationData == null) return fallback;

    if (locationData is GeoLocation) {
      return locationData.toString();
    }

    if (locationData is String) {
      final trimmed = locationData.trim();
      if (trimmed.isEmpty) return fallback;

      // Check if it's "lat, lng" coordinates
      if (trimmed.contains(',')) {
        final parsed = parseCoordinates(trimmed);
        if (parsed != null) {
          // If a city name was recognized, return it; otherwise return formatted coords
          return parsed.name ?? '${parsed.latitude.toStringAsFixed(2)}, ${parsed.longitude.toStringAsFixed(2)}';
        }
      }
      return trimmed;
    }

    if (locationData is Map) {
      final name = locationData['name'] ?? locationData['city'] ?? locationData['address'];
      if (name != null && name.toString().isNotEmpty) {
        return name.toString();
      }
      final lat = locationData['lat'] ?? locationData['latitude'];
      final lng = locationData['lng'] ?? locationData['longitude'];
      if (lat != null && lng != null) {
        return '${(lat as num).toDouble().toStringAsFixed(2)}, ${(lng as num).toDouble().toStringAsFixed(2)}';
      }
    }

    if (locationData is GeoPoint) {
      return '${locationData.latitude.toStringAsFixed(2)}, ${locationData.longitude.toStringAsFixed(2)}';
    }

    return fallback;
  }

  /// Formats location with distance tag: "Cebu City • 3.2 km away"
  static String formatLocationWithDistance({
    dynamic locationData,
    double? distanceKm,
    String fallbackCity = 'Nearby',
  }) {
    final locationText = formatLocationDisplay(locationData, fallback: '');
    final distText = distanceKm != null ? formatDistance(distanceKm) : null;

    if (locationText.isNotEmpty && distText != null) {
      return '$locationText • $distText';
    } else if (distText != null) {
      return distText;
    } else if (locationText.isNotEmpty) {
      return locationText;
    }
    return fallbackCity;
  }

  /// Finds the closest preset city name within [maxDistanceKm].
  static String? getNearestCityName(double lat, double lng, {double maxDistanceKm = 30.0}) {
    GeoLocation? closest;
    double minDistance = double.infinity;

    for (final preset in presetLocations) {
      final d = calculateDistance(lat, lng, preset.latitude, preset.longitude);
      if (d < minDistance) {
        minDistance = d;
        closest = preset;
      }
    }

    if (closest != null && minDistance <= maxDistanceKm) {
      return closest.name?.split('(').first.trim();
    }
    return null;
  }

  /// Attempts to fetch live device GPS location using [Geolocator].
  /// Falls back to IP-based location and preset defaults if permissions/hardware are unavailable.
  static Future<GeoLocation> getDeviceLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final ipLoc = await getIpLocation();
        if (ipLoc != null) return ipLoc;
        return defaultLocation;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          final ipLoc = await getIpLocation();
          if (ipLoc != null) return ipLoc;
          return defaultLocation;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        final ipLoc = await getIpLocation();
        if (ipLoc != null) return ipLoc;
        return defaultLocation;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final nearestCity = getNearestCityName(position.latitude, position.longitude);
      final locName = nearestCity ?? 'My Location (${position.latitude.toStringAsFixed(2)}, ${position.longitude.toStringAsFixed(2)})';

      return GeoLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        name: locName,
      );
    } catch (_) {
      final ipLoc = await getIpLocation();
      if (ipLoc != null) return ipLoc;
      return defaultLocation;
    }
  }

  /// Fallback IP-based geolocation (works on laptops/desktops and web without GPS sensors).
  static Future<GeoLocation?> getIpLocation() async {
    try {
      final res = await http.get(Uri.parse('http://ip-api.com/json')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lon'] as num?)?.toDouble();
        final city = data['city'] as String?;
        final region = data['regionName'] as String?;

        if (lat != null && lng != null) {
          final name = city != null ? (region != null ? '$city, $region' : city) : 'My Location';
          return GeoLocation(
            latitude: lat,
            longitude: lng,
            name: name,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// Reverse geocodes coordinates to a clean place or city name using Nominatim / presets.
  static Future<String> reverseGeocode(double lat, double lng) async {
    final nearest = getNearestCityName(lat, lng, maxDistanceKm: 12.0);
    if (nearest != null) return nearest;

    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=14');
      final res = await http.get(url, headers: {'User-Agent': 'LendlyApp/1.0'}).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final city = address['city'] ?? address['town'] ?? address['municipality'] ?? address['county'];
          final state = address['state'] ?? address['region'];
          if (city != null) {
            return state != null ? '$city, $state' : city.toString();
          }
        }
        final displayName = data['display_name'] as String?;
        if (displayName != null) {
          final parts = displayName.split(',');
          if (parts.length >= 2) {
            return '${parts[0].trim()}, ${parts[1].trim()}';
          }
          return displayName;
        }
      }
    } catch (_) {}

    return nearest ?? '${lat.toStringAsFixed(3)}, ${lng.toStringAsFixed(3)}';
  }
}
