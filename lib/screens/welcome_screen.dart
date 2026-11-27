import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';
import 'chat_screen.dart';

/// Экран приветствия: логотип, описание возможностей и кнопка «Начать общение».
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _features = [
    (Icons.chat_bubble_outline, 'Задавайте любые вопросы и получайте ответы AI'),
    (Icons.bolt_outlined, 'Ответ появляется сразу, по мере набора'),
    (Icons.history, 'История диалогов сохраняется — продолжайте в любой момент'),
    (Icons.switch_account_outlined,
        'Выбирайте роль: преподаватель, программист, переводчик, консультант'),
    (Icons.image_outlined, 'Отправляйте фото и спрашивайте, что на нём'),
  ];

  void _start(BuildContext context) {
    context.read<ChatProvider>().startNewChat();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ChatScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [scheme.primary, scheme.tertiary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(Icons.auto_awesome,
                        size: 56, color: scheme.onPrimary),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Мой AI-помощник',
                    style: text.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Умный собеседник, который всегда под рукой',
                    style: text.bodyLarge
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  for (final (icon, label) in _features)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, color: scheme.primary),
                          const SizedBox(width: 14),
                          Expanded(child: Text(label, style: text.bodyLarge)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () => _start(context),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Начать общение',
                          style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
