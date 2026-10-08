// lib/models/participante.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import 'package:lego/models/inventario.dart' show Rodadas;

/// Status individual do participante em uma rodada (`status_cN`).
/// Fluxo 2 grava apenas [emAndamento] e [finalizado].
/// Os demais existem em documentos do fluxo 1.
class StatusParticipante {
  StatusParticipante._();
  static const String emAndamento = 'em_andamento';
  static const String finalizado = 'finalizado';

  // Legados (fluxo 1)
  static const String finalizadaLegado = 'finalizada';
  static const String bloqueada = 'bloqueada';
  static const String naoParticipou = 'nao_participou';
}

/// Quem finalizou a participação (`finalizado_por_cN`).
class FinalizadoPor {
  FinalizadoPor._();
  static const String usuario = 'usuario';   // "Finalizar minha contagem"
  static const String analista = 'analista'; // encerramento global da rodada
}

DateTime? _lerData(dynamic valor) {
  if (valor is Timestamp) return valor.toDate();
  if (valor is DateTime) return valor;
  return null;
}

int _lerInt(dynamic valor) => valor is num ? valor.toInt() : 0;

Timestamp? _gravarData(DateTime? valor) =>
    valor != null ? Timestamp.fromDate(valor) : null;

class Participante extends Equatable {
  final String uid;
  final String displayName;
  final String? email;
  final String? deviceInfo;
  final String? contagemAtual;
  final String? statusC1;
  final String? statusC2;
  final String? statusC3;
  final bool liberadoParaC2;
  final bool liberadoParaC3;
  final DateTime? primeiroAcesso;
  final DateTime? ultimoAcesso;
  final DateTime? iniciouC1Em;
  final DateTime? finalizouC1Em;
  final DateTime? iniciouC2Em;
  final DateTime? finalizouC2Em;
  final DateTime? iniciouC3Em;
  final DateTime? finalizouC3Em;
  final int totalLancamentosC1;
  final int totalLancamentosC2;
  final int totalLancamentosC3;
  final String? status;              // Fluxo 1: solicitacao_pendente | aprovado | rejeitado
  final String? contagemSolicitada;  // Fluxo 1

  // Fluxo 2
  final String? rodadaBase;          // 'contagem_1' | 'contagem_2' — imutável no inventário
  final String? finalizadoPorC1;     // ver FinalizadoPor
  final String? finalizadoPorC2;
  final String? finalizadoPorC3;
  final int pendentesLocais;         // lançamentos ainda no Hive do coletor
  final DateTime? pendentesInformadosEm;

  const Participante({
    required this.uid,
    required this.displayName,
    this.email,
    this.deviceInfo,
    this.contagemAtual,
    this.statusC1,
    this.statusC2,
    this.statusC3,
    this.liberadoParaC2 = false,
    this.liberadoParaC3 = false,
    this.primeiroAcesso,
    this.ultimoAcesso,
    this.iniciouC1Em,
    this.finalizouC1Em,
    this.iniciouC2Em,
    this.finalizouC2Em,
    this.iniciouC3Em,
    this.finalizouC3Em,
    this.totalLancamentosC1 = 0,
    this.totalLancamentosC2 = 0,
    this.totalLancamentosC3 = 0,
    this.status,
    this.contagemSolicitada,
    this.rodadaBase,
    this.finalizadoPorC1,
    this.finalizadoPorC2,
    this.finalizadoPorC3,
    this.pendentesLocais = 0,
    this.pendentesInformadosEm,
  });

