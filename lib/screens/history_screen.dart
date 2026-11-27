import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/chat_provider.dart';
import 'admin_screen.dart';

/// Экран истории: список диалогов, открытие, удаление, создание нового чата.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static final DateFormat _dateFormat = DateFormat('dd.MM.yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ChatProvider>().loadConversations();
    });
  }

  void _open(Conversation conversation) {
    context.read<ChatProvider>().openConversation(conversation.id);
    Navigator.of(context).pop();
  }

  void _newChat() {
    context.read<ChatProvider>().startNewChat();
    Navigator.of(context).pop();
  }

  Future<void> _delete(Conversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить диалог?'),
        content: Text(
            '«${conversation.title}» будет удалён без возможности восстановления.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final error =
        await context.read<ChatProvider>().deleteConversation(conversation.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error ?? 'Диалог удалён')));
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('История чатов'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: chat.loadConversations,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Панель администратора',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminScreen()),
            ),
            icon: const Icon(Icons.admin_panel_settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newChat,
        icon: const Icon(Icons.add),
        label: const Text('Новый чат'),
      ),
      body: SafeArea(child: _buildBody(chat)),
    );
  }

  Widget _buildBody(ChatProvider chat) {
    final scheme = Theme.of(context).colorScheme;

    if (chat.historyState == LoadState.loading ||
        chat.historyState == LoadState.idle) {
      return const Center(child: CircularProgressIndicator());
    }

    if (chat.historyState == LoadState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: scheme.error),
              const SizedBox(height: 12),
              Text('Не удалось загрузить историю',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(chat.historyError ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: chat.loadConversations,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    if (chat.conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 56, color: scheme.primary),
              const SizedBox(height: 12),
              Text('Диалогов пока нет',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('Создайте новый чат и задайте первый вопрос',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: chat.loadConversations,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: chat.conversations.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final conversation = chat.conversations[index];
          final role = AiRole.byId(conversation.roleId);
          final isCurrent = conversation.id == chat.conversationId;

          return ListTile(
            selected: isCurrent,
            leading: CircleAvatar(child: Icon(role.icon)),
            title: Text(conversation.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              'Создан: ${_dateFormat.format(conversation.createdAt)}\n'
              '${role.title} · сообщений: ${conversation.messageCount}',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: 'Удалить диалог',
              onPressed: () => _delete(conversation),
              icon: const Icon(Icons.delete_outline),
            ),
            onTap: () => _open(conversation),
          );
        },
      ),
    );
  }
}
