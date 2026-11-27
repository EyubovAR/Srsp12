import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';

/// «Пузырёк» одного сообщения: текст, картинка, время, ошибка и кнопка повтора.
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, this.onRetry});

  final ChatMessage message;
  final VoidCallback? onRetry;

  static final DateFormat _timeFormat = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final failed = message.status == MessageStatus.failed;
    final isTyping = !isUser && message.text.isEmpty;

    final background = failed
        ? scheme.errorContainer
        : isUser
            ? scheme.primary
            : scheme.surfaceContainerHighest;
    final foreground = failed
        ? scheme.onErrorContainer
        : isUser
            ? scheme.onPrimary
            : scheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width.clamp(0, 760) * 0.82,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.imageBytes != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          message.imageBytes!,
                          height: 180,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  else if (message.hasImage)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.image_outlined,
                              size: 16, color: foreground),
                          const SizedBox(width: 6),
                          Text('Изображение',
                              style: TextStyle(
                                  color: foreground,
                                  fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                  if (isTyping)
                    TypingIndicator(color: foreground)
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: 1,
                      child: SelectableText(
                        message.text,
                        style: TextStyle(
                            color: foreground, fontSize: 15.5, height: 1.35),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isTyping
                            ? 'AI печатает…'
                            : _timeFormat.format(message.time),
                        style: TextStyle(
                          color: foreground.withValues(alpha: 0.7),
                          fontSize: 11.5,
                        ),
                      ),
                      if (isUser &&
                          message.status == MessageStatus.sending) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.schedule,
                            size: 13, color: foreground.withValues(alpha: 0.7)),
                      ],
                      if (failed) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.error_outline, size: 14, color: scheme.error),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (failed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      message.errorText ?? 'Не удалось отправить сообщение.',
                      style: TextStyle(color: scheme.error, fontSize: 12.5),
                      textAlign: TextAlign.end,
                    ),
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Повторить'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Индикатор набора ответа: три «прыгающие» точки.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key, required this.color});

  final Color color;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'AI печатает',
      child: SizedBox(
        height: 22,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                // Каждая точка «подпрыгивает» со сдвигом по времени.
                final phase = (_controller.value - index * 0.18) % 1.0;
                final lift = phase < 0.4 ? (1 - (phase / 0.2 - 1).abs()) : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Transform.translate(
                    offset: Offset(0, -5 * lift),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.45 + 0.5 * lift),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
