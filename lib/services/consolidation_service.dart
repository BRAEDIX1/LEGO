// lib/services/consolidation_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lego/models/produto_consolidado.dart';
import 'package:lego/models/balanco_financeiro.dart';
import 'package:lego/models/divergencia.dart';
import 'package:flutter/foundation.dart';

/// ⭐⭐⭐ MOTOR DE CONSOLIDAÇÃO - CORAÇÃO DO SISTEMA
///
/// Responsável por:
/// 1. Buscar dados de materiais/, estoque/ e lancamentos/
/// 2. Fazer JOIN das três fontes
/// 3. Consolidar lançamentos por código+contagem+localização
/// 4. Aplicar a REGRA DE OURO (quantidadeContada)
/// 5. Calcular impactos financeiros
/// 6. Retornar stream que atualiza em tempo real
class ConsolidationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>>? _materiaisCache;
  List<Map<String, dynamic>>? _estoqueCache;
  DateTime? _lastCacheTime;

  // Validade do cache: 5 minutos
  static const _cacheValidity = Duration(minutes: 5);

  /// ⭐ MÉTODO PRINCIPAL: Stream de produtos consolidados
  ///
  /// Retorna um stream que atualiza automaticamente quando:
  /// - Tablets sincronizam novos lançamentos
  /// - Estoque é atualizado
  /// - Materiais são modificados
  Stream<List<ProdutoConsolidado>> streamProdutosConsolidados(String inventarioId) {
    // Escuta mudanças nos lançamentos deste inventário
    return _firestore
        .collection('lancamentos')
        .where('inventarioId', isEqualTo: inventarioId)
        .snapshots()
        .asyncMap((lancamentosSnapshot) async {
      // Quando lançamentos mudam, reconstrói tudo
      return await _consolidarTudo(inventarioId);
    });
  }

  /// Consolida TUDO: materiais + estoque + lançamentos
  Future<List<ProdutoConsolidado>> _consolidarTudo(String inventarioId) async {
    try {
      // ✅ 1. Garantir que cache está carregado
      await _ensureCacheLoaded();

      // ✅ 2. Buscar APENAS lançamentos (única query que muda frequentemente)
      final lancamentosSnapshot = await _firestore
          .collection('lancamentos')
          .where('inventarioId', isEqualTo: inventarioId)
          .get();

      // ✅ 3. Consolidar usando cache em memória
      return _consolidarComCache(lancamentosSnapshot);

    } catch (e, stackTrace) {
      debugPrint('❌ Erro na consolidação: $e');
      debugPrint('Stack: $stackTrace');
      return [];
    }
  }

  /// Garante que o cache de materiais e estoque está carregado
  Future<void> _ensureCacheLoaded() async {
    final now = DateTime.now();

    // Verifica se cache é válido
    final cacheValido = _materiaisCache != null &&
        _estoqueCache != null &&
        _lastCacheTime != null &&
        now.difference(_lastCacheTime!) < _cacheValidity;

    if (cacheValido) {
      debugPrint('✅ Usando cache (idade: ${now.difference(_lastCacheTime!).inSeconds}s)');
      return;
    }

    debugPrint('🔄 Recarregando cache de materiais e estoque...');

    try {
      // Carregar materiais e estoque em paralelo
      final results = await Future.wait([
        _firestore.collection('materiais').get(),
        _firestore.collection('estoque').get(),
      ]);

      _materiaisCache = results[0].docs.map((d) => {
        ...d.data(),
        'id': d.id,
      }).toList();

      _estoqueCache = results[1].docs.map((d) => {
        ...d.data(),
        'id': d.id,
      }).toList();

      _lastCacheTime = now;

      debugPrint('✅ Cache carregado: ${_materiaisCache!.length} materiais, ${_estoqueCache!.length} estoque');

    } catch (e, stackTrace) {
      debugPrint('❌ Erro ao carregar cache: $e');
      debugPrint('Stack: $stackTrace');

      // Em caso de erro, inicializa com listas vazias
      _materiaisCache ??= [];
      _estoqueCache ??= [];
      _lastCacheTime = now;
    }
  }

  /// Consolida produtos usando dados do cache
  /// Consolida produtos usando dados do cache
  List<ProdutoConsolidado> _consolidarComCache(
      QuerySnapshot<Map<String, dynamic>> lancamentosSnapshot,
      ) {
    final produtos = <String, ProdutoConsolidado>{};

    // 1. Processar materiais do cache
    for (final material in _materiaisCache ?? []) {
      final codigo = material['codigo'] as String?;
      if (codigo == null) continue;

      final produto = ProdutoConsolidado(
        codigo: codigo,
        descricao: material['descricao'] as String? ?? '',
        unidade: material['unidade'] as String? ?? 'UN',
        valorUnitario: _toDouble(material['valor_unitario']),
        quantidadeSistema: 0.0, // Será preenchido do estoque
        deposito: material['deposito'] as String?,
        // ✅ NÃO passar getters - são calculados automaticamente
      );

      produtos[codigo] = produto;
    }

    // 2. Adicionar quantidades do estoque do cache
    for (final estoqueDoc in _estoqueCache ?? []) {
      final codigo = estoqueDoc['codigo'] as String?;
      if (codigo == null) continue;

      if (produtos.containsKey(codigo)) {
        final quantidadeEstoque = _toDouble(estoqueDoc['quantidade']);
        produtos[codigo] = produtos[codigo]!.copyWith(
          quantidadeSistema: quantidadeEstoque,
        );
      }
    }

    // 3. Processar lançamentos (dados em tempo real)
    for (final lancDoc in lancamentosSnapshot.docs) {
      final dados = lancDoc.data();
      final codigo = dados['codigo'] as String?;
      if (codigo == null) continue;

      // Buscar ou criar produto
      if (!produtos.containsKey(codigo)) {
        // Produto não estava no cache - criar novo
        produtos[codigo] = ProdutoConsolidado(
          codigo: codigo,
          descricao: dados['descricao'] as String? ?? '',
          unidade: dados['unidade'] as String? ?? 'UN',
          valorUnitario: _toDouble(dados['valor_unitario']),
          quantidadeSistema: 0.0,
          deposito: dados['deposito'] as String?,
          // ✅ NÃO passar getters
        );
      }

      // Adicionar quantidades por contagem e local
      final contagemId = dados['contagemId'] as String?;
      final localizacao = dados['localizacao'] as String? ?? 'SEM_LOCAL';
      final quantidade = _toDouble(dados['quantidade']);

      final produto = produtos[codigo]!;
      Map<String, double> mapaLocal;

      switch (contagemId) {
        case 'contagem_1':
          mapaLocal = Map<String, double>.from(produto.contagem1PorLocal ?? {});
          mapaLocal[localizacao] = (mapaLocal[localizacao] ?? 0.0) + quantidade;
          produtos[codigo] = produto.copyWith(contagem1PorLocal: mapaLocal);
          break;
        case 'contagem_2':
          mapaLocal = Map<String, double>.from(produto.contagem2PorLocal ?? {});
          mapaLocal[localizacao] = (mapaLocal[localizacao] ?? 0.0) + quantidade;
          produtos[codigo] = produto.copyWith(contagem2PorLocal: mapaLocal);
          break;
        case 'contagem_3':
          mapaLocal = Map<String, double>.from(produto.contagem3PorLocal ?? {});
          mapaLocal[localizacao] = (mapaLocal[localizacao] ?? 0.0) + quantidade;
          produtos[codigo] = produto.copyWith(contagem3PorLocal: mapaLocal);
          break;
      }
    }

    // 4. Retornar lista de produtos
    // ✅ Os getters (quantidadeContada, variacao, status, etc.)
    //    são calculados automaticamente ao acessar
    return produtos.values.toList();
  }

  /// Invalida o cache forçando reload na próxima consolidação
  /// Útil quando materiais/estoque são atualizados
  Future<void> invalidarCache() async {
    debugPrint('🔄 Cache invalidado manualmente');
    _materiaisCache = null;
    _estoqueCache = null;
    _lastCacheTime = null;
    await _ensureCacheLoaded();
  }

  /// Consolida lançamentos de uma contagem específica por localização
  ///
  /// Exemplo de entrada:
  /// [
  ///   {codigo: 'PROD001', prateleira: 'mesa', quantidade: 3.0},
  ///   {codigo: 'PROD001', prateleira: 'fruteira', quantidade: 2.0},
  ///   {codigo: 'PROD001', prateleira: 'mesa', quantidade: 1.0}, // duplicado
  /// ]
  ///
  /// Saída: {'mesa': 4.0, 'fruteira': 2.0}
  Map<String, double> _consolidarLancamentosPorLocal(
      List<Map<String, dynamic>> lancamentos,
      ) {
    final consolidado = <String, double>{};

    for (var lanc in lancamentos) {
      final local = (lanc['prateleira'] as String? ?? '').trim();
      if (local.isEmpty) continue;

      final quantidade = (lanc['quantidade'] ?? 0.0).toDouble();

      consolidado[local] = (consolidado[local] ?? 0.0) + quantidade;
    }

    return consolidado;
  }

  /// Calcula o balanço financeiro a partir de produtos consolidados
  BalancoFinanceiro calcularBalanco(List<ProdutoConsolidado> produtos) {
    final builder = BalancoFinanceiroBuilder();

    for (var produto in produtos) {
      final contado = produto.quantidadeContada;

      // Item aguardando C3 - não entra no balanço
      if (contado == null) {
        builder.addItemAguardandoC3();
        continue;
      }

      // Item não encontrado (crítico)
      if (contado == 0.0 && produto.quantidadeSistema > 0) {
        builder.addItemNaoEncontrado();

        // Mas AINDA ASSIM entra no balanço como falta
        final subtotal = produto.quantidadeSistema * produto.valorUnitario;
        builder.addFalta(subtotal);
        continue;
      }

      final variacao = produto.variacao!;

      // Item OK (sem variação)
      if (variacao == 0.0) {
        builder.addItemOk();
        continue;
      }

      // Sobra (sem imposto)
      if (variacao > 0) {
        final valor = variacao * produto.valorUnitario;
        builder.addSobra(valor);
        continue;
      }

      // Falta (com imposto)
      if (variacao < 0) {
        final subtotal = variacao.abs() * produto.valorUnitario;
        builder.addFalta(subtotal);
        continue;
      }
    }

    return builder.build();
  }

  /// Extrai apenas produtos com divergência entre C1 e C2
  List<Divergencia> extrairDivergencias(List<ProdutoConsolidado> produtos) {
    final divergencias = <Divergencia>[];

    for (var produto in produtos) {
      if (!produto.temDivergencia) continue;

      final divergencia = DivergenciaBuilder.fromProdutoConsolidado(
        codigo: produto.codigo,
        descricao: produto.descricao,
        unidade: produto.unidade,
        contagem1PorLocal: produto.contagem1PorLocal,
        contagem2PorLocal: produto.contagem2PorLocal,
      );

      if (divergencia != null) {
        divergencias.add(divergencia);
      }
    }

    // Ordena por diferença absoluta (maior primeiro)
    divergencias.sort((a, b) =>
        b.diferencaAbsoluta.compareTo(a.diferencaAbsoluta)
    );

    return divergencias;
  }

  /// Filtra produtos por status
  List<ProdutoConsolidado> filtrarPorStatus(
      List<ProdutoConsolidado> produtos,
      StatusProduto status,
      ) {
    return produtos.where((p) => p.status == status).toList();
  }

  /// Filtra produtos por código ou descrição
  List<ProdutoConsolidado> filtrarPorBusca(
      List<ProdutoConsolidado> produtos,
      String busca,
      ) {
    if (busca.isEmpty) return produtos;

    final buscaLower = busca.toLowerCase();

    return produtos.where((p) {
      return p.codigo.toLowerCase().contains(buscaLower) ||
          p.descricao.toLowerCase().contains(buscaLower);
    }).toList();
  }

  /// Ordena produtos por critério
  List<ProdutoConsolidado> ordenar(
      List<ProdutoConsolidado> produtos,
      OrdenacaoCriterio criterio, {
        bool crescente = true,
      }) {
    final produtosCopia = List<ProdutoConsolidado>.from(produtos);

    switch (criterio) {
      case OrdenacaoCriterio.codigo:
        produtosCopia.sort((a, b) => a.codigo.compareTo(b.codigo));
        break;

      case OrdenacaoCriterio.descricao:
        produtosCopia.sort((a, b) => a.descricao.compareTo(b.descricao));
        break;

      case OrdenacaoCriterio.variacao:
        produtosCopia.sort((a, b) {
          final varA = a.variacao ?? 0.0;
          final varB = b.variacao ?? 0.0;
          return varA.compareTo(varB);
        });
        break;

      case OrdenacaoCriterio.impactoFinanceiro:
        produtosCopia.sort((a, b) {
          final impA = a.impactoFinanceiro ?? 0.0;
          final impB = b.impactoFinanceiro ?? 0.0;
          return impA.compareTo(impB);
        });
        break;

      case OrdenacaoCriterio.status:
        produtosCopia.sort((a, b) => a.status.index.compareTo(b.status.index));
        break;
    }

    if (!crescente) {
      return produtosCopia.reversed.toList();
    }

    return produtosCopia;
  }

  /// Exporta produtos para formato de relatório
  Map<String, dynamic> gerarRelatorio(
      List<ProdutoConsolidado> produtos,
      BalancoFinanceiro balanco,
      ) {
    return {
      'data_geracao': DateTime.now().toIso8601String(),
      'total_itens': produtos.length,
      'balanco': {
        'total_sobras': balanco.totalSobras,
        'quantidade_sobras': balanco.quantidadeSobras,
        'total_faltas': balanco.totalFaltas,
        'subtotal_faltas': balanco.subtotalFaltas,
        'imposto_faltas': balanco.impostoFaltas,
        'quantidade_faltas': balanco.quantidadeFaltas,
        'saldo_liquido': balanco.saldoLiquido,
        'itens_ok': balanco.itensOk,
        'itens_nao_encontrados': balanco.itensNaoEncontrados,
        'itens_aguardando_c3': balanco.itensAguardandoC3,
      },
      'produtos': produtos.map((p) => {
        'codigo': p.codigo,
        'descricao': p.descricao,
        'unidade': p.unidade,
        'quantidade_sistema': p.quantidadeSistema,
        'quantidade_contada': p.quantidadeContada,
        'variacao': p.variacao,
        'valor_unitario': p.valorUnitario,
        'impacto_financeiro': p.impactoFinanceiro,
        'status': p.status.name,
      }).toList(),
    };
  }

  /// Busca estatísticas rápidas (sem stream)
  Future<Map<String, dynamic>> getEstatisticasRapidas(String inventarioId) async {
    try {
      final produtos = await _consolidarTudo(inventarioId);
      final balanco = calcularBalanco(produtos);
      final divergencias = extrairDivergencias(produtos);

      return {
        'total_produtos': produtos.length,
        'produtos_ok': balanco.itensOk,
        'produtos_divergentes': divergencias.length,
        'produtos_nao_encontrados': balanco.itensNaoEncontrados,
        'aguardando_c3': balanco.itensAguardandoC3,
        'saldo_liquido': balanco.saldoLiquido,
        'percentual_processado': balanco.percentualProcessado,
      };
    } catch (e) {
      print('❌ Erro ao buscar estatísticas: $e');
      return {
        'erro': e.toString(),
      };
    }
  }

  /// Verifica se um produto específico precisa de C3
  Future<bool> produtoPrecisaC3(String inventarioId, String codigo) async {
    try {
      final lancamentos = await _firestore
          .collection('lancamentos')
          .where('inventarioId', isEqualTo: inventarioId)
          .where('codigo', isEqualTo: codigo)
          .get();

      final contagem1 = _consolidarLancamentosPorLocal(
        lancamentos.docs
            .where((d) => d.data()['contagemId'] == 'contagem_1')
            .map((d) => d.data())
            .toList(),
      );

      final contagem2 = _consolidarLancamentosPorLocal(
        lancamentos.docs
            .where((d) => d.data()['contagemId'] == 'contagem_2')
            .map((d) => d.data())
            .toList(),
      );

      final total1 = contagem1.values.fold(0.0, (sum, qtd) => sum + qtd);
      final total2 = contagem2.values.fold(0.0, (sum, qtd) => sum + qtd);

      return total1 != total2;
    } catch (e) {
      print('❌ Erro ao verificar C3: $e');
      return false;
    }
  }

  /// Converte valor para double de forma segura
  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
    }
    return 0.0;
  }
} // ← Chave final da classe

/// Critérios de ordenação disponíveis
enum OrdenacaoCriterio {
  codigo,
  descricao,
  variacao,
  impactoFinanceiro,
  status,
}

/// Extension para label dos critérios
extension OrdenacaoCriterioLabel on OrdenacaoCriterio {
  String get label {
    switch (this) {
      case OrdenacaoCriterio.codigo:
        return 'Código';
      case OrdenacaoCriterio.descricao:
        return 'Descrição';
      case OrdenacaoCriterio.variacao:
        return 'Variação';
      case OrdenacaoCriterio.impactoFinanceiro:
        return 'Impacto Financeiro';
      case OrdenacaoCriterio.status:
        return 'Status';
    }
  }
}