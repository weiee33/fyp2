import '../../shared/localization/app_language.dart';

/// Event keys are assigned by the server when the change occurs. A historical
/// suspension stays a warning even after the account is reactivated.
class CustomerNotificationContent {
  static bool isSuspension(Map<String, dynamic> notification) =>
      notification['event_key'] == 'account.suspended';

  static String message(Map<String, dynamic> notification) {
    final source = notification['message']?.toString() ?? '';
    if (isSuspension(notification)) {
      return '${tr('Your account is suspended. Contact Help Centre for support.')}\n$source'
          .trim();
    }
    if (notification['event_key'] == 'account.reactivated') {
      return '${tr('Your account is active now.')}\n$source'.trim();
    }
    if (notification['event_key'] == 'customer.activity') {
      // Each line is fixed application copy. Do not translate arbitrary admin
      // reasons, chat messages or other user-authored content line by line.
      return source.split('\n').map(tr).join('\n');
    }
    return tr(source);
  }
}
