/// Enum representando o status do produto após consolidação

enum StatusProduto {
  ok,              // C1 = C2 = Sistema (ou próximo)
  sobra,           // Contado > Sistema
  falta,           // Contado < Sistema
  naoEncontrado,   // C1 = 0 E C2 = 0 (crítico)
  aguardandoC3,    // C1 ≠ C2 E sem C3 ainda
}
/// Extension para obter cor/ícone do status

extension StatusProdutoUI on StatusProduto {
  String get label {
    switch (this) {
      case StatusProduto.ok:
        return 'OK';
      case StatusProduto.sobra:
        return 'Sobra';
      case StatusProduto.falta:
        return 'Falta';
      case StatusProduto.naoEncontrado:
        return 'Não Encontrado';
      case StatusProduto.aguardandoC3:
        return 'Aguardando C3';
    }
  }

  String get emoji {
    switch (this) {
      case StatusProduto.ok:
        return '✅';
      case StatusProduto.sobra:
        return '📈';
      case StatusProduto.falta:
        return '📉';
      case StatusProduto.naoEncontrado:
        return '⚠️';
      case StatusProduto.aguardandoC3:
        return '⏳';
    }
  }
}
// lib/models/produto_consolidado.dart

/// Representa um produto após JOIN e consolidação de todas as fontes
/// Este é o MODEL MAIS IMPORTANTE do sistema desktop
class ProdutoConsolidado {
  // ========== DADOS CADASTRAIS (de materiais/) ==========
  final String codigo;
  final String descricao;
  final String unidade;

  // ========== DADOS ESTOQUE (de estoque/) ==========
  final double quantidadeSistema; // Saldo contábil esperado
  final double valorUnitario;
  final String? deposito;

  // ========== DADOS CONTAGENS (de lancamentos/ consolidados) ==========
  /// Map<localização, quantidade> para cada contagem
  /// Ex: {'mesa': 3.0, 'fruteira': 2.0, 'micro': 4.0}
  final Map<String, double>? contagem1PorLocal;
  final Map<String, double>? contagem2PorLocal;
  final Map<String, double>? contagem3PorLocal;

  ProdutoConsolidado({
    required this.codigo,
    required this.descricao,
    required this.unidade,
    required this.quantidadeSistema,
    required this.valorUnitario,
    this.deposito,
    this.contagem1PorLocal,
    this.contagem2PorLocal,
    this.contagem3PorLocal,
  });

  // ========== GETTERS CALCULADOS - APLICAM REGRAS DE NEGÓCIO ==========

  /// Total da Contagem 1 (soma de todas as localizações)
  double get totalContagem1 => _somarLocais(contagem1PorLocal);

  /// Total da Contagem 2 (soma de todas as localizações)
  double get totalContagem2 => _somarLocais(contagem2PorLocal);

  /// Total da Contagem 3 (soma de todas as localizações)
  double get totalContagem3 => _somarLocais(contagem3PorLocal);

  /// ⭐ REGRA DE OURO: Quantidade Contada Final
  /// Esta é a LÓGICA CENTRAL do sistema
  double? get quantidadeContada {
    // CENÁRIO 1: C1 = C2 → valor confirmado
    if (contagem1PorLocal != null && contagem2PorLocal != null) {
      if (totalContagem1 == totalContagem2) {
        return totalContagem1;
      }
    }

    // CENÁRIO 2: C1 ≠ C2 mas existe C3 → C3 é definitivo
    if (contagem1PorLocal != null &&
        contagem2PorLocal != null &&
        contagem3PorLocal != null) {
      if (totalContagem1 != totalContagem2) {
        return totalContagem3;
      }
    }

    // CENÁRIO 3: C1 = 0 E C2 = 0 → item não encontrado
    if (contagem1PorLocal != null && contagem2PorLocal != null) {
      if (totalContagem1 == 0.0 && totalContagem2 == 0.0) {
        return 0.0;
      }
    }

    // CENÁRIO 4: C1 ≠ C2 E NÃO existe C3 → aguardando (null)
    return null;
  }

