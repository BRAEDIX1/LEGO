import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'lanc_local.g.dart';

@HiveType(typeId: 41)
enum LancStatus {
  @HiveField(0) pending,
  @HiveField(1) synced,
  @HiveField(2) error,
}

@HiveType(typeId: 43)
enum TipoRegistro {
  @HiveField(0) automatico,
  @HiveField(1) manual,
}

@HiveType(typeId: 42)
class LancLocal {
  @HiveField(0)  String idLocal;
  @HiveField(1)  String uid;
  @HiveField(2)  String codigo;
  @HiveField(3)  String descricao;
  @HiveField(4)  String unidade;
  @HiveField(5)  double quantidade;
  @HiveField(6)  String prateleira;
  @HiveField(7)  double cheio;
  @HiveField(8)  double vazio;
  @HiveField(9)  String? lote;
  @HiveField(10) String? tag;
  @HiveField(11) DateTime createdAtLocal;
  @HiveField(12) LancStatus status;
  @HiveField(13) String? errorCode;
  @HiveField(14) String? remoteId;
  @HiveField(15) TipoRegistro registro;
  @HiveField(16) double? volume;
  @HiveField(17) String? inventarioId;
  @HiveField(18) String? contagemId;
  @HiveField(19) String? nickname;
  @HiveField(20) String? nomeCompleto;

  // ⭐ NOVOS CAMPOS: Localização geográfica (planta)
  @HiveField(21) String? localizacaoId;    // ex: "ENCHIMENTO_OXIGENIO"
  @HiveField(22) String? localizacaoNome;  // ex: "Enchimento de Oxigênio"

  LancLocal({
    required this.idLocal,
    required this.uid,
    required this.codigo,
    required this.descricao,
    required this.unidade,
    required this.quantidade,
    required this.prateleira,
    required this.cheio,
    required this.vazio,
    this.lote,
    this.tag,
    required this.createdAtLocal,
    required this.status,
    this.errorCode,
    this.remoteId,
    this.registro = TipoRegistro.automatico,
    this.volume,
    this.inventarioId,
    this.contagemId,
    this.nickname,
    this.nomeCompleto,
    this.localizacaoId,    // ⭐ NOVO
    this.localizacaoNome,  // ⭐ NOVO
  });

  LancLocal copyWith({
    String? idLocal,
    String? uid,
    String? codigo,
    String? descricao,
    String? unidade,
    double? quantidade,
    String? prateleira,
    double? cheio,
    double? vazio,
    String? lote,
    String? tag,
    DateTime? createdAtLocal,
    LancStatus? status,
    String? errorCode,
    String? remoteId,
    TipoRegistro? registro,
    double? volume,
    String? inventarioId,
    String? contagemId,
    String? nickname,
    String? nomeCompleto,
    String? localizacaoId,    // ⭐ NOVO
    String? localizacaoNome,  // ⭐ NOVO
  }) {
    return LancLocal(
      idLocal:        idLocal        ?? this.idLocal,
      uid:            uid            ?? this.uid,
      codigo:         codigo         ?? this.codigo,
      descricao:      descricao      ?? this.descricao,
      unidade:        unidade        ?? this.unidade,
      quantidade:     quantidade     ?? this.quantidade,
      prateleira:     prateleira     ?? this.prateleira,
      cheio:          cheio          ?? this.cheio,
      vazio:          vazio          ?? this.vazio,
      lote:           lote           ?? this.lote,
      tag:            tag            ?? this.tag,
      createdAtLocal: createdAtLocal ?? this.createdAtLocal,
      status:         status         ?? this.status,
      errorCode:      errorCode      ?? this.errorCode,
      remoteId:       remoteId       ?? this.remoteId,
      registro:       registro       ?? this.registro,
      volume:         volume         ?? this.volume,
      inventarioId:   inventarioId   ?? this.inventarioId,
      contagemId:     contagemId     ?? this.contagemId,
      nickname:       nickname       ?? this.nickname,
      nomeCompleto:   nomeCompleto   ?? this.nomeCompleto,
      localizacaoId:   localizacaoId   ?? this.localizacaoId,    // ⭐ NOVO
      localizacaoNome: localizacaoNome ?? this.localizacaoNome,  // ⭐ NOVO
    );
  }
}

extension LancLocalToJson on LancLocal {
  Map<String, dynamic> toJson() {
    return {
      'uid':            uid,
      'nickname':       nickname,
      'nomeCompleto':   nomeCompleto,
      'codigo':         codigo,
      'descricao':      descricao,
      'quantidade':     quantidade,
      'cheio':          cheio,
      'vazio':          vazio,
      'unidade':        unidade,
      'prateleira':     prateleira,
      'tag':            tag,
      'lote':           lote,
      'registro':       registro == TipoRegistro.manual ? 'manual' : 'automatico',
      'volume':         volume,
      'createdAt':      Timestamp.fromDate(createdAtLocal),
      'inventarioId':   inventarioId,
      'contagemId':     contagemId,
      // ⭐ NOVOS: Localização geográfica
      'localizacaoId':   localizacaoId,
      'localizacaoNome': localizacaoNome,
    };
  }
}
