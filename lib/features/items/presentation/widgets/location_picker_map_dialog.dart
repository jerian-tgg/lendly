import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lendly/core/utils/location_helper.dart';

class LocationRadiusResult {
  final GeoLocation location;
  final double radiusKm;

  const LocationRadiusResult({
    required this.location,
    required this.radiusKm,
  });
}

class LocationPickerMapDialog extends StatefulWidget {
  final GeoLocation initialLocation;
  final double initialRadiusKm;
  final String title;
  final bool showRadiusSelector;

  const LocationPickerMapDialog({
    super.key,
    required this.initialLocation,
    this.initialRadiusKm = LocationHelper.defaultDiscoveryRadiusKm,
    this.title = 'Location & Radius',
    this.showRadiusSelector = true,
  });

  /// Static helper to display the modal bottom sheet
  static Future<LocationRadiusResult?> show(
    BuildContext context, {
    required GeoLocation initialLocation,
    double initialRadiusKm = LocationHelper.defaultDiscoveryRadiusKm,
    String title = 'Location & Radius',
    bool showRadiusSelector = true,
  }) {
    return showModalBottomSheet<LocationRadiusResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (_) => LocationPickerMapDialog(
        initialLocation: initialLocation,
        initialRadiusKm: initialRadiusKm,
        title: title,
        showRadiusSelector: showRadiusSelector,
      ),
    );
  }

  @override
  State<LocationPickerMapDialog> createState() => _LocationPickerMapDialogState();
}

class _LocationPickerMapDialogState extends State<LocationPickerMapDialog> {
  // Strict bounding box for the Philippines to prevent erratic camera panning
  static final LatLngBounds _philippinesBounds = LatLngBounds(
    const LatLng(LocationHelper.phMinLat, LocationHelper.phMinLng),
    const LatLng(LocationHelper.phMaxLat, LocationHelper.phMaxLng),
  );

  static const double _minZoom = 5.5;
  static const double _maxZoom = 18.0;
  static const List<double> _radiusChips = [5.0, 10.0, 25.0, 50.0, 100.0];

  late final MapController _mapController;
  late final ValueNotifier<LatLng> _pinNotifier;
  late final ValueNotifier<double> _radiusNotifier;
  late final ValueNotifier<String> _locationNameNotifier;
  late final ValueNotifier<bool> _isGeocodingNotifier;
  late final ValueNotifier<bool> _isLoadingGpsNotifier;
  late final ValueNotifier<List<GeoLocation>> _searchResultsNotifier;

  final TextEditingController _searchController = TextEditingController();
  Timer? _geocodeDebounce;
  int _geocodeRequestId = 0;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    // Sanitize initial coordinates to ensure the map always starts within the Philippines
    final safeInitial = LocationHelper.sanitizeToPhilippines(widget.initialLocation);
    _pinNotifier = ValueNotifier<LatLng>(
      LatLng(safeInitial.latitude, safeInitial.longitude),
    );
    _radiusNotifier = ValueNotifier<double>(
      widget.initialRadiusKm.clamp(5.0, 100.0),
    );

    final initialName = safeInitial.name ?? '';
    _locationNameNotifier = ValueNotifier<String>(
      initialName.isNotEmpty ? initialName : 'Bacolod / Visayas Area',
    );
    _isGeocodingNotifier = ValueNotifier<bool>(false);
    _isLoadingGpsNotifier = ValueNotifier<bool>(false);
    _searchResultsNotifier = ValueNotifier<List<GeoLocation>>([]);

