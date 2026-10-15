import 'package:flutter/material.dart';
import 'app_language.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});
  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String _selected = AppLanguage.instance.code;
  bool _saving = false;
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AppLanguage.instance.select(_selected);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Could not save your language. Please retry.')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Choose language')),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(tr('Done')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final entry in AppLanguage.names.entries) ...[
                  if (entry.key != 'en')
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  Semantics(
                    selected: _selected == entry.key,
                    child: ListTile(
                      title: Text(entry.value),
                      minVerticalPadding: 18,
                      selected: _selected == entry.key,
                      selectedTileColor: const Color(0xFFFFF3E8),
                      trailing: AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        child: _selected == entry.key
                            ? const Icon(
                                Icons.check_rounded,
                                key: ValueKey('selected'),
                                color: Color(0xFFFF6B00),
                              )
                            : const SizedBox(width: 24),
                      ),
                      onTap: _saving
                          ? null
                          : () => setState(() => _selected = entry.key),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              tr(
                'Applies throughout Home Serve. Your messages and provider descriptions stay in their original language.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
