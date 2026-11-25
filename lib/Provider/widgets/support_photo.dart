import 'package:flutter/material.dart';
import '../../shared/localization/app_language.dart';
import '../services/support_service.dart';

class SupportPhoto extends StatefulWidget {
  final String path;
  final ProviderSupportService service;
  const SupportPhoto({super.key, required this.path, required this.service});
  @override
  State<SupportPhoto> createState() => _SupportPhotoState();
}

class _SupportPhotoState extends State<SupportPhoto> {
  late Future<String> _url = widget.service.photoUrl(widget.path);

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _url,
    builder: (context, snapshot) {
      final retry = TextButton.icon(
        onPressed: () => setState(() => _url = widget.service.photoUrl(widget.path)),
        icon: const Icon(Icons.refresh),
        label: Text(tr('Retry photo')),
      );
      if (snapshot.hasError) return retry;
      if (!snapshot.hasData) {
        return const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          snapshot.data!,
          fit: BoxFit.contain,
          errorBuilder: (_, e, s) => retry,
        ),
      );
    },
  );
}