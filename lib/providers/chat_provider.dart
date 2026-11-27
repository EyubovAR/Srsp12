import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/api_service.dart';

/// Состояние загрузки списка/диалога.
enum LoadState { idle, loading, loaded, error }

/// Главное состояние приложения (Provider): текущий чат, история диалогов, сеть.
class ChatProvider extends ChangeNotifier {
  ChatProvider([this._api]);

  ApiService? _api;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  final Random _random = Random();

  // ---------- Текущий чат ----------
  final List<ChatMessage> messages = [];
  String? conversationId;
  AiRole role = AiRole.defaultRole;
  bool isSending = false;
  LoadState chatState = LoadState.idle;
  String? chatError;

  // ---------- История ----------
  List<Conversation> conversations = [];
  LoadState historyState = LoadState.idle;
  String? historyError;

  // ---------- Настройки и сеть ----------
  bool streamingEnabled = true;
  bool isOffline = false;

  ApiService get api => _api!;

  /// Запускается один раз при старте приложения.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    var userId = prefs.getString('user_id');
    if (userId == null) {
      userId = 'user_${_randomId(16)}';
      await prefs.setString('user_id', userId);
    }
    streamingEnabled = prefs.getBool('streaming') ?? true;
    _api ??= ApiService(userId: userId);

    try {
      final connectivity = Connectivity();
      _applyConnectivity(await connectivity.checkConnectivity());
      _connectivitySub =
          connectivity.onConnectivityChanged.listen(_applyConnectivity);
    } catch (_) {
      // На платформе нет данных о сети — считаем, что сеть есть.
    }
    notifyListeners();
  }

  void _applyConnectivity(List<ConnectivityResult> results) {
    final offline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (offline != isOffline) {
      isOffline = offline;
      notifyListeners();
    }
  }

  String _randomId(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(length, (_) => chars[_random.nextInt(chars.length)])
        .join();
  }

  Future<void> setStreaming(bool value) async {
    streamingEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('streaming', value);
  }

  void setRole(AiRole newRole) {
    role = newRole;
    notifyListeners();
  }

  // ---------- Чаты ----------

  /// Начать новый пустой чат.
  void startNewChat() {
    if (isSending) return;
    conversationId = null;
    messages.clear();
    role = AiRole.defaultRole;
    chatState = LoadState.idle;
    chatError = null;
    notifyListeners();
  }

  /// Открыть старый диалог из истории.
  Future<void> openConversation(String id) async {
    if (isSending) return;
    conversationId = id;
    messages.clear();
    chatState = LoadState.loading;
    chatError = null;
    notifyListeners();

    try {
      final (conversation, loaded) = await api.getConversation(id);
      if (conversationId != id) return; // пользователь уже открыл другой чат
      role = AiRole.byId(conversation.roleId);
      messages
        ..clear()
        ..addAll(loaded);
      chatState = LoadState.loaded;
    } on ApiException catch (e) {
      if (conversationId != id) return;
      chatState = LoadState.error;
      chatError = e.message;
    }
    notifyListeners();
  }

  /// Отправить новое сообщение. Возвращает true, если AI успешно ответил.
  Future<bool> sendMessage(String text,
      {Uint8List? imageBytes, String? imageMime}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isSending) return false;

    // Если пользователь заново отправляет тот же текст после ошибки —
    // не дублируем сообщение в списке.
    if (messages.isNotEmpty &&
        messages.last.isUser &&
        messages.last.status == MessageStatus.failed &&
        messages.last.text == trimmed) {
      messages.removeLast();
    }

    final message = ChatMessage(
      text: trimmed,
      isUser: true,
      time: DateTime.now(),
      status: MessageStatus.sending,
      imageBytes: imageBytes,
      imageMime: imageMime,
      hasImage: imageBytes != null,
    );
    messages.add(message);
    return _deliver(message);
  }

  /// Повторить неудачный запрос.
  Future<bool> retry(ChatMessage message) async {
    if (isSending || message.status != MessageStatus.failed) return false;
    // Переносим сообщение в конец, чтобы ответ AI оказался сразу под ним.
    messages
      ..remove(message)
      ..add(message);
    message.time = DateTime.now();
    return _deliver(message);
  }

  Future<bool> _deliver(ChatMessage message) async {
    isSending = true; // блокирует повторную отправку, пока идёт запрос
    message.status = MessageStatus.sending;
    message.errorText = null;
    conversationId ??=
        'conv_${DateTime.now().millisecondsSinceEpoch}_${_randomId(6)}';
    final sentConversationId = conversationId!;

    // Пустое сообщение AI = индикатор «AI печатает…»
    final answer = ChatMessage(
      text: '',
      isUser: false,
      time: DateTime.now(),
      status: MessageStatus.sending,
    );
    messages.add(answer);
    notifyListeners();

    try {
      final ChatReply result;
      if (streamingEnabled) {
        result = await api.sendMessageStream(
          message: message.text,
          conversationId: sentConversationId,
          roleId: role.id,
          imageBytes: message.imageBytes,
          imageMime: message.imageMime,
          onDelta: (delta) {
            answer.text += delta;
            notifyListeners();
          },
        );
      } else {
        result = await api.sendMessage(
          message: message.text,
          conversationId: sentConversationId,
          roleId: role.id,
          imageBytes: message.imageBytes,
          imageMime: message.imageMime,
        );
      }

      answer
        ..text = result.reply
        ..time = DateTime.now()
        ..status = MessageStatus.sent;
      message.status = MessageStatus.sent;
      isSending = false;
      notifyListeners();
      unawaited(loadConversations(silent: true));
      return true;
    } on ApiException catch (e) {
      // Сообщение пользователя остаётся в чате — его можно отправить повторно.
      messages.remove(answer);
      message
        ..status = MessageStatus.failed
        ..errorText = e.message;
      isSending = false;
      notifyListeners();
      return false;
    }
  }

  // ---------- История ----------

  Future<void> loadConversations({bool silent = false}) async {
    if (!silent) {
      historyState = LoadState.loading;
      historyError = null;
      notifyListeners();
    }
    try {
      conversations = await api.getConversations();
      historyState = LoadState.loaded;
      historyError = null;
    } on ApiException catch (e) {
      if (silent) return;
      historyState = LoadState.error;
      historyError = e.message;
    }
    notifyListeners();
  }

  /// Удалить диалог. Возвращает текст ошибки или null, если всё получилось.
  Future<String?> deleteConversation(String id) async {
    try {
      await api.deleteConversation(id);
      conversations = conversations.where((c) => c.id != id).toList();
      if (conversationId == id) {
        conversationId = null;
        messages.clear();
        role = AiRole.defaultRole;
        chatState = LoadState.idle;
      }
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }
}
