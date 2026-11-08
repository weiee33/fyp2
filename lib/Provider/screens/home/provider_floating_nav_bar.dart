import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:fyp2/shared/localization/app_language.dart'; // Import tr()


class ProviderFloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTabChanged;
  final VoidCallback onOpenAi;

  const ProviderFloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabChanged,
    required this.onOpenAi,
  });

  static const _primaryOrange = Color(0xFFFF6B00);
  static const _textSecondary = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    // Add this to listen to language changes so the bar rebuilds
    AppLanguage.watch(context);

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardOpen) return const SizedBox.shrink();

    final bottomGap = MediaQuery.viewPaddingOf(context).bottom + 16.0;

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottomGap,
      child: SizedBox(
        height: 80,
        child: Stack(
          children: [
            // Background blur layer
            Positioned.fill(
              top: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .08),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(36),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: .84),
                            Colors.white.withValues(alpha: .68),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(36),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .85),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Buttons layer
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Use tr() here
                _tab(0, tr('Home'), Icons.home_outlined),
                _tab(1, tr('Bookings'), Icons.receipt_long_outlined),

                // Center raised AI button
                Expanded(
                  child: Semantics(
                    button: true,
                    label: tr('Open AI assistant'), // Use tr()
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onOpenAi,
                      child: SizedBox(
                        height: 80,
                        child: Column(
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: _primaryOrange,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 4),
                                boxShadow: [
                                  BoxShadow(
                                    color: _primaryOrange.withValues(alpha: .3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.auto_awesome_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tr('AI'), // Use tr()
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                _tab(2, tr('Schedule'), Icons.calendar_today_outlined), // Use tr()
                _tab(3, tr('Profile'), Icons.person_outline_rounded), // Use tr()
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(int index, String label, IconData icon) {
    final selected = currentIndex == index;
    final glyph = Icon(
      icon,
      size: 23,
      color: selected ? _primaryOrange : _textSecondary,
    );

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: () => onTabChanged(index),
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected ? _primaryOrange.withValues(alpha: 0.1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: glyph,
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label, // Label is already translated when passed in
                    style: TextStyle(
                      fontSize: 11,
                      color: selected ? _primaryOrange : _textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}