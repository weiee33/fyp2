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

  // 🎨 Unified theme colors
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  // ============= Pop-up Box 弹窗 =============
  void _showAppDialog({required String title, required String message, required bool isError}) {
    showDialog(
      context: context,
      builder: (ctx) {
        final lang = Localizations.localeOf(context).languageCode;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 10,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isError ? Colors.red.shade50 : Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isError ? Icons.error_outline : Icons.check_circle_outline,
                    color: isError ? Colors.red.shade600 : Colors.green.shade600,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      lang == 'zh' ? '知道了' : (lang == 'ms' ? 'OK' : 'OK'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
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
        final lang = Localizations.localeOf(context).languageCode;
        _showAppDialog(
          title: lang == 'zh' ? '定位失败' : (lang == 'ms' ? 'Gagal mencari lokasi' : 'Location Error'),
          message: lang == 'zh'
              ? '无法获取当前位置。请点击地图选择您服务中心的位置。'
              : (lang == 'ms'
              ? 'Lokasi tidak tersedia. Ketik peta untuk memilih pusat perkhidmatan anda.'
              : 'Location unavailable. Tap the map to select your service centre.'),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          isZh ? '服务区域中心' : (isMs ? 'Pusat kawasan perkhidmatan' : 'Service area centre'),
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
              isZh
                  ? '点击您的业务或服务区域中心。此图钉和您的服务半径将对客户可见。'
                  : (isMs
                  ? 'Ketik pusat perniagaan atau kawasan perkhidmatan anda. Pin ini dan radius perkhidmatan anda akan kelihatan kepada pelanggan.'
                  : 'Tap your business or service-area centre. This pin and your service radius will be visible to customers.'),
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
                height: 1.4,
              ),
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
                        ? (isZh
                        ? '选择一个图钉以继续'
                        : (isMs
                        ? 'Pilih pin untuk meneruskan'
                        : 'Select a pin to continue'))
                        : (isZh
                        ? '距离 ${_point!.latitude.toStringAsFixed(4)}, ${_point!.longitude.toStringAsFixed(4)} 约 ${widget.radiusKm.toInt()} 公里'
                        : (isMs
                        ? '${widget.radiusKm.toInt()} km dari ${_point!.latitude.toStringAsFixed(4)}, ${_point!.longitude.toStringAsFixed(4)}'
                        : '${widget.radiusKm.toInt()} km from ${_point!.latitude.toStringAsFixed(4)}, ${_point!.longitude.toStringAsFixed(4)}')),
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
                      _locating
                          ? (isZh ? '定位中...' : (isMs ? 'Mencari lokasi...' : 'Locating...'))
                          : (isZh ? '使用我的位置' : (isMs ? 'Guna lokasi saya' : 'Use my location')),
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
                        isZh
                            ? '使用此服务中心'
                            : (isMs
                            ? 'Gunakan pusat perkhidmatan ini'
                            : 'Use this service centre'),
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