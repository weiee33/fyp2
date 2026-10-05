@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fyp2/Customer/services/customer_recovery_service.dart';

Map<String, dynamic> session(String tokenName) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {
    'access_token':
        '${encode({'alg': 'HS256'})}.${encode({'sub': '00000000-0000-4000-8000-000000000001', 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600, 'session_id': tokenName})}.fixture',
    'refresh_token': tokenName,
    'expires_in': 3600,
    'token_type': 'bearer',
    'user': {
      'id': '00000000-0000-4000-8000-000000000001',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'fixture@example.invalid',
      'created_at': '2026-10-01T00:00:00Z',
    },
  };
}

void main() {
  for (final phase in [
    'after password check',
    'during password check',
    'during OTP verification',
  ]) {
    test(
      'leaving $phase preserves the main browser session and its RPC access',
      () async {
        final primary = session('main');
        final temporary = session('temporary');
        final mainClient = SupabaseClient(
          'https://fixture.invalid',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/account_identity')) {
              expect(
                request.headers['Authorization'] ??
                    request.headers['authorization'],
                'Bearer ${primary['access_token']}',
              );
              return http.Response(
                '{"role":"customer"}',
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            throw StateError(
              'Main client must not sign in/out during cancellation',
            );
          }),
        );
        addTearDown(mainClient.dispose);
        final events = <AuthChangeEvent>[];
        final restored = Completer<void>();
        final listener = mainClient.auth.onAuthStateChange.listen((state) {
          if (!restored.isCompleted &&
              state.event == AuthChangeEvent.tokenRefreshed) {
            restored.complete();
          }
          if (state.event != AuthChangeEvent.initialSession) {
            events.add(state.event);
          }
        });
        addTearDown(listener.cancel);
        await mainClient.auth.recoverSession(jsonEncode(primary));
        // recoverSession itself emits tokenRefreshed. Observe setup completion
        // before measuring events caused by the recovery/cancellation flow.
        await restored.future;
        events.clear();
        final gate = Completer<void>();
        var mutations = 0, cleanups = 0;
        final httpClient = MockClient((request) async {
          Object body = {};
          if (request.url.path.endsWith('/token') ||
              request.url.path.endsWith('/verify')) {
            if (phase != 'after password check') await gate.future;
            body = temporary;
          } else if (request.url.path.endsWith('/account_identity')) {
            body = {'role': 'customer'};
          } else if (request.url.path.endsWith('/logout')) {
            expect(request.url.queryParameters['scope'], 'local');
            cleanups++;
          } else if (request.url.path.endsWith('/user')) {
            mutations++;
          } else {
            throw StateError('Unexpected recovery request');
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });
        final service = CustomerRecoveryService(
          httpClient: httpClient,
          url: 'https://fixture.invalid',
          anonKey: 'test',
        );
        addTearDown(httpClient.close);
        addTearDown(service.dispose);
        if (phase == 'after password check') {
          await service.verifyCurrentPassword(
            'fixture@example.invalid',
            'current',
          );
          await service.dispose();
        } else {
          final operation = phase == 'during password check'
              ? service.verifyCurrentPassword(
                  'fixture@example.invalid',
                  'current',
                )
              : service.changePassword(
                  email: 'fixture@example.invalid',
                  code: '123456',
                  password: 'new-password-123',
                );
          final assertion = expectLater(operation, throwsStateError);
          final disposed = service.dispose();
          gate.complete();
          await assertion;
          await disposed;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(
          mainClient.auth.currentSession?.accessToken,
          primary['access_token'],
        );
        expect(events, isEmpty);
        expect(mutations, 0);
        expect(cleanups, 1);
        expect((await mainClient.rpc('account_identity'))['role'], 'customer');
      },
    );
  }
}
