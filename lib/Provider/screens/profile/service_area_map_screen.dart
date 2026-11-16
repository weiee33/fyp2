import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../Customer/services/customer_location_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ServiceAreaMapScreen extends StatefulWidget {
  final LatLng? initial;
  final double radiusKm;
  const ServiceAreaMapScreen({super.key, this.initial, required this.radiusKm});

  @override
  State<ServiceAreaMapScreen> createState() => _ServiceAreaMapState();
}

class _ServiceAreaMapState extends State<ServiceAreaMapScreen> {
  late LatLng? _point = widget.initial;
  final _map = MapController();
  bool _locating = false;
  String? _error;

  // 🎨 Unified theme colors
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final point = await CustomerLocationService.currentPosition();
      if (!mounted) return;
      if (point.latitude < -1 ||
          point.latitude > 8 ||
          point.longitude < 99 ||
          point.longitude > 120) {
        throw const FormatException('Select a service area in Malaysia.');
      }
      setState(() => _point = point);
      _map.move(point, 12);
    } catch (_) {
      if (mounted) {
        setState(
              () => _error =
          'Location unavailable. Tap the map to select your service centre.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          tr('Service area centre'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ---- Top Info Bar ----
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: _lightOrange,
              border: Border(
                bottom: BorderSide(color: _borderOrange),
              ),
            ),
            child: Text(
              tr(
                'Tap your business or service-area centre. This pin and your service radius will be visible to customers.',
              ),
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
          ),

          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.red.shade50,
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // ---- Map Area ----
          Expanded(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _point ?? const LatLng(4.2, 108),
                initialZoom: _point == null ? 5 : 12,
                maxZoom: 19,
                onTap: (_, p) {
                  if (p.latitude >= -1 &&
                      p.latitude <= 8 &&
                      p.longitude >= 99 &&
                      p.longitude <= 120) {
                    setState(() => _point = p);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: const String.fromEnvironment(
                    'MAP_TILE_URL',
                    defaultValue:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),
                  userAgentPackageName: 'com.locallife.fyp2',
                ),
                if (_point != null)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: _point!,
                        radius: widget.radiusKm * 1000,
                        useRadiusInMeter: true,
                        color: _primaryOrange.withValues(alpha: .15),
                        borderColor: _primaryOrange,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                if (_point != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _point!,
                        child: const Icon(
                          Icons.location_pin,
                          color: _primaryOrange,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                      onTap: () => launchUrl(
                        Uri.parse('https://www.openstreetmap.org/copyright'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ---- Bottom Action Panel ----
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: _borderOrange),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    _point == null
                        ? tr('Select a pin to continue')
                        : tr("{0} km from {1}, {2}", [
                      widget.radiusKm.toInt(),
                      _point!.latitude.toStringAsFixed(4),
                      _point!.longitude.toStringAsFixed(4),
                    ]),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _locating ? null : _locate,
                    icon: const Icon(Icons.my_location, color: _primaryOrange),
                    label: Text(
                      tr(_locating ? 'Locating…' : 'Use my location'),
                      style: const TextStyle(color: _primaryOrange),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _point == null
                          ? null
                          : () => Navigator.pop(context, _point),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        tr('Use this service centre'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}