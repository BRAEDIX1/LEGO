// lib/services/compatibilidade_service.dart
//
// Lote 3B (D11): busca a política de compatibilidade em `sistema/app_config`
// e aplica a regra pura de compatibilidade.dart.
//
// - [verificarNoServidor]: leitura OBRIGATÓRIA no servidor (entrada na
//   Completa, nova entrada no Controlado, desktop). Erros do Firestore sobem
//   como FirebaseException (o B34 distingue unavailable/permission-denied);
//   os demais, como [CompatibilidadeException].
// - [avaliarComCache]: tenta o servidor e, se falhar, usa a última política
//   lida (restauração do Controlado e vínculo automático da HomePage legada).
//   Nunca lança: sem servidor e sem cache devolve `politicaIndisponivel`
//   (falha fechada). R26: o cache não sabe de um mínimo elevado depois.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lego/services/compatibilidade.dart';

enum PlataformaCompat { mobile, desktop }

/// Recusa por compatibilidade com o tipo e a mensagem para o operador.
class CompatibilidadeException implements Exception {
  final ResultadoCompat tipo;
  final String mensagem;
  const CompatibilidadeException(this.tipo, this.mensagem);

  @override
  String toString() => mensagem;
}

class CompatibilidadeService {
  static final CompatibilidadeService _instance = CompatibilidadeService._();
  factory CompatibilidadeService() => _instance;
  CompatibilidadeService._();

  static const _timeoutServidor = Duration(seconds: 8);
  static const _campoMobile = 'versao_minima_mobile';
  static const _campoDesktop = 'versao_minima_desktop';
  static const _prefsPrefixo = 'compat_politica_';

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('sistema').doc('app_config');

  String _campo(PlataformaCompat p) =>
      p == PlataformaCompat.mobile ? _campoMobile : _campoDesktop;

  /// Leitura obrigatória no servidor. Liberado → retorna a decisão.
  /// Qualquer outro caso → lança (FirebaseException ou
  /// CompatibilidadeException).
  Future<DecisaoCompat> verificarNoServidor(PlataformaCompat plataforma) async {
    Object? minima;
    try {
      minima = await _lerMinimaDoServidor(plataforma);
    } on TimeoutException {
      throw const CompatibilidadeException(
        ResultadoCompat.politicaIndisponivel,
        'Sem resposta do servidor ao conferir a compatibilidade deste aparelho. '
        'Verifique a conexão e tente de novo.',
      );
    }
    final decisao = await _avaliar(plataforma, minima);
    debugPrint('🔒 Compatibilidade (servidor): $decisao');
    if (!decisao.liberado) {
      throw CompatibilidadeException(decisao.resultado, decisao.mensagem);
    }
    return decisao;
  }

  /// Servidor e, se falhar, a última política em cache. Nunca lança.
  Future<DecisaoCompat> avaliarComCache(PlataformaCompat plataforma) async {
    Object? minima;
    var obtida = false;
    try {
      minima = await _lerMinimaDoServidor(plataforma);
      obtida = true;
    } catch (e) {
      debugPrint('⚠️ Compatibilidade: servidor indisponível ($e); usando cache');
      final cache = await _lerCache(plataforma);
      if (cache.$1) {
        minima = cache.$2;
        obtida = true;
      }
    }
    if (!obtida) {
      const d = DecisaoCompat(
        ResultadoCompat.politicaIndisponivel,
        'Não foi possível conferir a compatibilidade deste aparelho '
        '(sem conexão e sem política salva). Conecte à internet.',
      );
      debugPrint('🔒 Compatibilidade (cache): $d');
      return d;
    }
    try {
      final d = await _avaliar(plataforma, minima);
      debugPrint('🔒 Compatibilidade (servidor/cache): $d');
      return d;
    } catch (e) {
      debugPrint('⚠️ Compatibilidade: falha ao avaliar ($e)');
      return const DecisaoCompat(
        ResultadoCompat.politicaIndisponivel,
        'Não foi possível conferir a compatibilidade deste aparelho.',
      );
    }
  }

  // ---------------------------------------------------------------------

  /// Lê o campo da plataforma no servidor e atualiza o cache.
  /// Documento ausente → valor null (a avaliação dá configuração inválida).
  Future<Object?> _lerMinimaDoServidor(PlataformaCompat plataforma) async {
    final snap = await _ref
        .get(const GetOptions(source: Source.server))
        .timeout(_timeoutServidor);
    // Sem `?[` dentro de ternário: o parser do Dart confunde com `? [`.
    final dados = snap.exists ? snap.data() : null;
    final Object? valor = dados == null ? null : dados[_campo(plataforma)];
    if (!snap.exists) {
      debugPrint('⚠️ Compatibilidade: sistema/app_config não existe');
    }
    await _salvarCache(plataforma, valor);
    return valor;
  }

  Future<void> _salvarCache(PlataformaCompat p, Object? valor) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chave = '$_prefsPrefixo${p.name}';
      // Guarda o valor bruto como texto; ausente/não-texto vira '' (inválido).
      await prefs.setString(chave, valor is String ? valor : '');
      await prefs.setString('${chave}_lido_em', DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('⚠️ Compatibilidade: falha ao salvar cache ($e)');
    }
  }

  /// (existe, valor). Valor '' = política inválida lida antes (falha fechada).
  Future<(bool, Object?)> _lerCache(PlataformaCompat p) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chave = '$_prefsPrefixo${p.name}';
      if (!prefs.containsKey(chave)) return (false, null);
      return (true, prefs.getString(chave));
    } catch (_) {
      return (false, null);
    }
  }

  Future<DecisaoCompat> _avaliar(PlataformaCompat plataforma, Object? minima) async {
    final info = await PackageInfo.fromPlatform();
    final buildInstalado = int.tryParse(info.buildNumber);
    int? buildPreparado;
    if (plataforma == PlataformaCompat.mobile) {
      buildPreparado = await _lerBuildPreparado();
    }
    return avaliarCompatibilidade(
      versaoInstalada: info.version,
      versaoMinima: minima,
      exigirPreparacao: plataforma == PlataformaCompat.mobile,
      buildInstalado: buildInstalado,
      buildPreparado: buildPreparado,
    );
  }

  /// `app_state.last_seeded_version_code`, gravado só quando a
  /// FirstSyncScreen conclui (A4).
  Future<int?> _lerBuildPreparado() async {
    try {
      final state = Hive.isBoxOpen('app_state')
          ? Hive.box('app_state')
          : await Hive.openBox('app_state');
      final v = state.get('last_seeded_version_code');
      return v is int ? v : null;
    } catch (e) {
      debugPrint('⚠️ Compatibilidade: falha ao ler a preparação ($e)');
      return null;
    }
  }
}
