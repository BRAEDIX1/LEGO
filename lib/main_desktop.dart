// lib/main_desktop.dart
//
// D16/D16-1: o ambiente do desktop é fixado pelo PONTO DE ENTRADA:
//   lib/main_desktop.dart        → produção (murilo-21h52m)
//   lib/main_desktop_teste.dart  → teste (lego-teste)
// Nenhum parâmetro de build decide; esquecer um define não muda o ambiente.
// Os mesmos portões do celular rodam antes de qualquer login: opções
// conferidas, Firebase iniciado, projeto/appId conferidos de novo.
// No teste, uma faixa laranja fixa no topo de toda tela.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lego/config/ambiente.dart';
import 'firebase_options.dart';
import 'firebase_options_teste.dart';

// ⭐ Telas do Desktop (todas as fases)
import 'package:lego/ui/desktop/screens/dashboard_desktop_screen.dart';
import 'package:lego/services/compatibilidade_service.dart';
import 'package:lego/services/registro_erros.dart';
import 'package:open_filex/open_filex.dart';

/// Ambiente deste executável, fixado pelo ponto de entrada.
Ambiente _ambienteDesktop = Ambiente.producao;
bool get _ehTeste => _ambienteDesktop == Ambiente.teste;

/// Produção. O teste entra por lib/main_desktop_teste.dart.
Future<void> main() => iniciarLegoDesktop(Ambiente.producao);

/// Pacote 1 (P0-06): tudo roda numa zona protegida e com os tratadores
/// globais de erro ligados (RegistroErros → arquivo de log local).
Future<void> iniciarLegoDesktop(Ambiente ambiente) =>
    RegistroErros.executarProtegido(() => _iniciarLegoDesktop(ambiente));

Future<void> _iniciarLegoDesktop(Ambiente ambiente) async {
  WidgetsFlutterBinding.ensureInitialized();
  _ambienteDesktop = ambiente;
  await RegistroErros.instalar(ambiente.name);

  final bloqueio = await _inicializarFirebaseDesktop();
  if (bloqueio != null) {
    debugPrint('⛔ Desktop bloqueado: $bloqueio');
    runApp(_DesktopBloqueado(bloqueio));
    return;
  }

  // Configurar Firestore para Desktop
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  await _descartarSessaoDeOutroProjeto();

  runApp(const LegoDesktopApp());
}

String? _projetoIniciado;

/// Devolve `null` quando tudo confere; senão, o motivo do bloqueio.
Future<ResultadoPortao?> _inicializarFirebaseDesktop() async {
  final amb = _ambienteDesktop;

  final FirebaseOptions opcoes;
  try {
    opcoes = switch (amb) {
      Ambiente.producao => DefaultFirebaseOptions.currentPlatform,
      Ambiente.teste => TesteFirebaseOptions.currentPlatform,
    };
  } catch (e) {
    return ResultadoPortao.bloqueado(
        MotivoBloqueioInicial.configuracaoIncompleta, '$e');
  }

  final conferidas = portaoOpcoes(
    ambiente: amb,
    projectId: opcoes.projectId,
    appId: opcoes.appId,
    apiKey: opcoes.apiKey,
    messagingSenderId: opcoes.messagingSenderId,
    storageBucket: opcoes.storageBucket,
    appIdExigido: appIdEsperadoDesktop(amb),
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
    appIdExigido: appIdEsperadoDesktop(amb),
  );
  return pos.liberado ? null : pos;
}

/// D16: no Windows o login salvo pode ter vindo do OUTRO projeto (produção e
/// teste no mesmo PC). Se o servidor recusar a sessão, sai e pede login.
/// Sem internet não faz nada (o portão de compatibilidade já exige servidor).
Future<void> _descartarSessaoDeOutroProjeto() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    await user.getIdToken(true).timeout(const Duration(seconds: 10));
  } on FirebaseAuthException catch (e) {
    if (e.code == 'network-request-failed') return;
    debugPrint('🔑 Sessão salva recusada (${e.code}); saindo');
    await FirebaseAuth.instance.signOut();
  } catch (_) {
    // timeout ou outro erro: segue; o login/portão tratam depois
  }
}

/// Faixa fixa do ambiente de teste, acima de qualquer tela.
Widget _comFaixaDeTeste(Widget? child) {
  if (!_ehTeste) return child ?? const SizedBox.shrink();
  return Column(
    children: [
      Material(
        color: Colors.orange.shade700,
        child: SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'LEGO TESTE · ambiente de teste (lego-teste) · não é produção',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
              ),
              // Pacote 1 (P0-06): abre a pasta do log de erros. (Sem Tooltip:
              // a faixa fica acima do Navigator, onde não há Overlay.)
              InkWell(
                onTap: () {
                  final pasta = RegistroErros.pasta;
                  if (pasta != null) OpenFilex.open(pasta);
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text('Log de erros',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          decoration: TextDecoration.underline)),
                ),
              ),
            ],
          ),
        ),
      ),
      Expanded(child: child ?? const SizedBox.shrink()),
    ],
  );
}

