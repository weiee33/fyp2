import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'provider/core/supabase_config.dart';
import 'provider/core/provider_theme.dart';
import 'provider/screens/auth/login_screen.dart';
import 'provider/screens/profile/my_profile_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  // Uncomment after adding firebase config files:
  // await Firebase.initializeApp();

  runApp(const LocalLifeProviderApp());
}

class LocalLifeProviderApp extends StatelessWidget {
  const LocalLifeProviderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Life Provider',
      theme: ProviderTheme.light,
      debugShowCheckedModeBanner: false,
      home: Supabase.instance.client.auth.currentSession == null
          ? const LoginScreen()
          : const MyProfileScreen(),
    );
  }
}