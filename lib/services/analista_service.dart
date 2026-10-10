// lib/services/analista_service.dart
//
// Item 8: lê `sistema/app_config.analistas` e diz se o usuário logado é
// analista. Cache por uid (troca de login relê). Erro de leitura = não é
// analista (falha fechada); as regras do Firestore são a proteção de fato.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:lego/services/analista.dart';

class AnalistaService {
  static final AnalistaService _instance = AnalistaService._();
  factory AnalistaService() => _instance;
  AnalistaService._();

  String? _uid;
  bool? _resposta;
  DateTime? _lidoEm;
  /// B81-A: a resposta vale 2 min; depois relê (quem sai da lista perde a
  /// tela de analista sem reiniciar o app). As regras barram de qualquer jeito.
  static const _validade = Duration(minutes: 2);

  Future<bool> souAnalista() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return false;
    // Só o "sim" fica em cache, e só por [_validade].
    final lido = _lidoEm;
    if (_uid == u.uid &&
        _resposta == true &&
        lido != null &&
        DateTime.now().difference(lido) < _validade) {
      return true;
    }
    try {
      // Fonte padrão: servidor, e o cache se estiver offline.
      final snap = await FirebaseFirestore.instance
          .collection('sistema')
          .doc('app_config')
          .get()
          .timeout(const Duration(seconds: 8));
      final r = ehAnalista(snap.data()?['analistas'], u.email);
      _uid = u.uid;
      _resposta = r;
      _lidoEm = DateTime.now();
      return r;
    } catch (e) {
      debugPrint('⚠️ Analista: não foi possível ler app_config ($e)');
      return false;
    }
  }
}
