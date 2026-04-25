import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/auth_service.dart';
import 'home_page.dart';
import 'package:hive/hive.dart';
import 'first_sync_screen.dart';
import 'package:lego/services/fixed_collections_sync.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _nomeCtrl = TextEditingController();
  final _sobrenomeCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _authService = AuthService();
  bool _obscure = true;
  bool _isLoading = false;
  bool _isRegister = false;
  bool _remember = false;
  String _versao = '';

  final String? _allowedDomain = null;

  final FocusNode _emailFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _emailFocus.requestFocus();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _versao = info.version);
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _nomeCtrl.dispose();
    _sobrenomeCtrl.dispose();
    _nicknameCtrl.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Informe o e-mail';
    final email = v.trim();
    final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email);
    if (!ok) return 'E-mail inválido';
    if (_allowedDomain != null && !email.toLowerCase().endsWith(_allowedDomain)) {
      return 'Use um e-mail $_allowedDomain';
    }
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Informe a senha';
    if (v.length < 6) return 'Mínimo de 6 caracteres';
    return null;
  }

  String? _validateNickname(String? v) {
    if (v == null || v.trim().isEmpty) return 'Informe o nickname';
    if (v.trim().length < 3) return 'Mínimo de 3 caracteres';
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(v)) {
      return 'Use apenas letras minúsculas, números e underscore';
    }
    return null;
  }

  String? _validateNome(String? v, String campo) {
    if (v == null || v.trim().isEmpty) return 'Informe o $campo';
    if (v.trim().length < 2) return '$campo muito curto';
    return null;
  }

  /// Inicia o listener de versão do Firestore após login bem-sucedido.
  /// O listener fica ativo enquanto o app estiver aberto e detecta
  /// atualizações em tempo real no documento sistema/versoes.
  void _iniciarListenerVersao() {
    FixedCollectionsSync().iniciarListenerVersao();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;

    setState(() => _isLoading = true);
    try {
      if (_isRegister) {
        await _authService.registerWithEmail(
          email: email,
          password: pass,
          nickname: _nicknameCtrl.text.trim().toLowerCase(),
          nome: _nomeCtrl.text.trim(),
          sobrenome: _sobrenomeCtrl.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conta criada com sucesso!')),
        );
        final needsSync = await _checkNeedsSync();
        if (!mounted) return;

        _iniciarListenerVersao(); // ✅ Inicia listener após registro

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => needsSync
                ? const FirstSyncScreen()
                : const HomePage(),
          ),
        );
      } else {
        final userCredential = await _authService.signInWithEmailAndPassword(
            email: email, password: pass);
        if (!mounted) return;
        final verified = userCredential.user?.emailVerified ?? false;
        if (!verified) {
          await userCredential.user?.sendEmailVerification();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('E-mail não verificado. Reenviamos o link.')),
          );
          await _authService.signOut();
        } else {
          final needsSync = await _checkNeedsSync();
          if (!mounted) return;

          _iniciarListenerVersao(); // ✅ Inicia listener após login

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => needsSync
                  ? const FirstSyncScreen()
                  : const HomePage(),
            ),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = _translateAuthError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _translateAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'E-mail inválido';
      case 'user-disabled':
        return 'Usuário desabilitado';
      case 'user-not-found':
        return 'Usuário não encontrado';
      case 'wrong-password':
        return 'Senha incorreta';
      case 'email-already-in-use':
        return 'Já existe uma conta com este e-mail';
      case 'nickname-already-in-use':
        return e.message ?? 'Nickname já está em uso';
      case 'weak-password':
        return 'Senha fraca (mín. 6 caracteres)';
      case 'too-many-requests':
        return 'Muitas tentativas. Tente novamente em instantes';
      default:
        return 'Falha de autenticação (${e.code})';
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Informe o e-mail para redefinir a senha')),
      );
      return;
    }
    try {
      await _authService.sendPasswordResetEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Enviamos um link de redefinição para seu e-mail.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível enviar o e-mail: $e')),
      );
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final userCredential = await _authService.signInWithGoogle();
      if (userCredential == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final needsSync = await _checkNeedsSync();
      if (!mounted) return;

      _iniciarListenerVersao(); // ✅ Inicia listener após login com Google

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => needsSync
              ? const FirstSyncScreen()
              : const HomePage(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = _translateAuthError(e);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Falha: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Verifica se precisa fazer sincronização inicial
  Future<bool> _checkNeedsSync() async {
    try {
      final state = await Hive.openBox('app_state');
      final seedDone = state.get('seed_v1_done') == true;
      return !seedDone;
    } catch (e) {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      bottomNavigationBar: _versao.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'v$_versao',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
      body: LayoutBuilder(
        builder: (context, c) {
          const mobileMax = 600.0;
          const tabletMax = 1024.0;
          final isMobile = c.maxWidth <= mobileMax;
          final isTablet = c.maxWidth > mobileMax && c.maxWidth <= tabletMax;
          final isDesktop = c.maxWidth > tabletMax;

          final form = ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: isDesktop || isTablet ? 420 : double.infinity),
            child: Card(
              elevation: isMobile ? 0 : 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              margin: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 24, vertical: 24),
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 16 : 24),
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline,
                            size: isMobile ? 48 : 64),
                        const SizedBox(height: 12),
                        Text(
                          _isRegister ? 'Criar conta' : 'Entrar',
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 24),

                        if (_isRegister) ...[
                          TextFormField(
                            controller: _nomeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nome',
                              hintText: 'Ex: Djalma',
                              prefixIcon: Icon(Icons.person),
                            ),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) => _validateNome(v, 'nome'),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _sobrenomeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Sobrenome',
                              hintText: 'Ex: Tolentino',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) =>
                                _validateNome(v, 'sobrenome'),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _nicknameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nickname/Apelido',
                              hintText: 'Ex: djalma_tolentino',
                              prefixIcon:
                                  Icon(Icons.alternate_email),
                              helperText:
                                  'Apenas letras minúsculas, números e underscore',
                            ),
                            validator: _validateNickname,
                            textInputAction: TextInputAction.next,
                            onChanged: (value) {
                              if (value != value.toLowerCase()) {
                                _nicknameCtrl.value =
                                    _nicknameCtrl.value.copyWith(
                                  text: value.toLowerCase(),
                                  selection: TextSelection.collapsed(
                                      offset: value.length),
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                        ],

                        TextFormField(
                          controller: _emailCtrl,
                          focusNode: _emailFocus,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [
                            AutofillHints.email,
                            AutofillHints.username
                          ],
                          decoration: const InputDecoration(
                            labelText: 'E-mail',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: _validateEmail,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              FocusScope.of(context).nextFocus(),
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Senha',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(_obscure
                                  ? Icons.visibility
                                  : Icons.visibility_off),
                            ),
                          ),
                          validator: _validatePassword,
                          textInputAction: _isRegister
                              ? TextInputAction.next
                              : TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (_isRegister) {
                              FocusScope.of(context).nextFocus();
                            } else {
                              _handleSubmit();
                            }
                          },
                        ),

                        if (_isRegister) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirmCtrl,
                            obscureText: _obscure,
                            decoration: const InputDecoration(
                              labelText: 'Confirmar senha',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            validator: (v) {
                              final msg = _validatePassword(v);
                              if (msg != null) return msg;
                              if (v != _passCtrl.text)
                                return 'As senhas não coincidem';
                              return null;
                            },
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _handleSubmit(),
                          ),
                        ],

                        const SizedBox(height: 8),

                        if (!_isRegister)
                          Row(
                            children: [
                              Checkbox(
                                value: _remember,
                                onChanged: (v) =>
                                    setState(() => _remember = v ?? false),
                              ),
                              const Text('Lembrar-me'),
                              const Spacer(),
                              TextButton(
                                onPressed: _forgotPassword,
                                child: const Text('Esqueci a senha'),
                              ),
                            ],
                          ),

                        const SizedBox(height: 12),

                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            onPressed:
                                _isLoading ? null : _handleSubmit,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Text(_isRegister
                                    ? 'Criar conta'
                                    : 'Entrar'),
                          ),
                        ),

                        const SizedBox(height: 12),

                        OutlinedButton.icon(
                          onPressed:
                              _isLoading ? null : _signInWithGoogle,
                          icon: const Icon(Icons.login),
                          label: const Text('Entrar com Google'),
                        ),

                        const SizedBox(height: 12),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_isRegister
                                ? 'Já tem conta?'
                                : 'Novo por aqui?'),
                            TextButton(
                              onPressed: () => setState(
                                  () => _isRegister = !_isRegister),
                              child: Text(_isRegister
                                  ? 'Entrar'
                                  : 'Criar conta'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

          final sidePanel = Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.1),
                    theme.colorScheme.secondary.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.dashboard_customize_rounded,
                        size: isDesktop ? 140 : 100,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Bem-vindo ao seu painel',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Acesse a plataforma para gerenciar seus dados com segurança.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodyMedium?.color
                              ?.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

          if (isMobile) {
            return SafeArea(
              child: Center(
                  child: SingleChildScrollView(child: form)),
            );
          }
          return Row(
            children: [
              Expanded(
                  child: Center(
                      child: SingleChildScrollView(child: form))),
              sidePanel,
            ],
          );
        },
      ),
    );
  }
}
