import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Customer feedback always stays visible until acknowledged.
class CustomerDialogs {
  static final Set<Object> _open = {};
  static Future<void> show(
    BuildContext context, {
    required String message,
    String title = 'Local Life',
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
            title: Text(title),
            content: SingleChildScrollView(child: Text(message)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
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
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OK'),
            ),
          ],
        ),
      ) ??
      false;

  static Future<void> error(BuildContext context, Object error) =>
      show(context, title: 'Unable to complete', message: errorMessage(error));

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
