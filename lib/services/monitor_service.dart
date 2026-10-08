// lib/services/monitor_service.dart
//
// Entrega 3 (teste acelerado): dados e ações do Monitor mínimo do analista.
// Regra de negócio aqui, não nos widgets: o Desktop definitivo poderá usar
// as mesmas operações.

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/models/participante.dart';
import 'package:lego/services/comparativo_rodadas_service.dart';

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
  PendentesLocaisException(this.quem);
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

  /// Lançamentos de uma rodada já no servidor, por usuário.
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

  /// Encerramento global de C1/C2 com a checagem A2.
  Future<void> encerrarRodada(String inventarioId, String rodada,
      {bool forcar = false}) async {
    final parts = (await _fs
            .collection('inventarios')
            .doc(inventarioId)
            .collection('participantes')
            .get(const GetOptions(source: Source.server)))
        .docs
        .map((d) => {...d.data(), 'uid': d.id})
        .toList();
    final daRodada = participantesDaRodada(parts, rodada, const {});
    final comPendentes = daRodada.where((p) => p.pendentesLocais > 0).toList();
    final emAndamento = daRodada.where((p) => !p.finalizou).length;
    if (comPendentes.isNotEmpty && !forcar) {
      throw PendentesLocaisException(comPendentes
          .map((p) => '${p.nome} (${p.pendentesLocais})')
          .toList());
    }
    await _comparativo.encerrarRodada(inventarioId, rodada,
        dadosParticipantes: {
          'em_andamento': emAndamento,
          'com_pendentes': comPendentes.length,
          'forcado': forcar && comPendentes.isNotEmpty,
        });
  }
}
