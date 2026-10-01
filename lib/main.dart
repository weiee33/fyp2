import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'Provider/core/supabase_config.dart';
import 'shared/portal_entry_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(const LocalLifeApp());
}

class LocalLifeApp extends StatelessWidget {
  const LocalLifeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Local Life Service Assistant',
      debugShowCheckedModeBanner: false,
      home: PortalEntryScreen(),
    );
  }
}