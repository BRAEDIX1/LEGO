// lib/models/sessao_contagem.dart
import 'dart:convert';

import 'package:lego/models/inventario.dart' show Rodadas, StatusRodada;
import 'package:lego/models/participante.dart' show StatusParticipante;

/// Tipo de contagem escolhido após o login (fluxo 2).
enum TipoSessao {
  simples,  // sem inventário numerado; grava com IDs vazios (D1)
  completa, // vinculada a um Inventário Completo e a uma rodada
}

/// Marca de exclusão pendente usada nos tombstones (B21).
const String kDeletePending = 'DELETE_PENDING';

/// Sessão de contagem do coletor (Plano Lote 3A, T17).
///
/// É a ÚNICA fonte de inventário, rodada e permissão de gravação no fluxo 2.
/// Persistida no aparelho para restaurar offline, mas só vale para o usuário
/// que a criou (B16).
class SessaoContagem {
  static const int schemaAtual = 1;

  final int schemaVersao;
  final String usuarioUid;
  final TipoSessao tipo;

  // Somente Completa
  final String? inventarioId;
  final int? numero;
  final String? codigo;
  final String? rodada;           // 'contagem_1' | 'contagem_2'
  final String? statusRodada;     // ver StatusRodada
  final String? statusIndividual; // ver StatusParticipante
  final bool inventarioAtivo;
  /// L4: tipo do inventário ('material' | 'cilindro' | 'gas'); null = antigo
  /// ou Simples. Define que produtos podem ser lançados.
  final String? natureza;

  final DateTime atualizadoEm;

  const SessaoContagem._({
    required this.schemaVersao,
    required this.usuarioUid,
    required this.tipo,
    this.inventarioId,
    this.numero,
    this.codigo,
    this.rodada,
    this.statusRodada,
    this.statusIndividual,
    this.inventarioAtivo = false,
    this.natureza,
    required this.atualizadoEm,
  });

  factory SessaoContagem.simples(String usuarioUid) => SessaoContagem._(
        schemaVersao: schemaAtual,
        usuarioUid: usuarioUid,
        tipo: TipoSessao.simples,
        atualizadoEm: DateTime.now(),
      );

  factory SessaoContagem.completa({
    required String usuarioUid,
    required String inventarioId,
    required int numero,
    required String codigo,
    required String rodada,
    required String? statusRodada,
    required String? statusIndividual,
    bool inventarioAtivo = true,
    String? natureza,
  }) =>
      SessaoContagem._(
        schemaVersao: schemaAtual,
        usuarioUid: usuarioUid,
        tipo: TipoSessao.completa,
        inventarioId: inventarioId,
        numero: numero,
        codigo: codigo,
        rodada: rodada,
        statusRodada: statusRodada,
        statusIndividual: statusIndividual,
        inventarioAtivo: inventarioAtivo,
        natureza: natureza,
        atualizadoEm: DateTime.now(),
      );

  /// L4: o produto (coleção `materiais` ou `gases`) cabe neste inventário?
  /// Inventário de Materiais só aceita `materiais`; de Cilindros ou Gases,
  /// só `gases`. Simples ou inventário sem tipo: aceita tudo.
  bool aceitaOrigem(String? origem) => origemPermitida(natureza, origem);

  static bool origemPermitida(String? natureza, String? origem) {
    switch (natureza) {
      case 'material':
        return origem == 'materiais';
      case 'cilindro':
      case 'gas':
        return origem == 'gases';
      default:
        return true;
    }
  }

  /// Rótulo do tipo para mensagens.
  static String rotuloNatureza(String? natureza) => switch (natureza) {
        'material' => 'Materiais',
        'cilindro' => 'Cilindros',
        'gas' => 'Gases',
        _ => '—',
      };

  bool get isSimples => tipo == TipoSessao.simples;
  bool get isCompleta => tipo == TipoSessao.completa;

  /// B16: a sessão só vale para o usuário que a criou.
  bool pertenceA(String? uid) => uid != null && uid.isNotEmpty && uid == usuarioUid;

  /// T18: regra de gravação.
  /// Simples: sempre pode. Completa: participação em andamento, rodada não
  /// encerrada e inventário ativo.
  bool get podeLancar {
    if (isSimples) return true;
    return inventarioAtivo &&
        (inventarioId?.isNotEmpty ?? false) &&
        Rodadas.isValida(rodada) &&
        statusIndividual == StatusParticipante.emAndamento &&
        statusRodada != StatusRodada.encerrada;
  }

  /// Texto para o operador quando [podeLancar] é falso.
  String? get motivoBloqueio {
    if (podeLancar) return null;
    if (!inventarioAtivo) return 'O inventário não está mais ativo.';
    if (statusRodada == StatusRodada.encerrada) {
      return 'A ${Rodadas.rotulo(rodada ?? '')} foi encerrada pelo analista.';
    }
    if (statusIndividual == StatusParticipante.finalizado ||
        statusIndividual == StatusParticipante.finalizadaLegado) {
      return 'Sua participação na ${Rodadas.rotulo(rodada ?? '')} já foi finalizada.';
    }
    return 'Sessão de contagem inválida. Escolha o tipo de contagem novamente.';
  }

