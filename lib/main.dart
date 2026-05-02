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

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
class _Bootstrapper extends StatefulWidget {
  const _Bootstrapper();

  @override
  State<_Bootstrapper> createState() => _BootstrapperState();
}

class _BootstrapperState extends State<_Bootstrapper> {
  late final Future<Widget> _startPageFuture;

  @override
  void initState() {
    super.initState();
    _startPageFuture = _decideStartPage();
  }

  Future<bool> _checkNeedsSync() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    final state = Hive.isBoxOpen('app_state')
        ? Hive.box('app_state')
        : await Hive.openBox('app_state');
    final lastSeeded = state.get('last_seeded_version_code');
    final last = lastSeeded is int ? lastSeeded : 0;
    return currentBuild > last;
  }

  Future<Widget> _decideStartPage() async {
    final needsSync = await _checkNeedsSync();
    if (needsSync) {
      return const FirstSyncScreen();
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const LoginPage();
    }

    try {
      await HiveBoxes.openUserLancamentos(user.uid);
      FixedCollectionsSync().iniciarListenerVersao();
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
      future: _startPageFuture,
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
