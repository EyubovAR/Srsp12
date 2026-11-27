import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';

/// Вид ошибки — по нему интерфейс решает, что показать пользователю.
enum ApiErrorKind { offline, timeout, rateLimit, validation, server }

class ApiException implements Exception {
  ApiException(this.kind, this.message);

  final ApiErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// Результат успешного запроса к чату.
class ChatReply {
  ChatReply(this.reply, this.conversationId);

  final String reply;
  final String conversationId;
}

/// Клиент Backend-сервера. Все запросы к AI идут только через него.
class ApiService {
  ApiService({required this.userId, http.Client? client})
      : _client = client ?? http.Client();

  final String userId;
  final http.Client _client;

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        'X-User-Id': userId,
      };

  // ---------- Чат ----------

  Map<String, dynamic> _chatBody({
    required String message,
    required String conversationId,
    required String roleId,
    Uint8List? imageBytes,
    String? imageMime,
  }) {
    return {
      'message': message,
      'conversationId': conversationId,
      'role': roleId,
      if (imageBytes != null)
        'image':
            'data:${imageMime ?? 'image/jpeg'};base64,${base64Encode(imageBytes)}',
    };
  }

  /// POST /api/chat — ответ приходит целиком.
  Future<ChatReply> sendMessage({
    required String message,
    required String conversationId,
    required String roleId,
    Uint8List? imageBytes,
    String? imageMime,
  }) async {
    final json = await _request(() => _client.post(
          _uri('/api/chat'),
          headers: _headers,
          body: jsonEncode(_chatBody(
            message: message,
            conversationId: conversationId,
            roleId: roleId,
            imageBytes: imageBytes,
            imageMime: imageMime,
          )),
        ));
    return ChatReply(json['reply'] as String, json['conversationId'] as String);
  }

  /// POST /api/chat/stream — ответ приходит по частям (Server-Sent Events).
  /// [onDelta] вызывается для каждого нового кусочка текста.
  Future<ChatReply> sendMessageStream({
    required String message,
    required String conversationId,
    required String roleId,
    required void Function(String delta) onDelta,
    Uint8List? imageBytes,
    String? imageMime,
  }) async {
    final request = http.Request('POST', _uri('/api/chat/stream'))
      ..headers.addAll(_headers)
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode(_chatBody(
        message: message,
        conversationId: conversationId,
        roleId: roleId,
        imageBytes: imageBytes,
        imageMime: imageMime,
      ));

    try {
      final response =
          await _client.send(request).timeout(AppConfig.requestTimeout);

      if (response.statusCode != 200) {
        final body = await response.stream
            .bytesToString()
            .timeout(AppConfig.requestTimeout);
        throw _errorFromResponse(response.statusCode, body);
      }

      final events = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(AppConfig.streamIdleTimeout);

      await for (final line in events) {
        if (!line.startsWith('data:')) continue;
        final event = jsonDecode(line.substring(5).trim());
        if (event is! Map<String, dynamic>) continue;

        switch (event['type']) {
          case 'delta':
            onDelta(event['text'] as String? ?? '');
          case 'done':
            return ChatReply(
              event['reply'] as String,
              event['conversationId'] as String,
            );
          case 'error':
            throw ApiException(
              _kindFromCode(event['code'] as String?, 502),
              event['error'] as String? ?? 'Ошибка сервера.',
            );
        }
      }
      throw ApiException(
        ApiErrorKind.server,
        'Соединение с сервером прервалось. Попробуйте ещё раз.',
      );
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw _timeout();
    } on http.ClientException {
      throw _offline();
    } on FormatException {
      throw ApiException(ApiErrorKind.server, 'Сервер прислал непонятный ответ.');
    } catch (_) {
      throw _offline();
    }
  }

  // ---------- История диалогов ----------

  Future<List<Conversation>> getConversations() async {
    final json = await _request(
        () => _client.get(_uri('/api/conversations'), headers: _headers));
    return (json['conversations'] as List)
        .map((item) => Conversation.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<(Conversation, List<ChatMessage>)> getConversation(String id) async {
    final json = await _request(
        () => _client.get(_uri('/api/conversations/$id'), headers: _headers));
    final conversation =
        Conversation.fromJson(json['conversation'] as Map<String, dynamic>);
    final messages = (json['messages'] as List)
        .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
        .toList();
    return (conversation, messages);
  }

  Future<void> deleteConversation(String id) async {
    await _request(() =>
        _client.delete(_uri('/api/conversations/$id'), headers: _headers));
  }

  // ---------- Панель администратора ----------

  Future<Map<String, dynamic>> getAdminStats(String adminToken) async {
    return _request(() => _client.get(
          _uri('/api/admin/stats'),
          headers: {..._headers, 'X-Admin-Token': adminToken},
        ));
  }

  // ---------- Общая обработка ответов и ошибок ----------

  Future<Map<String, dynamic>> _request(
      Future<http.Response> Function() send) async {
    final http.Response response;
    try {
      response = await send().timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw _timeout();
    } on http.ClientException {
      throw _offline();
    } catch (_) {
      throw _offline();
    }

    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _errorFromResponse(response.statusCode, body);
    }
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(ApiErrorKind.server, 'Сервер прислал непонятный ответ.');
    }
  }

  ApiException _errorFromResponse(int status, String body) {
    String? code;
    String? message;
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        code = json['code'] as String?;
        message = json['error'] as String?;
      }
    } catch (_) {
      // Ответ не в формате JSON — покажем общее сообщение.
    }
    return ApiException(
      _kindFromCode(code, status),
      message ?? 'Ошибка сервера ($status). Попробуйте позже.',
    );
  }

  ApiErrorKind _kindFromCode(String? code, int status) {
    if (code == 'AI_TIMEOUT' || status == 504 || status == 408) {
      return ApiErrorKind.timeout;
    }
    if (status == 429 || code == 'RATE_LIMIT' || code == 'AI_RATE_LIMIT') {
      return ApiErrorKind.rateLimit;
    }
    if (status == 400 || status == 413) return ApiErrorKind.validation;
    return ApiErrorKind.server;
  }

  ApiException _timeout() => ApiException(
        ApiErrorKind.timeout,
        'Превышено время ожидания ответа. Попробуйте ещё раз.',
      );

  ApiException _offline() => ApiException(
        ApiErrorKind.offline,
        'Нет связи с сервером. Проверьте интернет и попробуйте снова.',
      );
}
