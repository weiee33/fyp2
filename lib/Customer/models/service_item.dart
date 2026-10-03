/// Public discovery projection. Never contains private provider/account fields.
class ServiceItem {
  final String serviceId;
  final String providerId;
  final String categoryId;
  final String categoryName;
  final String name;
  final String description;
  final double price;
  final String businessName;
  final double rating;
  final int reviewCount;
  final String? photoUrl;
  final int? durationMinutes;
  final String? city;
  final String pricingType;

  const ServiceItem({
    required this.serviceId,
    required this.providerId,
    required this.categoryId,
    required this.categoryName,
    required this.name,
    required this.description,
    required this.price,
    required this.businessName,
    required this.rating,
    required this.reviewCount,
    this.photoUrl,
    this.durationMinutes,
    this.city,
    this.pricingType = 'Fixed',
  });

  factory ServiceItem.fromJson(Map<String, dynamic> json) => ServiceItem(
    serviceId: json['service_id'] as String,
    providerId: json['provider_id'] as String,
    categoryId: json['category_id'] as String,
    categoryName: json['category_name'] as String,
    name: json['service_name'] as String,
    description: json['description'] as String? ?? '',
    price: (json['base_price'] as num).toDouble(),
    businessName: json['business_name'] as String,
    rating: (json['overall_rating'] as num?)?.toDouble() ?? 0,
    reviewCount: (json['total_reviews'] as num?)?.toInt() ?? 0,
    photoUrl: json['profile_photo_url'] as String?,
    durationMinutes: (json['estimated_duration'] as num?)?.toInt(),
    city: json['city'] as String?,
    pricingType: json['pricing_type'] as String? ?? 'Fixed',
  );

  String get ratingLabel => reviewCount == 0
      ? 'No reviews yet'
      : '${rating.toStringAsFixed(1)} ($reviewCount reviews)';

  String get priceLabel =>
      'RM ${price.toStringAsFixed(2)}${pricingType == 'Hourly' ? '/hour' : ''}';
}
