// lib/services/monitor_service.dart
//
// Entrega 3 (teste acelerado): dados e ações do Monitor mínimo do analista.
// Regra de negócio aqui, não nos widgets: o Desktop definitivo poderá usar
// as mesmas operações.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/models/participante.dart';
import 'package:lego/services/acompanhamento_sync_service.dart';
import 'package:lego/services/comparativo_rodadas_service.dart';
import 'package:lego/services/sincronizacao/status_sync_aparelho.dart'
    show FirestoreCanalStatusSync;

/// Situação de um participante numa rodada (C1 ou C2), para o monitor.
class ParticipanteRodada {
  final String uid;
  final String nome;
  final String? status; // em_andamento | finalizado
  final int pendentesLocais;
  final DateTime? pendentesInformadosEm;
  final int sincronizados; // lançamentos da rodada no servidor
  const ParticipanteRodada({
    required this.uid,
    required this.nome,
    this.status,
    this.pendentesLocais = 0,
    this.pendentesInformadosEm,
    this.sincronizados = 0,
  });

  bool get finalizou =>
      status == StatusParticipante.finalizado ||
      status == StatusParticipante.finalizadaLegado;
}

/// A2: encerrar com lançamentos ainda no aparelho deixaria o comparativo
/// incompleto. Recusado, a não ser com confirmação explícita (forcar).
class PendentesLocaisException implements Exception {
  final List<String> quem;
  /// rev1: detalhe por participante (pendência conhecida, sem informe ou
  /// informe antigo), com a idade de cada informação.
  final List<PendenciaEncerramento> detalhes;
  PendentesLocaisException(this.quem, {this.detalhes = const []});
  @override
  String toString() =>
      'Há lançamentos ainda não sincronizados: ${quem.join(', ')}';
}

class MonitorService {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final ComparativoRodadasService _comparativo = ComparativoRodadasService();

  Stream<Inventario?> streamInventario(String id) => _fs
      .collection('inventarios')
      .doc(id)
      .snapshots()
      .map((s) => s.exists ? Inventario.fromFirestore(s) : null);

  Stream<List<Map<String, dynamic>>> streamParticipantes(String id) => _fs
      .collection('inventarios')
      .doc(id)
      .collection('participantes')
      .snapshots()
      .map((s) => s.docs.map((d) => {...d.data(), 'uid': d.id}).toList());

  /// Tempo real: lançamentos da rodada no servidor, por usuário. Escuta
  /// (custo: a carga inicial e depois 1 leitura por lançamento novo), em vez
  /// de reler tudo de tempos em tempos.
  Stream<Map<String, int>> streamSincronizadosPorUsuario(
          String inventarioId, String rodada) =>
      _fs
          .collection('lancamentos')
          .where('inventarioId', isEqualTo: inventarioId)
          .where('contagemId', isEqualTo: rodada)
          .snapshots()
          .map((s) {
        final out = <String, int>{};
        for (final d in s.docs) {
          final uid = (d.data()['uid'] ?? '?').toString();
          out[uid] = (out[uid] ?? 0) + 1;
        }
        return out;
      });

  /// Lançamentos de uma rodada já no servidor, por usuário (leitura única).
  Future<Map<String, int>> sincronizadosPorUsuario(
      String inventarioId, String rodada) async {
    final s = await _fs
        .collection('lancamentos')
        .where('inventarioId', isEqualTo: inventarioId)
        .where('contagemId', isEqualTo: rodada)
        .get(const GetOptions(source: Source.server));
    final out = <String, int>{};
    for (final d in s.docs) {
      final uid = (d.data()['uid'] ?? '?').toString();
      out[uid] = (out[uid] ?? 0) + 1;
    }
    return out;
  }

