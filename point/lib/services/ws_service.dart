import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';

class WsService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  final ValueNotifier<bool> connectionState = ValueNotifier(false);

  String? _token;
  bool _isConnected = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;

  bool get isConnected => _isConnected;

  void connect(String token) {
    _token = token;
    _reconnectAttempt = 0;
    _connect();
  }

  void _connect() {
    if (_disposed) return;

    final uri = Uri.parse('${AppConfig.wsUrl}?token=$_token');
    _channel = WebSocketChannel.connect(uri);

    _isConnected = true;
    connectionState.value = true;
    _reconnectAttempt = 0;

    _subscription = _channel!.stream.listen(
      (data) {
        try {
          final message = jsonDecode(data as String) as Map<String, dynamic>;
          _controller.add(message);
        } catch (_) {
          // Ignore malformed messages
        }
      },
      onDone: () {
        _isConnected = false;
        connectionState.value = false;
        _scheduleReconnect();
      },
      onError: (error) {
        _isConnected = false;
        connectionState.value = false;
        _scheduleReconnect();
      },
    );
  }

  void _scheduleReconnect() {
    if (_disposed || _token == null) return;

    _reconnectTimer?.cancel();
    final delaySec = min(pow(2, _reconnectAttempt).toInt(), 300);
    _reconnectAttempt++;

    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      _connect();
    });
  }

  void send(Map<String, dynamic> message) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  void sendLocationUpdate({
    required String recipientType,
    required String recipientId,
    required String encryptedBlob,
    required String sourceType,
    required int timestamp,
    int? ttl,
  }) {
    send({
      'type': 'location.update',
      'recipient_type': recipientType,
      'recipient_id': recipientId,
      'encrypted_blob': encryptedBlob,
      'source_type': sourceType,
      'timestamp': timestamp,
      'ttl': ?ttl,
    });
  }

  void sendPresence({int? battery, String? activity}) {
    send({
      'type': 'presence.update',
      'battery': ?battery,
      'activity': ?activity,
    });
  }

  /// Request a fresh location from a specific user.
  /// Server relays this as a nudge + FCM wake push if they're offline.
  void requestFreshLocation(String userId) {
    send({
      'type': 'location.nudge',
      'target_user_id': userId,
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    connectionState.value = false;
    _token = null;
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _controller.close();
  }
}
