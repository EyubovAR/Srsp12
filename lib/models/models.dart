import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Состояние сообщения в чате.
enum MessageStatus { sending, sent, failed }

/// Одно сообщение в чате (пользователя или AI).
class ChatMessage {
  ChatMessage({
    required this.text,
    required this.isUser,
    required this.time,
    this.status = MessageStatus.sent,
    this.imageBytes,
    this.imageMime,
    this.hasImage = false,
    this.errorText,
  });

  String text;
  final bool isUser;
  DateTime time;
  MessageStatus status;

  /// Картинка, прикреплённая к сообщению (хранится только на устройстве в текущем сеансе).
  final Uint8List? imageBytes;
  final String? imageMime;
  final bool hasImage;

  /// Текст ошибки, если отправка не удалась.
  String? errorText;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      text: json['content'] as String? ?? '',
      isUser: json['sender'] == 'user',
      time: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      hasImage: json['hasImage'] == true,
    );
  }
}

/// Диалог в списке истории.
class Conversation {
  Conversation({
    required this.id,
    required this.title,
    required this.roleId,
    required this.createdAt,
    required this.updatedAt,
    required this.messageCount,
  });

  final String id;
  final String title;
  final String roleId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;

  factory Conversation.fromJson(Map<String, dynamic> json) {
    DateTime parse(String key) =>
        DateTime.tryParse(json[key] as String? ?? '')?.toLocal() ??
        DateTime.now();
    return Conversation(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Без названия',
      roleId: json['role'] as String? ?? AiRole.defaultRole.id,
      createdAt: parse('createdAt'),
      updatedAt: parse('updatedAt'),
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Роль AI-помощника. Идентификаторы совпадают с ролями на сервере (backend/src/roles.js).
class AiRole {
  const AiRole(this.id, this.title, this.description, this.icon);

  final String id;
  final String title;
  final String description;
  final IconData icon;

  static const List<AiRole> all = [
    AiRole('assistant', 'Помощник', 'Универсальный помощник на любой вопрос',
        Icons.auto_awesome),
    AiRole('teacher', 'Преподаватель',
        'Объясняет темы простым языком с примерами', Icons.school),
    AiRole('programmer', 'Программист', 'Помогает писать и разбирать код',
        Icons.code),
    AiRole('translator', 'Переводчик', 'Переводит тексты между языками',
        Icons.translate),
    AiRole('consultant', 'Консультант',
        'Даёт советы и помогает принять решение', Icons.support_agent),
  ];

  static AiRole get defaultRole => all.first;

  static AiRole byId(String? id) =>
      all.firstWhere((role) => role.id == id, orElse: () => defaultRole);
}
