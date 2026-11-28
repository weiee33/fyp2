import 'package:flutter/material.dart';
import 'localization/app_language.dart';

class PhotoRemoveButton extends StatelessWidget {
  const PhotoRemoveButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tr('Remove photo'),
    style: IconButton.styleFrom(
      backgroundColor: Colors.black54,
      foregroundColor: Colors.white,
      minimumSize: const Size(32, 32),
      padding: EdgeInsets.zero,
    ),
    onPressed: onPressed,
    icon: const Icon(Icons.close, size: 18),
  );
}
