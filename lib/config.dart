import 'package:flutter/foundation.dart';

/// Настройки приложения.
///
/// Здесь НЕТ ключа OpenAI: приложение общается только со своим Backend-сервером,
/// а ключ хранится на сервере в файле .env.
class AppConfig {
  /// Адрес сервера можно задать при запуске:
  /// `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3000`
  static const String _fromEnvironment = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_fromEnvironment.isNotEmpty) return _fromEnvironment;
    // В Android-эмуляторе компьютер разработчика доступен по адресу 10.0.2.2.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  /// Сколько ждать ответа сервера, прежде чем показать «Превышено время ожидания».
  static const Duration requestTimeout = Duration(seconds: 45);

  /// Сколько ждать очередную часть потокового ответа.
  static const Duration streamIdleTimeout = Duration(seconds: 30);
}
