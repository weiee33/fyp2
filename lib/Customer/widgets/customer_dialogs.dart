import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Customer feedback always stays visible until acknowledged.
class CustomerDialogs {
  static final Set<Object> _open = {};
  static Future<void> show(
    BuildContext context, {
    required String message,
    String title = 'Home Serve',
  }) async {
    final Object owner =
        context; // Identity only; no widget access after disposal.
    if (!context.mounted ||
        ModalRoute.of(context)?.isCurrent == false ||
        !_open.add(owner)) {
      return;
    }
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(tr(title)),
            content: SingleChildScrollView(child: Text(tr(message))),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('OK')),
              ),
            ],
          ),
        ),
      );
    } finally {
      _open.remove(owner);
    }
  }

  static Future<bool> confirm(
    BuildContext context, {
    required String message,
    required String title,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(tr(title)),
          content: Text(tr(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('OK')),
            ),
          ],
        ),
      ) ??
      false;

  static Future<void> error(BuildContext context, Object error) => show(
    context,
    title: tr('Unable to complete'),
    message: errorMessage(error),
  );

  static String errorMessage(Object error) {
    if (error is AuthException) return error.message;
    if (error is PostgrestException) {
      return error.code == '23505'
          ? 'These details are already in use. Please check and try again.'
          : error.message;
    }
    if (error is FormatException) return error.message;
    return 'Please check your connection and try again.';
  }
}
