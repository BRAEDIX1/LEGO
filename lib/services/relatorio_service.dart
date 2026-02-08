// lib/services/relatorio_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:lego/models/balanco_financeiro.dart';
import 'package:lego/models/divergencia.dart';
import 'package:lego/models/inventario.dart';

/// Constantes para cálculos financeiros
class ConstantesFinanceiras {
  static const double taxaImposto = 0.2195; // 21.95%
  static const double multiplicadorFalta = 1.2195; // 1 + 21.95%
}

/// Resultado da apuração de um item
class ItemApurado {
  final String codigo;
  final String descricao;
  final String lote;
  final double quantidadeSistema;
  final double quantidadeContada;
  final double valorUnitario;
  final double diferenca;
  final double impactoFinanceiro;
  final StatusApuracao status;
  final String? localizacao;

  ItemApurado({
    required this.codigo,
    required this.descricao,
    required this.lote,
    required this.quantidadeSistema,
    required this.quantidadeContada,
    required this.valorUnitario,
    required this.diferenca,
    required this.impactoFinanceiro,
    required this.status,
    this.localizacao,
  });

  bool get isSobra => diferenca > 0;
  bool get isFalta => diferenca < 0;
  bool get isOk => diferenca == 0;

  Map<String, dynamic> toMap() => {
    'codigo': codigo,
    'descricao': descricao,
    'lote': lote,
    'quantidade_sistema': quantidadeSistema,
    'quantidade_contada': quantidadeContada,
    'valor_unitario': valorUnitario,
    'diferenca': diferenca,
    'impacto_financeiro': impactoFinanceiro,
    'status': status.name,
    'localizacao': localizacao,
  };
}

/// Status da apuração do item
enum StatusApuracao {
  ok,              // Contado = Sistema
  sobra,           // Contado > Sistema
  falta,           // Contado < Sistema
  naoEncontrado,   // Contado = 0 e Sistema > 0 (crítico)
  naoNoSistema,    // Contado > 0 e Sistema = 0
  aguardandoC3,    // C1 ≠ C2, aguarda recontagem
}

/// Resultado consolidado do relatório
class ResultadoRelatorio {
  final String inventarioId;
  final String codigoInventario;
  final DateTime dataGeracao;
  final TipoRelatorio tipo;
  final BalancoFinanceiro balanco;
  final List<ItemApurado> itens;
  final List<Divergencia> divergencias;
  final Map<String, dynamic> estatisticas;

  ResultadoRelatorio({
    required this.inventarioId,
    required this.codigoInventario,
    required this.dataGeracao,
    required this.tipo,
    required this.balanco,
    required this.itens,
    required this.divergencias,
    required this.estatisticas,
  });

  List<ItemApurado> get itensSobra => itens.where((i) => i.status == StatusApuracao.sobra).toList();
  List<ItemApurado> get itensFalta => itens.where((i) => i.status == StatusApuracao.falta || i.status == StatusApuracao.naoEncontrado).toList();
  List<ItemApurado> get itensOk => itens.where((i) => i.status == StatusApuracao.ok).toList();
  List<ItemApurado> get itensCriticos => itens.where((i) => i.status == StatusApuracao.naoEncontrado).toList();
}

/// Tipos de relatório
enum TipoRelatorio {
  simples,       // Final de contagem simples
  divergenciasC2, // Após C2, mostra divergências para C3
  apuracaoFinal, // Após C3 ou quando não há divergências
}