  factory Participante.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> snapshot,
      SnapshotOptions? options,
      ) {
    final data = snapshot.data() ?? <String, dynamic>{};

    // Os campos iniciou_/finalizou_ foram gravados com dois nomes no fluxo 1
    // (B5): 'iniciou_c1_em' (correto) e 'iniciou_contagem_1_em' (bug).
    // Lê os dois para recuperar o histórico já gravado.
    DateTime? lerMarco(String prefixo, String sufixo, String rodadaId) =>
        _lerData(data['${prefixo}_${sufixo}_em'] ?? data['${prefixo}_${rodadaId}_em']);

    return Participante(
      uid: (data['uid'] as String?) ?? snapshot.id,
      displayName: (data['displayName'] as String?) ??
          (data['email'] as String?) ??
          'Sem nome',
      email: data['email'] as String?,
      deviceInfo: data['deviceInfo'] as String?,
      contagemAtual: data['contagem_atual'] as String?,
      statusC1: data['status_c1'] as String?,
      statusC2: data['status_c2'] as String?,
      statusC3: data['status_c3'] as String?,
      liberadoParaC2: data['liberado_para_c2'] as bool? ?? false,
      liberadoParaC3: data['liberado_para_c3'] as bool? ?? false,
      primeiroAcesso: _lerData(data['primeiro_acesso']),
      ultimoAcesso: _lerData(data['ultimo_acesso']),
      iniciouC1Em: lerMarco('iniciou', 'c1', Rodadas.c1),
      finalizouC1Em: lerMarco('finalizou', 'c1', Rodadas.c1),
      iniciouC2Em: lerMarco('iniciou', 'c2', Rodadas.c2),
      finalizouC2Em: lerMarco('finalizou', 'c2', Rodadas.c2),
      iniciouC3Em: lerMarco('iniciou', 'c3', Rodadas.c3),
      finalizouC3Em: lerMarco('finalizou', 'c3', Rodadas.c3),
      totalLancamentosC1: _lerInt(data['total_lancamentos_c1']),
      totalLancamentosC2: _lerInt(data['total_lancamentos_c2']),
      totalLancamentosC3: _lerInt(data['total_lancamentos_c3']),
      status: data['status'] as String?,
      contagemSolicitada: data['contagem_solicitada'] as String?,
      rodadaBase: data['rodada_base'] as String?,
      finalizadoPorC1: data['finalizado_por_c1'] as String?,
      finalizadoPorC2: data['finalizado_por_c2'] as String?,
      finalizadoPorC3: data['finalizado_por_c3'] as String?,
      pendentesLocais: _lerInt(data['pendentes_locais']),
      pendentesInformadosEm: _lerData(data['pendentes_informados_em']),
    );
  }

  /// ATENÇÃO: não usar com `set()` sem `SetOptions(merge: true)` em documento
  /// existente — campos não modelados seriam apagados.
  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'deviceInfo': deviceInfo,
      'contagem_atual': contagemAtual,
      'status_c1': statusC1,
      'status_c2': statusC2,
      'status_c3': statusC3,
      'liberado_para_c2': liberadoParaC2,
      'liberado_para_c3': liberadoParaC3,
      'primeiro_acesso': _gravarData(primeiroAcesso),
      'ultimo_acesso': _gravarData(ultimoAcesso),
      'iniciou_c1_em': _gravarData(iniciouC1Em),
      'finalizou_c1_em': _gravarData(finalizouC1Em),
      'iniciou_c2_em': _gravarData(iniciouC2Em),
      'finalizou_c2_em': _gravarData(finalizouC2Em),
      'iniciou_c3_em': _gravarData(iniciouC3Em),
      'finalizou_c3_em': _gravarData(finalizouC3Em),
      'total_lancamentos_c1': totalLancamentosC1,
      'total_lancamentos_c2': totalLancamentosC2,
      'total_lancamentos_c3': totalLancamentosC3,
      // B6: antes estes dois campos eram omitidos e se perdiam na escrita
      'status': status,
      'contagem_solicitada': contagemSolicitada,
      // Fluxo 2
      'rodada_base': rodadaBase,
      'finalizado_por_c1': finalizadoPorC1,
      'finalizado_por_c2': finalizadoPorC2,
      'finalizado_por_c3': finalizadoPorC3,
      'pendentes_locais': pendentesLocais,
      'pendentes_informados_em': _gravarData(pendentesInformadosEm),
    };
  }

  // ---------------- Regras de leitura (fluxo 2) ----------------

  /// Status individual na rodada ('contagem_1' | 'contagem_2' | 'contagem_3').
  String? statusDaRodada(String rodadaId) {
    switch (rodadaId) {
      case Rodadas.c1:
        return statusC1;
      case Rodadas.c2:
        return statusC2;
      case Rodadas.c3:
        return statusC3;
      default:
        return null;
    }
  }

  /// Quem finalizou a participação na rodada (usuario | analista).
  String? finalizadoPor(String rodadaId) {
    switch (rodadaId) {
      case Rodadas.c1:
        return finalizadoPorC1;
      case Rodadas.c2:
        return finalizadoPorC2;
      case Rodadas.c3:
        return finalizadoPorC3;
      default:
        return null;
    }
  }

  /// Finalizado na rodada (aceita a grafia legada 'finalizada').
  bool estaFinalizadoEm(String rodadaId) {
    final s = statusDaRodada(rodadaId);
    return s == StatusParticipante.finalizado ||
        s == StatusParticipante.finalizadaLegado;
  }

  /// Regra individual de lançamento: participação em andamento na rodada.
  /// O status GLOBAL da rodada (encerrada ou não) é checado à parte,
  /// pela sessão no MobileSyncService (Fase 3).
  bool podeLancarEm(String rodadaId) =>
      statusDaRodada(rodadaId) == StatusParticipante.emAndamento;

  Participante copyWith({
    String? uid,
    String? displayName,
    String? email,
    String? deviceInfo,
    String? contagemAtual,
    String? statusC1,
    String? statusC2,
    String? statusC3,
    bool? liberadoParaC2,
    bool? liberadoParaC3,
    DateTime? primeiroAcesso,
    DateTime? ultimoAcesso,
    DateTime? iniciouC1Em,
    DateTime? finalizouC1Em,
    DateTime? iniciouC2Em,
    DateTime? finalizouC2Em,
    DateTime? iniciouC3Em,
    DateTime? finalizouC3Em,
    int? totalLancamentosC1,
    int? totalLancamentosC2,
    int? totalLancamentosC3,
    String? status,
    String? contagemSolicitada,
    String? rodadaBase,
    String? finalizadoPorC1,
    String? finalizadoPorC2,
    String? finalizadoPorC3,
    int? pendentesLocais,
    DateTime? pendentesInformadosEm,
  }) {
    return Participante(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      contagemAtual: contagemAtual ?? this.contagemAtual,
      statusC1: statusC1 ?? this.statusC1,
      statusC2: statusC2 ?? this.statusC2,
      statusC3: statusC3 ?? this.statusC3,
      liberadoParaC2: liberadoParaC2 ?? this.liberadoParaC2,
      liberadoParaC3: liberadoParaC3 ?? this.liberadoParaC3,
      primeiroAcesso: primeiroAcesso ?? this.primeiroAcesso,
      ultimoAcesso: ultimoAcesso ?? this.ultimoAcesso,
      iniciouC1Em: iniciouC1Em ?? this.iniciouC1Em,
      finalizouC1Em: finalizouC1Em ?? this.finalizouC1Em,
      iniciouC2Em: iniciouC2Em ?? this.iniciouC2Em,
      finalizouC2Em: finalizouC2Em ?? this.finalizouC2Em,
      iniciouC3Em: iniciouC3Em ?? this.iniciouC3Em,
      finalizouC3Em: finalizouC3Em ?? this.finalizouC3Em,
      totalLancamentosC1: totalLancamentosC1 ?? this.totalLancamentosC1,
      totalLancamentosC2: totalLancamentosC2 ?? this.totalLancamentosC2,
      totalLancamentosC3: totalLancamentosC3 ?? this.totalLancamentosC3,
      status: status ?? this.status,
      contagemSolicitada: contagemSolicitada ?? this.contagemSolicitada,
      rodadaBase: rodadaBase ?? this.rodadaBase,
      finalizadoPorC1: finalizadoPorC1 ?? this.finalizadoPorC1,
      finalizadoPorC2: finalizadoPorC2 ?? this.finalizadoPorC2,
      finalizadoPorC3: finalizadoPorC3 ?? this.finalizadoPorC3,
      pendentesLocais: pendentesLocais ?? this.pendentesLocais,
      pendentesInformadosEm: pendentesInformadosEm ?? this.pendentesInformadosEm,
    );
  }

  @override
  List<Object?> get props => [
    uid,
    displayName,
    email,
    deviceInfo,
    contagemAtual,
    statusC1,
    statusC2,
    statusC3,
    liberadoParaC2,
    liberadoParaC3,
    primeiroAcesso,
    ultimoAcesso,
    iniciouC1Em,
    finalizouC1Em,
    iniciouC2Em,
    finalizouC2Em,
    iniciouC3Em,
    finalizouC3Em,
    totalLancamentosC1,
    totalLancamentosC2,
    totalLancamentosC3,
    status,
    contagemSolicitada,
    rodadaBase,
    finalizadoPorC1,
    finalizadoPorC2,
    finalizadoPorC3,
    pendentesLocais,
    pendentesInformadosEm,
  ];
}
