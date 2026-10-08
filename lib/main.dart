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
import 'package:lego/ui/resolver_tela_inicial.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:lego/config/ambiente.dart';
import 'firebase_options.dart';
import 'firebase_options_teste.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 3C (T45/B55): portões ANTES de Hive, login e sincronização.
  // Qualquer inconsistência de build → tela fixa, e o app para aqui.
  final bloqueio = await _inicializarFirebaseDoAmbiente();
  if (bloqueio != null) {
    debugPrint('⛔ Build inconsistente: $bloqueio');
    runApp(_AppBuildInconsistente(bloqueio));
    return;
  }

  await Hive.initFlutter();
  HiveBoxes.ensureAdapters();

  runApp(const MyApp());
}

/// Opções do Firebase de cada ambiente (T44).
FirebaseOptions _opcoesDo(Ambiente ambiente) => switch (ambiente) {
      Ambiente.producao => DefaultFirebaseOptions.currentPlatform,
      Ambiente.teste => TesteFirebaseOptions.currentPlatform,
    };

/// Devolve `null` quando tudo confere; senão, o motivo do bloqueio.
/// Portão 1: ambiente. Portão 2: pacote. Ambos antes do Firebase.
/// Portão das opções (B56): projectId/appId das opções vs. fontes independentes.
/// Portão 3: inicialização (exceção bloqueia) + projectId + appId do app iniciado.
/// Para a tela de bloqueio: o que foi lido em cada portão.
String? _pacoteLido;
String? _projetoIniciado;

Future<ResultadoPortao?> _inicializarFirebaseDoAmbiente() async {
  final ambiente = ambienteAtual;

  String? pacote;
  try {
    pacote = (await PackageInfo.fromPlatform()).packageName;
  } catch (e) {
    pacote = null; // pacote desconhecido → portão 2 bloqueia
  }
  _pacoteLido = pacote;

  final pre = portaoPreFirebase(ambiente: ambiente, packageName: pacote);
  if (!pre.liberado) return pre;
  final amb = ambiente!; // garantido pelo portão 1

  final FirebaseOptions opcoes;
  try {
    opcoes = _opcoesDo(amb);
  } catch (e) {
    return ResultadoPortao.bloqueado(
        MotivoBloqueioInicial.configuracaoIncompleta, '$e');
  }
  // B56: projectId e appId das opções conferidos ANTES do Firebase,
  // contra fontes independentes (projetoEsperado / appIdEsperado).
  final conferidas = portaoOpcoes(
    ambiente: amb,
    projectId: opcoes.projectId,
    appId: opcoes.appId,
    apiKey: opcoes.apiKey,
    messagingSenderId: opcoes.messagingSenderId,
    storageBucket: opcoes.storageBucket,
  );
  if (!conferidas.liberado) return conferidas;

  try {
    await Firebase.initializeApp(options: opcoes);
  } catch (e) {
    return ResultadoPortao.bloqueado(MotivoBloqueioInicial.firebaseFalhou, '$e');
  }

  final app = Firebase.app();
  _projetoIniciado = app.options.projectId;
  final pos = portaoPosFirebase(
    ambiente: amb,
    projectId: app.options.projectId,
    appId: app.options.appId,
  );
  return pos.liberado ? null : pos;
}

/// Tela única quando o build não confere (B55). Sem rotas, sem login,
/// sem Hive: não há como seguir a partir daqui.
class _AppBuildInconsistente extends StatelessWidget {
  final ResultadoPortao resultado;
  const _AppBuildInconsistente(this.resultado);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LEGO – build inconsistente',
      home: Scaffold(
        backgroundColor: Colors.red.shade50,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.block, size: 56, color: Colors.red.shade700),
                const SizedBox(height: 16),
                const Text(
                  'Build inconsistente',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Este APK não confere com o ambiente para o qual foi gerado. '
                  'Não use este aparelho para contagem. Avise o responsável '
                  'pelo LEGO.',
                ),
                const SizedBox(height: 16),
                SelectableText(
                  'Ambiente: ${ambienteAtual?.name ?? "inválido"}\n'
                  'Pacote: ${_pacoteLido ?? "(não lido)"}\n'
                  'Projeto: ${_projetoIniciado ?? "(Firebase não iniciado)"}\n'
                  'Motivo: ${resultado.motivo?.name}\n'
                  'Detalhe: ${resultado.detalhe}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 3C (T46/T47): no teste, sem tela de atualização e com a faixa TESTE.
    // Na produção, nada muda.
    final teste = ambienteAtual == Ambiente.teste;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: teste ? 'LEGO TESTE' : 'LEGO Inventário',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      builder: teste
          ? (context, child) => Banner(
                message: 'TESTE',
                location: BannerLocation.topEnd,
                color: Colors.red,
                textDirection: TextDirection.ltr,
                layoutDirection: TextDirection.ltr,
                child: child ?? const SizedBox.shrink(),
              )
          : null,
      routes: {
        '/login':         (context) => const LoginPage(),
        '/home':          (context) => const HomePage(),
        '/modo_operacao': (context) => const ModoOperacaoScreen(),
      },
      home: teste
          ? const _Bootstrapper()
          : const UpdateCheckerScreen(proximaTela: _Bootstrapper()),
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

    // B18: regra única (com LEGO_FLUXO2 desligado devolve a HomePage, como antes)
    return resolverTelaInicial();
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
