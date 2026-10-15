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
  String get code => _code;
  Locale get locale => Locale(_code);
  String get name => names[_code]!;
  String get speechLocale =>
      {'en': 'en_MY', 'zh': 'zh_CN', 'ms': 'ms_MY'}[_code]!;

  Future<void> load() async {
    final data =
        jsonDecode(await rootBundle.loadString('assets/l10n/messages.json'))
            as Map<String, dynamic>;
    _catalog = data.map(
      (key, value) => MapEntry(key, List<String>.from(value as List)),
    );
    await initializeDateFormatting();
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(preferenceKey);
    _code = names.containsKey(saved) ? saved! : 'en';
    Intl.defaultLocale = _code;
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
    notifyListeners();
  }

  /// Only use for app-owned display copy, never arbitrary user messages/names.
  /// Templates preserve substituted values verbatim and support reordered slots.
  String text(String source, [List<Object?> arguments = const []]) {
    final translated = _code == 'en'
        ? source
        : _catalog[source]?[_code == 'zh' ? 0 : 1] ?? source;
    if (arguments.isEmpty) return translated;
    return translated.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
      final index = int.parse(match.group(1)!);
      return index < arguments.length
          ? '${arguments[index] ?? ''}'
          : match.group(0)!;
    });
  }

  static void watch(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<LanguageScope>();
  }
}

class LanguageScope extends InheritedNotifier<AppLanguage> {
  LanguageScope({super.key, required super.child})
    : super(notifier: AppLanguage.instance);
}

String tr(String source, [List<Object?> arguments = const []]) =>
    AppLanguage.instance.text(source, arguments);
String? trOrNull(String? source) => source == null ? null : tr(source);

/// Relative timestamps are app copy, independent of stored ISO timestamps.
String relativeTime(DateTime value, {DateTime? now}) {
  final age = (now ?? DateTime.now()).difference(value);
  if (age.inMinutes < 1) return tr('Just now');
  if (age.inHours < 1) return tr('{0} min ago', [age.inMinutes]);
  if (age.inDays < 1) return tr('{0} hr ago', [age.inHours]);
  if (age.inDays < 7) return tr('{0} days ago', [age.inDays]);
  return DateFormat.yMMMd().format(value.toLocal());
}

/// Translate only fixed, versioned summary copy, preserving server-authoritative
/// booking values and any user-provided instructions or cancellation reasons.
String actionSummary(Map<String, dynamic> action) {
  final source = action['summary']?.toString() ?? '';
  final lines = source.split('\n');
  if (action['kind'] == 'booking' &&
      lines.length >= 5 &&
      lines.last ==
          'Provider acceptance is required. Payment is handled by you.') {
    lines[2] = lines[2].replaceFirst('(Malaysia time)', tr('(Malaysia time)'));
    if (lines.length > 5 && lines[4].startsWith('Instructions: ')) {
      lines[4] = tr('Instructions: {0}', [lines[4].substring(14)]);
    }
    lines[lines.length - 1] = tr(lines.last);
  } else if (action['kind'] == 'cancel_booking' &&
      lines.length >= 3 &&
      lines.first.startsWith('Cancel ') &&
      lines.first.endsWith('?') &&
      lines[1].startsWith('Reason: ') &&
      lines.last ==
          'Paid bookings follow the existing support/refund process; cancellation is not a refund confirmation.') {
    lines[0] = tr('Cancel {0}?', [
      lines.first.substring(7, lines.first.length - 1),
    ]);
    lines[1] = tr('Reason: {0}', [lines[1].substring(8)]);
    lines[lines.length - 1] = tr(lines.last);
  }
  return lines.join('\n');
}
