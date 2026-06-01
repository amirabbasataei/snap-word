import 'dart:async';
import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketEvent {
  final String type;
  final Map<String, dynamic> data;

  const WebSocketEvent(this.type, this.data);
}

class WebSocketService {
  final Logger _log = Logger();

  WebSocketChannel? _channel;
  final _controller = StreamController<WebSocketEvent>.broadcast();
  bool _disposed = false;

  Stream<WebSocketEvent> get events => _controller.stream;

  void connect(String url) {
    _log.i('WebSocket connecting to $url');
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _channel!.stream.listen(
        (raw) {
          try {
            final json = jsonDecode(raw as String) as Map<String, dynamic>;
            final type = json['type'] as String? ?? '';
            _controller.add(WebSocketEvent(type, json));
          } catch (e) {
            _log.w('WebSocket parse error: $e');
          }
        },
        onError: (Object e) => _log.e('WebSocket error: $e'),
        onDone: () => _log.i('WebSocket connection closed'),
      );
    } catch (e) {
      _log.e('WebSocket connect failed: $e');
    }
  }

  void send(Map<String, dynamic> message) {
    if (_channel == null) {
      _log.w('WebSocket send called but channel is null');
      return;
    }
    try {
      _channel!.sink.add(jsonEncode(message));
    } catch (e) {
      _log.e('WebSocket send error: $e');
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    disconnect();
    _controller.close();
  }
}
