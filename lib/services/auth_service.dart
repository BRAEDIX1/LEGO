// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../data/local/hive_boxes.dart';
import '../data/repositories/lancamentos_repository.dart';
import '../services/connectivity_service.dart';
import '../services/seed_bootstrap.dart';
import 'user_service.dart';  // ⭐ NOVO IMPORT

class AuthService {
  // Singleton (mantém compatibilidade com quem usa AuthService.instance)
  AuthService._();
  static final AuthService instance = AuthService._();
  // E também permite AuthService() em telas antigas
  factory AuthService() => instance;

  final ConnectivityService _conn = ConnectivityService();

  User? get currentUser => FirebaseAuth.instance.currentUser;
  String? get uid => currentUser?.uid;

  // ----------------- LOGIN / CADASTRO -----------------

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _afterLogin(cred.user!.uid);
    return cred;
  }

  // ⭐ MODIFICADO: Adicionados parâmetros nickname, nome, sobrenome
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String nickname,
    required String nome,
    required String sobrenome,
  }) async {
    // 1. Validar nickname
    final userService = UserService();

    bool disponivel;
    try {
      disponivel = await userService.nicknameDisponivel(nickname);
    } catch (e) {
      // Se der erro ao verificar, avisar o usuário
      throw FirebaseAuthException(
        code: 'verification-failed',
        message: 'Não foi possível verificar o nickname. Verifique sua conexão e tente novamente.',
      );
    }

    if (!disponivel) {
      throw FirebaseAuthException(
        code: 'nickname-already-in-use',
        message: 'Nickname "$nickname" já está em uso',
      );
    }

    // 2. Criar usuário no Firebase Auth
    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    try {
      // 3. Criar perfil no Firestore
      await userService.criarPerfil(
        uid: cred.user!.uid,
        email: email,
        nickname: nickname,
        nome: nome,
        sobrenome: sobrenome,
      );

      // 4. Atualizar displayName do Firebase Auth
      await cred.user!.updateDisplayName('$nome $sobrenome');

      await _afterLogin(cred.user!.uid);
      return cred;
    } catch (e) {
      // Se falhar ao criar perfil, deletar usuário do Auth
      await cred.user!.delete();
      rethrow;
    }
  }

  /// Google (web via popup). Em mobile, troque por google_sign_in ou signInWithProvider.
  Future<UserCredential> signInWithGoogle() async {
    final auth = FirebaseAuth.instance;
    if (kIsWeb) {
      final provider = GoogleAuthProvider()..addScope('email');
      final cred = await auth.signInWithPopup(provider);
      await _afterLogin(cred.user!.uid);
      return cred;
    } else {
      throw FirebaseAuthException(
        code: 'unimplemented',
        message: 'signInWithGoogle() só está implementado para Web neste projeto.',
      );
    }
  }

  Future<void> sendPasswordResetEmail(String email) {
    return FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  // ----------------- SIGN OUT -----------------

  /// Sai apenas se não houver pendentes/erros locais (protege o usuário).
  Future<bool> signOutWithGuard() async {
    final u = uid;
    if (u == null) return true;

    final repo = LancamentosRepository(uid: u);
    final pend = await repo.countPending();
    final errs = await repo.countErrors();
    if (pend > 0 || errs > 0) {
      // Há itens locais não sincronizados: não sair.
      return false;
    }

    // Tudo limpo → pode sair
    await HiveBoxes.closeUserLancamentos(u);
    _conn.stop();
    await FirebaseAuth.instance.signOut();
    return true;
  }

  /// Sai sem checar pendências.
  Future<void> signOut() async {
    final u = uid;
    if (u != null) {
      await HiveBoxes.closeUserLancamentos(u);
    }
    _conn.stop();
    UserService.limparCache();
    await FirebaseAuth.instance.signOut();
  }

  // ----------------- PÓS-LOGIN -----------------

  /// Fluxo único pós-login: adapters → boxes → seed → conectividade/sync.
  Future<void> _afterLogin(String uid) async {
    // 1) Adapters ANTES de abrir qualquer box
    HiveBoxes.ensureAdapters();

    // 2) Abrir boxes necessárias
    await HiveBoxes.openUserLancamentos(uid);

    // 3) ✅ REMOVIDO: Seed não acontece mais aqui
    // await SeedBootstrap.ensureSeedOnce(...);

    // 4) Opcional: aquece repositório (força leitura para validar)
    final repo = LancamentosRepository(uid: uid);
    await repo.countPending();
    await repo.countErrors();

    // 5) Conectividade/sincronização
    _conn.start();

    // 6) Pré-carregar perfil do usuário para cache
    try {
      final userService = UserService();
      await userService.buscarPerfil(uid);
      print('✅ Perfil do usuário carregado no cache');
    } catch (e) {
      print('⚠️ Não foi possível carregar perfil: $e');
    }
  }}