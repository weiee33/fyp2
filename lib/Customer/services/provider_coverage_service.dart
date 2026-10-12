import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'customer_transaction_service.dart';

class ProviderCoverage {
  final String id, name, city;
  final LatLng centre;
  final double radiusKm;
  final List<String> services;
  ProviderCoverage(Map<String, dynamic> data)
    : id = data['provider_id'].toString(),
      name = data['business_name'].toString(),
      city = data['city']?.toString() ?? '',
      centre = LatLng(
        (data['service_latitude'] as num).toDouble(),
        (data['service_longitude'] as num).toDouble(),
      ),
      radiusKm = (data['service_radius_km'] as num).toDouble(),
      services = List<String>.from(data['services'] as List? ?? []);
  bool covers(LatLng point) =>
      const Distance().as(LengthUnit.Meter, centre, point) <= radiusKm * 1000;
}

class ProviderCoverageService {
  final CustomerRpc? rpc;
  ProviderCoverageService({this.rpc});
  Future<List<ProviderCoverage>> nearby(LatLng point) async {
    final params = {
      'p_lat': point.latitude,
      'p_lng': point.longitude,
      'p_range_km': 50,
    };
    final rows = await (rpc != null
        ? rpc!('customer_provider_coverage', params)
        : Supabase.instance.client.rpc(
            'customer_provider_coverage',
            params: params,
          ));
    return (rows as List)
        .map((r) => ProviderCoverage(Map<String, dynamic>.from(r as Map)))
        .toList();
  }
}