  /// Variação = Contado - Sistema
  /// Retorna null se ainda não há valor contado confirmado
  double? get variacao {
    final contado = quantidadeContada;
    if (contado == null) return null;
    return contado - quantidadeSistema;
  }

  /// Impacto Financeiro com cálculo de imposto para faltas
  double? get impactoFinanceiro {
    final var_ = variacao;
    if (var_ == null) return null;

    if (var_ > 0) {
      // SOBRA: sem imposto
      return var_ * valorUnitario;
    } else if (var_ < 0) {
      // FALTA: com imposto 21.95%
      final subtotal = var_.abs() * valorUnitario;
      final imposto = subtotal * 0.2195;
      return -(subtotal + imposto);
    }

    return 0.0; // Sem variação
  }

  /// Status do produto baseado na consolidação
  StatusProduto get status {
    final contado = quantidadeContada;

    // Aguardando C3
    if (contado == null) {
      return StatusProduto.aguardandoC3;
    }

    // Não encontrado (crítico)
    if (contado == 0.0 && quantidadeSistema > 0) {
      return StatusProduto.naoEncontrado;
    }

    final var_ = variacao!;

    // OK (bateu)
    if (var_ == 0.0) {
      return StatusProduto.ok;
    }

    // Sobra
    if (var_ > 0) {
      return StatusProduto.sobra;
    }

    // Falta
    return StatusProduto.falta;
  }

  /// Verifica se há divergência entre C1 e C2
  bool get temDivergencia {
    if (contagem1PorLocal == null || contagem2PorLocal == null) {
      return false;
    }
    return totalContagem1 != totalContagem2;
  }

  /// Retorna lista de localizações onde há divergência entre C1 e C2
  List<String> get locaisDivergentes {
    if (!temDivergencia) return [];

    final locais = <String>{};

    // Adiciona todas as localizações de ambas as contagens
    if (contagem1PorLocal != null) {
      locais.addAll(contagem1PorLocal!.keys);
    }
    if (contagem2PorLocal != null) {
      locais.addAll(contagem2PorLocal!.keys);
    }

    // Filtra apenas as que têm valores diferentes
    return locais.where((local) {
      final qtd1 = contagem1PorLocal?[local] ?? 0.0;
      final qtd2 = contagem2PorLocal?[local] ?? 0.0;
      return qtd1 != qtd2;
    }).toList();
  }

  // ========== MÉTODOS AUXILIARES ==========

  /// Soma todas as quantidades de um mapa de localizações
  double _somarLocais(Map<String, double>? mapa) {
    if (mapa == null || mapa.isEmpty) return 0.0;
    return mapa.values.fold(0.0, (sum, qtd) => sum + qtd);
  }

  /// Cria uma cópia com campos atualizados
  ProdutoConsolidado copyWith({
    String? codigo,
    String? descricao,
    String? unidade,
    double? quantidadeSistema,
    double? valorUnitario,
    String? deposito,
    Map<String, double>? contagem1PorLocal,
    Map<String, double>? contagem2PorLocal,
    Map<String, double>? contagem3PorLocal,
  }) {
    return ProdutoConsolidado(
      codigo: codigo ?? this.codigo,
      descricao: descricao ?? this.descricao,
      unidade: unidade ?? this.unidade,
      quantidadeSistema: quantidadeSistema ?? this.quantidadeSistema,
      valorUnitario: valorUnitario ?? this.valorUnitario,
      deposito: deposito ?? this.deposito,
      contagem1PorLocal: contagem1PorLocal ?? this.contagem1PorLocal,
      contagem2PorLocal: contagem2PorLocal ?? this.contagem2PorLocal,
      contagem3PorLocal: contagem3PorLocal ?? this.contagem3PorLocal,
    );
  }

  @override
  String toString() {
    return 'ProdutoConsolidado($codigo - $descricao, Sistema: $quantidadeSistema, '
        'Contado: $quantidadeContada, Status: ${status.name})';
  }
}
