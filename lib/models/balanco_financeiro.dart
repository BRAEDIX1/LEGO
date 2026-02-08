// lib/models/balanco_financeiro.dart

/// Representa o resumo financeiro do inventário
/// Usado no cabeçalho da Aba de Análise Patrimonial
class BalancoFinanceiro {
  // ========== SOBRAS (sem imposto) ==========
  final double totalSobras;           // Valor total das sobras
  final int quantidadeSobras;         // Número de itens com sobra

  // ========== FALTAS (com imposto) ==========
  final double totalFaltas;           // Valor total das faltas (já com imposto)
  final double subtotalFaltas;        // Subtotal antes do imposto
  final double impostoFaltas;         // Valor do imposto (21.95%)
  final int quantidadeFaltas;         // Número de itens com falta

  // ========== SALDO ==========
  final double saldoLiquido;          // Sobras - Faltas

  // ========== CONTADORES ==========
  final int totalItens;               // Total de itens processados
  final int itensOk;                  // Itens sem variação
  final int itensNaoEncontrados;      // Itens com C1=0 e C2=0 (crítico)
  final int itensAguardandoC3;        // Itens pendentes de C3

  BalancoFinanceiro({
    required this.totalSobras,
    required this.quantidadeSobras,
    required this.totalFaltas,
    required this.subtotalFaltas,
    required this.impostoFaltas,
    required this.quantidadeFaltas,
    required this.saldoLiquido,
    required this.totalItens,
    required this.itensOk,
    required this.itensNaoEncontrados,
    required this.itensAguardandoC3,
  });

  /// Cria um balanço vazio (para inicialização)
  factory BalancoFinanceiro.zero() {
    return BalancoFinanceiro(
      totalSobras: 0.0,
      quantidadeSobras: 0,
      totalFaltas: 0.0,
      subtotalFaltas: 0.0,
      impostoFaltas: 0.0,
      quantidadeFaltas: 0,
      saldoLiquido: 0.0,
      totalItens: 0,
      itensOk: 0,
      itensNaoEncontrados: 0,
      itensAguardandoC3: 0,
    );
  }

  /// Percentual de itens processados (sem contar aguardando C3)
  double get percentualProcessado {
    final processados = totalItens - itensAguardandoC3;
    if (totalItens == 0) return 0.0;
    return (processados / totalItens) * 100;
  }

  /// Verifica se há itens críticos (não encontrados)
  bool get temItensCriticos => itensNaoEncontrados > 0;

  /// Verifica se há itens pendentes
  bool get temItensPendentes => itensAguardandoC3 > 0;

  /// Verifica se o balanço é negativo (prejuízo)
  bool get isPrejuizo => saldoLiquido < 0;

  /// Verifica se o balanço é positivo (lucro)
  bool get isLucro => saldoLiquido > 0;

  /// Verifica se o balanço está equilibrado
  bool get isEquilibrado => saldoLiquido == 0;

  /// Retorna descrição do status do balanço
  String get statusDescricao {
    if (isPrejuizo) return 'Prejuízo';
    if (isLucro) return 'Lucro';
    return 'Equilibrado';
  }

  /// Emoji representando o status
  String get statusEmoji {
    if (isPrejuizo) return '📉';
    if (isLucro) return '📈';
    return '➖';
  }

  /// Formata valor monetário
  String formatarValor(double valor) {
    final isNegativo = valor < 0;
    final valorAbs = valor.abs();
    final formatado = valorAbs.toStringAsFixed(2).replaceAll('.', ',');

    // Adiciona separador de milhares
    final parts = formatado.split(',');
    final inteira = parts[0];
    final decimal = parts.length > 1 ? parts[1] : '00';

    // Adiciona pontos de milhar
    final inteiraFormatada = _adicionarSeparadorMilhar(inteira);

    final valorFinal = 'R\$ $inteiraFormatada,$decimal';
    return isNegativo ? '-$valorFinal' : valorFinal;
  }

