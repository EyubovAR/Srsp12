import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_ai_assistant/models/models.dart';
import 'package:my_ai_assistant/providers/chat_provider.dart';
import 'package:my_ai_assistant/screens/welcome_screen.dart';
import 'package:my_ai_assistant/services/api_service.dart';
import 'package:provider/provider.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

ChatProvider _provider(MockClient client, {bool streaming = false}) {
  return ChatProvider(ApiService(userId: 'test_user', client: client))
    ..streamingEnabled = streaming;
}

void main() {
  testWidgets('Экран приветствия показывает название и кнопку', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => _provider(MockClient((_) async => _json({}))),
        child: const MaterialApp(home: WelcomeScreen()),
      ),
    );
    expect(find.text('Мой AI-помощник'), findsOneWidget);
    expect(find.text('Начать общение'), findsOneWidget);
  });

  test('Успешный ответ: сообщение и ответ AI попадают в чат', () async {
    late Map<String, dynamic> sent;
    final provider = _provider(MockClient((request) async {
      if (request.url.path == '/api/chat') {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.headers['X-User-Id'], 'test_user');
        return _json({
          'success': true,
          'reply': 'Flutter — это UI-фреймворк',
          'conversationId': sent['conversationId'],
        });
      }
      return _json({'success': true, 'conversations': []});
    }));
    provider.setRole(AiRole.byId('teacher'));

    final ok = await provider.sendMessage('Что такое Flutter?');

    expect(ok, isTrue);
    expect(sent['message'], 'Что такое Flutter?');
    expect(sent['role'], 'teacher');
    expect(provider.messages, hasLength(2));
    expect(provider.messages[0].status, MessageStatus.sent);
    expect(provider.messages[1].text, 'Flutter — это UI-фреймворк');
    expect(provider.isSending, isFalse);
  });

  test('Ошибка сервера: сообщение сохраняется и его можно повторить', () async {
    var fail = true;
    final provider = _provider(MockClient((request) async {
      if (request.url.path != '/api/chat') {
        return _json({'success': true, 'conversations': []});
      }
      if (fail) {
        return _json(
            {'success': false, 'code': 'AI_ERROR', 'error': 'Сервис недоступен'},
            502);
      }
      return _json(
          {'success': true, 'reply': 'Готово', 'conversationId': 'conv_1'});
    }));

    expect(await provider.sendMessage('Привет'), isFalse);
    expect(provider.messages, hasLength(1));
    expect(provider.messages.single.status, MessageStatus.failed);
    expect(provider.messages.single.errorText, 'Сервис недоступен');

    fail = false;
    expect(await provider.retry(provider.messages.single), isTrue);
    expect(provider.messages, hasLength(2));
    expect(provider.messages.last.text, 'Готово');
  });

  test('Нельзя отправить второе сообщение, пока идёт запрос', () async {
    var calls = 0;
    final provider = _provider(MockClient((request) async {
      if (request.url.path == '/api/chat') {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return _json(
            {'success': true, 'reply': 'Ответ', 'conversationId': 'conv_1'});
      }
      return _json({'success': true, 'conversations': []});
    }));

    final first = provider.sendMessage('Первое');
    expect(provider.isSending, isTrue);
    expect(await provider.sendMessage('Второе'), isFalse);
    expect(await first, isTrue);
    expect(calls, 1);
  });

  test('Таймаут и лимит запросов распознаются по ответу сервера', () async {
    final api = ApiService(
      userId: 'u',
      client: MockClient((request) async => request.body.contains('slow')
          ? _json({'success': false, 'code': 'AI_TIMEOUT', 'error': 't'}, 504)
          : _json({'success': false, 'code': 'RATE_LIMIT', 'error': 'r'}, 429)),
    );
    Future<ApiErrorKind> kindOf(String message) async {
      try {
        await api.sendMessage(
            message: message, conversationId: 'c', roleId: 'assistant');
      } on ApiException catch (e) {
        return e.kind;
      }
      fail('Ожидалась ошибка');
    }

    expect(await kindOf('slow'), ApiErrorKind.timeout);
    expect(await kindOf('many'), ApiErrorKind.rateLimit);
  });

  test('Потоковый ответ собирается по частям', () async {
    final sse = [
      {'type': 'start', 'conversationId': 'conv_1'},
      {'type': 'delta', 'text': 'При'},
      {'type': 'delta', 'text': 'вет!'},
      {'type': 'done', 'reply': 'Привет!', 'conversationId': 'conv_1'},
    ].map((e) => 'data: ${jsonEncode(e)}\n\n').join();

    final deltas = <String>[];
    final api = ApiService(
      userId: 'u',
      client: MockClient.streaming((request, body) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode(sse)),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      }),
    );

    final result = await api.sendMessageStream(
      message: 'Привет',
      conversationId: 'conv_1',
      roleId: 'assistant',
      onDelta: deltas.add,
    );

    expect(deltas, ['При', 'вет!']);
    expect(result.reply, 'Привет!');
  });
}
