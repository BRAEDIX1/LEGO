// lib/services/comparativo_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:lego/models/inventario.dart';

/// Resultado da comparação entre dois inventários
class ResultadoComparativo {
  final Inventario inventarioA;
  final Inventario inventarioB;
  final DateTime dataGeracao;
  final ResumoComparativo resumo;
  final List<ItemComparativo> itens;
  final List<ItemComparativo> novosItens;      // Só em B
  final List<ItemComparativo> itensRemovidos;  // Só em A
  final List<ItemComparativo> itensAlterados;  // Em ambos, com diferença

  ResultadoComparativo({
    required this.inventarioA,
    required this.inventarioB,
    required this.dataGeracao,
    required this.resumo,
    required this.itens,
    required this.novosItens,
    required this.itensRemovidos,
    required this.itensAlterados,
  });
}

/// Resumo estatístico do comparativo
class ResumoComparativo {
  final int totalItensA;
  final int totalItensB;
  final int itensEmComum;
  final int itensNovos;
  final int itensRemovidos;
  final int itensAlterados;
  final int itensSemAlteracao;

  final double valorTotalA;
  final double valorTotalB;
  final double diferencaValor;
  final double percentualVariacao;

  final double quantidadeTotalA;
  final double quantidadeTotalB;
  final double diferencaQuantidade;

  ResumoComparativo({
    required this.totalItensA,
    required this.totalItensB,
    required this.itensEmComum,
    required this.itensNovos,
    required this.itensRemovidos,
    required this.itensAlterados,
    required this.itensSemAlteracao,
    required this.valorTotalA,
    required this.valorTotalB,
    required this.diferencaValor,
    required this.percentualVariacao,
    required this.quantidadeTotalA,
    required this.quantidadeTotalB,
    required this.diferencaQuantidade,
  });

  bool get houveCrescimento => diferencaValor > 0;
  bool get houveReducao => diferencaValor < 0;
  bool get estavel => diferencaValor == 0;
}

/// Item individual no comparativo
class ItemComparativo {
  final String codigo;
  final String descricao;
  final String? lote;
  final String chave; // codigo ou codigo_lote

  // Valores do inventário A (anterior)
  final double? quantidadeA;
  final double? valorUnitarioA;
  final double? valorTotalA;

  // Valores do inventário B (atual)
  final double? quantidadeB;
  final double? valorUnitarioB;
  final double? valorTotalB;

  // Diferenças calculadas
  final double diferencaQuantidade;
  final double diferencaValor;
  final double percentualVariacao;

  final TipoAlteracao tipo;

  ItemComparativo({
    required this.codigo,
    required this.descricao,
    this.lote,
    required this.chave,
    this.quantidadeA,
    this.valorUnitarioA,
    this.valorTotalA,
    this.quantidadeB,
    this.valorUnitarioB,
    this.valorTotalB,
    required this.diferencaQuantidade,
    required this.diferencaValor,
    required this.percentualVariacao,
    required this.tipo,
  });

  bool get isNovo => tipo == TipoAlteracao.novo;
  bool get isRemovido => tipo == TipoAlteracao.removido;
  bool get isAlterado => tipo == TipoAlteracao.alterado;
  bool get isSemAlteracao => tipo == TipoAlteracao.semAlteracao;
}

/// Tipo de alteração do item
enum TipoAlteracao {
  novo,          // Só existe em B
  removido,      // Só existe em A
  alterado,      // Existe em ambos com diferença
  semAlteracao,  // Existe em ambos, igual
}

