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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Service area centre')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Tap your business or service-area centre. This pin and your service radius will be visible to customers.',
          ),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
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
                      color: Colors.orange.withValues(alpha: .15),
                      borderColor: Colors.orange,
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
                        color: Colors.deepOrange,
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
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  _point == null
                      ? 'Select a pin to continue'
                      : '${widget.radiusKm.toInt()} km from ${_point!.latitude.toStringAsFixed(4)}, ${_point!.longitude.toStringAsFixed(4)}',
                ),
                TextButton.icon(
                  onPressed: _locating ? null : _locate,
                  icon: const Icon(Icons.my_location),
                  label: Text(_locating ? 'Locating…' : 'Use my location'),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _point == null
                        ? null
                        : () => Navigator.pop(context, _point),
                    child: const Text('Use this service centre'),
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
