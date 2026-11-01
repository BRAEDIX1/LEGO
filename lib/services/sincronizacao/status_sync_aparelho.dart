// lib/services/sincronizacao/status_sync_aparelho.dart
//
// Pacote 1 (fila offline): o coletor informa ao Desktop a situação das suas
// pendências de envio, em `sync_status/{uid}`. O Desktop mostra SÓ o que o
// aparelho transmitiu (com a hora do informe); o que está apenas no Hive de
// um aparelho offline não é visível até ele se conectar.
//
// rev3 (atualidade): antes de montar o informe o aparelho faz um "pulso" no
// servidor (`relogio_servidor/{uid}` com serverTimestamp, relido do
// servidor) e grava essa hora em `base_servidor`. O conteúdo é sempre
// produzido DEPOIS dessa hora. Sem pulso (offline), NÃO informa — um
// informe enfileirado offline não pode chegar depois parecendo recente.
// O Desktop mede a idade por `base_servidor` (relógio do servidor) e trata
// como atrasado o informe que chegou muito depois da base. O relógio do
// aparelho (`aparelho_em`) é só informativo.
//
// Antes (rev2): escrita sem esperar o servidor (offline, o Firestore guarda
// e envia ao reconectar). Informa na hora quando as contagens mudam (ou [forcar]); sem
// mudança, renova o informe a cada 5 min (rev1: o Desktop usa a IDADE do
// informe para não tomar informe velho como "sem pendências").

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:lego/data/local/registro_sync.dart';
import 'package:lego/data/repositories/lancamentos_repository.dart';
import 'package:lego/services/mobile_sync_service.dart';
import 'package:lego/services/sincronizacao/observador_pendencias.dart';
import 'package:lego/services/sincronizacao/pendencias_sync.dart';

class StatusSyncAparelho {
  StatusSyncAparelho._();

  /// Itens detalhados no informe (os mais antigos primeiro).
  static const int maxItens = 50;
  static const Duration intervaloRenovacao = Duration(minutes: 5);

  static final Map<String, (DateTime, String)> _ultimo = {};

  /// Monta o informe a partir do Hive (função testável).
  static Map<String, dynamic> montar({
    required String uid,
    required QuadroPendencias quadro,
    required DateTime agora,
    String? nome,
    DateTime? ultimoSucesso,
    EventoSync? ultimaFalha,
    DateTime? baseServidor,
  }) {
    final pendencias = quadro.lancamentos;
    return {
      'uid': uid,
      'nome': nome,
      // rev2: formato com escopos VERIFICADOS. Escopo listado com total 0 =
      // zero confirmado; escopo ausente = sem informação (o Desktop não
      // trata como zero).
      'formato': 2,
      'escopos_verificados': (quadro.escoposInformados.toList()..sort()),
      ...quadro.contagem.toMap(),
      'escopos': {
        for (final e in quadro.porEscopo.entries) e.key: e.value.toMap(),
      },
      'exclusoes_antigas': [
        for (final x in quadro.exclusoesLegadas)
          {
            'doc': x.docId,
            'situacao': x.situacao.name,
            'erro_codigo': x.estado?.codigo,
            'tentativas': x.estado?.tentativas ?? 0,
          },
      ],
      'itens': [
        for (final p in pendencias.take(maxItens))
          {
            'id_local': p.lanc.idLocal,
            'situacao': p.situacao.name,
            'escopo': p.escopo,
            'codigo': p.lanc.codigo,
            'descricao': p.lanc.descricao,
            'lote': p.lanc.lote,
            'area': p.lanc.localizacaoNome ?? p.lanc.localizacaoId,
            'quantidade': p.lanc.quantidade,
            'cheio': p.lanc.cheio,
            'vazio': p.lanc.vazio,
            'criado_em': Timestamp.fromDate(p.lanc.createdAtLocal),
            'tentativas': p.estado?.tentativas ?? 0,
            'erro_codigo': p.estado?.codigo,
            'erro_mensagem': p.estado?.mensagem,
            'recuperacao_enviada': p.estado?.recuperacaoEnviadaEm != null,
          },
      ],
      'itens_omitidos': pendencias.length > maxItens
          ? pendencias.length - maxItens
          : 0,
      'ultimo_sucesso':
          ultimoSucesso == null ? null : Timestamp.fromDate(ultimoSucesso),
      'ultima_falha': ultimaFalha == null
          ? null
          : {
              'codigo': ultimaFalha.codigo,
              'mensagem': ultimaFalha.mensagem,
              'resultado': ultimaFalha.resultado,
              'em': Timestamp.fromDate(ultimaFalha.em),
            },
      'aparelho_em': Timestamp.fromDate(agora),
      'base_servidor':
          baseServidor == null ? null : Timestamp.fromDate(baseServidor),
    };
  }