    if (initialName.isEmpty || initialName == 'Nearby' || initialName == 'Selected Location') {
      _scheduleReverseGeocode(safeInitial.latitude, safeInitial.longitude);
    }
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _mapController.dispose();
    _pinNotifier.dispose();
    _radiusNotifier.dispose();
    _locationNameNotifier.dispose();
    _isGeocodingNotifier.dispose();
    _isLoadingGpsNotifier.dispose();
    _searchResultsNotifier.dispose();
    _searchController.dispose();
    super.dispose();
  }

  LatLng _clampLatLngToPhilippines(double lat, double lng) {
    final clampedLat = lat.clamp(LocationHelper.phMinLat, LocationHelper.phMaxLat);
    final clampedLng = lng.clamp(LocationHelper.phMinLng, LocationHelper.phMaxLng);
    return LatLng(clampedLat, clampedLng);
  }

  void _scheduleReverseGeocode(double lat, double lng) {
    _geocodeDebounce?.cancel();
    // Instant local preset check before network call for zero-latency feedback
    final quickCity = LocationHelper.getNearestCityName(lat, lng, maxDistanceKm: 15.0);
    if (quickCity != null) {
      _locationNameNotifier.value = quickCity;
    }

    _geocodeDebounce = Timer(const Duration(milliseconds: 350), () async {
      final requestId = ++_geocodeRequestId;
      _isGeocodingNotifier.value = true;
      try {
        final name = await LocationHelper.reverseGeocode(lat, lng);
        if (mounted && requestId == _geocodeRequestId) {
          _locationNameNotifier.value = name;
        }
      } catch (_) {
        // Keep existing or coordinate fallback name
      } finally {
        if (mounted && requestId == _geocodeRequestId) {
          _isGeocodingNotifier.value = false;
        }
      }
    });
  }

  Future<void> _useDeviceLocation() async {
    if (_isLoadingGpsNotifier.value) return;
    _isLoadingGpsNotifier.value = true;
    try {
      final deviceLoc = await LocationHelper.getDeviceLocation();
      if (!mounted) return;

      final safeLoc = LocationHelper.sanitizeToPhilippines(deviceLoc);
      final target = LatLng(safeLoc.latitude, safeLoc.longitude);

      _pinNotifier.value = target;
      _locationNameNotifier.value = safeLoc.name ?? 'My Location';
      _isLoadingGpsNotifier.value = false;

      _moveCameraSmoothly(target, _getZoomForRadius(_radiusNotifier.value));
    } catch (_) {
      if (mounted) {
        _isLoadingGpsNotifier.value = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not fetch device location. Please enable GPS permissions.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _moveCameraSmoothly(LatLng target, double zoom) {
    final safeTarget = _clampLatLngToPhilippines(target.latitude, target.longitude);
    final safeZoom = zoom.clamp(_minZoom, _maxZoom);
    _mapController.move(safeTarget, safeZoom);
  }

  void _onMapTapped(TapPosition tapPosition, LatLng latLng) {
    final clamped = _clampLatLngToPhilippines(latLng.latitude, latLng.longitude);
    _pinNotifier.value = clamped;
    if (_searchResultsNotifier.value.isNotEmpty) {
      _searchResultsNotifier.value = [];
    }
    FocusScope.of(context).unfocus();
    _scheduleReverseGeocode(clamped.latitude, clamped.longitude);
  }

  void _onSearchChanged(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchResultsNotifier.value = [];
      return;
    }

    final lower = trimmed.toLowerCase();
    final results = LocationHelper.presetLocations.where((loc) {
      final name = (loc.name ?? '').toLowerCase();
      return name.contains(lower);
    }).toList();

    final parsed = LocationHelper.parseCoordinates(trimmed);
    if (parsed != null &&
        LocationHelper.isWithinPhilippines(parsed.latitude, parsed.longitude) &&
        !results.any((r) => r.latitude == parsed.latitude && r.longitude == parsed.longitude)) {
      results.insert(0, parsed);
    }

    _searchResultsNotifier.value = results;
  }

  void _selectLocation(GeoLocation loc) {
    final safeLoc = LocationHelper.sanitizeToPhilippines(loc);
    final target = LatLng(safeLoc.latitude, safeLoc.longitude);
    _pinNotifier.value = target;
    _locationNameNotifier.value = (safeLoc.name ?? 'Selected Location').split('(').first.trim();
    _searchController.clear();
    _searchResultsNotifier.value = [];
    FocusScope.of(context).unfocus();

    _moveCameraSmoothly(target, _getZoomForRadius(_radiusNotifier.value));
  }

  double _getZoomForRadius(double radiusKm) {
    if (!widget.showRadiusSelector) return 13.0;
    if (radiusKm <= 5.0) return 13.0;
    if (radiusKm <= 10.0) return 12.0;
    if (radiusKm <= 25.0) return 10.8;
    if (radiusKm <= 50.0) return 9.5;
    return 8.0;
  }

  void _applyAndClose() {
    final pin = _pinNotifier.value;
    final locName = _locationNameNotifier.value.trim();
    final result = LocationRadiusResult(
      location: GeoLocation(
        latitude: pin.latitude,
        longitude: pin.longitude,
        name: locName.isNotEmpty ? locName : 'Custom Pin',
      ),
      radiusKm: _radiusNotifier.value,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final initialPin = _pinNotifier.value;

    return Container(
      height: size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header: Title & Close
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B40B5).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on, color: Color(0xFF7B40B5), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.showRadiusSelector
                            ? 'Set map pin & distance within the Philippines'
                            : 'Tap on the map or use GPS to set your location',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Search Bar & GPS Quick Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchController,
                      builder: (context, textVal, _) {
                        return TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: 'Search PH city (e.g. Bacolod, Cebu, Manila)...',
                            hintStyle: TextStyle(fontSize: 12, color: Colors.grey[500]),
                            prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF7B40B5)),
                            suffixIcon: textVal.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      _onSearchChanged('');
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          style: const TextStyle(fontSize: 13),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Device GPS Button
                ValueListenableBuilder<bool>(
                  valueListenable: _isLoadingGpsNotifier,
                  builder: (context, isLoadingGps, _) {
                    return InkWell(
                      onTap: isLoadingGps ? null : _useDeviceLocation,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7B40B5),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7B40B5).withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: isLoadingGps
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location, color: Colors.white, size: 20),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Autocomplete suggestions overlay
          ValueListenableBuilder<List<GeoLocation>>(
            valueListenable: _searchResultsNotifier,
            builder: (context, results, _) {
              if (results.isEmpty) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final loc = results[idx];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.location_city, color: Color(0xFF7B40B5), size: 18),
                      title: Text(
                        loc.name ?? '${loc.latitude}, ${loc.longitude}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      onTap: () => _selectLocation(loc),
                    );
                  },
                ),
              );
            },
          ),

          // Map Area with Locked Philippines Bounds & Isolated Reactive Layers
          Expanded(
            child: RepaintBoundary(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: initialPin,
                      initialZoom: _getZoomForRadius(_radiusNotifier.value),
                      minZoom: _minZoom,
                      maxZoom: _maxZoom,
                      cameraConstraint: CameraConstraint.contain(
                        bounds: _philippinesBounds,
                      ),
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                      onTap: _onMapTapped,
                    ),
                    children: [
                      // OpenStreetMap Tiles with buffer caching for smooth panning
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.lendly.app',
                        maxZoom: _maxZoom,
                        minZoom: _minZoom,
                        keepBuffer: 3,
                        panBuffer: 1,
                      ),

                      // Reactive Circular Radius Overlay (rebuilds only when pin or radius changes)
                      if (widget.showRadiusSelector)
                        AnimatedBuilder(
                          animation: Listenable.merge([_pinNotifier, _radiusNotifier]),
                          builder: (context, _) {
                            final pin = _pinNotifier.value;
                            final rad = _radiusNotifier.value;
                            if (rad >= 100.0) return const SizedBox.shrink();
                            return CircleLayer(
                              circles: [
                                CircleMarker(
                                  point: pin,
                                  radius: rad * 1000,
                                  useRadiusInMeter: true,
                                  color: const Color(0xFF7B40B5).withValues(alpha: 0.16),
                                  borderColor: const Color(0xFF7B40B5),
                                  borderStrokeWidth: 2.0,
                                ),
                              ],
                            );
                          },
                        ),

                      // Reactive Pinned Marker Layer (rebuilds only when pin moves)
                      ValueListenableBuilder<LatLng>(
                        valueListenable: _pinNotifier,
                        builder: (context, pin, _) {
                          return MarkerLayer(
                            markers: [
                              Marker(
                                point: pin,
                                width: 50,
                                height: 50,
                                alignment: Alignment.topCenter,
                                child: const _MapPinMarkerWidget(),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),

                  // Floating Hint Pill
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.70),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.touch_app, color: Colors.white, size: 14),
                              SizedBox(width: 6),
                              Text(
                                'Tap anywhere on map to drop pin',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Floating Map Controls: Zoom In / Zoom Out & Center Pin
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: Column(
                      children: [
                        _buildFloatingButton(
                          icon: Icons.add,
                          tooltip: 'Zoom in',
                          onTap: () {
                            final currentZoom = _mapController.camera.zoom;
                            _moveCameraSmoothly(_pinNotifier.value, currentZoom + 1);
                          },
                        ),
                        const SizedBox(height: 6),
                        _buildFloatingButton(
                          icon: Icons.remove,
                          tooltip: 'Zoom out',
                          onTap: () {
                            final currentZoom = _mapController.camera.zoom;
                            _moveCameraSmoothly(_pinNotifier.value, currentZoom - 1);
                          },
                        ),
                        const SizedBox(height: 6),
                        _buildFloatingButton(
                          icon: Icons.center_focus_strong,
                          tooltip: 'Recenter on pin',
                          onTap: () {
                            _moveCameraSmoothly(
                              _pinNotifier.value,
                              _getZoomForRadius(_radiusNotifier.value),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Controls: Current Pin Address, Radius Slider & Apply
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pinned Location Info Card
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B40B5).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.push_pin, color: Color(0xFF7B40B5), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Pinned Location:',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              ValueListenableBuilder<bool>(
                                valueListenable: _isGeocodingNotifier,
                                builder: (context, isGeocoding, _) {
                                  if (!isGeocoding) return const SizedBox.shrink();
                                  return const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: Color(0xFF7B40B5),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          ValueListenableBuilder<String>(
                            valueListenable: _locationNameNotifier,
                            builder: (context, locName, _) {
                              return Text(
                                locName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    // Show Coords chip
                    ValueListenableBuilder<LatLng>(
                      valueListenable: _pinNotifier,
                      builder: (context, pin, _) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Text(
                            '${pin.latitude.toStringAsFixed(3)}, ${pin.longitude.toStringAsFixed(3)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[700],
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                if (widget.showRadiusSelector) ...[
                  const SizedBox(height: 10),
                  ValueListenableBuilder<double>(
                    valueListenable: _radiusNotifier,
                    builder: (context, radiusKm, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.radar, size: 16, color: Color(0xFF7B40B5)),
                                  SizedBox(width: 6),
                                  Text(
                                    'Search Radius:',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7B40B5).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  radiusKm >= 100.0 ? 'Any distance' : '${radiusKm.toInt()} km',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF7B40B5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                              activeTrackColor: const Color(0xFF7B40B5),
                              thumbColor: const Color(0xFF7B40B5),
                              inactiveTrackColor: Colors.purple.shade50,
                            ),
                            child: Slider(
                              value: radiusKm,
                              min: 5.0,
                              max: 100.0,
                              divisions: 19,
                              label: radiusKm >= 100.0 ? 'Any' : '${radiusKm.toInt()} km',
                              onChanged: (val) => _radiusNotifier.value = val,
                            ),
                          ),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _radiusChips.map((rad) {
                                final isSelected = radiusKm == rad;
                                final label = rad >= 100.0 ? 'Any distance' : '${rad.toInt()} km';
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(label, style: const TextStyle(fontSize: 11)),
                                    selected: isSelected,
                                    selectedColor: const Color(0xFF7B40B5),
                                    labelStyle: TextStyle(
                                      color: isSelected ? Colors.white : Colors.black87,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                    onSelected: (val) {
                                      if (val) {
                                        _radiusNotifier.value = rad;
                                        _moveCameraSmoothly(
                                          _pinNotifier.value,
                                          _getZoomForRadius(rad),
                                        );
                                      }
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],

                const SizedBox(height: 12),

                // Bottom Buttons: Use My Location & Apply Location
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _useDeviceLocation,
                      icon: const Icon(Icons.my_location, size: 16),
                      label: const Text('My Location', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF7B40B5),
                        side: const BorderSide(color: Color(0xFF7B40B5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _radiusNotifier,
                        builder: (context, radiusKm, _) {
                          final btnText = !widget.showRadiusSelector
                              ? 'Confirm Location'
                              : (radiusKm >= 100.0
                                  ? 'Apply (All Distances)'
                                  : 'Apply (${radiusKm.toInt()} km)');
                          return ElevatedButton.icon(
                            onPressed: _applyAndClose,
                            icon: const Icon(Icons.check, size: 18),
                            label: Text(
                              btnText,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7B40B5),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.black87, size: 18),
        tooltip: tooltip,
        onPressed: onTap,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Const marker widget to avoid rebuilding marker decorations during map pans
class _MapPinMarkerWidget extends StatelessWidget {
  const _MapPinMarkerWidget();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          bottom: 0,
          child: Container(
            width: 14,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ),
        Positioned(
          top: 0,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF9042D6), Color(0xFF6723A8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3)),
              ],
            ),
            child: const Icon(Icons.place, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }
}
