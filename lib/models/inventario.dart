// lib/models/inventario.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipos de contagem disponíveis
enum TipoContagem {
  simples,   // Uma contagem → resultado direto
  completa,  // C1 → C2 → C3 (se divergir)
}

/// Status possíveis do inventário
enum StatusInventario {
  rascunho,      // Criado mas sem estoque importado
  aguardando,    // Estoque importado, aguardando início
  emAndamento,   // Contagens em progresso
  finalizado,    // Concluído
  cancelado,     // Cancelado
}

/// Representa um inventário completo com suas contagens
class Inventario {
  final String id;
  final String codigo;
  final int numero;
  final DateTime dataInicio;
  final DateTime? dataFim;
  final String contagemAtiva; // 'contagem_1', 'contagem_2', 'contagem_3'
  final StatusInventario status;
  final String? versaoEstoque; // Referência da versão do estoque usada
  final Map<String, ContagemInfo> contagens; // Mapa de contagens

  // Novos campos
  final TipoContagem tipoContagem;
  final String? deposito;        // Código do depósito (ex: "A421", "I421")
  final String? tipoMaterial;    // "almoxarifado", "gases", "cilindros"
  final String? descricao;       // Descrição livre
  final int totalItensEstoque;   // Total de itens importados
  final double valorTotalEstoque; // Valor total do estoque importado
  final String? criadoPor;       // UID do criador

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
  });

  /// Cria um Inventario a partir de um documento Firestore
  factory Inventario.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Carrega as contagens se existirem
    final contagensMap = <String, ContagemInfo>{};
    if (data.containsKey('contagens')) {
      final contagensData = data['contagens'] as Map<String, dynamic>;
      contagensData.forEach((key, value) {
        contagensMap[key] = ContagemInfo.fromMap(value as Map<String, dynamic>);
      });
    }

    return Inventario(
      id: doc.id,
      codigo: data['codigo'] ?? '',
      numero: data['numero'] ?? 0,
      dataInicio: data['data_inicio'] != null
          ? (data['data_inicio'] as Timestamp).toDate()
          : DateTime.now(),
      dataFim: data['data_fim'] != null
          ? (data['data_fim'] as Timestamp).toDate()
          : null,
      contagemAtiva: data['contagem_ativa'] ?? 'contagem_1',
      status: _parseStatus(data['status']),
      versaoEstoque: data['versao_estoque'],
      contagens: contagensMap,
      tipoContagem: _parseTipoContagem(data['tipo_contagem']),
      deposito: data['deposito'],
      tipoMaterial: data['tipo_material'],
      descricao: data['descricao'],
      totalItensEstoque: data['total_itens_estoque'] ?? 0,
      valorTotalEstoque: (data['valor_total_estoque'] ?? 0.0).toDouble(),
      criadoPor: data['criado_por'],
    );
  }

  /// Converte o Inventario para Map para salvar no Firestore
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
    };
  }

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

  /// Retorna a próxima contagem na sequência
  String? proximaContagem() {
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

  /// Verifica se está na última contagem possível
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
        return 'Finalizado';
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

  /// Retorna label da contagem ativa
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
    );
  }
}

/// Informações sobre uma contagem específica
class ContagemInfo {
  final DateTime? iniciadaEm;
  final DateTime? finalizadaEm;
  final List<String> usuarios; // UIDs dos usuários que participaram
  final int totalLancamentos;
  final List<String>? itensMarcados; // Para C3: lista de códigos a recontar

  ContagemInfo({
    this.iniciadaEm,
    this.finalizadaEm,
    this.usuarios = const [],
    this.totalLancamentos = 0,
    this.itensMarcados,
  });

  /// Cria ContagemInfo a partir de um Map
  factory ContagemInfo.fromMap(Map<String, dynamic> map) {
    return ContagemInfo(
      iniciadaEm: map['iniciada_em'] != null
          ? (map['iniciada_em'] as Timestamp).toDate()
          : null,
      finalizadaEm: map['finalizada_em'] != null
          ? (map['finalizada_em'] as Timestamp).toDate()
          : null,
      usuarios: map['usuarios'] != null
          ? List<String>.from(map['usuarios'])
          : [],
      totalLancamentos: map['total_lancamentos'] ?? 0,
      itensMarcados: map['itens_marcados'] != null
          ? List<String>.from(map['itens_marcados'])
          : null,
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
    };
  }

  /// Verifica se a contagem está em andamento
  bool get emAndamento => iniciadaEm != null && finalizadaEm == null;

  /// Verifica se a contagem foi finalizada
  bool get finalizada => finalizadaEm != null;

  /// Duração da contagem (se finalizada)
  Duration? get duracao {
    if (iniciadaEm != null && finalizadaEm != null) {
      return finalizadaEm!.difference(iniciadaEm!);
    }
    return null;
  }
}

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