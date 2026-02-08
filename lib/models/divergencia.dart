// lib/models/divergencia.dart

/// Representa uma divergência entre Contagem 1 e Contagem 2
/// Usado na aba "Divergências Entre Contagens"
class Divergencia {
  final String codigo;
  final String descricao;
  final String unidade;

  // Totais gerais
  final double totalContagem1;
  final double totalContagem2;

  // Breakdown por localização
  final Map<String, DivergenciaLocal> locaisDivergentes;

  // Flag indicando se já foi marcado para C3
  final bool marcadoParaC3;

  Divergencia({
    required this.codigo,
    required this.descricao,
    required this.unidade,
    required this.totalContagem1,
    required this.totalContagem2,
    required this.locaisDivergentes,
    this.marcadoParaC3 = false,
  });

  /// Diferença total entre C1 e C2
  double get diferencaTotal => totalContagem2 - totalContagem1;

  /// Diferença absoluta (sempre positiva)
  double get diferencaAbsoluta => diferencaTotal.abs();

  /// Número de localizações divergentes
  int get quantidadeLocaisDivergentes => locaisDivergentes.length;

  /// Lista dos nomes das localizações divergentes
  List<String> get nomesLocaisDivergentes =>
      locaisDivergentes.keys.toList()..sort();

  /// Verifica se a divergência é significativa (diferença > 10%)
  bool get isSignificativa {
    final media = (totalContagem1 + totalContagem2) / 2;
    if (media == 0) return true; // Se média é zero, qualquer diferença é crítica
    return (diferencaAbsoluta / media) > 0.1;
  }

  /// Cria uma cópia com campos atualizados
  Divergencia copyWith({
    String? codigo,
    String? descricao,
    String? unidade,
    double? totalContagem1,
    double? totalContagem2,
    Map<String, DivergenciaLocal>? locaisDivergentes,
    bool? marcadoParaC3,
  }) {
    return Divergencia(
      codigo: codigo ?? this.codigo,
      descricao: descricao ?? this.descricao,
      unidade: unidade ?? this.unidade,
      totalContagem1: totalContagem1 ?? this.totalContagem1,
      totalContagem2: totalContagem2 ?? this.totalContagem2,
      locaisDivergentes: locaisDivergentes ?? this.locaisDivergentes,
      marcadoParaC3: marcadoParaC3 ?? this.marcadoParaC3,
    );
  }

  @override
  String toString() {
    return 'Divergencia($codigo - $descricao: C1=$totalContagem1, '
        'C2=$totalContagem2, diff=$diferencaTotal)';
  }
}

/// Representa uma divergência em uma localização específica
class DivergenciaLocal {
  final String localizacao;
  final double quantidadeC1;
  final double quantidadeC2;

  DivergenciaLocal({
    required this.localizacao,
    required this.quantidadeC1,
    required this.quantidadeC2,
  });

  /// Diferença nesta localização
  double get diferenca => quantidadeC2 - quantidadeC1;

  /// Diferença absoluta
  double get diferencaAbsoluta => diferenca.abs();

  /// Tipo de divergência
  TipoDivergenciaLocal get tipo {
    if (quantidadeC1 == 0 && quantidadeC2 > 0) {
      return TipoDivergenciaLocal.apenasC2;
    } else if (quantidadeC1 > 0 && quantidadeC2 == 0) {
      return TipoDivergenciaLocal.apenasC1;
    } else if (quantidadeC1 > quantidadeC2) {
      return TipoDivergenciaLocal.c1Maior;
    } else {
      return TipoDivergenciaLocal.c2Maior;
    }
  }

  @override
  String toString() {
    return 'DivergenciaLocal($localizacao: C1=$quantidadeC1, '
        'C2=$quantidadeC2, diff=$diferenca)';
  }
}

/// Tipo de divergência local
enum TipoDivergenciaLocal {
  apenasC1,    // Item encontrado apenas na C1
  apenasC2,    // Item encontrado apenas na C2
  c1Maior,     // C1 encontrou mais que C2
  c2Maior,     // C2 encontrou mais que C1
}

/// Extension para UI
extension TipoDivergenciaLocalUI on TipoDivergenciaLocal {
  String get label {
    switch (this) {
      case TipoDivergenciaLocal.apenasC1:
        return 'Apenas em C1';
      case TipoDivergenciaLocal.apenasC2:
        return 'Apenas em C2';
      case TipoDivergenciaLocal.c1Maior:
        return 'C1 > C2';
      case TipoDivergenciaLocal.c2Maior:
        return 'C2 > C1';
    }
  }

  String get emoji {
    switch (this) {
      case TipoDivergenciaLocal.apenasC1:
        return '1️⃣';
      case TipoDivergenciaLocal.apenasC2:
        return '2️⃣';
      case TipoDivergenciaLocal.c1Maior:
        return '⬆️';
      case TipoDivergenciaLocal.c2Maior:
        return '⬇️';
    }
  }
}

/// Builder para facilitar criação de Divergencia a partir de ProdutoConsolidado
class DivergenciaBuilder {
  /// Cria uma Divergencia a partir de dados consolidados
  static Divergencia? fromProdutoConsolidado({
    required String codigo,
    required String descricao,
    required String unidade,
    required Map<String, double>? contagem1PorLocal,
    required Map<String, double>? contagem2PorLocal,
    bool marcadoParaC3 = false,
  }) {
    // Verifica se há dados suficientes
    if (contagem1PorLocal == null || contagem2PorLocal == null) {
      return null;
    }

    // Calcula totais
    final totalC1 = _somarLocais(contagem1PorLocal);
    final totalC2 = _somarLocais(contagem2PorLocal);

    // Se não há divergência, retorna null
    if (totalC1 == totalC2) {
      return null;
    }

    // Identifica locais divergentes
    final locaisDivergentes = <String, DivergenciaLocal>{};
    final todosLocais = <String>{
      ...contagem1PorLocal.keys,
      ...contagem2PorLocal.keys,
    };

    for (final local in todosLocais) {
      final qtdC1 = contagem1PorLocal[local] ?? 0.0;
      final qtdC2 = contagem2PorLocal[local] ?? 0.0;

      // Só adiciona se houver divergência neste local
      if (qtdC1 != qtdC2) {
        locaisDivergentes[local] = DivergenciaLocal(
          localizacao: local,
          quantidadeC1: qtdC1,
          quantidadeC2: qtdC2,
        );
      }
    }

    return Divergencia(
      codigo: codigo,
      descricao: descricao,
      unidade: unidade,
      totalContagem1: totalC1,
      totalContagem2: totalC2,
      locaisDivergentes: locaisDivergentes,
      marcadoParaC3: marcadoParaC3,
    );
  }

  static double _somarLocais(Map<String, double> mapa) {
    if (mapa.isEmpty) return 0.0;
    return mapa.values.fold(0.0, (sum, qtd) => sum + qtd);
  }
}