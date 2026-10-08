// lib/models/inventario.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipos de contagem disponíveis
enum TipoContagem {
  simples,   // Uma contagem → resultado direto
  completa,  // C1 + C2 (paralelas) → C3 só se divergir
}

/// Status possíveis do inventário
enum StatusInventario {
  rascunho,      // Criado mas sem estoque importado
  aguardando,    // Estoque importado, aguardando início
  emAndamento,   // Contagens em progresso
  finalizado,    // Concluído (no fluxo 2 = "Encerrado")
  cancelado,     // Cancelado
}

// =====================================================================
// CONSTANTES DO FLUXO 2 (máquina de estados da Contagem Completa)
// Strings gravadas no Firestore. Centralizadas aqui para evitar literais
// espalhados pelo código.
// =====================================================================

/// Versão do fluxo do inventário.
/// 1 = legado (sequência rígida C1 → C2 → C3, contagem_ativa).
/// 2 = máquina de estados (C1/C2 paralelas, reconciliação, C3 condicional).
/// Documento sem o campo `fluxo_versao` é lido como 1.
class FluxoVersao {
  FluxoVersao._();
  static const int legado = 1;
  static const int maquinaEstados = 2;
}

/// IDs das rodadas. São os MESMOS valores já gravados em
/// `lancamentos.contagemId` e nas chaves do mapa `contagens`.
/// C1/C2/C3 são apenas rótulos de tela.
class Rodadas {
  Rodadas._();
  static const String c1 = 'contagem_1';
  static const String c2 = 'contagem_2';
  static const String c3 = 'contagem_3';

  /// Rodadas que o usuário pode escolher ao entrar (rodada_base).
  static const List<String> base = [c1, c2];
  static const List<String> todas = [c1, c2, c3];

  static bool isValida(String? id) => id != null && todas.contains(id);
  static bool isBase(String? id) => id != null && base.contains(id);

  /// 'contagem_1' → 'c1' (sufixo usado nos campos do participante).
  static String sufixo(String id) => id.replaceAll('contagem_', 'c');

  /// 'contagem_1' → 'C1'
  static String rotulo(String id) {
    switch (id) {
      case c1:
        return 'C1';
      case c2:
        return 'C2';
      case c3:
        return 'C3';
      default:
        return id;
    }
  }
}

/// Status global de uma rodada (`contagens.contagem_N.status`).
/// C1/C2: disponivel → em_andamento → encerrada.
/// C3:    nao_necessaria | pendente → em_andamento → encerrada.
class StatusRodada {
  StatusRodada._();
  static const String disponivel = 'disponivel';
  static const String emAndamento = 'em_andamento';
  static const String encerrada = 'encerrada';
  static const String naoNecessaria = 'nao_necessaria'; // só C3
  static const String pendente = 'pendente';            // só C3
  /// Entrega 3 (teste): C3 chamada, esperando operadores confirmarem.
  static const String aguardandoParticipantes = 'aguardando_participantes'; // só C3
  /// B62: trava transitória enquanto as tarefas são gravadas.
  static const String distribuindo = 'distribuindo';     // só C3
  static const String redistribuindo = 'redistribuindo'; // só C3

  static String rotulo(String? status) {
    switch (status) {
      case disponivel:
        return 'Disponível';
      case emAndamento:
        return 'Em andamento';
      case encerrada:
        return 'Encerrada';
      case naoNecessaria:
        return 'Não necessária';
      case pendente:
        return 'Pendente';
      case aguardandoParticipantes:
        return 'Aguardando participantes';
      case distribuindo:
        return 'Distribuindo tarefas…';
      case redistribuindo:
        return 'Redistribuindo tarefas…';
      default:
        return '—';
    }
  }
}

/// Status da reconciliação C1 x C2 (`reconciliacao.status`).
class StatusReconciliacao {
  StatusReconciliacao._();
  static const String naoExecutada = 'nao_executada';
  static const String executando = 'executando';
  static const String concluida = 'concluida';
}

/// Converte valores de data vindos do Firestore de forma tolerante.
/// Aceita Timestamp, DateTime ou null (escrita pendente com serverTimestamp).
DateTime? _lerData(dynamic valor) {
  if (valor is Timestamp) return valor.toDate();
  if (valor is DateTime) return valor;
  return null;
}

