import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lendly/core/utils/location_helper.dart';

void main() {
  group('LocationHelper Haversine Distance Calculation', () {
    test('Calculates zero distance for identical coordinates', () {
      final dist = LocationHelper.calculateDistance(10.123, 122.345, 10.123, 122.345);
      expect(dist, closeTo(0.0, 0.01));
    });

    test('Calculates realistic distance between Bacolod and Iloilo (~43 km)', () {
      final dist = LocationHelper.calculateDistance(10.6765, 122.9509, 10.7202, 122.5621);
      expect(dist, greaterThan(40.0));
      expect(dist, lessThan(46.0));
    });

    test('Calculates realistic distance between Bacolod and Cebu (~105-115 km)', () {
      final dist = LocationHelper.calculateDistance(10.6765, 122.9509, 10.3157, 123.8854);
      expect(dist, greaterThan(100.0));
      expect(dist, lessThan(125.0));
    });

    test('Calculates realistic distance between Bacolod and Manila (~480-520 km)', () {
      final dist = LocationHelper.calculateDistance(10.6765, 122.9509, 14.5995, 120.9842);
      expect(dist, greaterThan(470.0));
      expect(dist, lessThan(530.0));
    });
  });

  group('LocationHelper Coordinate Parsing', () {
    test('Parses comma-separated numeric string', () {
      final loc = LocationHelper.parseCoordinates('10.3157, 123.8854');
      expect(loc, isNotNull);
      expect(loc!.latitude, closeTo(10.3157, 0.0001));
      expect(loc.longitude, closeTo(123.8854, 0.0001));
    });

    test('Parses Map with lat and lng keys', () {
      final loc = LocationHelper.parseCoordinates({'lat': 10.123, 'lng': 122.345});
      expect(loc, isNotNull);
      expect(loc!.latitude, closeTo(10.123, 0.0001));
      expect(loc.longitude, closeTo(122.345, 0.0001));
    });

    test('Parses GeoPoint object', () {
      const geoPoint = GeoPoint(14.5995, 120.9842);
      final loc = LocationHelper.parseCoordinates(geoPoint);
      expect(loc, isNotNull);
      expect(loc!.latitude, closeTo(14.5995, 0.0001));
      expect(loc.longitude, closeTo(120.9842, 0.0001));
    });

    test('Recognizes city names', () {
      final bacolod = LocationHelper.parseCoordinates('Bacolod City');
      expect(bacolod, isNotNull);
      expect(bacolod!.latitude, closeTo(10.6765, 0.01));

      final cebu = LocationHelper.parseCoordinates('Cebu');
      expect(cebu, isNotNull);
      expect(cebu!.latitude, closeTo(10.3157, 0.01));

      final manila = LocationHelper.parseCoordinates('Metro Manila');
      expect(manila, isNotNull);
      expect(manila!.latitude, closeTo(14.5995, 0.01));
    });
  });

  group('LocationHelper Distance and Location Formatting', () {
    test('Formats distance correctly for close and far distances', () {
      expect(LocationHelper.formatDistance(0.05), 'Nearby (< 100m)');
      expect(LocationHelper.formatDistance(0.45), '450 m away');
      expect(LocationHelper.formatDistance(4.24), '4.2 km away');
      expect(LocationHelper.formatDistance(25.87), '25.9 km away');
      expect(LocationHelper.formatDistance(null), 'Distance unknown');
    });

    test('Formats combined location with distance badge', () {
      final result = LocationHelper.formatLocationWithDistance(
        locationData: 'Cebu City',
        distanceKm: 3.5,
      );
      expect(result, 'Cebu City • 3.5 km away');
    });

    test('Formats Map location nicely for profile display', () {
      final display = LocationHelper.formatLocationDisplay({'lat': 10.123, 'lng': 122.345});
      expect(display, '10.12, 122.34');
    });
  });

  group('Geographical Radius Filter Logic', () {
    const reference = GeoLocation(latitude: 10.6765, longitude: 122.9509, name: 'Bacolod');

    test('Filters items correctly at 10km radius', () {
      // Point 5km away
      final p5km = LocationHelper.calculateDistance(reference.latitude, reference.longitude, 10.70, 122.97);
      expect(p5km <= 10.0, isTrue);

      // Point 43km away (Iloilo)
      final p43km = LocationHelper.calculateDistance(reference.latitude, reference.longitude, 10.7202, 122.5621);
      expect(p43km <= 10.0, isFalse);
    });

    test('Filters items correctly at 50km radius', () {
      // Iloilo (~43km) is inside 50km radius
      final pIloilo = LocationHelper.calculateDistance(reference.latitude, reference.longitude, 10.7202, 122.5621);
      expect(pIloilo <= 50.0, isTrue);

      // Cebu (~110km) is outside 50km radius
      final pCebu = LocationHelper.calculateDistance(reference.latitude, reference.longitude, 10.3157, 123.8854);
      expect(pCebu <= 50.0, isFalse);
    });

    test('Any distance (100km+) includes all items', () {
      const selectedRadius = 100.0;
      final pManila = LocationHelper.calculateDistance(reference.latitude, reference.longitude, 14.5995, 120.9842);
      final matchesRadius = selectedRadius >= 100.0 || pManila <= selectedRadius;
      expect(matchesRadius, isTrue);
    });
  });
}
