import 'package:flutter/material.dart';
import '../localization/app_language.dart';

class HomeServeMark extends StatelessWidget {
  final double size;
  const HomeServeMark({super.key, this.size = 120});
  @override
  Widget build(BuildContext context) => Image.asset('assets/brand/home-serve-mark.png', width: size, height: size, semanticLabel: 'Home Serve');
}

/// Runs once per app launch. Startup work can run while the first frame is shown;
/// reduced-motion users see a static mark, and failures expose a real retry.
class BrandSplash extends StatefulWidget {
  final Future<void> Function() initialize;
  final Widget child;
  const BrandSplash({super.key, required this.initialize, required this.child});
  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
  bool _ready = false, _failed = false, _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _start();
  }
  Future<void> _start() async {
    setState(() => _failed = false);
    final reduced = MediaQuery.disableAnimationsOf(context);
    try {
      await Future.wait([
        widget.initialize().timeout(const Duration(seconds: 25)),
        if (!reduced) _motion.forward(from: 0).orCancel,
      ]);
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }
  @override
  void dispose() { _motion.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 300),
      child: _ready ? KeyedSubtree(key: const ValueKey('ready'), child: widget.child) : Scaffold(
        key: const ValueKey('launch'),
        backgroundColor: Colors.white,
        body: SafeArea(child: Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: reduced ? const AlwaysStoppedAnimation(1.0) : Tween(begin: .92, end: 1.0).animate(CurvedAnimation(parent: _motion, curve: Curves.easeOutCubic)),
              child: const HomeServeMark(),
            ),
            const SizedBox(height: 24),
            FadeTransition(
              opacity: reduced ? const AlwaysStoppedAnimation(1.0) : CurvedAnimation(parent: _motion, curve: const Interval(.25, 1, curve: Curves.easeOut)),
              child: Column(children: [
                const Text('Home Serve', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -.7)),
                const SizedBox(height: 8),
                Text(tr('A little care. A better home.'), style: const TextStyle(color: Color(0xFF6B7280))),
              ]),
            ),
            if (_failed) ...[
              const SizedBox(height: 32),
              Text(tr('Unable to start. Check your connection and retry.')),
              TextButton(onPressed: _start, child: Text(tr('Retry'))),
            ],
          ],
        ))),
      ),
    );
  }
}