/// Serviço de geração de relatórios
class RelatorioService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== GERAÇÃO DE RELATÓRIOS ====================

  /// Gera relatório baseado no estado atual do inventário
  Future<ResultadoRelatorio> gerarRelatorio(String inventarioId) async {
    try {
      // 1. Busca inventário
      final invDoc = await _firestore.collection('inventarios').doc(inventarioId).get();
      if (!invDoc.exists) throw Exception('Inventário não encontrado');

      final inventario = Inventario.fromFirestore(invDoc);

      // 2. Determina tipo de relatório
      final tipo = _determinarTipoRelatorio(inventario);

      // 3. Busca estoque base
      final estoqueSnapshot = await _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('estoque')
          .get();

      final estoque = <String, Map<String, dynamic>>{};
      for (final doc in estoqueSnapshot.docs) {
        estoque[doc.id] = doc.data();
      }

      // 4. Busca lançamentos
      final lancamentosSnapshot = await _firestore
          .collection('lancamentos')
          .where('inventarioId', isEqualTo: inventarioId)
          .get();

      // Agrupa lançamentos por contagem e código
      final lancamentosPorContagem = _agruparLancamentos(lancamentosSnapshot.docs);

      // 5. Gera relatório conforme tipo
      switch (tipo) {
        case TipoRelatorio.simples:
          return _gerarRelatorioSimples(inventario, estoque, lancamentosPorContagem);
        case TipoRelatorio.divergenciasC2:
          return _gerarRelatorioDivergencias(inventario, estoque, lancamentosPorContagem);
        case TipoRelatorio.apuracaoFinal:
          return _gerarRelatorioFinal(inventario, estoque, lancamentosPorContagem);
      }
    } catch (e) {
      debugPrint('❌ Erro ao gerar relatório: $e');
      rethrow;
    }
  }

  /// Determina o tipo de relatório baseado no estado do inventário
  TipoRelatorio _determinarTipoRelatorio(Inventario inventario) {
    if (inventario.isSimples) {
      return TipoRelatorio.simples;
    }

    // Se está em C2 ou finalizou C2, mostra divergências
    if (inventario.contagemAtiva == 'contagem_2') {
      return TipoRelatorio.divergenciasC2;
    }

    // Se está em C3 ou finalizado, mostra apuração final
    return TipoRelatorio.apuracaoFinal;
  }

  /// Agrupa lançamentos por contagem e código
  Map<String, Map<String, List<Map<String, dynamic>>>> _agruparLancamentos(
      List<QueryDocumentSnapshot> docs,
      ) {
    final resultado = <String, Map<String, List<Map<String, dynamic>>>>{
      'contagem_1': {},
      'contagem_2': {},
      'contagem_3': {},
    };

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final contagem = data['contagemId'] as String? ?? 'contagem_1';
      final codigo = data['codigo'] as String? ?? '';
      final lote = data['lote'] as String? ?? '';
      final chave = lote.isEmpty ? codigo : '${codigo}_$lote';

      resultado[contagem] ??= {};
      resultado[contagem]![chave] ??= [];
      resultado[contagem]![chave]!.add(data);
    }

    return resultado;
  }

  // ==================== RELATÓRIO SIMPLES ====================

  Future<ResultadoRelatorio> _gerarRelatorioSimples(
      Inventario inventario,
      Map<String, Map<String, dynamic>> estoque,
      Map<String, Map<String, List<Map<String, dynamic>>>> lancamentos,
      ) async {
    final builder = BalancoFinanceiroBuilder();
    final itensApurados = <ItemApurado>[];
    final lancamentosC1 = lancamentos['contagem_1'] ?? {};

    // Processa cada item do estoque
    for (final entry in estoque.entries) {
      final chave = entry.key;
      final dadosEstoque = entry.value;

      final codigo = dadosEstoque['codigo'] as String? ?? chave;
      final descricao = dadosEstoque['descricao'] as String? ?? '';
      final lote = dadosEstoque['lote'] as String? ?? '';
      final qtdSistema = (dadosEstoque['quantidade'] ?? 0.0).toDouble();
      final valorUnitario = (dadosEstoque['valor_unitario'] ?? 0.0).toDouble();

      // Soma lançamentos de C1
      final lancsItem = lancamentosC1[chave] ?? [];
      final qtdContada = _somarQuantidadeLancamentos(lancsItem);

      // Calcula diferença e impacto
      final diferenca = qtdContada - qtdSistema;
      final status = _determinarStatus(qtdSistema, qtdContada);
      final impacto = _calcularImpactoFinanceiro(diferenca, valorUnitario);

      // Adiciona ao builder
      _adicionarAoBuilder(builder, status, impacto.abs());

      itensApurados.add(ItemApurado(
        codigo: codigo,
        descricao: descricao,
        lote: lote,
        quantidadeSistema: qtdSistema,
        quantidadeContada: qtdContada,
        valorUnitario: valorUnitario,
        diferenca: diferenca,
        impactoFinanceiro: impacto,
        status: status,
        localizacao: _extrairLocalizacao(lancsItem),
      ));
    }

    // Verifica itens contados que não estão no estoque
    _verificarItensExtras(lancamentosC1, estoque, itensApurados, builder);

    return ResultadoRelatorio(
      inventarioId: inventario.id,
      codigoInventario: inventario.codigo,
      dataGeracao: DateTime.now(),
      tipo: TipoRelatorio.simples,
      balanco: builder.build(),
      itens: itensApurados,
      divergencias: [],
      estatisticas: _calcularEstatisticas(itensApurados),
    );
  }

  // ==================== RELATÓRIO DE DIVERGÊNCIAS ====================

  Future<ResultadoRelatorio> _gerarRelatorioDivergencias(
      Inventario inventario,
      Map<String, Map<String, dynamic>> estoque,
      Map<String, Map<String, List<Map<String, dynamic>>>> lancamentos,
      ) async {
    final builder = BalancoFinanceiroBuilder();
    final itensApurados = <ItemApurado>[];
    final divergencias = <Divergencia>[];

    final lancamentosC1 = lancamentos['contagem_1'] ?? {};
    final lancamentosC2 = lancamentos['contagem_2'] ?? {};

    // Todas as chaves (estoque + lançamentos)
    final todasChaves = <String>{
      ...estoque.keys,
      ...lancamentosC1.keys,
      ...lancamentosC2.keys,
    };

    for (final chave in todasChaves) {
      final dadosEstoque = estoque[chave];
      final codigo = dadosEstoque?['codigo'] as String? ?? chave.split('_').first;
      final descricao = dadosEstoque?['descricao'] as String? ?? '';
      final lote = dadosEstoque?['lote'] as String? ?? '';
      final qtdSistema = (dadosEstoque?['quantidade'] ?? 0.0).toDouble();
      final valorUnitario = (dadosEstoque?['valor_unitario'] ?? 0.0).toDouble();

      // Soma lançamentos
      final lancsC1 = lancamentosC1[chave] ?? [];
      final lancsC2 = lancamentosC2[chave] ?? [];
      final qtdC1 = _somarQuantidadeLancamentos(lancsC1);
      final qtdC2 = _somarQuantidadeLancamentos(lancsC2);

      // Regra de Ouro
      if (qtdC1 == qtdC2) {
        // Confirmado - usa valor de C1 (ou C2)
        final diferenca = qtdC1 - qtdSistema;
        final status = _determinarStatus(qtdSistema, qtdC1);
        final impacto = _calcularImpactoFinanceiro(diferenca, valorUnitario);

        _adicionarAoBuilder(builder, status, impacto.abs());

        itensApurados.add(ItemApurado(
          codigo: codigo,
          descricao: descricao,
          lote: lote,
          quantidadeSistema: qtdSistema,
          quantidadeContada: qtdC1,
          valorUnitario: valorUnitario,
          diferenca: diferenca,
          impactoFinanceiro: impacto,
          status: status,
        ));
      } else {
        // Divergência - aguarda C3
        builder.addItemAguardandoC3();

        itensApurados.add(ItemApurado(
          codigo: codigo,
          descricao: descricao,
          lote: lote,
          quantidadeSistema: qtdSistema,
          quantidadeContada: 0, // Indefinido
          valorUnitario: valorUnitario,
          diferenca: 0,
          impactoFinanceiro: 0,
          status: StatusApuracao.aguardandoC3,
        ));

        // Cria objeto de divergência com localizações
        final locaisC1 = _agruparPorLocal(lancsC1);
        final locaisC2 = _agruparPorLocal(lancsC2);

        final divergencia = DivergenciaBuilder.fromProdutoConsolidado(
          codigo: codigo,
          descricao: descricao,
          unidade: 'UN',
          contagem1PorLocal: locaisC1,
          contagem2PorLocal: locaisC2,
        );

        if (divergencia != null) {
          divergencias.add(divergencia);
        }
      }
    }

    return ResultadoRelatorio(
      inventarioId: inventario.id,
      codigoInventario: inventario.codigo,
      dataGeracao: DateTime.now(),
      tipo: TipoRelatorio.divergenciasC2,
      balanco: builder.build(),
      itens: itensApurados,
      divergencias: divergencias,
      estatisticas: _calcularEstatisticas(itensApurados, divergencias: divergencias),
    );
  }

  // ==================== RELATÓRIO FINAL ====================

  Future<ResultadoRelatorio> _gerarRelatorioFinal(
      Inventario inventario,
      Map<String, Map<String, dynamic>> estoque,
      Map<String, Map<String, List<Map<String, dynamic>>>> lancamentos,
      ) async {
    final builder = BalancoFinanceiroBuilder();
    final itensApurados = <ItemApurado>[];

    final lancamentosC1 = lancamentos['contagem_1'] ?? {};
    final lancamentosC2 = lancamentos['contagem_2'] ?? {};
    final lancamentosC3 = lancamentos['contagem_3'] ?? {};

    final todasChaves = <String>{
      ...estoque.keys,
      ...lancamentosC1.keys,
      ...lancamentosC2.keys,
      ...lancamentosC3.keys,
    };

    for (final chave in todasChaves) {
      final dadosEstoque = estoque[chave];
      final codigo = dadosEstoque?['codigo'] as String? ?? chave.split('_').first;
      final descricao = dadosEstoque?['descricao'] as String? ?? '';
      final lote = dadosEstoque?['lote'] as String? ?? '';
      final qtdSistema = (dadosEstoque?['quantidade'] ?? 0.0).toDouble();
      final valorUnitario = (dadosEstoque?['valor_unitario'] ?? 0.0).toDouble();

      // Soma lançamentos
      final qtdC1 = _somarQuantidadeLancamentos(lancamentosC1[chave] ?? []);
      final qtdC2 = _somarQuantidadeLancamentos(lancamentosC2[chave] ?? []);
      final qtdC3 = _somarQuantidadeLancamentos(lancamentosC3[chave] ?? []);

      // Determina quantidade final
      double qtdFinal;
      if (qtdC1 == qtdC2) {
        // C1 = C2: confirmado
        qtdFinal = qtdC1;
      } else if (qtdC3 > 0 || lancamentosC3[chave] != null) {
        // Houve C3: usa C3
        qtdFinal = qtdC3;
      } else {
        // Sem C3 mas houve divergência: usa média ou C2
        qtdFinal = qtdC2;
      }

      final diferenca = qtdFinal - qtdSistema;
      final status = _determinarStatus(qtdSistema, qtdFinal);
      final impacto = _calcularImpactoFinanceiro(diferenca, valorUnitario);

      _adicionarAoBuilder(builder, status, impacto.abs());

      itensApurados.add(ItemApurado(
        codigo: codigo,
        descricao: descricao,
        lote: lote,
        quantidadeSistema: qtdSistema,
        quantidadeContada: qtdFinal,
        valorUnitario: valorUnitario,
        diferenca: diferenca,
        impactoFinanceiro: impacto,
        status: status,
      ));
    }

    return ResultadoRelatorio(
      inventarioId: inventario.id,
      codigoInventario: inventario.codigo,
      dataGeracao: DateTime.now(),
      tipo: TipoRelatorio.apuracaoFinal,
      balanco: builder.build(),
      itens: itensApurados,
      divergencias: [],
      estatisticas: _calcularEstatisticas(itensApurados),
    );
  }

  // ==================== HELPERS ====================

  double _somarQuantidadeLancamentos(List<Map<String, dynamic>> lancamentos) {
    if (lancamentos.isEmpty) return 0.0;
    return lancamentos.fold(0.0, (sum, lanc) {
      return sum + (lanc['quantidade'] ?? 0.0).toDouble();
    });
  }

  StatusApuracao _determinarStatus(double sistema, double contado) {
    if (contado == sistema) return StatusApuracao.ok;
    if (contado == 0 && sistema > 0) return StatusApuracao.naoEncontrado;
    if (contado > 0 && sistema == 0) return StatusApuracao.naoNoSistema;
    if (contado > sistema) return StatusApuracao.sobra;
    return StatusApuracao.falta;
  }

  double _calcularImpactoFinanceiro(double diferenca, double valorUnitario) {
    if (diferenca == 0) return 0.0;

    if (diferenca > 0) {
      // Sobra: sem imposto
      return diferenca * valorUnitario;
    } else {
      // Falta: com imposto
      return diferenca * valorUnitario * ConstantesFinanceiras.multiplicadorFalta;
    }
  }

  void _adicionarAoBuilder(BalancoFinanceiroBuilder builder, StatusApuracao status, double valor) {
    switch (status) {
      case StatusApuracao.ok:
        builder.addItemOk();
        break;
      case StatusApuracao.sobra:
      case StatusApuracao.naoNoSistema:
        builder.addSobra(valor);
        break;
      case StatusApuracao.falta:
        builder.addFalta(valor / ConstantesFinanceiras.multiplicadorFalta);
        break;
      case StatusApuracao.naoEncontrado:
        builder.addItemNaoEncontrado();
        break;
      case StatusApuracao.aguardandoC3:
        builder.addItemAguardandoC3();
        break;
    }
  }

  String? _extrairLocalizacao(List<Map<String, dynamic>> lancamentos) {
    if (lancamentos.isEmpty) return null;
    final locais = lancamentos
        .map((l) => l['prateleira'] as String?)
        .where((l) => l != null && l.isNotEmpty)
        .toSet();
    return locais.isNotEmpty ? locais.join(', ') : null;
  }

  Map<String, double> _agruparPorLocal(List<Map<String, dynamic>> lancamentos) {
    final resultado = <String, double>{};
    for (final lanc in lancamentos) {
      final local = lanc['prateleira'] as String? ?? 'SEM_LOCAL';
      final qtd = (lanc['quantidade'] ?? 0.0).toDouble();
      resultado[local] = (resultado[local] ?? 0.0) + qtd;
    }
    return resultado;
  }

  void _verificarItensExtras(
      Map<String, List<Map<String, dynamic>>> lancamentos,
      Map<String, Map<String, dynamic>> estoque,
      List<ItemApurado> itensApurados,
      BalancoFinanceiroBuilder builder,
      ) {
    final chavesJaProcessadas = itensApurados.map((i) =>
    i.lote.isEmpty ? i.codigo : '${i.codigo}_${i.lote}').toSet();

    for (final entry in lancamentos.entries) {
      if (!chavesJaProcessadas.contains(entry.key) && !estoque.containsKey(entry.key)) {
        final lancs = entry.value;
        if (lancs.isEmpty) continue;

        final codigo = lancs.first['codigo'] as String? ?? entry.key;
        final descricao = lancs.first['descricao'] as String? ?? '';
        final lote = lancs.first['lote'] as String? ?? '';
        final qtdContada = _somarQuantidadeLancamentos(lancs);

        // Item não está no sistema = sobra
        builder.addSobra(0); // Sem valor unitário conhecido

        itensApurados.add(ItemApurado(
          codigo: codigo,
          descricao: descricao,
          lote: lote,
          quantidadeSistema: 0,
          quantidadeContada: qtdContada,
          valorUnitario: 0,
          diferenca: qtdContada,
          impactoFinanceiro: 0,
          status: StatusApuracao.naoNoSistema,
        ));
      }
    }
  }

  Map<String, dynamic> _calcularEstatisticas(
      List<ItemApurado> itens, {
        List<Divergencia>? divergencias,
      }) {
    return {
      'total_itens': itens.length,
      'itens_ok': itens.where((i) => i.status == StatusApuracao.ok).length,
      'itens_sobra': itens.where((i) => i.status == StatusApuracao.sobra).length,
      'itens_falta': itens.where((i) => i.status == StatusApuracao.falta).length,
      'itens_nao_encontrados': itens.where((i) => i.status == StatusApuracao.naoEncontrado).length,
      'itens_nao_no_sistema': itens.where((i) => i.status == StatusApuracao.naoNoSistema).length,
      'itens_aguardando_c3': itens.where((i) => i.status == StatusApuracao.aguardandoC3).length,
      'total_divergencias': divergencias?.length ?? 0,
      'divergencias_significativas': divergencias?.where((d) => d.isSignificativa).length ?? 0,
    };
  }

  // ==================== MARCAÇÃO PARA C3 ====================

  /// Retorna lista de códigos divergentes para marcar no C3
  Future<List<String>> getCodigosDivergentes(String inventarioId) async {
    final relatorio = await gerarRelatorio(inventarioId);
    return relatorio.divergencias.map((d) => d.codigo).toList();
  }

  /// Marca divergências para C3 no inventário
  Future<void> marcarDivergenciasParaC3(String inventarioId) async {
    final codigos = await getCodigosDivergentes(inventarioId);

    await _firestore.collection('inventarios').doc(inventarioId).update({
      'contagens.contagem_3.itens_marcados': codigos,
    });

    debugPrint('✅ ${codigos.length} itens marcados para C3');
  }
}