/// Tela única quando o desktop não confere com o ambiente (sem login).
class _DesktopBloqueado extends StatelessWidget {
  final ResultadoPortao resultado;
  const _DesktopBloqueado(this.resultado);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LEGO Desktop – bloqueado',
      home: Scaffold(
        backgroundColor: Colors.red.shade50,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.block, size: 56, color: Colors.red.shade700),
                  const SizedBox(height: 16),
                  const Text('Build desktop inconsistente',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text('Este executável não confere com o ambiente para '
                      'o qual foi gerado. Avise o responsável pelo LEGO.'),
                  const SizedBox(height: 16),
                  SelectableText(
                    'Ambiente: ${_ambienteDesktop.name}\n'
                    'Projeto: ${_projetoIniciado ?? "(Firebase não iniciado)"}\n'
                    'Motivo: ${resultado.motivo?.name}\n'
                    'Detalhe: ${resultado.detalhe}',
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
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

class LegoDesktopApp extends StatelessWidget {
  const LegoDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _ehTeste ? 'LEGO TESTE - Desktop' : 'LEGO Inventário - Desktop',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => _comFaixaDeTeste(child),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _ehTeste ? Colors.orange : Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 1,
          margin: EdgeInsets.all(8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        dataTableTheme: DataTableThemeData(
          headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
          dataRowMinHeight: 48,
          dataRowMaxHeight: 64,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.light,
      home: const AuthWrapper(),
    );
  }
}

/// Wrapper para gerenciar autenticação
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          // T34 (3B, D11): o dashboard só abre com compatibilidade liberada
          return _PortaoCompatibilidade(
            key: ValueKey(snapshot.data!.uid),
            child: const DashboardDesktopScreen(),
          );
        }

        return const LoginDesktopScreen();
      },
    );
  }
}

/// T34 (3B): confere `versao_minima_desktop` no servidor antes do dashboard.
/// Documento ausente/inválido, versão abaixo ou falha de leitura = bloqueio.
class _PortaoCompatibilidade extends StatefulWidget {
  final Widget child;
  const _PortaoCompatibilidade({super.key, required this.child});

  @override
  State<_PortaoCompatibilidade> createState() => _PortaoCompatibilidadeState();
}

class _PortaoCompatibilidadeState extends State<_PortaoCompatibilidade> {
  bool _verificando = true;
  bool _liberado = false;
  String _motivo = '';

  @override
  void initState() {
    super.initState();
    _verificar();
  }

  Future<void> _verificar() async {
    setState(() {
      _verificando = true;
      _motivo = '';
    });
    var liberado = false;
    var motivo = '';
    try {
      await CompatibilidadeService()
          .verificarNoServidor(PlataformaCompat.desktop);
      liberado = true;
    } on CompatibilidadeException catch (e) {
      motivo = e.mensagem;
    } on FirebaseException catch (e) {
      motivo = e.code == 'unavailable'
          ? 'Servidor Firestore indisponível ou sem conexão com a internet.'
          : e.code == 'permission-denied'
              ? 'Sem permissão para ler a configuração de compatibilidade '
                  '(regras do Firestore). Detalhe: ${e.message}'
              : 'Erro ao conferir a compatibilidade (${e.code}): ${e.message}';
    } catch (e) {
      motivo = 'Erro ao conferir a compatibilidade: $e';
    }
    if (!mounted) return;
    setState(() {
      _verificando = false;
      _liberado = liberado;
      _motivo = motivo;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_verificando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_liberado) return widget.child;
    return Scaffold(
      body: Center(
        child: Card(
          elevation: 8,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, size: 56, color: Colors.red.shade700),
                const SizedBox(height: 16),
                Text(
                  'LEGO Desktop bloqueado',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(_motivo, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _verificar,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                    TextButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: const Text('Sair'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tela de login para desktop
class LoginDesktopScreen extends StatefulWidget {
  const LoginDesktopScreen({super.key});

  @override
  State<LoginDesktopScreen> createState() => _LoginDesktopScreenState();
}

class _LoginDesktopScreenState extends State<LoginDesktopScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _getErrorMessage(e.code);
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao fazer login: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'Usuário não encontrado';
      case 'wrong-password':
        return 'Senha incorreta';
      case 'invalid-email':
        return 'E-mail inválido';
      case 'user-disabled':
        return 'Usuário desabilitado';
      case 'too-many-requests':
        return 'Muitas tentativas. Tente novamente mais tarde';
      default:
        return 'Erro ao fazer login. Verifique suas credenciais';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Card(
          elevation: 8,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.inventory, size: 64, color: Colors.blue),
                const SizedBox(height: 16),
                Text(
                  _ehTeste ? 'LEGO TESTE' : 'LEGO Inventário',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Central de Análise Desktop',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Senha',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _isLoading ? null : (_) => _login(),
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 24),
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                FilledButton(
                  onPressed: _isLoading ? null : _login,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('ENTRAR'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
