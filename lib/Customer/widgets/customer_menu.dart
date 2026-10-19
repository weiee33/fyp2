import 'package:flutter/material.dart';
import '../core/customer_theme.dart';

/// Shared menu surface for compact actions, with generous touch targets.
class CustomerMenu<T> extends StatelessWidget {
  const CustomerMenu({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.tooltip,
    this.initialValue,
    this.enabled = true,
    this.child,
    this.icon,
  });
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final String? tooltip;
  final T? initialValue;
  final bool enabled;
  final Widget? child;
  final Widget? icon;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    tooltip: tooltip,
    initialValue: initialValue,
    enabled: enabled,
    onSelected: onSelected,
    itemBuilder: itemBuilder,
    icon: icon,
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.black26,
    elevation: 8,
    constraints: const BoxConstraints(minWidth: 216, maxWidth: 280),
    menuPadding: const EdgeInsets.all(8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: CustomerTheme.borderColor),
    ),
    child: child,
  );
}

class CustomerMenuRow extends StatelessWidget {
  const CustomerMenuRow({
    super.key,
    this.icon,
    required this.label,
    this.selected = false,
    this.destructive = false,
    this.showCheck = true,
  });
  final IconData? icon;
  final String label;
  final bool selected;
  final bool destructive;
  final bool showCheck;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? CustomerTheme.danger
        : selected
        ? CustomerTheme.primary
        : CustomerTheme.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (selected && showCheck) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_rounded, size: 18, color: color),
          ],
        ],
      ),
    );
  }
}