  /// Lê o Hive e grava o informe. Nunca lança erro.
  /// rev4: distingue entrega CONFIRMADA pelo servidor de escrita que excedeu
  /// o tempo e pode continuar na fila do SDK ([ResultadoPublicacao]). Só a
  /// confirmada conta como informe entregue (e segura a próxima renovação).
  static Future<ResultadoPublicacao> publicar(String uid,
      {bool forcar = false, CanalStatusSync? canal}) async {
    final c = canal ?? FirestoreCanalStatusSync();
    try {
      final repo = LancamentosRepository(uid: uid);
      final reg = RegistroSync(uid);
      // A sessão ativa do Completo conta como escopo verificado mesmo antes
      // do primeiro lançamento.
      final extras = <String>{};
      try {
        final sessao = MobileSyncService().sessaoAtual;
        if (sessao != null && sessao.isCompleta && sessao.pertenceA(uid)) {
          final (inv, rod) = sessao.idsGravacao;
          if (inv.isNotEmpty) extras.add('${inv}__$rod');
        }
      } catch (_) {}

      // Assinatura das contagens: mudou = informa já.
      final previa =
          await lerQuadroPendencias(uid, repo, reg, escoposExtras: extras);
      final assinatura = previa.porEscopo.entries
          .map((e) => '${e.key}:${e.value.toMap()}')
          .join('|');
      final agora = DateTime.now();
      final ant = _ultimo[uid];
      if (!forcar &&
          ant != null &&
          ant.$2 == assinatura &&
          agora.difference(ant.$1) < intervaloRenovacao) {
        return ResultadoPublicacao.semMudanca;
      }

      // Pulso: hora do SERVIDOR antes de produzir o conteúdo. Sem conexão,
      // não informa (nada fica enfileirado para chegar velho depois).
      final DateTime base;
      try {
        base = await c.horaServidor(uid);
      } catch (e) {
        debugPrint('[SYNC] informe adiado (sem confirmação do servidor): $e');
        return ResultadoPublicacao.semConexao;
      }

      // Conteúdo lido DEPOIS da base.
      final todos = await repo.listarTodos();
      final estados = await reg.todos();
      final quadro =
          await lerQuadroPendencias(uid, repo, reg, escoposExtras: extras);
      DateTime? ultimoSucesso;
      for (final e in estados.values) {
        final s = e.ultimoSucesso;
        if (s != null && (ultimoSucesso == null || s.isAfter(ultimoSucesso))) {
          ultimoSucesso = s;
        }
      }
      EventoSync? ultimaFalha;
      for (final ev in await reg.historico()) {
        if (ev.resultado != 'ok' && ev.resultado != 'reenfileirado') {
          ultimaFalha = ev;
          break; // histórico vem do mais recente
        }
      }
      String? nome;
      if (todos.isNotEmpty) {
        final l = (todos.toList()
              ..sort((a, b) => b.createdAtLocal.compareTo(a.createdAtLocal)))
            .first;
        nome = l.nomeCompleto ?? l.nickname;
      }
      final dados = montar(
        uid: uid,
        quadro: quadro,
        agora: DateTime.now(),
        nome: nome,
        ultimoSucesso: ultimoSucesso,
        ultimaFalha: ultimaFalha,
        baseServidor: base,
      );
      final entrega = await c.gravar(uid, dados);
      if (entrega == EntregaInforme.confirmada) {
        _ultimo[uid] = (agora, assinatura);
        return ResultadoPublicacao.confirmado;
      }
      // Sem resposta do servidor: NÃO registra entrega. A próxima execução
      // tenta de novo (com nova base); se esta chegar tarde, o Desktop vê o
      // atraso pela diferença entre `atualizado_em` e `base_servidor`.
      debugPrint('[SYNC] informe sem confirmação do servidor (pode estar na '
          'fila do SDK)');
      return ResultadoPublicacao.semConfirmacao;
    } catch (e) {
      debugPrint('[SYNC] informe de status falhou: $e');
      return ResultadoPublicacao.falhou;
    }
  }
}

enum ResultadoPublicacao {
  /// O servidor confirmou a gravação.
  confirmado,
  /// Gravação sem resposta no prazo: pode estar na fila do SDK. Não é
  /// entrega.
  semConfirmacao,
  /// Sem pulso no servidor: nada foi gravado.
  semConexao,
  /// Nada mudou e o último informe confirmado é recente.
  semMudanca,
  falhou,
}

enum EntregaInforme { confirmada, semConfirmacao }

/// Canal do informe (Firestore; um falso nos testes).
abstract class CanalStatusSync {
  /// Hora do servidor obtida AGORA por ida e volta (lança erro sem conexão).
  Future<DateTime> horaServidor(String uid);
  /// Grava o informe (o servidor carimba `atualizado_em`). Só devolve
  /// [EntregaInforme.confirmada] com resposta do servidor.
  Future<EntregaInforme> gravar(String uid, Map<String, dynamic> dados);
}

class FirestoreCanalStatusSync implements CanalStatusSync {
  static const Duration limite = Duration(seconds: 10);
  final FirebaseFirestore _fs;
  FirestoreCanalStatusSync([FirebaseFirestore? fs])
      : _fs = fs ?? FirebaseFirestore.instance;

  @override
  Future<DateTime> horaServidor(String uid) async {
    final ref = _fs.collection('relogio_servidor').doc(uid);
    await ref.set({'em': FieldValue.serverTimestamp()}).timeout(limite);
    final snap =
        await ref.get(const GetOptions(source: Source.server)).timeout(limite);
    final em = snap.data()?['em'];
    if (em is! Timestamp) throw StateError('relógio do servidor sem hora');
    return em.toDate();
  }

  @override
  Future<EntregaInforme> gravar(String uid, Map<String, dynamic> dados) async {
    try {
      // A Future do set só completa quando o SERVIDOR confirma.
      await _fs
          .collection('sync_status')
          .doc(uid)
          .set({...dados, 'atualizado_em': FieldValue.serverTimestamp()})
          .timeout(limite);
      return EntregaInforme.confirmada;
    } on TimeoutException {
      // Sem resposta: a escrita pode continuar na fila do SDK. Não é
      // confirmação de entrega.
      return EntregaInforme.semConfirmacao;
    }
  }
}