int _lerInt(dynamic valor, [int padrao = 0]) {
  if (valor is num) return valor.toInt();
  return padrao;
}

// =====================================================================
// INVENTÁRIO
// =====================================================================

/// Representa um inventário completo com suas contagens
class Inventario {
  final String id;
  final String codigo;
  final int numero;
  final DateTime dataInicio;
  final DateTime? dataFim;
  final String contagemAtiva; // 'contagem_1', 'contagem_2', 'contagem_3' (só fluxo 1)
  final StatusInventario status;
  final String? versaoEstoque; // Referência da versão do estoque usada
  final Map<String, ContagemInfo> contagens; // Mapa de contagens

  // Campos do wizard desktop
  final TipoContagem tipoContagem;
  final String? deposito;        // Código do depósito (ex: "A421", "I421")
  final String? tipoMaterial;    // "almoxarifado", "gases", "cilindros"
  final String? descricao;       // Descrição livre
  final int totalItensEstoque;   // Total de itens importados
  final double valorTotalEstoque; // Valor total do estoque importado
  final String? criadoPor;       // UID do criador

  // Campos do fluxo 2 (todos opcionais: inventário antigo continua lendo)
  final int fluxoVersao;                  // 1 = legado, 2 = máquina de estados
  final ReconciliacaoInfo? reconciliacao; // marca de idempotência (§12.2)
  final String? origemCriacao;            // 'mobile' | 'desktop'
  final String? encerradoPor;             // UID de quem encerrou
  final String? canceladoPor;             // UID de quem cancelou
  final String? motivoCancelamento;

  Inventario({
    required this.id,
    required this.codigo,
    required this.numero,
    required this.dataInicio,
    this.dataFim,
    required this.contagemAtiva,
    required this.status,
    this.versaoEstoque,
    required this.contagens,
    this.tipoContagem = TipoContagem.completa,
    this.deposito,
    this.tipoMaterial,
    this.descricao,
    this.totalItensEstoque = 0,
    this.valorTotalEstoque = 0.0,
    this.criadoPor,
    this.fluxoVersao = FluxoVersao.legado,
    this.reconciliacao,
    this.origemCriacao,
    this.encerradoPor,
    this.canceladoPor,
    this.motivoCancelamento,
  });

