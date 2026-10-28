import 'dart:math';
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

  const LocationPickerMapDialog({
    super.key,
    required this.initialLocation,
    required this.initialRadiusKm,
    this.title = 'Location & Radius',
  });

  /// Static helper to display the modal bottom sheet or dialog
  static Future<LocationRadiusResult?> show(
    BuildContext context, {
    required GeoLocation initialLocation,
    required double initialRadiusKm,
    String title = 'Location & Radius',
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
      ),
    );
  }

  @override
  State<LocationPickerMapDialog> createState() => _LocationPickerMapDialogState();
}

class _LocationPickerMapDialogState extends State<LocationPickerMapDialog> {
  late final MapController _mapController;
  late double _pinnedLat;
  late double _pinnedLng;
  late double _radiusKm;
  String _locationName = '';
  bool _isLoadingLocation = false;
  bool _isGeocoding = false;

  final TextEditingController _searchController = TextEditingController();
  List<GeoLocation> _filteredPresets = [];
  bool _showSearchResults = false;

  final List<double> _radiusChips = [5.0, 10.0, 25.0, 50.0, 100.0];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pinnedLat = widget.initialLocation.latitude;
    _pinnedLng = widget.initialLocation.longitude;
    _radiusKm = widget.initialRadiusKm;
    _locationName = widget.initialLocation.name ?? 'Selected Location';

    if (_locationName.isEmpty || _locationName == 'Nearby') {
      _reverseGeocodePin();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reverseGeocodePin() async {
    setState(() => _isGeocoding = true);
    try {
      final name = await LocationHelper.reverseGeocode(_pinnedLat, _pinnedLng);
      if (mounted) {
        setState(() {
          _locationName = name;
          _isGeocoding = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isGeocoding = false);
      }
    }
  }

  Future<void> _useDeviceLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final deviceLoc = await LocationHelper.getDeviceLocation();
      if (!mounted) return;

      setState(() {
        _pinnedLat = deviceLoc.latitude;
        _pinnedLng = deviceLoc.longitude;
        _locationName = deviceLoc.name ?? 'My Location';
        _isLoadingLocation = false;
      });

      _mapController.move(
        LatLng(_pinnedLat, _pinnedLng),
        _getZoomForRadius(_radiusKm),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not fetch device location. Please enable GPS permissions.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _onMapTapped(TapPosition tapPosition, LatLng latLng) {
    setState(() {
      _pinnedLat = latLng.latitude;
      _pinnedLng = latLng.longitude;
      _showSearchResults = false;
    });
    _reverseGeocodePin();
  }

  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _filteredPresets = [];
        _showSearchResults = false;
      });
      return;
    }

    final lower = query.toLowerCase();
    final results = LocationHelper.presetLocations.where((loc) {
      final name = (loc.name ?? '').toLowerCase();
      return name.contains(lower);
    }).toList();

    // Also check coordinate pattern "lat, lng"
    final parsed = LocationHelper.parseCoordinates(query);
    if (parsed != null && !results.any((r) => r.latitude == parsed.latitude && r.longitude == parsed.longitude)) {
      results.insert(0, parsed);
    }

