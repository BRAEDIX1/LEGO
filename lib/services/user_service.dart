import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/user_profile.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ⭐ CACHE EM MEMÓRIA
  static UserProfile? _cachedProfile;

  /// Cria perfil do usuário no Firestore
  Future<void> criarPerfil({
    required String uid,
    required String email,
    required String nickname,
    required String nome,
    required String sobrenome,
  }) async {
    // Validar nickname (minúsculas, números e underscore)
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(nickname)) {
      throw Exception('Nickname inválido. Use apenas letras minúsculas, números e underscore');
    }

    // Verificar se nickname já existe
    final existente = await _firestore
        .collection('users')
        .where('nickname', isEqualTo: nickname)
        .limit(1)
        .get();

    if (existente.docs.isNotEmpty) {
      throw Exception('Nickname "$nickname" já está em uso');
    }

    // Criar perfil
    final profile = UserProfile(
      uid: uid,
      email: email,
      nickname: nickname.toLowerCase().trim(),
      nome: nome.trim(),
      sobrenome: sobrenome.trim(),
      criadoEm: DateTime.now(),
    );

    await _firestore.collection('users').doc(uid).set(profile.toFirestore());

    // ⭐ SALVAR NO CACHE
    _cachedProfile = profile;
    await _salvarCacheLocal(profile);

    debugPrint('✅ Perfil criado: $nickname (${profile.nomeCompleto})');
  }

  /// Busca perfil do usuário (com cache)
  Future<UserProfile?> buscarPerfil(String uid) async {
    // ⭐ 1. Tentar cache em memória primeiro
    if (_cachedProfile != null && _cachedProfile!.uid == uid) {
      debugPrint('💾 Perfil carregado do cache em memória');
      return _cachedProfile;
    }

    // ⭐ 2. Tentar cache local (SharedPreferences)
    final cacheLocal = await _carregarCacheLocal(uid);
    if (cacheLocal != null) {
      _cachedProfile = cacheLocal;
      debugPrint('💾 Perfil carregado do cache local');
      return cacheLocal;
    }

    // ⭐ 3. Buscar no Firestore (apenas se necessário)
    try {
      debugPrint('🌐 Buscando perfil no Firestore...');
      final doc = await _firestore.collection('users').doc(uid).get();

      if (!doc.exists) {
        debugPrint('⚠️ Perfil não encontrado para UID: $uid');
        return null;
      }

      final profile = UserProfile.fromFirestore(doc);

      // Salvar em cache
      _cachedProfile = profile;
      await _salvarCacheLocal(profile);

      debugPrint('✅ Perfil buscado e salvo em cache');
      return profile;
    } catch (e) {
      debugPrint('❌ Erro ao buscar perfil: $e');
      return null;
    }
  }

  /// Busca nickname por UID (usa cache)
  Future<String> buscarNickname(String uid) async {
    final profile = await buscarPerfil(uid);
    return profile?.nickname ?? 'desconhecido';
  }

  /// Atualiza perfil do usuário
  Future<void> atualizarPerfil({
    required String uid,
    String? nome,
    String? sobrenome,
  }) async {
    if (nome == null && sobrenome == null) return;

    final updates = <String, dynamic>{
      'atualizadoEm': FieldValue.serverTimestamp(),
    };

    if (nome != null) {
      updates['nome'] = nome.trim();
    }
    if (sobrenome != null) {
      updates['sobrenome'] = sobrenome.trim();
    }

    // Recalcular campos derivados se necessário
    if (nome != null || sobrenome != null) {
      final profile = await buscarPerfil(uid);
      if (profile != null) {
        final novoNome = nome ?? profile.nome;
        final novoSobrenome = sobrenome ?? profile.sobrenome;
        updates['nomeCompleto'] = '$novoNome $novoSobrenome';
        updates['iniciais'] = '${novoNome[0].toUpperCase()}${novoSobrenome[0].toUpperCase()}';
      }
    }

    await _firestore.collection('users').doc(uid).update(updates);

    // ⭐ Limpar cache para forçar reload
    _cachedProfile = null;
    await _limparCacheLocal(uid);

    debugPrint('✅ Perfil atualizado para UID: $uid');
  }

  /// Verifica se nickname está disponível
  Future<bool> nicknameDisponivel(String nickname) async {
    try {
      debugPrint('🔍 Verificando disponibilidade do nickname: $nickname');

      final query = await _firestore
          .collection('users')
          .where('nickname', isEqualTo: nickname.toLowerCase())
          .limit(1)
          .get();

      final disponivel = query.docs.isEmpty;

      debugPrint('✅ Nickname "$nickname" disponível: $disponivel (encontrados: ${query.docs.length})');

      return disponivel;
    } catch (e) {
      debugPrint('❌ ERRO ao verificar nickname: $e');
      rethrow;
    }
  }

  // ⭐ MÉTODOS DE CACHE LOCAL

  Future<void> _salvarCacheLocal(UserProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode({
        'uid': profile.uid,
        'email': profile.email,
        'nickname': profile.nickname,
        'nome': profile.nome,
        'sobrenome': profile.sobrenome,
        'nomeCompleto': profile.nomeCompleto,
        'iniciais': profile.iniciais,
        'criadoEm': profile.criadoEm.toIso8601String(),
      });
      await prefs.setString('user_profile_${profile.uid}', json);
    } catch (e) {
      debugPrint('⚠️ Erro ao salvar cache local: $e');
    }
  }

  Future<UserProfile?> _carregarCacheLocal(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('user_profile_$uid');

      if (json == null) return null;

      final data = jsonDecode(json) as Map<String, dynamic>;
      return UserProfile(
        uid: data['uid'] as String,
        email: data['email'] as String,
        nickname: data['nickname'] as String,
        nome: data['nome'] as String,
        sobrenome: data['sobrenome'] as String,
        criadoEm: DateTime.parse(data['criadoEm'] as String),
      );
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar cache local: $e');
      return null;
    }
  }

  Future<void> _limparCacheLocal(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_profile_$uid');
    } catch (e) {
      debugPrint('⚠️ Erro ao limpar cache local: $e');
    }
  }

  /// Limpa todo o cache (útil no logout)
  static void limparCache() {
    _cachedProfile = null;
  }
}