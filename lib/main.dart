// lib/main.dart - Mobile

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:lego/data/local/hive_boxes.dart';
import 'package:lego/services/mobile_sync_service.dart';  // ⭐ FASE 5
import 'package:lego/ui/home_page.dart';
import 'package:lego/ui/login_page.dart';
import 'package:lego/ui/mobile/screens/modo_operacao_screen.dart';  // ⭐ FASE 5
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Hive
  await Hive.initFlutter();
  HiveBoxes.ensureAdapters();

  // ⭐ FASE 5: Inicializa serviço de sincronização mobile
  // (será carregado após login, quando tivermos usuário)

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LEGO Inventário',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
        '/modo_operacao': (context) => const ModoOperacaoScreen(),  // ⭐ FASE 5
      },
      home: const _Bootstrapper(),
    );
  }
}

/// Decide qual tela abrir e garante que as boxes do usuário estejam prontas.
class _Bootstrapper extends StatelessWidget {
  const _Bootstrapper();

  Future<Widget> _decideStartPage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const LoginPage();
    }

    try {
      // Abre boxes do usuário
      await HiveBoxes.openUserLancamentos(user.uid);
      
      // ⭐ FASE 5: Inicializa serviço de sincronização
      await MobileSyncService().inicializar();
      
    } catch (e) {
      debugPrint('Falha na inicialização: $e');
      return const LoginPage();
    }

    return const HomePage();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _decideStartPage(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data ?? const LoginPage();
      },
    );
  }
}
