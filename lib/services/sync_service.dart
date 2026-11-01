// lib/services/sync_service.dart
//
// Envio dos lançamentos pendentes do Hive para o Firestore.
// API estática mantida (runOnce, schedule, cancel, syncLancamentos).
//
// Pacote 1 (fila offline): o trabalho é do MotorSincronizacao
// (lib/services/sincronizacao/motor_sincronizacao.dart): falha de rede e
// passageira voltam sozinhas para a fila, recusa definitiva fica registrada
// com o motivo e vai para a Recuperação, reenvio manual por registro ou em
// lote. Depois de cada execução o aparelho informa o resumo ao Desktop
// (StatusSyncAparelho).

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:lego/data/local/lanc_local.dart';

import 'package:lego/services/sincronizacao/motor_sincronizacao.dart';
import 'package:lego/services/sincronizacao/status_sync_aparelho.dart';

class SyncService {
  SyncService._(); // evita instanciação

  // Timers por usuário (agendamentos periódicos)
  static final Map<String, Timer> _timers = <String, Timer>{};

  static MotorSincronizacao _motor(String uid) => MotorSincronizacao(uid: uid);

  /// Executa uma sincronização única imediatamente para o [uid].
  /// [ignorarEspera]: a conexão acabou de voltar — tenta já os que esperavam
  /// por rede.
  static Future<void> runOnce(String uid, {bool ignorarEspera = false}) async {
    try {
      await _syncLancamentos(uid, ignorarEspera: ignorarEspera);
    } catch (e, st) {
      debugPrint('[SYNC] runOnce falhou ($uid): $e\n$st');
    }
  }

  /// Agenda sincronizações periódicas para o [uid].
  /// Se já existir um timer, ele será substituído (reiniciado).
  static void schedule(String uid,
      {Duration interval = const Duration(seconds: 30)}) {
    cancel(uid);
    _timers[uid] = Timer.periodic(interval, (_) {
      // A trava do motor evita sobreposição (execução em curso = sai).
      unawaited(runOnce(uid));
    });
    debugPrint('[SYNC] schedule iniciado para $uid (cada ${interval.inSeconds}s)');
  }

  /// Cancela o agendamento periódico do [uid].
  static void cancel(String uid) {
    final t = _timers.remove(uid);
    t?.cancel();
    debugPrint('[SYNC] schedule cancelado para $uid');
  }

  /// Exposta para compatibilidade (chama o fluxo interno).
  static Future<void> syncLancamentos(String uid) => _syncLancamentos(uid);

  static Future<void> _syncLancamentos(String uid,
      {bool ignorarEspera = false}) async {
    final r = await _motor(uid).executarAutomatico(ignorarEspera: ignorarEspera);
    if (r == null) return; // outra execução em curso
    if (r.isNotEmpty) {
      debugPrint('[SYNC] ${r.where((x) => x.resultado.sucesso).length}/'
          '${r.length} enviado(s)');
    }
    unawaited(StatusSyncAparelho.publicar(uid));
  }

  /// Reenvio manual (painel do coletor): [ids] null = todas as pendências do
  /// usuário. Devolve o resultado de cada registro.
  static Future<List<ResultadoItem>> reenviar(String uid,
      [Iterable<String>? ids]) async {
    final r = await _motor(uid).reenviar(ids);
    unawaited(StatusSyncAparelho.publicar(uid, forcar: true));
    return r;
  }

  /// Recuperação administrativa (painel do coletor): garante a cópia dos
  /// recusados em definitivo em `lancamentos_recuperacao`. Não toca a
  /// coleção oficial.
  static Future<List<ResultadoItem>> recuperar(String uid,
      [Iterable<String>? ids]) async {
    final r = await _motor(uid).recuperar(ids);
    unawaited(StatusSyncAparelho.publicar(uid, forcar: true));
    return r;
  }

  /// Reenvio de tudo que não está sincronizado num inventário + rodada
  /// (usado ao finalizar a participação no Completo).
  static Future<List<ResultadoItem>> reenviarEscopo(
      String uid, String inventarioId, String contagemId) async {
    final motor = _motor(uid);
    final ids = [
      for (final l in await motor.repo.listarTodos())
        if (l.status != LancStatus.synced &&
            (l.inventarioId ?? '') == inventarioId &&
            (l.contagemId ?? '') == contagemId)
          l.idLocal,
    ];
    final r = await motor.reenviar(ids);
    unawaited(StatusSyncAparelho.publicar(uid, forcar: true));
    return r;
  }
}
