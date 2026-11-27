
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/models.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import 'history_screen.dart';

/// Экран чата: сообщения, поле ввода, индикатор набора, состояния ошибок.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const int _maxImageBytes = 4 * 1024 * 1024;

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  late final ChatProvider _provider;

  Uint8List? _imageBytes;
  String? _imageMime;
  int _lastMessageCount = 0;
  int _lastTextLength = 0;

  // Голосовой ввод: речь превращается в текст и попадает в поле ввода.
  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;
  bool _listening = false;
  String _textBeforeVoice = '';

  @override
  void initState() {
    super.initState();
    _provider = context.read<ChatProvider>();
    _provider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    _speech.cancel();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Прокручиваем вниз, когда появилось новое сообщение или AI дописал текст.
  void _onProviderChanged() {
    final messages = _provider.messages;
    final textLength = messages.isEmpty ? 0 : messages.last.text.length;
    if (messages.length != _lastMessageCount || textLength != _lastTextLength) {
      _lastMessageCount = messages.length;
      _lastTextLength = textLength;
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_provider.isSending) return;
    if (_listening) await _speech.stop();
    if (text.isEmpty) {
      if (_imageBytes != null) _showSnack('Напишите вопрос к изображению.');
      return;
    }

    final imageBytes = _imageBytes;
    final imageMime = _imageMime;
    final success = await _provider.sendMessage(
      text,
      imageBytes: imageBytes,
      imageMime: imageMime,
    );
    if (!mounted) return;

    if (success) {
      // Поле ввода очищается только после успешной отправки.
      _input.clear();
      setState(() {
        _imageBytes = null;
        _imageMime = null;
      });
    }
    _focus.requestFocus();
  }

  /// Кнопка микрофона: начинает запись голоса или останавливает её.
  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      return;
    }

    try {
      if (!_speechReady) {
        // При первом запуске система спросит разрешение на микрофон.
        _speechReady = await _speech.initialize(
          onStatus: _onSpeechStatus,
          onError: _onSpeechError,
        );
      }
      if (!mounted) return;
      if (!_speechReady) {
        _showSnack(
            'Голосовой ввод недоступен: разрешите доступ к микрофону и проверьте, что на устройстве есть распознавание речи.');
        return;
      }

      // Распознаём по-русски, если устройство это умеет, иначе — на языке системы.
      final locales = await _speech.locales();
      final hasRussian = locales.any((l) => l.localeId.startsWith('ru'));
      if (!mounted) return;

      _textBeforeVoice = _input.text.trim();
      setState(() => _listening = true);
      await _speech.listen(
        onResult: _onSpeechResult,
        listenOptions: SpeechListenOptions(
          localeId: hasRussian ? 'ru_RU' : null,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _listening = false);
      _showSnack('Не удалось запустить голосовой ввод.');
    }
  }

  /// Распознанный текст дописывается к тому, что уже было в поле ввода.
  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    final spoken = result.recognizedWords.trim();
    if (spoken.isEmpty) return;
    final text =
        _textBeforeVoice.isEmpty ? spoken : '$_textBeforeVoice $spoken';
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    final listening = status == SpeechToText.listeningStatus;
    if (listening != _listening) setState(() => _listening = listening);
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    setState(() => _listening = false);
    final nothingHeard = error.errorMsg == 'error_no_match' ||
        error.errorMsg == 'error_speech_timeout';
    _showSnack(nothingHeard
        ? 'Не удалось распознать речь. Попробуйте ещё раз.'
        : 'Ошибка голосового ввода. Проверьте микрофон и интернет.');
  }

  Future<void> _pickImage() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 75,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > _maxImageBytes) {
        _showSnack('Изображение слишком большое (максимум 4 МБ).');
        return;
      }
      setState(() {
        _imageBytes = bytes;
        _imageMime = _detectMime(file);
      });
    } catch (_) {
      if (mounted) _showSnack('Не удалось открыть изображение.');
    }
  }

  String _detectMime(XFile file) {
    final mime = file.mimeType;
    if (mime != null && mime.startsWith('image/')) return mime;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  void _newChat() {
    _provider.startNewChat();
    _input.clear();
    setState(() {
      _imageBytes = null;
      _imageMime = null;
    });
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }

  void _chooseRole() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Роль AI-помощника',
                    style: Theme.of(sheetContext).textTheme.titleMedium),
              ),
              for (final role in AiRole.all)
                ListTile(
                  leading: Icon(role.icon),
                  title: Text(role.title),
                  subtitle: Text(role.description),
                  trailing: role.id == _provider.role.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    _provider.setRole(role);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: chat.isSending ? null : _chooseRole,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(chat.role.icon, color: scheme.primary),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(chat.role.title,
                          style: const TextStyle(fontSize: 17),
                          overflow: TextOverflow.ellipsis),
                      Text('Нажмите, чтобы сменить роль',
                          style: TextStyle(
                              fontSize: 11.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Новый чат',
            onPressed: chat.isSending ? null : _newChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: 'История чатов',
            onPressed: chat.isSending ? null : _openHistory,
            icon: const Icon(Icons.history),
          ),
          PopupMenuButton<String>(
            tooltip: 'Настройки',
            onSelected: (_) => chat.setStreaming(!chat.streamingEnabled),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'streaming',
                checked: chat.streamingEnabled,
                child: const Text('Показывать ответ по мере набора'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (chat.isOffline) const _OfflineBanner(),
            Expanded(child: _buildBody(chat)),
            _buildInput(chat, scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ChatProvider chat) {
    switch (chat.chatState) {
      case LoadState.loading:
        // Состояние Loading: загружается старый диалог.
        return const Center(child: CircularProgressIndicator());
      case LoadState.error:
        // Состояние Error: диалог не удалось загрузить.
        return _CenteredMessage(
          icon: Icons.error_outline,
          title: 'Не удалось загрузить диалог',
          subtitle: chat.chatError ?? '',
          actionLabel: 'Повторить',
          onAction: () => chat.openConversation(chat.conversationId!),
        );
      case LoadState.idle:
      case LoadState.loaded:
        break;
    }

    if (chat.messages.isEmpty) {
      // Состояние Empty: сообщений ещё нет.
      return _EmptyChat(
        role: chat.role,
        onRoleSelected: chat.setRole,
        onSuggestion: (text) {
          _input.text = text;
          _input.selection = TextSelection.collapsed(offset: text.length);
          _focus.requestFocus();
        },
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          itemCount: chat.messages.length,
          itemBuilder: (context, index) {
            final message = chat.messages[index];
            return MessageBubble(
              message: message,
              onRetry: chat.isSending ? null : () => chat.retry(message),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInput(ChatProvider chat, ColorScheme scheme) {
    final blocked = chat.isSending || chat.chatState == LoadState.loading;

    return Material(
      color: scheme.surface,
      elevation: 6,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_imageBytes != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 48, bottom: 8),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(_imageBytes!,
                                width: 72, height: 72, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: -10,
                            right: -10,
                            child: IconButton.filledTonal(
                              tooltip: 'Убрать изображение',
                              visualDensity: VisualDensity.compact,
                              iconSize: 16,
                              onPressed: blocked
                                  ? null
                                  : () => setState(() {
                                        _imageBytes = null;
                                        _imageMime = null;
                                      }),
                              icon: const Icon(Icons.close),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Прикрепить изображение',
                      onPressed: blocked ? null : _pickImage,
                      icon: const Icon(Icons.image_outlined),
                    ),
                    Expanded(
                      child: Shortcuts(
                        shortcuts: const {
                          // Enter отправляет сообщение, Shift+Enter — новая строка.
                          SingleActivator(LogicalKeyboardKey.enter):
                              _SendIntent(),
                        },
                        child: Actions(
                          actions: {
                            _SendIntent: CallbackAction<_SendIntent>(
                              onInvoke: (_) => _send(),
                            ),
                          },
                          child: TextField(
                            controller: _input,
                            focusNode: _focus,
                            readOnly: blocked,
                            minLines: 1,
                            maxLines: 5,
                            maxLength: 4000,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: blocked
                                  ? 'AI отвечает…'
                                  : _listening
                                      ? 'Говорите…'
                                      : 'Напишите сообщение…',
                              counterText: '',
                              filled: true,
                              fillColor: scheme.surfaceContainerHighest,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    // Голосовой ввод: во время записи кнопка подсвечена, повторное нажатие останавливает запись.
                    IconButton(
                      tooltip: _listening
                          ? 'Остановить запись'
                          : 'Голосовой ввод',
                      isSelected: _listening,
                      color: _listening ? scheme.error : null,
                      onPressed: blocked ? null : _toggleVoice,
                      icon: Icon(_listening ? Icons.stop_circle : Icons.mic_none),
                    ),
                    const SizedBox(width: 2),
                    // Пока идёт запрос, кнопка отправки отключена — повторно отправить нельзя.
                    IconButton.filled(
                      tooltip: 'Отправить',
                      onPressed: blocked ? null : _send,
                      icon: chat.isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}

/// Состояние Offline: уведомление об отсутствии интернета.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.wifi_off, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Нет подключения к интернету',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({
    required this.role,
    required this.onRoleSelected,
    required this.onSuggestion,
  });

  final AiRole role;
  final ValueChanged<AiRole> onRoleSelected;
  final ValueChanged<String> onSuggestion;

  static const _suggestions = {
    'assistant': ['Что такое Flutter?', 'Придумай план на выходные'],
    'teacher': ['Объясни, что такое рекурсия', 'Как работает фотосинтез?'],
    'programmer': [
      'Напиши функцию сортировки на Dart',
      'Чем отличается Future от Stream?'
    ],
    'translator': ['Переведи: «Доброе утро, как дела?»', 'How are you doing?'],
    'consultant': [
      'Как выбрать ноутбук для учёбы?',
      'Как подготовиться к собеседованию?'
    ],
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 56, color: scheme.primary),
              const SizedBox(height: 12),
              Text('Сообщений пока нет', style: text.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Выберите роль помощника и задайте первый вопрос',
                style:
                    text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final item in AiRole.all)
                    ChoiceChip(
                      avatar: Icon(item.icon, size: 18),
                      label: Text(item.title),
                      selected: item.id == role.id,
                      showCheckmark: false,
                      onSelected: (_) => onRoleSelected(item),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              for (final suggestion in _suggestions[role.id] ?? const <String>[])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => onSuggestion(suggestion),
                      child: Text(suggestion, textAlign: TextAlign.center),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