  /// Cria um Inventario a partir de um documento Firestore
  factory Inventario.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};

    // Carrega as contagens se existirem
    final contagensMap = <String, ContagemInfo>{};
    final contagensData = data['contagens'];
    if (contagensData is Map) {
      contagensData.forEach((key, value) {
        if (value is Map) {
          contagensMap[key.toString()] =
              ContagemInfo.fromMap(Map<String, dynamic>.from(value));
        }
      });
    }

    final reconciliacaoData = data['reconciliacao'];

    return Inventario(
      id: doc.id,
      codigo: data['codigo'] ?? '',
      numero: _lerInt(data['numero']),
      dataInicio: _lerData(data['data_inicio']) ?? DateTime.now(),
      dataFim: _lerData(data['data_fim']),
      contagemAtiva: data['contagem_ativa'] ?? Rodadas.c1,
      status: _parseStatus(data['status']),
      versaoEstoque: data['versao_estoque'],
      contagens: contagensMap,
      tipoContagem: _parseTipoContagem(data['tipo_contagem']),
      deposito: data['deposito'],
      tipoMaterial: data['tipo_material'],
      descricao: data['descricao'],
      totalItensEstoque: _lerInt(data['total_itens_estoque']),
      valorTotalEstoque: (data['valor_total_estoque'] ?? 0.0).toDouble(),
      criadoPor: data['criado_por'],
      fluxoVersao: _lerInt(data['fluxo_versao'], FluxoVersao.legado),
      reconciliacao: reconciliacaoData is Map
          ? ReconciliacaoInfo.fromMap(Map<String, dynamic>.from(reconciliacaoData))
          : null,
      origemCriacao: data['origem_criacao'],
      encerradoPor: data['encerrado_por'],
      canceladoPor: data['cancelado_por'],
      motivoCancelamento: data['motivo_cancelamento'],
    );
  }

  /// Converte o Inventario para Map para salvar no Firestore.
  ///
  /// ATENÇÃO (fluxo 2): não usar com `set()` para ATUALIZAR um inventário
  /// existente — campos que o modelo não conhece seriam apagados. No fluxo 2
  /// toda alteração é feita com `update()` campo a campo, dentro de transação.
  Map<String, dynamic> toFirestore() {
    final contagensMap = <String, dynamic>{};
    contagens.forEach((key, value) {
      contagensMap[key] = value.toMap();
    });

    return {
      'codigo': codigo,
      'numero': numero,
      'data_inicio': Timestamp.fromDate(dataInicio),
      'data_fim': dataFim != null ? Timestamp.fromDate(dataFim!) : null,
      'contagem_ativa': contagemAtiva,
      'status': status.name,
      'versao_estoque': versaoEstoque,
      'contagens': contagensMap,
      'tipo_contagem': tipoContagem.name,
      'deposito': deposito,
      'tipo_material': tipoMaterial,
      'descricao': descricao,
      'total_itens_estoque': totalItensEstoque,
      'valor_total_estoque': valorTotalEstoque,
      'criado_por': criadoPor,
      'fluxo_versao': fluxoVersao,
      if (reconciliacao != null) 'reconciliacao': reconciliacao!.toMap(),
      if (origemCriacao != null) 'origem_criacao': origemCriacao,
      if (encerradoPor != null) 'encerrado_por': encerradoPor,
      if (canceladoPor != null) 'cancelado_por': canceladoPor,
      if (motivoCancelamento != null) 'motivo_cancelamento': motivoCancelamento,
    };
  }

  /// Valores de `status` que significam "ativo" no Firestore.
  /// Inclui a grafia antiga 'em_andamento' (B3).
  static const List<String> valoresStatusAtivo = [
    'emAndamento',
    'em_andamento',
    'aguardando',
  ];

  /// Parse do status vindo do Firestore
  static StatusInventario _parseStatus(String? value) {
    if (value == null) return StatusInventario.rascunho;

    // Compatibilidade com valores antigos
    switch (value) {
      case 'em_andamento':
        return StatusInventario.emAndamento;
      case 'finalizado':
        return StatusInventario.finalizado;
      case 'rascunho':
        return StatusInventario.rascunho;
      case 'aguardando':
        return StatusInventario.aguardando;
      case 'cancelado':
        return StatusInventario.cancelado;
      default:
      // Tenta parse direto do enum
        return StatusInventario.values.firstWhere(
              (e) => e.name == value,
          orElse: () => StatusInventario.rascunho,
        );
    }
  }

  /// Parse do tipo de contagem vindo do Firestore
  static TipoContagem _parseTipoContagem(String? value) {
    if (value == null) return TipoContagem.completa;
    return TipoContagem.values.firstWhere(
          (e) => e.name == value,
      orElse: () => TipoContagem.completa,
    );
  }

  /// Retorna a próxima contagem na sequência (SOMENTE fluxo 1).
  @Deprecated('Fluxo 1 apenas. No fluxo 2, C1/C2 são paralelas e a C3 nasce '
      'da reconciliação. Ver Plano v1.0 §2.')
  String? proximaContagem() {
    // Fluxo 2 não tem sequência rígida
    if (isFluxoMaquinaEstados) return null;

    // Em contagem simples, não há próxima
    if (tipoContagem == TipoContagem.simples) {
      return null;
    }

    switch (contagemAtiva) {
      case 'contagem_1':
        return 'contagem_2';
      case 'contagem_2':
        return 'contagem_3';
      case 'contagem_3':
        return null; // Não há próxima contagem
      default:
        return null;
    }
  }

  /// Verifica se o inventário está finalizado
  bool get isFinalizado => status == StatusInventario.finalizado;

  /// Verifica se está na última contagem possível (SOMENTE fluxo 1)
  @Deprecated('Fluxo 1 apenas. No fluxo 2 use statusRodada().')
  bool get isUltimaContagem {
    if (tipoContagem == TipoContagem.simples) {
      return contagemAtiva == 'contagem_1';
    }
    return contagemAtiva == 'contagem_3';
  }

  /// Verifica se é contagem simples
  bool get isSimples => tipoContagem == TipoContagem.simples;

  /// Verifica se é contagem completa
  bool get isCompleta => tipoContagem == TipoContagem.completa;

  /// Verifica se tem estoque importado
  bool get temEstoque => totalItensEstoque > 0;

  // ---------------- Fluxo 2 ----------------

  /// Inventário criado pela máquina de estados (Contagem Completa nova).
  bool get isFluxoMaquinaEstados => fluxoVersao >= FluxoVersao.maquinaEstados;

  /// Em andamento ou aguardando (ainda ocupa a vaga de "ativo").
  bool get isAtivo =>
      status == StatusInventario.emAndamento ||
      status == StatusInventario.aguardando;

  /// Número com 3 dígitos: 1 → "001".
  String get numeroFormatado => numero.toString().padLeft(3, '0');

  /// Status global de uma rodada. Null quando a rodada ainda não existe
  /// (ex.: C3 antes da reconciliação).
  String? statusRodada(String rodadaId) => contagens[rodadaId]?.statusEfetivo;

  bool rodadaEncerrada(String rodadaId) =>
      statusRodada(rodadaId) == StatusRodada.encerrada;

  /// 'contagem_1' → 'C1'
  String rotuloRodada(String rodadaId) => Rodadas.rotulo(rodadaId);

  /// Lista o que ainda impede o encerramento do inventário no fluxo 2
  /// (Plano §7 e §9.1). Lista vazia = apto a encerrar.
  List<String> pendenciasParaEncerrar() {
    final pendencias = <String>[];
    if (!isFluxoMaquinaEstados) {
      pendencias.add('Inventário do fluxo legado: use o encerramento antigo.');
      return pendencias;
    }
    if (status != StatusInventario.emAndamento) {
      pendencias.add('Inventário não está em andamento (${status.name}).');
    }
    for (final rodada in Rodadas.base) {
      if (!rodadaEncerrada(rodada)) {
        pendencias.add('${Rodadas.rotulo(rodada)} ainda não foi encerrada.');
      }
    }
    final rec = reconciliacao;
    if (rec == null || rec.status != StatusReconciliacao.concluida) {
      pendencias.add('Reconciliação C1 x C2 não concluída.');
    } else if (rec.emAnalise > 0) {
      pendencias.add('${rec.emAnalise} linha(s) ainda em análise.');
    }
    final c3 = statusRodada(Rodadas.c3);
    if (c3 != StatusRodada.naoNecessaria && c3 != StatusRodada.encerrada) {
      pendencias.add('C3 necessária e não encerrada.');
    }
    return pendencias;
  }

  bool get aptoAEncerrar => pendenciasParaEncerrar().isEmpty;

  /// Retorna label amigável do status
  String get statusLabel {
    switch (status) {
      case StatusInventario.rascunho:
        return 'Rascunho';
      case StatusInventario.aguardando:
        return 'Aguardando Início';
      case StatusInventario.emAndamento:
        return 'Em Andamento';
      case StatusInventario.finalizado:
        return isFluxoMaquinaEstados ? 'Encerrado' : 'Finalizado';
      case StatusInventario.cancelado:
        return 'Cancelado';
    }
  }

  /// Retorna label amigável do tipo de contagem
  String get tipoContagemLabel {
    switch (tipoContagem) {
      case TipoContagem.simples:
        return 'Simples (1 contagem)';
      case TipoContagem.completa:
        return 'Completa (até 3 contagens)';
    }
  }

  /// Retorna label da contagem ativa (fluxo 1)
  String get contagemAtivaLabel {
    switch (contagemAtiva) {
      case 'contagem_1':
        return isSimples ? 'Contagem Única' : 'Contagem 1';
      case 'contagem_2':
        return 'Contagem 2';
      case 'contagem_3':
        return 'Contagem 3';
      default:
        return contagemAtiva;
    }
  }

  /// Cria cópia com alterações
  Inventario copyWith({
    String? id,
    String? codigo,
    int? numero,
    DateTime? dataInicio,
    DateTime? dataFim,
    String? contagemAtiva,
    StatusInventario? status,
    String? versaoEstoque,
    Map<String, ContagemInfo>? contagens,
    TipoContagem? tipoContagem,
    String? deposito,
    String? tipoMaterial,
    String? descricao,
    int? totalItensEstoque,
    double? valorTotalEstoque,
    String? criadoPor,
    int? fluxoVersao,
    ReconciliacaoInfo? reconciliacao,
    String? origemCriacao,
    String? encerradoPor,
    String? canceladoPor,
    String? motivoCancelamento,
  }) {
    return Inventario(
      id: id ?? this.id,
      codigo: codigo ?? this.codigo,
      numero: numero ?? this.numero,
      dataInicio: dataInicio ?? this.dataInicio,
      dataFim: dataFim ?? this.dataFim,
      contagemAtiva: contagemAtiva ?? this.contagemAtiva,
      status: status ?? this.status,
      versaoEstoque: versaoEstoque ?? this.versaoEstoque,
      contagens: contagens ?? this.contagens,
      tipoContagem: tipoContagem ?? this.tipoContagem,
      deposito: deposito ?? this.deposito,
      tipoMaterial: tipoMaterial ?? this.tipoMaterial,
      descricao: descricao ?? this.descricao,
      totalItensEstoque: totalItensEstoque ?? this.totalItensEstoque,
      valorTotalEstoque: valorTotalEstoque ?? this.valorTotalEstoque,
      criadoPor: criadoPor ?? this.criadoPor,
      fluxoVersao: fluxoVersao ?? this.fluxoVersao,
      reconciliacao: reconciliacao ?? this.reconciliacao,
      origemCriacao: origemCriacao ?? this.origemCriacao,
      encerradoPor: encerradoPor ?? this.encerradoPor,
      canceladoPor: canceladoPor ?? this.canceladoPor,
      motivoCancelamento: motivoCancelamento ?? this.motivoCancelamento,
    );
  }
}

