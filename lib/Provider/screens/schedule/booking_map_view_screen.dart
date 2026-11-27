import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class BookingMapViewScreen extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String address;
  final String title;

  const BookingMapViewScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.address,
    this.title = 'Customer Location',
  });

  @override
  State<BookingMapViewScreen> createState() => _BookingMapViewScreenState();
}

class _BookingMapViewScreenState extends State<BookingMapViewScreen> {
  // 🎨 Unified Orange + White theme
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  final _mapController = MapController();

  LatLng get _center => LatLng(widget.latitude, widget.longitude);

  void _recenter() {
    _mapController.move(_center, 15);
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);

    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    // 动态解析标题的多语言
    String displayTitle = widget.title;
    if (widget.title == 'Customer Location' || widget.title == '客户位置') {
      displayTitle = isZh ? '客户位置' : (isMs ? 'Lokasi Pelanggan' : 'Customer Location');
    } else if (widget.title == 'Service Address' || widget.title == '服务地址') {
      displayTitle = isZh ? '服务地址' : (isMs ? 'Alamat Perkhidmatan' : 'Service Address');
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          displayTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // ---- Map ----
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.fyp2',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _center,
                    width: 60,
                    height: 60,
                    child: const Icon(
                      Icons.location_pin,
                      color: _primaryOrange,
                      size: 50,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ---- Bottom Info Card (with Bouncing Scroll) ----
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            // 使用 ConstrainedBox 限制最大高度，并允许内容如果太长可以弹性滑动
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: Card(
                elevation: 4,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: _borderOrange),
                ),
                child: SingleChildScrollView(
                  // 👇 添加了弹性滑动
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _lightOrange,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: _primaryOrange,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isZh ? '服务地址' : (isMs ? 'Alamat Perkhidmatan' : 'Service Address'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _primaryOrange,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.address,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.my_location,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.latitude.toStringAsFixed(6)}, ${widget.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ---- Recenter Button ----
          Positioned(
            right: 16,
            // 根据屏幕高度动态调整定位，避免遮挡底部卡片
            bottom: MediaQuery.of(context).size.height * 0.4 + 30,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              backgroundColor: Colors.white,
              foregroundColor: _primaryOrange,
              elevation: 2,
              tooltip: isZh
                  ? '回到当前位置'
                  : (isMs ? 'Kembali ke lokasi' : 'Recenter'),
              onPressed: _recenter,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}