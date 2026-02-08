// lib/models/participante.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class Participante extends Equatable {
  final String uid;
  final String displayName;
  final String? email;
  final String? deviceInfo;
  final String?contagemAtual;
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
  final String? status;  // Adicione esta linha
  final String? contagemSolicitada;  // Adicione esta linha

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
  });

  factory Participante.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> snapshot,
      SnapshotOptions? options,
      ) {
    final data = snapshot.data()!;
    return Participante(
      uid: data['uid'] as String,
      displayName: data['displayName'] as String,
      email: data['email'] as String?,
      deviceInfo: data['deviceInfo'] as String?,
      contagemAtual: data['contagem_atual'] as String?,
      statusC1: data['status_c1'] as String?,
      statusC2: data['status_c2'] as String?,
      statusC3: data['status_c3'] as String?,
      liberadoParaC2: data['liberado_para_c2'] as bool? ?? false,
      liberadoParaC3: data['liberado_para_c3'] as bool? ?? false,
      primeiroAcesso: (data['primeiro_acesso'] as Timestamp?)?.toDate(),
      ultimoAcesso: (data['ultimo_acesso'] as Timestamp?)?.toDate(),
      iniciouC1Em: (data['iniciou_c1_em'] as Timestamp?)?.toDate(),
      finalizouC1Em: (data['finalizou_c1_em'] as Timestamp?)?.toDate(),
      iniciouC2Em: (data['iniciou_c2_em'] as Timestamp?)?.toDate(),
      finalizouC2Em: (data['finalizou_c2_em'] as Timestamp?)?.toDate(),
      iniciouC3Em: (data['iniciou_c3_em'] as Timestamp?)?.toDate(),
      finalizouC3Em: (data['finalizou_c3_em'] as Timestamp?)?.toDate(),
      totalLancamentosC1: data['total_lancamentos_c1'] as int? ?? 0,
      totalLancamentosC2: data['total_lancamentos_c2'] as int? ?? 0,
      totalLancamentosC3: data['total_lancamentos_c3'] as int? ?? 0,
      status: data['status'] as String?,
      contagemSolicitada: data['contagem_solicitada'] as String?,
    );
  }

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
      'primeiro_acesso': primeiroAcesso != null ? Timestamp.fromDate(primeiroAcesso!) : null,
      'ultimo_acesso': ultimoAcesso != null ? Timestamp.fromDate(ultimoAcesso!) : null,
      'iniciou_c1_em': iniciouC1Em != null ? Timestamp.fromDate(iniciouC1Em!) : null,
      'finalizou_c1_em': finalizouC1Em != null ? Timestamp.fromDate(finalizouC1Em!) : null,
      'iniciou_c2_em': iniciouC2Em != null ? Timestamp.fromDate(iniciouC2Em!) : null,
      'finalizou_c2_em': finalizouC2Em != null ? Timestamp.fromDate(finalizouC2Em!) : null,
      'iniciou_c3_em': iniciouC3Em != null ? Timestamp.fromDate(iniciouC3Em!) : null,
      'finalizou_c3_em': finalizouC3Em != null ? Timestamp.fromDate(finalizouC3Em!) : null,
      'total_lancamentos_c1': totalLancamentosC1,
      'total_lancamentos_c2': totalLancamentosC2,
      'total_lancamentos_c3': totalLancamentosC3,
    };
  }

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
  ];
}