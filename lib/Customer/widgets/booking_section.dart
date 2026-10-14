import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import '../core/customer_theme.dart';

class BookingSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool highlighted;
  final Color? accentColor;
  const BookingSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.highlighted = false,
    this.accentColor,
  });
  @override
  Widget build(BuildContext context) { AppLanguage.watch(context); return  Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color:
          accentColor?.withValues(alpha: .05) ??
          (highlighted ? CustomerTheme.primarySurface : Colors.white),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color:
            accentColor?.withValues(alpha: .3) ??
            (highlighted
                ? CustomerTheme.primaryLight
                : CustomerTheme.borderColor),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: accentColor ?? CustomerTheme.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr(title),
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
  ); }
}