  /// Adiciona separador de milhar (ponto)
  String _adicionarSeparadorMilhar(String numero) {
    if (numero.length <= 3) return numero;

    final buffer = StringBuffer();
    var contador = 0;

    for (var i = numero.length - 1; i >= 0; i--) {
      if (contador > 0 && contador % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(numero[i]);
      contador++;
    }

    return buffer.toString().split('').reversed.join();
  }

  /// Retorna resumo textual do balanço
  String get resumo {
    final sobrasFormatado = formatarValor(totalSobras);
    final faltasFormatado = formatarValor(totalFaltas);
    final saldoFormatado = formatarValor(saldoLiquido);

    return '''
Sobras: $sobrasFormatado ($quantidadeSobras itens)
Faltas: $faltasFormatado ($quantidadeFaltas itens)
Saldo: $saldoFormatado
Status: $statusEmoji $statusDescricao
    '''.trim();
  }

  @override
  String toString() {
    return 'BalancoFinanceiro(Sobras: ${formatarValor(totalSobras)}, '
        'Faltas: ${formatarValor(totalFaltas)}, '
        'Saldo: ${formatarValor(saldoLiquido)})';
  }

  /// Cria uma cópia com campos atualizados
  BalancoFinanceiro copyWith({
    double? totalSobras,
    int? quantidadeSobras,
    double? totalFaltas,
    double? subtotalFaltas,
    double? impostoFaltas,
    int? quantidadeFaltas,
    double? saldoLiquido,
    int? totalItens,
    int? itensOk,
    int? itensNaoEncontrados,
    int? itensAguardandoC3,
  }) {
    return BalancoFinanceiro(
      totalSobras: totalSobras ?? this.totalSobras,
      quantidadeSobras: quantidadeSobras ?? this.quantidadeSobras,
      totalFaltas: totalFaltas ?? this.totalFaltas,
      subtotalFaltas: subtotalFaltas ?? this.subtotalFaltas,
      impostoFaltas: impostoFaltas ?? this.impostoFaltas,
      quantidadeFaltas: quantidadeFaltas ?? this.quantidadeFaltas,
      saldoLiquido: saldoLiquido ?? this.saldoLiquido,
      totalItens: totalItens ?? this.totalItens,
      itensOk: itensOk ?? this.itensOk,
      itensNaoEncontrados: itensNaoEncontrados ?? this.itensNaoEncontrados,
      itensAguardandoC3: itensAguardandoC3 ?? this.itensAguardandoC3,
    );
  }
}

/// Builder para facilitar criação de BalancoFinanceiro
class BalancoFinanceiroBuilder {
  double _totalSobras = 0.0;
  int _quantidadeSobras = 0;
  double _subtotalFaltas = 0.0;
  double _impostoFaltas = 0.0;
  int _quantidadeFaltas = 0;
  int _totalItens = 0;
  int _itensOk = 0;
  int _itensNaoEncontrados = 0;
  int _itensAguardandoC3 = 0;

  /// Adiciona uma sobra ao balanço
  void addSobra(double valor) {
    _totalSobras += valor;
    _quantidadeSobras++;
    _totalItens++;
  }

  /// Adiciona uma falta ao balanço (com cálculo de imposto)
  void addFalta(double subtotal) {
    _subtotalFaltas += subtotal;
    _impostoFaltas += subtotal * 0.2195; // 21.95%
    _quantidadeFaltas++;
    _totalItens++;
  }

  /// Adiciona um item OK (sem variação)
  void addItemOk() {
    _itensOk++;
    _totalItens++;
  }

  /// Adiciona um item não encontrado
  void addItemNaoEncontrado() {
    _itensNaoEncontrados++;
    _totalItens++;
  }

  /// Adiciona um item aguardando C3
  void addItemAguardandoC3() {
    _itensAguardandoC3++;
    _totalItens++;
  }

  /// Constrói o BalancoFinanceiro final
  BalancoFinanceiro build() {
    final totalFaltas = _subtotalFaltas + _impostoFaltas;
    final saldoLiquido = _totalSobras - totalFaltas;

    return BalancoFinanceiro(
      totalSobras: _totalSobras,
      quantidadeSobras: _quantidadeSobras,
      totalFaltas: totalFaltas,
      subtotalFaltas: _subtotalFaltas,
      impostoFaltas: _impostoFaltas,
      quantidadeFaltas: _quantidadeFaltas,
      saldoLiquido: saldoLiquido,
      totalItens: _totalItens,
      itensOk: _itensOk,
      itensNaoEncontrados: _itensNaoEncontrados,
      itensAguardandoC3: _itensAguardandoC3,
    );
  }

  /// Reseta o builder para reutilização
  void reset() {
    _totalSobras = 0.0;
    _quantidadeSobras = 0;
    _subtotalFaltas = 0.0;
    _impostoFaltas = 0.0;
    _quantidadeFaltas = 0;
    _totalItens = 0;
    _itensOk = 0;
    _itensNaoEncontrados = 0;
    _itensAguardandoC3 = 0;
  }
}