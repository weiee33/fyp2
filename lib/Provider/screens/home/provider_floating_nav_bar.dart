import 'package:flutter/material.dart';
import 'package:fyp2/shared/localization/app_language.dart';

class ProviderFloatingNavBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTabChanged;

  const ProviderFloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabChanged,
  });

  @override
  State<ProviderFloatingNavBar> createState() => _ProviderFloatingNavBarState();
}

class _ProviderFloatingNavBarState extends State<ProviderFloatingNavBar> {
  static const _primaryOrange = Color(0xFFFF6B00);
  static const _textSecondary = Color(0xFF6B7280);

  // 【核心修改】使用绝对定位 + Overlay 弹窗，确保 100% 能点到
  void _showAiMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    // 计算中间按钮相对于屏幕的位置，让菜单精准弹在按钮正上方
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(button.size.width / 2, 0), ancestor: overlay),
        button.localToGlobal(Offset(button.size.width / 2, 0), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    showMenu<int>(
      context: context,
      position: position.shift(const Offset(-110, -140)), // 往左偏移居中，往上弹出
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      elevation: 8,
      items: [
        PopupMenuItem<int>(
          value: 2,
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: _primaryOrange, size: 20),
              const SizedBox(width: 12),
              Text(
                isZh ? 'AI 匹配' : (isMs ? 'AI Padanan' : 'AI Job Match'),
                style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<int>(
          value: 3,
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_outlined, color: _primaryOrange, size: 20),
              const SizedBox(width: 12),
              Text(
                isZh ? 'AI 日程' : (isMs ? 'AI Jadual' : 'AI Smart Schedule'),
                style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    ).then((selectedTab) {
      if (selectedTab != null) {
        widget.onTabChanged(selectedTab);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardOpen) {
      return const SizedBox.shrink();
    }

    final bottomGap = MediaQuery.viewPaddingOf(context).bottom + 16.0;
    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottomGap,
      child: SizedBox(
        height: 80,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // 1. 背景导航栏
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
                  _tab(0, Icons.home_outlined, isZh ? '首页' : (isMs ? 'Utama' : 'Home')),
                  _tab(1, Icons.receipt_long_outlined, isZh ? '预约' : (isMs ? 'Tempahan' : 'Bookings')),
                  const SizedBox(width: 60), // 中间凸起按钮的留空
                  _tab(4, Icons.calendar_today_outlined, isZh ? '日程' : (isMs ? 'Jadual' : 'Schedule')),
                  _tab(5, Icons.person_outline_rounded, isZh ? '我的' : (isMs ? 'Profil' : 'Profile')),
                ],
              ),
            ),

            // 2. 中间凸起的网格按钮（点击直接触发全局弹出菜单）
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
                      Icons.grid_view_rounded,
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

  Widget _tab(int index, IconData icon, String label) {
    final selected = widget.currentIndex == index;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: () => widget.onTabChanged(index),
          child: SizedBox(
            height: 64,
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
        ),
      ),
    );
  }
}