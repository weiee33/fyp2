import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-wide display preference. API identifiers and customer content remain
/// unchanged. English is the explicit first-launch default, regardless of OS.
class AppLanguage extends ChangeNotifier {
  AppLanguage._();
  static final instance = AppLanguage._();
  static const supported = [Locale('en'), Locale('zh'), Locale('ms')];
  static const names = {'en': 'English', 'zh': '简体中文', 'ms': 'Bahasa Melayu'};
  static const preferenceKey = 'home_serve.language';
  String _code = 'en';
  Map<String, List<String>> _catalog = {};
  final Map<String, String> _resolved = {};
  String get code => _code;
  Locale get locale => Locale(_code);
  String get name => names[_code]!;
  String get speechLocale => {'en': 'en_MY', 'zh': 'zh_CN', 'ms': 'ms_MY'}[_code]!;

  Future<void> load() async {
    final data = jsonDecode(await rootBundle.loadString('assets/l10n/messages.json')) as Map<String, dynamic>;
    _catalog = data.map((key, value) => MapEntry(key, List<String>.from(value as List)));
    await initializeDateFormatting();
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(preferenceKey);
    _code = names.containsKey(saved) ? saved! : 'en';
    Intl.defaultLocale = _code;
    _resolved.clear();
    notifyListeners();
  }

  Future<void> select(String code) async {
    if (!names.containsKey(code)) throw ArgumentError.value(code, 'code');
    if (code == _code) return;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(preferenceKey, code)) {
      throw StateError('Could not save language');
    }
    _code = code;
    Intl.defaultLocale = code;
    _resolved.clear();
    notifyListeners();
  }

  /// Only use for app-owned display copy, never arbitrary user messages/names.
  /// Templates preserve substituted values verbatim and support reordered slots.
  String text(String source) {
    if (_code == 'en') return source;
    return _resolved.putIfAbsent(source, () {
      final index = _code == 'zh' ? 0 : 1;
      final exact = _catalog[source];
      if (exact != null) return exact[index];
      for (final entry in _catalog.entries) {
        if (!entry.key.contains(RegExp(r'\{\d+\}'))) continue;
        final slots = RegExp(r'\{(\d+)\}').allMatches(entry.key).toList();
        var pattern = '^';
        var end = 0;
        for (final slot in slots) {
          pattern += RegExp.escape(entry.key.substring(end, slot.start));
          pattern += '([\\s\\S]*?)';
          end = slot.end;
        }
        pattern += '${RegExp.escape(entry.key.substring(end))}\$';
        final match = RegExp(pattern).firstMatch(source);
        if (match == null) continue;
        final values = <String, String>{};
        for (var i = 0; i < slots.length; i++) {
          values[slots[i].group(1)!] = match.group(i + 1)!;
        }
        return entry.value[index].replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) => values[m.group(1)] ?? m.group(0)!);
      }
      return source;
    });
  }

  static void watch(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<LanguageScope>();
  }
}

class LanguageScope extends InheritedNotifier<AppLanguage> {
  LanguageScope({super.key, required super.child}) : super(notifier: AppLanguage.instance);
}

String tr(String source) => AppLanguage.instance.text(source);
String? trOrNull(String? source) => source == null ? null : tr(source);