// =====================================================================
// CONTAGEM (RODADA)
// =====================================================================

/// Informações sobre uma contagem específica (rodada)
class ContagemInfo {
  final DateTime? iniciadaEm;
  final DateTime? finalizadaEm; // no fluxo 2 = momento do encerramento global
  final List<String> usuarios; // UIDs dos usuários que participaram
  final int totalLancamentos;
  final List<String>? itensMarcados; // Fluxo 1: lista de códigos a recontar

  // Fluxo 2
  final String? status;        // ver StatusRodada; null = documento legado
  final String? encerradaPor;  // UID do analista que encerrou
  final String? modo;          // C3: 'online' | 'offline'
  final int totalTarefas;      // C3: total de linhas a apurar
  final int tarefasConcluidas; // C3: linhas concluídas

  ContagemInfo({
    this.iniciadaEm,
    this.finalizadaEm,
    this.usuarios = const [],
    this.totalLancamentos = 0,
    this.itensMarcados,
    this.status,
    this.encerradaPor,
    this.modo,
    this.totalTarefas = 0,
    this.tarefasConcluidas = 0,
  });

  /// Cria ContagemInfo a partir de um Map
  factory ContagemInfo.fromMap(Map<String, dynamic> map) {
    return ContagemInfo(
      iniciadaEm: _lerData(map['iniciada_em']),
      finalizadaEm: _lerData(map['finalizada_em']),
      usuarios: map['usuarios'] is List
          ? List<String>.from(map['usuarios'])
          : [],
      totalLancamentos: _lerInt(map['total_lancamentos']),
      itensMarcados: map['itens_marcados'] is List
          ? List<String>.from(map['itens_marcados'])
          : null,
      status: map['status'] as String?,
      encerradaPor: map['encerrada_por'] as String?,
      modo: map['modo'] as String?,
      totalTarefas: _lerInt(map['total_tarefas']),
      tarefasConcluidas: _lerInt(map['tarefas_concluidas']),
    );
  }

