import 'package:flutter/material.dart';
import '../core/customer_theme.dart';

class BookingSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool highlighted;
  const BookingSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.highlighted = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: highlighted ? CustomerTheme.primarySurface : Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: highlighted
            ? CustomerTheme.primaryLight
            : CustomerTheme.borderColor,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: CustomerTheme.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}