  /// Monta a visão de uma rodada a partir dos participantes e da contagem
  /// de lançamentos no servidor.
  List<ParticipanteRodada> participantesDaRodada(
    List<Map<String, dynamic>> participantes,
    String rodada,
    Map<String, int> sincronizados,
  ) {
    final sufixo = Rodadas.sufixo(rodada);
    final out = <ParticipanteRodada>[];
    for (final p in participantes) {
      final status = p['status_$sufixo'] as String?;
      if (p['rodada_base'] != rodada && status == null) continue;
      final ts = p['pendentes_informados_em'];
      out.add(ParticipanteRodada(
        uid: p['uid'] as String,
        nome: (p['displayName'] ?? p['email'] ?? p['uid']).toString(),
        status: status,
        pendentesLocais: (p['pendentes_locais'] as num?)?.toInt() ?? 0,
        pendentesInformadosEm: ts is Timestamp ? ts.toDate() : null,
        sincronizados: sincronizados[p['uid']] ?? 0,
      ));
    }
    out.sort((a, b) => a.nome.compareTo(b.nome));
    return out;
  }

  /// rev3: hora do servidor agora (ida e volta em `relogio_servidor/{uid}`).
  Future<DateTime> _horaServidor() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Analista não autenticado');
    try {
      return await FirestoreCanalStatusSync(_fs).horaServidor(uid);
    } catch (e) {
      throw StateError('Sem confirmação da hora do servidor para conferir as '
          'pendências dos aparelhos: $e');
    }
  }

  /// Encerramento global de C1/C2 com a checagem A2.
  /// Pacote 1: encerramento FORÇADO (com pendências nos aparelhos) exige
  /// [motivo] e fica na auditoria com quem tinha pendência e quantas. Nada é
  /// apagado dos aparelhos: o que não chegou será recusado pelas regras e
  /// irá para a Recuperação (fora do resultado).
  Future<void> encerrarRodada(String inventarioId, String rodada,
      {bool forcar = false, String? motivo, DateTime? agora}) async {
    final parts = (await _fs
            .collection('inventarios')
            .doc(inventarioId)
            .collection('participantes')
            .get(const GetOptions(source: Source.server)))
        .docs
        .map((d) => {...d.data(), 'uid': d.id})
        .toList();
    final daRodada = participantesDaRodada(parts, rodada, const {});
    final emAndamento = daRodada.where((p) => !p.finalizou).length;

    // rev1: também o que cada APARELHO informou (sync_status), com a idade
    // do informe. Pendência conhecida nunca é ignorada; informe ausente ou
    // antigo de quem está em andamento não vale como "sem pendência".
    final statusSnap = await _fs
        .collection('sync_status')
        .get(const GetOptions(source: Source.server));
    final status = {
      for (final d in statusSnap.docs)
        d.id: StatusSyncInformado.deMapa(d.id, d.data()),
    };
    final pendencias = avaliarPendenciasEncerramento(
      inventarioId: inventarioId,
      rodada: rodada,
      participantes: [
        for (final p in daRodada)
          (
            uid: p.uid,
            nome: p.nome,
            finalizou: p.finalizou,
            pendentesLocais: p.pendentesLocais,
            pendentesInformadosEm: p.pendentesInformadosEm,
          ),
      ],
      status: status,
      // rev3: idade medida no relógio do SERVIDOR (pulso do Desktop), não no
      // relógio deste computador.
      agora: agora ?? await _horaServidor(),
    );
    if (pendencias.isNotEmpty && !forcar) {
      throw PendentesLocaisException(
          pendencias.map((p) => p.texto).toList(),
          detalhes: pendencias);
    }
    final forcado = forcar && pendencias.isNotEmpty;
    if (forcado && (motivo == null || motivo.trim().length < 10)) {
      throw ArgumentError('Encerramento forçado exige o motivo.');
    }
    final conhecidas = pendencias
        .where((p) =>
            p.motivo == MotivoPendenciaEncerramento.pendenciaInformada)
        .length;
    await _comparativo.encerrarRodada(inventarioId, rodada,
        dadosParticipantes: {
          'em_andamento': emAndamento,
          'com_pendentes': conhecidas,
          'pendencias_desconhecidas': pendencias.length - conhecidas,
          'forcado': forcado,
          if (forcado) 'motivo': motivo!.trim(),
          if (forcado)
            'pendencias': [for (final p in pendencias) p.toMap()],
        });
  }
}