/// Serviço de comparativo entre inventários
class ComparativoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Gera comparativo entre dois inventários
  Future<ResultadoComparativo> gerarComparativo(
      String inventarioIdA,
      String inventarioIdB,
      ) async {
    debugPrint('📊 Gerando comparativo: $inventarioIdA vs $inventarioIdB');

    // Busca inventários
    final docA = await _firestore.collection('inventarios').doc(inventarioIdA).get();
    final docB = await _firestore.collection('inventarios').doc(inventarioIdB).get();

    if (!docA.exists || !docB.exists) {
      throw Exception('Inventário não encontrado');
    }

    final inventarioA = Inventario.fromFirestore(docA);
    final inventarioB = Inventario.fromFirestore(docB);

    // Busca estoques
    final estoqueA = await _buscarEstoque(inventarioIdA);
    final estoqueB = await _buscarEstoque(inventarioIdB);

    // Processa comparação
    final itens = <ItemComparativo>[];
    final novos = <ItemComparativo>[];
    final removidos = <ItemComparativo>[];
    final alterados = <ItemComparativo>[];

    final chavesA = estoqueA.keys.toSet();
    final chavesB = estoqueB.keys.toSet();
    final todasChaves = chavesA.union(chavesB);

    double valorTotalA = 0;
    double valorTotalB = 0;
    double qtdTotalA = 0;
    double qtdTotalB = 0;
    int semAlteracao = 0;

    for (final chave in todasChaves) {
      final itemA = estoqueA[chave];
      final itemB = estoqueB[chave];

      final qA = itemA?['quantidade'] as double? ?? 0;
      final qB = itemB?['quantidade'] as double? ?? 0;
      final vuA = itemA?['valor_unitario'] as double? ?? 0;
      final vuB = itemB?['valor_unitario'] as double? ?? 0;
      final vtA = itemA?['valor_total'] as double? ?? 0;
      final vtB = itemB?['valor_total'] as double? ?? 0;

      valorTotalA += vtA;
      valorTotalB += vtB;
      qtdTotalA += qA;
      qtdTotalB += qB;

      TipoAlteracao tipo;
      if (itemA == null) {
        tipo = TipoAlteracao.novo;
      } else if (itemB == null) {
        tipo = TipoAlteracao.removido;
      } else if (qA != qB || (vuA - vuB).abs() > 0.01) {
        tipo = TipoAlteracao.alterado;
      } else {
        tipo = TipoAlteracao.semAlteracao;
        semAlteracao++;
      }

      final diffQtd = qB - qA;
      final diffValor = vtB - vtA;
      final pctVariacao = vtA > 0 ? ((vtB - vtA) / vtA) * 100.0 : (vtB > 0 ? 100.0 : 0.0);

      final item = ItemComparativo(
        codigo: itemA?['codigo'] ?? itemB?['codigo'] ?? chave.split('_').first,
        descricao: itemA?['descricao'] ?? itemB?['descricao'] ?? '',
        lote: itemA?['lote'] ?? itemB?['lote'],
        chave: chave,
        quantidadeA: itemA != null ? qA : null,
        valorUnitarioA: itemA != null ? vuA : null,
        valorTotalA: itemA != null ? vtA : null,
        quantidadeB: itemB != null ? qB : null,
        valorUnitarioB: itemB != null ? vuB : null,
        valorTotalB: itemB != null ? vtB : null,
        diferencaQuantidade: diffQtd,
        diferencaValor: diffValor,
        percentualVariacao: pctVariacao,
        tipo: tipo,
      );

      itens.add(item);

      switch (tipo) {
        case TipoAlteracao.novo:
          novos.add(item);
          break;
        case TipoAlteracao.removido:
          removidos.add(item);
          break;
        case TipoAlteracao.alterado:
          alterados.add(item);
          break;
        case TipoAlteracao.semAlteracao:
          break;
      }
    }

    // Ordena por impacto (maior diferença de valor primeiro)
    itens.sort((a, b) => b.diferencaValor.abs().compareTo(a.diferencaValor.abs()));
    alterados.sort((a, b) => b.diferencaValor.abs().compareTo(a.diferencaValor.abs()));

    final diffValorTotal = valorTotalB - valorTotalA;
    final pctVariacaoTotal = valorTotalA > 0
        ? ((valorTotalB - valorTotalA) / valorTotalA) * 100
        : 0.0;

    final resumo = ResumoComparativo(
      totalItensA: chavesA.length,
      totalItensB: chavesB.length,
      itensEmComum: chavesA.intersection(chavesB).length,
      itensNovos: novos.length,
      itensRemovidos: removidos.length,
      itensAlterados: alterados.length,
      itensSemAlteracao: semAlteracao,
      valorTotalA: valorTotalA,
      valorTotalB: valorTotalB,
      diferencaValor: diffValorTotal,
      percentualVariacao: pctVariacaoTotal,
      quantidadeTotalA: qtdTotalA,
      quantidadeTotalB: qtdTotalB,
      diferencaQuantidade: qtdTotalB - qtdTotalA,
    );

    return ResultadoComparativo(
      inventarioA: inventarioA,
      inventarioB: inventarioB,
      dataGeracao: DateTime.now(),
      resumo: resumo,
      itens: itens,
      novosItens: novos,
      itensRemovidos: removidos,
      itensAlterados: alterados,
    );
  }

  /// Busca estoque do inventário como Map<chave, dados>
  Future<Map<String, Map<String, dynamic>>> _buscarEstoque(String inventarioId) async {
    final snapshot = await _firestore
        .collection('inventarios')
        .doc(inventarioId)
        .collection('estoque')
        .get();

    final mapa = <String, Map<String, dynamic>>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final codigo = data['codigo']?.toString() ?? '';
      final lote = data['lote']?.toString() ?? '';
      final chave = lote.isNotEmpty ? '${codigo}_$lote' : codigo;

      mapa[chave] = {
        'codigo': codigo,
        'descricao': data['descricao'] ?? '',
        'lote': lote.isEmpty ? null : lote,
        'quantidade': (data['quantidade'] ?? 0).toDouble(),
        'valor_unitario': (data['valor_unitario'] ?? 0).toDouble(),
        'valor_total': (data['valor_total'] ?? 0).toDouble(),
      };
    }

    return mapa;
  }

  /// Lista inventários disponíveis para comparação
  Future<List<Inventario>> listarInventariosParaComparacao({
    String? tipoMaterial,
    String? deposito,
    int limite = 20,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('inventarios')
        .where('status', isEqualTo: 'finalizado')
        .orderBy('data_fim', descending: true)
        .limit(limite);

    if (tipoMaterial != null) {
      query = query.where('tipo_material', isEqualTo: tipoMaterial);
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => Inventario.fromFirestore(doc)).toList();
  }
}