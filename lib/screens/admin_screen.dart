import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';
import '../services/api_service.dart';

/// Панель администратора: статистика запросов, активность пользователей, расходы на API.
/// Доступ — по токену администратора, который проверяет сервер (ADMIN_TOKEN в .env).
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  static final DateFormat _dateFormat = DateFormat('dd.MM.yyyy HH:mm');

  final TextEditingController _token = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _model;
  Map<String, dynamic>? _stats;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = _token.text.trim();
    if (token.isEmpty || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final json = await context.read<ChatProvider>().api.getAdminStats(token);
      if (!mounted) return;
      setState(() {
        _stats = json['stats'] as Map<String, dynamic>;
        _model = json['model'] as String?;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _stats = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(num? value) => '\$${(value ?? 0).toStringAsFixed(4)}';

  String _date(String? iso) {
    final parsed = DateTime.tryParse(iso ?? '');
    return parsed == null ? '—' : _dateFormat.format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stats = _stats;

    return Scaffold(
      appBar: AppBar(title: const Text('Панель администратора')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _token,
                        obscureText: true,
                        onSubmitted: (_) => _load(),
                        decoration: const InputDecoration(
                          labelText: 'Токен администратора',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.key),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _loading ? null : _load,
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(stats == null ? 'Войти' : 'Обновить'),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: TextStyle(color: scheme.error)),
                  ),
                if (stats == null && _error == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Введите токен из файла backend/.env (ADMIN_TOKEN), чтобы увидеть статистику.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                if (stats != null) ...[
                  const SizedBox(height: 20),
                  _sectionTitle('Запросы'),
                  _grid([
                    _StatCard('Всего запросов', '${stats['totalRequests']}',
                        Icons.swap_vert),
                    _StatCard('Запросов к AI', '${stats['chatRequests']}',
                        Icons.chat_outlined),
                    _StatCard('С ошибкой', '${stats['failedRequests']}',
                        Icons.error_outline),
                    _StatCard('Средний ответ AI', '${stats['avgChatMs']} мс',
                        Icons.timer_outlined),
                  ]),
                  _sectionTitle('Активность'),
                  _grid([
                    _StatCard('Пользователей', '${stats['users']}',
                        Icons.people_outline),
                    _StatCard('Диалогов', '${stats['conversations']}',
                        Icons.forum_outlined),
                    _StatCard('Сообщений', '${stats['messages']}',
                        Icons.message_outlined),
                  ]),
                  _sectionTitle('Расходы на API${_model == null ? '' : ' ($_model)'}'),
                  _grid([
                    _StatCard('Стоимость', _money(stats['costUsd'] as num?),
                        Icons.payments_outlined),
                    _StatCard('Токены запросов', '${stats['promptTokens']}',
                        Icons.north_east),
                    _StatCard('Токены ответов',
                        '${stats['completionTokens']}', Icons.south_west),
                  ]),
                  _sectionTitle('По дням'),
                  for (final day in (stats['perDay'] as List? ?? const []))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.calendar_today, size: 20),
                      title: Text('${day['day']}'),
                      subtitle: Text(
                          'Запросов: ${day['requests']} · к AI: ${day['chatRequests']} · ошибок: ${day['failedRequests']}'),
                      trailing: Text(_money(day['costUsd'] as num?)),
                    ),
                  _sectionTitle('Пользователи'),
                  for (final user in (stats['perUser'] as List? ?? const []))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text('${user['userId']}'),
                      subtitle: Text(
                          'Запросов: ${user['requests']} · к AI: ${user['chatRequests']} · токенов: ${user['tokens']}\n'
                          'Последняя активность: ${_date(user['lastSeen'] as String?)}'),
                      isThreeLine: true,
                      trailing: Text(_money(user['costUsd'] as num?)),
                    ),
                  _sectionTitle('Последние ошибки'),
                  if ((stats['recentErrors'] as List? ?? const []).isEmpty)
                    const ListTile(dense: true, title: Text('Ошибок нет')),
                  for (final item
                      in (stats['recentErrors'] as List? ?? const []))
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.warning_amber, color: scheme.error),
                      title: Text('${item['status']} · ${item['path']}'),
                      subtitle: Text(
                          '${_date(item['ts'] as String?)}\n${item['error'] ?? ''}'),
                      isThreeLine: true,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _grid(List<_StatCard> cards) {
    return Wrap(spacing: 10, runSpacing: 10, children: cards);
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 168,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary, size: 22),
          const SizedBox(height: 10),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