  /// Converte ContagemInfo para Map
  Map<String, dynamic> toMap() {
    return {
      'iniciada_em': iniciadaEm != null
          ? Timestamp.fromDate(iniciadaEm!)
          : null,
      'finalizada_em': finalizadaEm != null
          ? Timestamp.fromDate(finalizadaEm!)
          : null,
      'usuarios': usuarios,
      'total_lancamentos': totalLancamentos,
      'itens_marcados': itensMarcados,
      if (status != null) 'status': status,
      if (encerradaPor != null) 'encerrada_por': encerradaPor,
      if (modo != null) 'modo': modo,
      if (totalTarefas > 0) 'total_tarefas': totalTarefas,
      if (tarefasConcluidas > 0) 'tarefas_concluidas': tarefasConcluidas,
    };
  }

  /// Status efetivo: o campo `status` quando existe (fluxo 2); senão deduz
  /// pelos timestamps (documentos legados).
  String get statusEfetivo {
    if (status != null) return status!;
    if (finalizadaEm != null) return StatusRodada.encerrada;
    if (iniciadaEm != null) return StatusRodada.emAndamento;
    return StatusRodada.disponivel;
  }

  /// Verifica se a contagem está em andamento
  bool get emAndamento => statusEfetivo == StatusRodada.emAndamento;

