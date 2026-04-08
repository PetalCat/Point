import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:unifiedpush/unifiedpush.dart';

import '../config.dart';
import 'notification_service.dart';

/// Abstraction over push notification backends.
/// Supports Firebase (Google), UnifiedPush (self-hostable), or disabled.
class PushService {
  static String? _token;
  static String? get token => _token;

  /// Initialize the push provider based on user setting.
  static Future<void> init({
    required Future<void> Function(String token) onTokenReceived,
    void Function(Map<String, dynamic> data)? onMessage,
  }) async {
    switch (AppConfig.pushProvider) {
      case PushProvider.firebase:
        await _initFirebase(onTokenReceived: onTokenReceived, onMessage: onMessage);
      case PushProvider.unified:
        await _initUnifiedPush(onTokenReceived: onTokenReceived, onMessage: onMessage);
      case PushProvider.none:
        debugPrint('[Push] Disabled — no push notifications');
    }
  }

  static Future<void> _initFirebase({
    required Future<void> Function(String token) onTokenReceived,
    void Function(Map<String, dynamic> data)? onMessage,
  }) async {
    final fcm = FirebaseMessaging.instance;
    await fcm.requestPermission(alert: true, badge: true, sound: true);

    final fcmToken = await fcm.getToken();
    if (fcmToken != null) {
      _token = fcmToken;
      debugPrint('[Push] Firebase token: ${fcmToken.substring(0, 20)}...');
      await onTokenReceived(fcmToken);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _token = newToken;
      onTokenReceived(newToken);
    });

    FirebaseMessaging.onMessage.listen((message) {
      if (message.notification != null) {
        NotificationService.show(
          title: message.notification!.title ?? 'Point',
          body: message.notification!.body ?? '',
        );
      }
      if (message.data.isNotEmpty && onMessage != null) {
        onMessage(message.data);
      }
    });
  }

  static Future<void> _initUnifiedPush({
    required Future<void> Function(String token) onTokenReceived,
    void Function(Map<String, dynamic> data)? onMessage,
  }) async {
    UnifiedPush.initialize(
      onNewEndpoint: (PushEndpoint endpoint, String instance) async {
        final url = endpoint.url;
        _token = url;
        debugPrint('[Push] UnifiedPush endpoint: $url');
        await onTokenReceived(url);
      },
      onRegistrationFailed: (FailedReason reason, String instance) {
        debugPrint('[Push] UnifiedPush registration failed: $reason');
      },
      onUnregistered: (String instance) {
        debugPrint('[Push] UnifiedPush unregistered');
        _token = null;
      },
      onMessage: (PushMessage message, String instance) {
        try {
          final content = utf8.decode(message.content);
          final data = jsonDecode(content) as Map<String, dynamic>;
          final title = data['title'] as String? ?? 'Point';
          final body = data['body'] as String? ?? '';
          if (body.isNotEmpty) {
            NotificationService.show(title: title, body: body);
          }
          onMessage?.call(data);
        } catch (e) {
          debugPrint('[Push] Failed to parse UnifiedPush message: $e');
        }
      },
    );

    await UnifiedPush.registerApp();
  }
}
