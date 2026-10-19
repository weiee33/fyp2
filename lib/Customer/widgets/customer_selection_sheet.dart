import '../agent/agent_surface.dart';
import 'customer_scaffold.dart';
import 'package:flutter/material.dart';
import '../core/customer_theme.dart';

class CustomerChoice<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData icon;
  const CustomerChoice({
    required this.value,
    required this.label,
    this.subtitle,
    required this.icon,
  });
}

/// One consistent, scrollable picker for short options and full postal addresses.
Future<T?> showCustomerSelection<T>({
  required BuildContext context,
  required String title,
  required List<CustomerChoice<T>> choices,
  T? selected,
  bool agentChoices = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => AgentSurface(
      name: agentChoices ? 'address_picker' : 'unsupported',
      localChoices: agentChoices,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .7,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: CustomerTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    physics: customerScrollPhysics(context),
                    shrinkWrap: true,
                    itemCount: choices.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final choice = choices[index];
                      final active = choice.value == selected;
                      return Semantics(
                        selected: active,
                        button: true,
                        child: Material(
                          color: active
                              ? CustomerTheme.primarySurface
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: active
                                  ? CustomerTheme.primary
                                  : CustomerTheme.borderColor,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () =>
                                Navigator.pop(sheetContext, choice.value),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(
                                    choice.icon,
                                    color: active
                                        ? CustomerTheme.primary
                                        : CustomerTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          choice.label,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: CustomerTheme.textPrimary,
                                          ),
                                        ),
                                        if (choice.subtitle != null) ...[
                                          const SizedBox(height: 5),
                                          Text(
                                            choice.subtitle!,
                                            style: const TextStyle(
                                              height: 1.4,
                                              color:
                                                  CustomerTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(
                                    active
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: active
                                        ? CustomerTheme.primary
                                        : CustomerTheme.borderColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
