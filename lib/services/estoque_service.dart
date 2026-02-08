// lib/services/estoque_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Serviço para gerenciamento de estoque
/// Responsável por importação e consulta de dados de estoque
class EstoqueService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== IMPORTAÇÃO PARA INVENTÁRIO ====================

  /// Importa estoque para a subcoleção de um inventário específico
  ///
  /// Estrutura: inventarios/{inventarioId}/estoque/{codigo_lote}
  Future<Map<String, dynamic>> importarEstoqueParaInventario({
    required String inventarioId,
    required List<Map<String, dynamic>> itens,
  }) async {
    try {
      int sucesso = 0;
      int falhas = 0;
      final erros = <String>[];

      // Referência para a subcoleção de estoque do inventário
      final estoqueRef = _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('estoque');

      // Processa em batches de 500 (limite do Firestore)
      final batches = <WriteBatch>[];
      var currentBatch = _firestore.batch();
      int operacoes = 0;

      for (var item in itens) {
        try {
          final codigo = item['codigo'] as String?;
          if (codigo == null || codigo.isEmpty) {
            falhas++;
            erros.add('Item sem código');
            continue;
          }

          // Monta chave única: codigo ou codigo_lote
          final lote = item['lote']?.toString() ?? '';
          final docId = lote.isEmpty ? codigo : '${codigo}_$lote';

          final docRef = estoqueRef.doc(docId);
          currentBatch.set(docRef, {
            'codigo': codigo,
            'descricao': item['descricao'] ?? '',
            'lote': lote,
            'quantidade': _toDouble(item['quantidade']),
            'valor_total': _toDouble(item['valor_total']),
            'valor_unitario': _toDouble(item['valor_unitario']),
            'importado_em': FieldValue.serverTimestamp(),
          });

          operacoes++;
          sucesso++;

          // Firestore batch tem limite de 500 operações
          if (operacoes >= 500) {
            batches.add(currentBatch);
            currentBatch = _firestore.batch();
            operacoes = 0;
          }
        } catch (e) {
          falhas++;
          erros.add('Erro no item ${item['codigo']}: $e');
        }
      }

      // Adiciona último batch se houver operações pendentes
      if (operacoes > 0) {
        batches.add(currentBatch);
      }

      // Executa todos os batches
      for (var batch in batches) {
        await batch.commit();
      }

      debugPrint('✅ Estoque importado para inventário $inventarioId: $sucesso sucesso, $falhas falhas');

      return {
        'sucesso': sucesso,
        'falhas': falhas,
        'total': itens.length,
        'erros': erros,
      };
    } catch (e) {
      debugPrint('❌ Erro ao importar estoque: $e');
      return {
        'sucesso': 0,
        'falhas': itens.length,
        'total': itens.length,
        'erros': [e.toString()],
      };
    }
  }

  /// Busca estoque de um inventário específico
  Future<List<Map<String, dynamic>>> buscarEstoqueInventario(
      String inventarioId, {
        int limite = 1000,
      }) async {
    try {
      final snapshot = await _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('estoque')
          .limit(limite)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'codigo': data['codigo'],
          'descricao': data['descricao'] ?? '',
          'lote': data['lote'] ?? '',
          'quantidade': (data['quantidade'] ?? 0.0).toDouble(),
          'valor_unitario': (data['valor_unitario'] ?? 0.0).toDouble(),
          'valor_total': (data['valor_total'] ?? 0.0).toDouble(),
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ Erro ao buscar estoque do inventário: $e');
      return [];
    }
  }

  /// Stream de estoque de um inventário
  Stream<List<Map<String, dynamic>>> streamEstoqueInventario(String inventarioId) {
    return _firestore
        .collection('inventarios')
        .doc(inventarioId)
        .collection('estoque')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'codigo': data['codigo'],
          'descricao': data['descricao'] ?? '',
          'lote': data['lote'] ?? '',
          'quantidade': (data['quantidade'] ?? 0.0).toDouble(),
          'valor_unitario': (data['valor_unitario'] ?? 0.0).toDouble(),
          'valor_total': (data['valor_total'] ?? 0.0).toDouble(),
        };
      }).toList();
    });
  }

  /// Busca um item de estoque específico do inventário
  Future<Map<String, dynamic>?> buscarItemEstoque(
      String inventarioId,
      String codigo, {
        String? lote,
      }) async {
    try {
      final docId = (lote?.isEmpty ?? true) ? codigo : '${codigo}_$lote';

      final doc = await _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('estoque')
          .doc(docId)
          .get();

      if (!doc.exists) {
        debugPrint('⚠️ Item $docId não encontrado no estoque');
        return null;
      }

      final data = doc.data()!;
      return {
        'id': doc.id,
        'codigo': data['codigo'],
        'descricao': data['descricao'] ?? '',
        'lote': data['lote'] ?? '',
        'quantidade': (data['quantidade'] ?? 0.0).toDouble(),
        'valor_unitario': (data['valor_unitario'] ?? 0.0).toDouble(),
        'valor_total': (data['valor_total'] ?? 0.0).toDouble(),
      };
    } catch (e) {
      debugPrint('❌ Erro ao buscar item: $e');
      return null;
    }
  }

  /// Estatísticas do estoque de um inventário
  Future<Map<String, dynamic>> getEstatisticasEstoque(String inventarioId) async {
    try {
      final snapshot = await _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('estoque')
          .get();

      double valorTotal = 0.0;
      double quantidadeTotal = 0.0;
      int comLote = 0;
      int semLote = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        valorTotal += (data['valor_total'] ?? 0.0).toDouble();
        quantidadeTotal += (data['quantidade'] ?? 0.0).toDouble();

        final lote = data['lote']?.toString() ?? '';
        if (lote.isNotEmpty) {
          comLote++;
        } else {
          semLote++;
        }
      }

      return {
        'total_itens': snapshot.size,
        'valor_total': valorTotal,
        'quantidade_total': quantidadeTotal,
        'itens_com_lote': comLote,
        'itens_sem_lote': semLote,
      };
    } catch (e) {
      debugPrint('❌ Erro ao obter estatísticas: $e');
      return {'erro': e.toString()};
    }
  }

  // ==================== MÉTODOS LEGADOS (coleção raiz) ====================

  /// Busca um produto completo (JOIN materiais + estoque) - LEGADO
  Future<Map<String, dynamic>?> getProdutoCompleto(String codigo) async {
    try {
      // Busca dados cadastrais (materiais)
      final materialDoc = await _firestore
          .collection('materiais')
          .where('material', isEqualTo: codigo)
          .limit(1)
          .get();

      if (materialDoc.docs.isEmpty) {
        debugPrint('⚠️ Material $codigo não encontrado');
        return null;
      }

      final materialData = materialDoc.docs.first.data();

      // Busca dados de estoque
      final estoqueDoc = await _firestore
          .collection('estoque')
          .where('codigo', isEqualTo: codigo)
          .limit(1)
          .get();

      if (estoqueDoc.docs.isEmpty) {
        debugPrint('⚠️ Estoque para $codigo não encontrado');
        return {
          'codigo': codigo,
          'descricao': materialData['descricao'] ?? '',
          'unidade': materialData['unidade'] ?? 'UN',
          'quantidade_sistema': 0.0,
          'valor_unitario': 0.0,
          'deposito': null,
        };
      }

      final estoqueData = estoqueDoc.docs.first.data();

      // Retorna JOIN completo
      return {
        'codigo': codigo,
        'descricao': materialData['descricao'] ?? '',
        'unidade': materialData['unidade'] ?? 'UN',
        'quantidade_sistema': (estoqueData['quantidade'] ?? 0.0).toDouble(),
        'valor_unitario': (estoqueData['valor_unitario'] ?? 0.0).toDouble(),
        'deposito': estoqueData['deposito'],
      };
    } catch (e) {
      debugPrint('❌ Erro ao buscar produto completo: $e');
      return null;
    }
  }

  /// Importa estoque a partir de uma lista de itens - LEGADO (coleção raiz)
  Future<Map<String, dynamic>> importarEstoque(
      List<Map<String, dynamic>> itens,
      ) async {
    try {
      int sucesso = 0;
      int falhas = 0;
      final erros = <String>[];

      final batch = _firestore.batch();
      int operacoes = 0;

      for (var item in itens) {
        try {
          final codigo = item['codigo'] as String?;
          if (codigo == null || codigo.isEmpty) {
            falhas++;
            erros.add('Item sem código');
            continue;
          }

          final quantidade = _toDouble(item['quantidade']);
          final valorUnitario = _toDouble(item['valor_unitario']);
          final deposito = item['deposito'] as String?;

          // Cria documento na coleção estoque/
          final docRef = _firestore.collection('estoque').doc();
          batch.set(docRef, {
            'codigo': codigo,
            'quantidade': quantidade,
            'valor_unitario': valorUnitario,
            'deposito': deposito,
            'atualizado_em': FieldValue.serverTimestamp(),
          });

          operacoes++;
          sucesso++;

          // Firestore batch tem limite de 500 operações
          if (operacoes >= 500) {
            await batch.commit();
            operacoes = 0;
          }
        } catch (e) {
          falhas++;
          erros.add('Erro no item ${item['codigo']}: $e');
        }
      }

      // Commit final se houver operações pendentes
      if (operacoes > 0) {
        await batch.commit();
      }

      debugPrint('✅ Importação concluída: $sucesso sucesso, $falhas falhas');

      return {
        'sucesso': sucesso,
        'falhas': falhas,
        'total': itens.length,
        'erros': erros,
      };
    } catch (e) {
      debugPrint('❌ Erro ao importar estoque: $e');
      return {
        'sucesso': 0,
        'falhas': itens.length,
        'total': itens.length,
        'erros': [e.toString()],
      };
    }
  }

  /// Valida arquivo de importação antes de processar
  List<String> validarArquivoImportacao(List<Map<String, dynamic>> itens) {
    final erros = <String>[];

    if (itens.isEmpty) {
      erros.add('Arquivo vazio');
      return erros;
    }

    // Valida colunas obrigatórias
    final primeiroItem = itens.first;
    if (!primeiroItem.containsKey('codigo')) {
      erros.add('Coluna "codigo" não encontrada');
    }
    if (!primeiroItem.containsKey('quantidade')) {
      erros.add('Coluna "quantidade" não encontrada');
    }

    // Valida cada item
    for (int i = 0; i < itens.length; i++) {
      final item = itens[i];
      final linha = i + 2; // +2 porque linha 1 é cabeçalho

      if (item['codigo'] == null || item['codigo'].toString().isEmpty) {
        erros.add('Linha $linha: Código vazio');
      }

      final qtd = _toDouble(item['quantidade']);
      if (qtd < 0) {
        erros.add('Linha $linha: Quantidade negativa');
      }
    }

    return erros;
  }

  /// Lista todos os itens de estoque - LEGADO
  Future<List<Map<String, dynamic>>> listarEstoque({
    int limite = 100,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('estoque')
          .limit(limite)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'codigo': data['codigo'],
          'quantidade': (data['quantidade'] ?? 0.0).toDouble(),
          'valor_unitario': (data['valor_unitario'] ?? 0.0).toDouble(),
          'deposito': data['deposito'],
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ Erro ao listar estoque: $e');
      return [];
    }
  }

  /// Busca estatísticas do estoque - LEGADO
  Future<Map<String, dynamic>> getEstatisticas() async {
    try {
      final snapshot = await _firestore.collection('estoque').get();

      double valorTotal = 0.0;
      int totalItens = snapshot.size;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final quantidade = (data['quantidade'] ?? 0.0).toDouble();
        final valorUnitario = (data['valor_unitario'] ?? 0.0).toDouble();
        valorTotal += quantidade * valorUnitario;
      }

      return {
        'total_itens': totalItens,
        'valor_total': valorTotal,
        'valor_medio': totalItens > 0 ? valorTotal / totalItens : 0.0,
      };
    } catch (e) {
      debugPrint('❌ Erro ao obter estatísticas: $e');
      return {
        'erro': e.toString(),
      };
    }
  }

  // ========== MÉTODOS AUXILIARES ==========

  /// Converte valor para double com fallback
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
}