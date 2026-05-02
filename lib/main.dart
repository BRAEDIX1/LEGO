// lib/main.dart - Mobile
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hive/hive.dart';
import 'package:lego/data/local/hive_boxes.dart';
import 'package:lego/services/mobile_sync_service.dart';
import 'package:lego/services/fixed_collections_sync.dart';
import 'package:lego/ui/home_page.dart';
import 'package:lego/ui/login_page.dart';
import 'package:lego/ui/first_sync_screen.dart';
import 'package:lego/ui/update_checker_screen.dart';
import 'package:lego/ui/mobile/screens/modo_operacao_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
        '/login':         (context) => const LoginPage(),
        '/home':          (context) => const HomePage(),
        '/modo_operacao': (context) => const ModoOperacaoScreen(),
      },
      home: const UpdateCheckerScreen(proximaTela: _Bootstrapper()),
    );
  }
}

/// Decide qual tela abrir e garante que as boxes do usuário estejam prontas.
class _Bootstrapper extends StatelessWidget {
  const _Bootstrapper();

  /// Verifica se o seed inicial já foi feito e se a versão ainda é a mesma
  Future<bool> _checkNeedsSync() async {
    try {
      final state = await Hive.openBox('app_state');
      final seedDone = state.get('seed_v1_done') == true;
      if (!seedDone) return true;

      final jsonString = await rootBundle.loadString('assets/firestore_dump.json');
      final Map<String, dynamic> dump = json.decode(jsonString);
      final versaoJson = (dump['version'] ?? '').toString();
      final versaoSeed = state.get('seed_app_version') as String?;
      return versaoSeed != versaoJson;
    } catch (e) {
      return true;
    }
  }

  Future<Widget> _decideStartPage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const LoginPage();
    }

    try {
      // Abre boxes do usuário
      await HiveBoxes.openUserLancamentos(user.uid);

      // ✅ Inicia listener de versão — detecta atualizações do Firestore
      // em tempo real e sincroniza automaticamente quando há mudança.
      FixedCollectionsSync().iniciarListenerVersao();

      // Verifica se o seed já foi feito
      final needsSync = await _checkNeedsSync();
      if (needsSync) {
        return const FirstSyncScreen();
      }

      // Seed já feito — inicializa serviço e vai para home
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