  /// T18: IDs gravados no lançamento. Nunca vêm de padrão nem da tela.
  (String, String) get idsGravacao =>
      isSimples ? ('', '') : (inventarioId ?? '', rodada ?? '');

  String get numeroFormatado => (numero ?? 0).toString().padLeft(3, '0');

  /// Cabeçalho fixo do coletor (§10): "Inventário 001 | C1 | Em andamento".
  String get rotuloCabecalho {
    if (isSimples) return 'Contagem Simples';
    final r = Rodadas.rotulo(rodada ?? '');
    // B72: o tipo aparece no cabeçalho ("Inventário 002 | Gases | C1 | …").
    final tipo = natureza != null ? ' | ${rotuloNatureza(natureza)}' : '';
    return 'Inventário $numeroFormatado$tipo | $r | $rotuloStatus';
  }

  String get rotuloStatus {
    if (isSimples) return 'Em andamento';
    if (!inventarioAtivo) return 'Inventário fechado';
    if (statusRodada == StatusRodada.encerrada) return 'Rodada encerrada';
    switch (statusIndividual) {
      case StatusParticipante.emAndamento:
        return 'Em andamento';
      case StatusParticipante.finalizado:
      case StatusParticipante.finalizadaLegado:
        return 'Finalizado';
      default:
        return '—';
    }
  }

  /// B23: um lançamento pertence ao escopo operacional desta sessão?
  /// Regra única e pura (testável sem Hive). Tombstones nunca aparecem.
  static bool escopoContem({
    required String? lancInventarioId,
    required String? lancContagemId,
    required String? lancErrorCode,
    required String inventarioId,
    required String contagemId,
  }) {
    if (lancErrorCode == kDeletePending) return false;
    return (lancInventarioId ?? '') == inventarioId &&
        (lancContagemId ?? '') == contagemId;
  }

  SessaoContagem copyWith({
    String? statusRodada,
    String? statusIndividual,
    bool? inventarioAtivo,
    int? numero,
    String? codigo,
  }) {
    return SessaoContagem._(
      schemaVersao: schemaVersao,
      usuarioUid: usuarioUid,
      tipo: tipo,
      inventarioId: inventarioId,
      numero: numero ?? this.numero,
      codigo: codigo ?? this.codigo,
      rodada: rodada,
      statusRodada: statusRodada ?? this.statusRodada,
      statusIndividual: statusIndividual ?? this.statusIndividual,
      inventarioAtivo: inventarioAtivo ?? this.inventarioAtivo,
      natureza: natureza,
      atualizadoEm: DateTime.now(),
    );
  }

  // ---------------- Persistência local ----------------

  Map<String, dynamic> toMap() => {
        'schema_versao': schemaVersao,
        'usuario_uid': usuarioUid,
        'tipo': tipo.name,
        'inventario_id': inventarioId,
        'numero': numero,
        'codigo': codigo,
        'rodada': rodada,
        'status_rodada': statusRodada,
        'status_individual': statusIndividual,
        'inventario_ativo': inventarioAtivo,
        if (natureza != null) 'natureza': natureza,
        'atualizado_em': atualizadoEm.toIso8601String(),
      };

  String toJson() => jsonEncode(toMap());

  /// Devolve null para dado ausente, corrompido ou de schema desconhecido.
  static SessaoContagem? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    if (m['schema_versao'] != schemaAtual) return null;
    final uid = m['usuario_uid'];
    if (uid is! String || uid.isEmpty) return null;

    final tipo = TipoSessao.values
        .where((t) => t.name == m['tipo'])
        .firstOrNull;
    if (tipo == null) return null;

    if (tipo == TipoSessao.simples) {
      return SessaoContagem._(
        schemaVersao: schemaAtual,
        usuarioUid: uid,
        tipo: tipo,
        atualizadoEm: DateTime.tryParse('${m['atualizado_em']}') ?? DateTime.now(),
      );
    }

    final inv = m['inventario_id'];
    final rodada = m['rodada'] is String ? m['rodada'] as String : null;
    if (inv is! String || inv.isEmpty || !Rodadas.isValida(rodada)) {
      return null;
    }
    return SessaoContagem._(
      schemaVersao: schemaAtual,
      usuarioUid: uid,
      tipo: tipo,
      inventarioId: inv,
      numero: (m['numero'] as num?)?.toInt(),
      codigo: m['codigo'] as String?,
      rodada: rodada,
      statusRodada: m['status_rodada'] as String?,
      statusIndividual: m['status_individual'] as String?,
      inventarioAtivo: m['inventario_ativo'] == true,
      natureza: m['natureza'] as String?,
      atualizadoEm: DateTime.tryParse('${m['atualizado_em']}') ?? DateTime.now(),
    );
  }

  static SessaoContagem? fromJson(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      return decoded is Map<String, dynamic> ? fromMap(decoded) : null;
    } catch (_) {
      return null;
    }
  }
}
