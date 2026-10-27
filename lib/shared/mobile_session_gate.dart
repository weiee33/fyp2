import 'package:flutter/material.dart';
import 'localization/app_language.dart';
import 'mobile_account_home.dart';
import 'mobile_auth_service.dart';
import 'portal_entry_screen.dart';

/// Used only at app startup; explicit logout still opens PortalEntryScreen.
class MobileSessionGate extends StatefulWidget {
  const MobileSessionGate({super.key, this.service, this.homeBuilder});

  final MobileAuthService? service;
  final Widget Function(MobileAccountRole)? homeBuilder;

  @override
  State<MobileSessionGate> createState() => _MobileSessionGateState();
}

class _MobileSessionGateState extends State<MobileSessionGate>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? MobileAuthService();
  bool _restoring = false, _failed = false;
  MobileAccountRole? _role;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  Future<void> _restore() async {
    if (_restoring) return;
    setState(() {
      _restoring = true;
      _failed = false;
    });
    try {
      final role = await _service.restoreSession();
      if (mounted) setState(() => _role = role);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _failed) _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    if (!_restoring && !_failed) {
      return _role == null
          ? const PortalEntryScreen()
          : (widget.homeBuilder ?? mobileAccountHome)(_role!);
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_restoring) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(tr('Restoring your session...')),
                ] else ...[
                  Text(
                    tr(
                      'Unable to restore your session. Check your connection and retry.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _restore, child: Text(tr('Retry'))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
