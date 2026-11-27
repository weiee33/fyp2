import 'package:flutter/material.dart';
import 'package:fyp2/shared/localization/app_language.dart';

class ProviderFloatingNavBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTabChanged;
  final bool visible;
  final int homeBadgeCount;
  final int bookingsBadgeCount;

  const ProviderFloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabChanged,
    this.visible = true,
    this.homeBadgeCount = 0,
    this.bookingsBadgeCount = 0,
  });

  @override
  State<ProviderFloatingNavBar> createState() => _ProviderFloatingNavBarState();
}

class _ProviderFloatingNavBarState extends State<ProviderFloatingNavBar> {
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _textSecondary = Color(0xFF6B7280);

  void _showAiMenu(BuildContext context) {
    final overlay = Overlay.of(context);
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlayBox = overlay.context.findRenderObject() as RenderBox;

    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlayBox);
    final buttonCenterX = buttonPosition.dx + (button.size.width / 2);

    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) {
        final lang = Localizations.localeOf(context).languageCode;
        final isZh = lang == 'zh';
        final isMs = lang == 'ms';

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => overlayEntry.remove(),
                behavior: HitTestBehavior.translucent,
              ),
            ),
            Positioned(
              bottom: MediaQuery.of(context).size.height - buttonPosition.dy + 8,
              // 👇 把 left 设为 -90（因为宽度设为 200，一半就是 100，留一点边距），让菜单稍微宽一点
              left: buttonCenterX - 100,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      alignment: Alignment.bottomCenter,
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    // 👇 加宽到 200，文字靠左更自然
                    width: 200,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 12,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            overlayEntry.remove();
                            widget.onTabChanged(2);
                          },
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                          child: Padding(
                            // 👇 文字靠左对齐，并增加 padding
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                isZh ? 'AI 匹配' : (isMs ? 'AI Padanan' : 'AI Job Match'),
                                style: const TextStyle(
                                    color: Colors.black87,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                        Divider(height: 1, color: Colors.grey.shade100),
                        InkWell(
                          onTap: () {
                            overlayEntry.remove();
                            widget.onTabChanged(3);
                          },
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                isZh ? 'AI 日程' : (isMs ? 'AI Jadual' : 'AI Smart Schedule'),
                                style: const TextStyle(
                                    color: Colors.black87,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(overlayEntry);
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottomGap = MediaQuery.viewPaddingOf(context).bottom + 16.0;
    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    final shouldShow = widget.visible && !keyboardOpen;
    final hiddenOffset = -(80 + bottomGap);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      left: 16,
      right: 16,
      bottom: shouldShow ? bottomGap : hiddenOffset,
      child: SizedBox(
        height: 80,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _tab(
                    0,
                    Icons.home_outlined,
                    isZh ? '首页' : (isMs ? 'Utama' : 'Home'),
                    badgeCount: widget.homeBadgeCount,
                  ),
                  _tab(
                    1,
                    Icons.receipt_long_outlined,
                    isZh ? '预约' : (isMs ? 'Tempahan' : 'Bookings'),
                    badgeCount: widget.bookingsBadgeCount,
                  ),
                  const SizedBox(width: 60),
                  _tab(4, Icons.calendar_today_outlined,
                      isZh ? '日程' : (isMs ? 'Jadual' : 'Schedule')),
                  _tab(5, Icons.person_outline_rounded,
                      isZh ? '我的' : (isMs ? 'Profil' : 'Profile')),
                ],
              ),
            ),
            Positioned(
              bottom: 24,
              child: Builder(
                builder: (menuContext) => GestureDetector(
                  onTap: () => _showAiMenu(menuContext),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _primaryOrange,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: _primaryOrange.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(int index, IconData icon, String label, {int badgeCount = 0}) {
    final selected = widget.currentIndex == index;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: () => widget.onTabChanged(index),
          child: SizedBox(
            height: 64,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 22,
                        color: selected ? _primaryOrange : _textSecondary,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          color: selected ? _primaryOrange : _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: 10,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        badgeCount > 9 ? '9+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
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