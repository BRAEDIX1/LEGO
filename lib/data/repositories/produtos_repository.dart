// lib/data/repositories/produtos_repository.dart
import 'package:hive/hive.dart';
import 'package:lego/data/local/hive_boxes.dart';
import 'package:lego/data/local/produto_local.dart';
import 'package:diacritic/diacritic.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ProdutosRepository {
  Future<Box<ProdutoLocal>> _open() async =>
      Hive.isBoxOpen(HiveBoxes.produtosBox)
          ? Hive.box<ProdutoLocal>(HiveBoxes.produtosBox)
          : await Hive.openBox<ProdutoLocal>(HiveBoxes.produtosBox);

  Future<ProdutoLocal?> getByCodigoPreferGases(String codigo) async {
    final box = await _open();
    final p = box.get(codigo);
    if (p == null) return null;
    if (p.origem == 'gases') return p;
    return p;
  }

  // Adicionar novo produto manual
  Future<ProdutoLocal> addManualProduct({
    required String codigo,
    required String descricao,
    required String unidade,
    double? volume,
  }) async {
    final box = await _open();

    // Verifica se já existe
    final existing = box.get(codigo);
    if (existing != null) {
      return existing;
    }

    final produto = ProdutoLocal(
      codigo: codigo,
      descricao: descricao,
      unidade: unidade,
      origem: 'manual', // Marca como origem manual
      updatedAt: DateTime.now(),
    );

    await box.put(codigo, produto);

    // Tenta sincronizar com Firestore
    try {
      await FirebaseFirestore.instance
          .collection('produtos_manuais')
          .doc(codigo)
          .set({
        'codigo': codigo,
        'descricao': descricao,
        'unidade': unidade,
        'volume': volume,
        'origem': 'manual',
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    } catch (e) {
      // Se falhar, continua com registro local
      print('Erro ao sincronizar produto manual: $e');
    }

    return produto;
  }

  Future<void> logAvailableKeys() async {
    final box = await _open();
    print('[Diag] Keys disponíveis em ${box.name}: ${box.keys.take(20).toList()}');
  }

  // Método atualizado para busca composta com suporte a acentos e termos parciais
  Future<List<String>> searchCodigosOuDescricoes(String query) async {
    final box = await _open();

    // Validação de entrada
    final q = query.trim();
    if (q.isEmpty) return [];

    try {
      // Normalizar com segurança (manter números intactos)
      final normalizedQuery = _normalizeQuerySafely(q);

      // Split com validação de palavras vazias
      final palavras = normalizedQuery
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty)
          .toList();

      if (palavras.isEmpty) return [];

      final resultados = <String>[];

      // Busca com limite para evitar processar milhares de itens
      for (final p in box.values) {
        final codigoNorm = _normalizeQuerySafely(p.codigo);
        final descricaoNorm = _normalizeQuerySafely(p.descricao);

        bool todasEncontradas = palavras.every((palavra) =>
        codigoNorm.contains(palavra) || descricaoNorm.contains(palavra)
        );

        if (todasEncontradas) {
          final origem = p.origem == 'manual' ? ' (Manual)' : '';
          resultados.add('${p.codigo} • ${p.descricao}$origem');
        }

        // Limite de resultados (evita processar toda a box)
        if (resultados.length >= 100) break;
      }

      // Ordenação segura
      resultados.sort((a, b) {
        final codigoA = a.split(' • ')[0].toLowerCase();
        final codigoB = b.split(' • ')[0].toLowerCase();

        // Priorizar match exato no início do código
        if (codigoA.startsWith(normalizedQuery)) return -1;
        if (codigoB.startsWith(normalizedQuery)) return 1;

        // Depois match parcial no código
        if (codigoA.contains(normalizedQuery)) return -1;
        if (codigoB.contains(normalizedQuery)) return 1;

        // Ordenação alfabética padrão
        return codigoA.compareTo(codigoB);
      });

      return resultados.take(50).toList();

    } catch (e, stackTrace) {
      // Log do erro mas não crasha app
      debugPrint('❌ Erro na busca de produtos: $e');
      debugPrint('Stack: $stackTrace');
      return []; // Retorna vazio em caso de erro
    }
  }

  /// Normaliza query de forma segura, mantendo números intactos
  String _normalizeQuerySafely(String text) {
    try {
      final lower = text.toLowerCase();

      // Se for puramente numérico, retorna direto (evita problema com diacritics)
      if (RegExp(r'^\d+$').hasMatch(lower)) {
        return lower;
      }

      // Se tem letras, remove diacríticos normalmente
      return removeDiacritics(lower);
    } catch (e) {
      // Fallback: retorna lowercase simples se der erro
      debugPrint('⚠️ Erro ao normalizar texto: $e');
      return text.toLowerCase();
    }
  }
}