    setState(() {
      _filteredPresets = results;
      _showSearchResults = results.isNotEmpty;
    });
  }

  void _selectLocation(GeoLocation loc) {
    setState(() {
      _pinnedLat = loc.latitude;
      _pinnedLng = loc.longitude;
      _locationName = loc.name ?? 'Selected Location';
      _searchController.clear();
      _showSearchResults = false;
    });

    _mapController.move(
      LatLng(_pinnedLat, _pinnedLng),
      _getZoomForRadius(_radiusKm),
    );
  }

  double _getZoomForRadius(double radiusKm) {
    if (radiusKm <= 5.0) return 13.0;
    if (radiusKm <= 10.0) return 12.0;
    if (radiusKm <= 25.0) return 10.8;
    if (radiusKm <= 50.0) return 9.5;
    return 8.0;
  }

  void _onRadiusChanged(double newRadiusKm) {
    setState(() {
      _radiusKm = newRadiusKm;
    });
  }

  void _applyAndClose() {
    final result = LocationRadiusResult(
      location: GeoLocation(
        latitude: _pinnedLat,
        longitude: _pinnedLng,
        name: _locationName.isNotEmpty ? _locationName : 'Custom Pin',
      ),
      radiusKm: _radiusKm,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Container(
      height: size.height * 0.90,
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
                      const Text(
                        'Set map pin & distance like Marketplace',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
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
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search city or area (e.g. Cebu, Bacolod)...',
                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF7B40B5)),
                        suffixIcon: _searchController.text.isNotEmpty
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
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Device GPS Button
                InkWell(
                  onTap: _isLoadingLocation ? null : _useDeviceLocation,
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
                    child: _isLoadingLocation
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // Autocomplete suggestions overlay if active
          if (_showSearchResults && _filteredPresets.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _filteredPresets.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final loc = _filteredPresets[idx];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_city, color: Color(0xFF7B40B5), size: 18),
                    title: Text(loc.name ?? '${loc.latitude}, ${loc.longitude}', style: const TextStyle(fontSize: 13)),
                    onTap: () => _selectLocation(loc),
                  );
                },
              ),
            ),

          // Map Area with Circular Radius Overlay & Custom Pin
          Expanded(
            child: Stack(
              children: [
                // OpenStreetMap View
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(_pinnedLat, _pinnedLng),
                    initialZoom: _getZoomForRadius(_radiusKm),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                    onTap: _onMapTapped,
                  ),
                  children: [
                    // OpenStreetMap Standard Tiles
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.lendly.app',
                      maxZoom: 18,
                    ),

                    // Circular Radius Shaded Area (Marketplace coverage circle!)
                    CircleLayer(
                      circles: [
                        if (_radiusKm < 100.0)
                          CircleMarker(
                            point: LatLng(_pinnedLat, _pinnedLng),
                            radius: _radiusKm * 1000, // meters
                            useRadiusInMeter: true,
                            color: const Color(0xFF7B40B5).withValues(alpha: 0.18),
                            borderColor: const Color(0xFF7B40B5),
                            borderStrokeWidth: 2.0,
                          ),
                      ],
                    ),

                    // Pinned Marker Layer
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(_pinnedLat, _pinnedLng),
                          width: 50,
                          height: 50,
                          alignment: Alignment.topCenter,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Pulsating base shadow
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
                              // Pin Icon
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
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Floating "Tap anywhere to drop pin" Hint Pill
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.touch_app, color: Colors.white, size: 14),
                          SizedBox(width: 6),
                          Text(
                            'Tap anywhere on map to drop pin',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
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
                          _mapController.move(LatLng(_pinnedLat, _pinnedLng), currentZoom + 1);
                        },
                      ),
                      const SizedBox(height: 6),
                      _buildFloatingButton(
                        icon: Icons.remove,
                        tooltip: 'Zoom out',
                        onTap: () {
                          final currentZoom = _mapController.camera.zoom;
                          _mapController.move(LatLng(_pinnedLat, _pinnedLng), max(2, currentZoom - 1));
                        },
                      ),
                      const SizedBox(height: 6),
                      _buildFloatingButton(
                        icon: Icons.center_focus_strong,
                        tooltip: 'Recenter on pin',
                        onTap: () {
                          _mapController.move(LatLng(_pinnedLat, _pinnedLng), _getZoomForRadius(_radiusKm));
                        },
                      ),
                    ],
                  ),
                ),
              ],
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
                                style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600),
                              ),
                              if (_isGeocoding) ...[
                                const SizedBox(width: 6),
                                const SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF7B40B5)),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            _locationName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Show Coords chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Text(
                        '${_pinnedLat.toStringAsFixed(2)}, ${_pinnedLng.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 10, color: Colors.grey[700], fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Radius Header & Value
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
                        _radiusKm >= 100.0 ? 'Any distance' : '${_radiusKm.toInt()} km',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF7B40B5),
                        ),
                      ),
                    ),
                  ],
                ),

                // Radius Slider
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    activeTrackColor: const Color(0xFF7B40B5),
                    thumbColor: const Color(0xFF7B40B5),
                    inactiveTrackColor: Colors.purple.shade50,
                  ),
                  child: Slider(
                    value: _radiusKm,
                    min: 5.0,
                    max: 100.0,
                    divisions: 19,
                    label: _radiusKm >= 100.0 ? 'Any' : '${_radiusKm.toInt()} km',
                    onChanged: _onRadiusChanged,
                  ),
                ),

                // Quick Radius Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _radiusChips.map((rad) {
                      final isSelected = _radiusKm == rad;
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
                            if (val) _onRadiusChanged(rad);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 12),

                // Bottom Buttons: Use My Location & Apply Location
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isLoadingLocation ? null : _useDeviceLocation,
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
                      child: ElevatedButton.icon(
                        onPressed: _applyAndClose,
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(
                          _radiusKm >= 100.0
                              ? 'Apply (All Distances)'
                              : 'Apply (${_radiusKm.toInt()} km)',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7B40B5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
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
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
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
