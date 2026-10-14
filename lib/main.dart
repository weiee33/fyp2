import 'Customer/core/customer_theme.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'Provider/core/supabase_config.dart';
import 'shared/portal_entry_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'shared/localization/app_language.dart';
import 'shared/brand/brand_splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(LanguageScope(child: const LocalLifeApp()));
}

Future<void> _initialize() async {
  await AppLanguage.instance.load();
  await Supabase.initialize(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
}

class LocalLifeApp extends StatelessWidget {
  const LocalLifeApp({super.key});

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return MaterialApp(
      theme: CustomerTheme.lightTheme,
      title: 'Home Serve',
      locale: AppLanguage.instance.locale,
      supportedLocales: AppLanguage.supported,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      home: BrandSplash(initialize: _initialize, child: const PortalEntryScreen()),
    );
  }
}