  /// Verifica se a contagem foi finalizada / encerrada
  bool get finalizada => statusEfetivo == StatusRodada.encerrada;

  /// Sinônimo de [finalizadaEm] no vocabulário do fluxo 2.
  DateTime? get encerradaEm => finalizadaEm;

  /// Duração da contagem (se finalizada)
  Duration? get duracao {
    if (iniciadaEm != null && finalizadaEm != null) {
      return finalizadaEm!.difference(iniciadaEm!);
    }
    return null;
  }
}

// =====================================================================
// RECONCILIAÇÃO (marca de idempotência no documento do inventário)
// =====================================================================

class ReconciliacaoInfo {
  final String status; // ver StatusReconciliacao
  final String? executorUid;
  final DateTime? iniciadaEm;
  final DateTime? concluidaEm;
  final int totalLinhas;
  final int encerradas;
  final int emAnalise;

  const ReconciliacaoInfo({
    this.status = StatusReconciliacao.naoExecutada,
    this.executorUid,
    this.iniciadaEm,
    this.concluidaEm,
    this.totalLinhas = 0,
    this.encerradas = 0,
    this.emAnalise = 0,
  });

  factory ReconciliacaoInfo.fromMap(Map<String, dynamic> map) {
    return ReconciliacaoInfo(
      status: map['status'] as String? ?? StatusReconciliacao.naoExecutada,
      executorUid: map['executor_uid'] as String?,
      iniciadaEm: _lerData(map['iniciada_em']),
      concluidaEm: _lerData(map['concluida_em']),
      totalLinhas: _lerInt(map['total_linhas']),
      encerradas: _lerInt(map['encerradas']),
      emAnalise: _lerInt(map['em_analise']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status,
      'executor_uid': executorUid,
      'iniciada_em': iniciadaEm != null ? Timestamp.fromDate(iniciadaEm!) : null,
      'concluida_em': concluidaEm != null ? Timestamp.fromDate(concluidaEm!) : null,
      'total_linhas': totalLinhas,
      'encerradas': encerradas,
      'em_analise': emAnalise,
    };
  }

  bool get concluida => status == StatusReconciliacao.concluida;
}

// =====================================================================
// TIPOS DE MATERIAL
// =====================================================================

/// Tipos de material predefinidos
class TiposMaterial {
  static const String almoxarifado = 'almoxarifado';
  static const String gases = 'gases';
  static const String cilindros = 'cilindros';
  static const String equipamentos = 'equipamentos';
  static const String outro = 'outro';

  static const List<String> todos = [
    almoxarifado,
    gases,
    cilindros,
    equipamentos,
    outro,
  ];

  static String label(String tipo) {
    switch (tipo) {
      case almoxarifado:
        return 'Almoxarifado';
      case gases:
        return 'Gases Industriais';
      case cilindros:
        return 'Cilindros';
      case equipamentos:
        return 'Equipamentos';
      case outro:
        return 'Outro';
      default:
        return tipo;
    }
  }

  /// Sugere tipo de contagem baseado no tipo de material
  static TipoContagem tipoContagemSugerido(String tipo) {
    switch (tipo) {
      case cilindros:
        return TipoContagem.simples; // Cilindros = contagem frequente, simples
      default:
        return TipoContagem.completa; // Almoxarifado/gases = maior rigor
    }
  }
}
