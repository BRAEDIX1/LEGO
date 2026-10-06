// lib/services/audit_event_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Tipos de evento gravados em `inventarios/{id}/eventos` (Plano §15).
/// Strings gravadas no Firestore: não renomear depois de publicado.
class TipoEvento {
  TipoEvento._();

  // Inventário
  static const String inventarioCriado = 'inventario_criado';
  static const String inventarioEncerrado = 'inventario_encerrado';
  static const String inventarioCancelado = 'inventario_cancelado';
  static const String travaOrfaLiberada = 'trava_orfa_liberada';

  // Participação e rodadas (Fases 3 a 5)
  static const String participanteEntrou = 'participante_entrou';
  static const String participanteFinalizou = 'participante_finalizou';
  static const String rodadaEncerrada = 'rodada_encerrada';

  // Reconciliação e C3 (Fases 6 a 9)
  static const String reconciliacaoIniciada = 'reconciliacao_iniciada';
  static const String reconciliacaoConcluida = 'reconciliacao_concluida';
  static const String c3Liberada = 'c3_liberada';
  static const String c3Distribuida = 'c3_distribuida';
  static const String c3Redistribuida = 'c3_redistribuida';
  static const String c3TarefaReservada = 'c3_tarefa_reservada';
  static const String c3TarefaConcluida = 'c3_tarefa_concluida';
  static const String c3Encerrada = 'c3_encerrada';
}

/// Grava eventos de auditoria SEMPRE no mesmo commit da mudança de estado
/// (transação ou batch de quem chama). Um evento nunca é gravado sozinho:
/// se a mudança falhar, o evento também não existe; se a mudança acontecer,
/// o evento existe.
///
/// Eventos são somente-inclusão: este serviço não tem método de alterar
/// nem de apagar.
class AuditEventService {
  AuditEventService._();

  static CollectionReference<Map<String, dynamic>> _colecao(String inventarioId) =>
      FirebaseFirestore.instance
          .collection('inventarios')
          .doc(inventarioId)
          .collection('eventos');

  static Map<String, dynamic> _montar({
    required String tipo,
    String? uid,
    String? rodada,
    Map<String, dynamic>? dados,
  }) {
    return {
      'tipo': tipo,
      'ts': FieldValue.serverTimestamp(),
      'uid': uid ?? FirebaseAuth.instance.currentUser?.uid,
      'rodada': rodada,
      'dados': dados ?? <String, dynamic>{},
    };
  }

  /// Registra o evento dentro de uma transação em andamento.
  /// Chamar DEPOIS de todas as leituras da transação (regra do Firestore:
  /// leituras antes de escritas).
  static void registrarNaTransacao(
    Transaction tx, {
    required String inventarioId,
    required String tipo,
    String? uid,
    String? rodada,
    Map<String, dynamic>? dados,
  }) {
    tx.set(
      _colecao(inventarioId).doc(),
      _montar(tipo: tipo, uid: uid, rodada: rodada, dados: dados),
    );
  }

  /// Registra o evento dentro de um WriteBatch.
  static void registrarNoBatch(
    WriteBatch batch, {
    required String inventarioId,
    required String tipo,
    String? uid,
    String? rodada,
    Map<String, dynamic>? dados,
  }) {
    batch.set(
      _colecao(inventarioId).doc(),
      _montar(tipo: tipo, uid: uid, rodada: rodada, dados: dados),
    );
  }

  /// Linha do tempo de um inventário (Fase 10), mais antigos primeiro.
  static Stream<List<Map<String, dynamic>>> streamEventos(String inventarioId) {
    return _colecao(inventarioId)
        .orderBy('ts')
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }
}
