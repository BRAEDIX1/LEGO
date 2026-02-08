// lib/services/sync_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:lego/data/repositories/lancamentos_repository.dart';
import 'package:lego/data/local/lanc_local.dart';

/// Serviço de sincronização: envia lançamentos pendentes do Hive para o Firestore.
/// API estática para compatibilidade com chamadas existentes: SyncService.runOnce(uid) etc.
class SyncService {
  SyncService._(); // evita instanciação

  // Timers por usuário (agendamentos periódicos)
  static final Map<String, Timer> _timers = <String, Timer>{};

  // Guard de concorrência por usuário (evita duas execuções simultâneas)
  static final Set<String> _busy = <String>{};

  /// Executa uma sincronização única imediatamente para o [uid].
  static Future<void> runOnce(String uid) async {
    try {
      await _syncLancamentos(uid);
    } catch (e, st) {
      debugPrint('[SYNC] runOnce falhou ($uid): $e\n$st');
    }
  }

  /// Agenda sincronizações periódicas para o [uid].
  /// Se já existir um timer, ele será substituído (reiniciado).
  static void schedule(String uid, {Duration interval = const Duration(seconds: 30)}) {
    cancel(uid);
    _timers[uid] = Timer.periodic(interval, (_) {
      // Evita overlap
      if (_busy.contains(uid)) return;
      // Dispara sem bloquear o timer
      unawaited(_syncLancamentos(uid));
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

  /// Fluxo interno de sincronização: envia pendentes do Hive -> Firestore (/lancamentos).
  static Future<void> _syncLancamentos(String uid) async {
    if (_busy.contains(uid)) return;
    _busy.add(uid);
    try {
      final repo = LancamentosRepository(uid: uid);
      final pendentes = await repo.getPending();
      if (pendentes.isEmpty) {
        // Nada a fazer.
        return;
      }
      
      for (final LancLocal lanc in pendentes) {
        try {
          final col = FirebaseFirestore.instance.collection('lancamentos');
          final docId = '${uid}_${lanc.idLocal}';
          if (lanc.errorCode == 'DELETE_PENDING') {
            await col.doc(docId).delete();
            final repo = LancamentosRepository(uid: uid);
            await repo.hardDeleteLocal(lanc.idLocal);
            debugPrint('[SYNC] DELETE OK ${lanc.idLocal} -> $docId');
          } else {
            await col.doc(docId).set(lanc.toJson(), SetOptions(merge: true));
            final repo = LancamentosRepository(uid: uid);
            await repo.markSynced(lanc.idLocal, docId);
            debugPrint('[SYNC] UPSERT OK ${lanc.idLocal} -> $docId');
          }
        } catch (e, st) {
          debugPrint('[SYNC] Falha pendente ${lanc.idLocal}: $e');
          debugPrint('$st');
          final repo = LancamentosRepository(uid: uid);
          await repo.markError(lanc.idLocal, e.toString());
        }
      }

    } finally {
      _busy.remove(uid);
    }
  }
}
