import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/localization/app_language.dart';
import '../screens/booking/customer_booking_detail_screen.dart';

@pragma('vm:entry-point')
Future<void> homeServeBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Android displays the notification payload. Do not display a second copy.
}

/// Android alerts are bound to a signed-in customer's current auth session.
/// Supabase remains the identity authority; Firebase is only the delivery channel.
class CustomerPushService with WidgetsBindingObserver {
  CustomerPushService._();
  static final instance = CustomerPushService._();
  static AndroidNotificationChannel get channel => AndroidNotificationChannel(
    'booking_alerts',
    tr('Booking & Payment Alerts'),
    description: tr('Time-sensitive booking and payment updates'),
    importance: Importance.high,
  );
  final status = ValueNotifier<String>('Not Set Up');
  final _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _active = false;
  bool _syncing = false;
  Future<void>? _clearing;
  BuildContext? _context;
  String? _pending;
  String? _token;
  final Set<String> _displayed = {};
  SupabaseClient get _client => Supabase.instance.client;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (!supported || _initialized) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(homeServeBackgroundMessage);
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_home_serve'),
        ),
        onDidReceiveNotificationResponse: (response) => _open(response.payload),
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
      FirebaseMessaging.onMessage.listen((message) {
        unawaited(_foreground(message));
      });
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _open(message.data['notification_id']),
      );
      FirebaseMessaging.instance.onTokenRefresh.listen((_) {
        unawaited(sync());
      });
      _client.auth.onAuthStateChange.listen((event) {
        if (event.session == null) {
          _active = false;
          _pending = null;
          _token = null;
          _clearing = _clearDevice();
        } else if (_active) {
          unawaited(sync());
        }
      });
      _pending = (await FirebaseMessaging.instance.getInitialMessage())
          ?.data['notification_id'];
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _pending = launch?.notificationResponse?.payload;
      }
      _initialized = true;
      WidgetsBinding.instance.addObserver(this);
      AppLanguage.instance.addListener(() {
        unawaited(sync());
      });
      status.value = 'Not Enabled';
    } catch (_) {
      status.value = 'Not Set Up';
      // Missing device configuration must not prevent sign-in or in-app alerts.
    }
  }

  Future<void> activate(BuildContext context) async {
    _context = context;
    _active = true;
    await initialize();
    if (!_initialized || !context.mounted || !_active) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('booking_alert_permission_asked') != true) {
      await prefs.setBool('booking_alert_permission_asked', true);
      await enable();
    } else {
      await sync();
    }
    if (_pending != null) _open(_pending);
  }

  void detach(BuildContext context) {
    if (identical(context, _context)) {
      _context = null;
      _active = false;
    }
  }

  Future<void> enable() async {
    await initialize();
    if (!_initialized) return;
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await sync();
    } catch (_) {
      status.value = 'Could Not Enable';
    }
  }

  Future<void> sync() async {
    if (!_initialized || !_active || _syncing) return;
    _syncing = true;
    final user = _client.auth.currentUser?.id;
    try {
      await _clearing;
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        status.value = 'Disabled In Phone Settings';
        await unregister();
        return;
      }
      if (user == null) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || !_active || _client.auth.currentUser?.id != user)
        return;
      await _client.rpc(
        'customer_register_push',
        params: {'p_token': token, 'p_language': AppLanguage.instance.code},
      );
      final previousToken = _token;
      _token = token;
      if (previousToken != null && previousToken != token) {
        await _client.rpc(
          'customer_unregister_push',
          params: {'p_token': previousToken},
        );
      }
      status.value = 'Enabled';
    } catch (_) {
      status.value = 'Could Not Enable';
    } finally {
      _syncing = false;
    }
  }

  Future<void> unregister() async {
    if (_token != null && _client.auth.currentUser != null) {
      await _client.rpc(
        'customer_unregister_push',
        params: {'p_token': _token},
      );
    }
    _token = null;
  }

  Future<void> _clearDevice() async {
    try {
      await _local.cancelAll();
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      /* Revoked auth sessions are also excluded by the delivery worker. */
    }
  }

  Future<void> _foreground(RemoteMessage message) async {
    if (!_active || _client.auth.currentUser == null) return;
    final user = _client.auth.currentUser!.id;
    final id = message.data['notification_id'];
    if (id == null || !_displayed.add(id)) return;
    if (_displayed.length > 100) _displayed.remove(_displayed.first);
    try {
      // Recheck ownership: a message queued before logout must not expose another account's content.
      final row = await _client
          .from('notifications')
          .select('notification_id')
          .eq('notification_id', id)
          .maybeSingle();
      if (row == null || !_active || _client.auth.currentUser?.id != user)
        return;
      await _local.show(
        id.hashCode & 0x7fffffff,
        message.notification?.title ?? tr('Booking Update'),
        message.notification?.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'booking_alerts',
            tr('Booking & Payment Alerts'),
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_home_serve',
            color: Color(0xFFFF6B00),
            visibility: NotificationVisibility.private,
          ),
        ),
        payload: id,
      );
    } catch (_) {
      /* The in-app notification remains available. */
    }
  }

  Future<void> _open(String? id) async {
    if (id == null || !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) return;
    _pending = id;
    final context = _context;
    if (!_active ||
        context == null ||
        !context.mounted ||
        _client.auth.currentUser == null)
      return;
    _pending = null;
    final user = _client.auth.currentUser!.id;
    try {
      final row = await _client
          .from('notifications')
          .select('booking_id')
          .eq('notification_id', id)
          .maybeSingle();
      if (row?['booking_id'] == null ||
          !context.mounted ||
          !_active ||
          _client.auth.currentUser?.id != user)
        return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CustomerBookingDetailScreen(
            bookingId: row!['booking_id'] as String,
          ),
        ),
      );
    } catch (_) {
      /* A removed or inaccessible booking is not opened. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
  }
}
