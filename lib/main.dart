import 'Customer/services/customer_push_service.dart';
import 'Customer/core/customer_theme.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'Provider/core/supabase_config.dart';
import 'shared/mobile_auth_service.dart';
import 'shared/mobile_session_gate.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'shared/localization/app_language.dart';
import 'shared/brand/brand_splash.dart';
import 'shared/app_scroll_behavior.dart';
import 'Customer/agent/agent_host.dart';
import 'Customer/services/customer_access.dart';
import 'Customer/widgets/customer_access_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(LanguageScope(child: const LocalLifeApp()));
}

Future<void>? _startup;
Future<void> _initialize() =>
    _startup ??= _initializeOnce().catchError((Object error) {
      _startup = null;
      throw error;
    });

Future<void> _initializeOnce() async {
  await AppLanguage.instance.load();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  await CustomerPushService.instance.initialize();
  CustomerAccess.instance.initialize(Supabase.instance.client);
}

class LocalLifeApp extends StatelessWidget {
  final Future<void> Function()? initialize;
  final MobileAuthService? authService;
  const LocalLifeApp({super.key, this.initialize, this.authService});

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return MaterialApp(
      navigatorKey: customerNavigatorKey,
      navigatorObservers: [customerAccessObserver],
      builder: (context, child) => CustomerAccessHost(
        child: AgentHost(child: child ?? const SizedBox.shrink()),
      ),
      scrollBehavior: const AppScrollBehavior(),
      theme: CustomerTheme.lightTheme,
      title: 'Local Life Service Assistant',
      locale: AppLanguage.instance.locale,
      supportedLocales: AppLanguage.supported,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      home: BrandSplash(
        initialize: initialize ?? _initialize,
        child: MobileSessionGate(service: authService),
      ),
    );
  }
}
