import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/chat_provider.dart';
import 'screens/welcome_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ChatProvider()..init(),
      child: const MyAiAssistantApp(),
    ),
  );
}

class MyAiAssistantApp extends StatelessWidget {
  const MyAiAssistantApp({super.key});

  static const Color _seed = Color(0xFF3F51B5);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Мой AI-помощник',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const WelcomeScreen(),
    );
  }
}
