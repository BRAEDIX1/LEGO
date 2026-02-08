import 'dart:convert';
import 'dart:developer';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive/hive.dart';

import 'package:lego/data/local/produto_local.dart';
import 'package:lego/data/local/barra_local.dart';
import 'package:lego/data/local/hive_boxes.dart';

/// Modelo de progresso da sincronização
class SyncProgress {
  final String etapa;
  final int atual;
  final int total;
  final double percentual;
  final String mensagem;

  SyncProgress({
    required this.etapa,
    required this.atual,
    required this.total,
    required this.percentual,
    required this.mensagem,
  });

  String get percentualFormatado => '${(percentual * 100).toInt()}%';
}

/// Importa um seed de assets para as boxes locais (produtos + barras).
class SeedImporter {

  /// ✅ NOVO: Versão COM progresso via Stream
  Stream<SyncProgress> importFromAssetJsonWithProgress(String assetPath) async* {
    try {
      // Fase 1: Lendo arquivo
      yield SyncProgress(
        etapa: 'lendo_arquivo',
        atual: 0,
        total: 100,
        percentual: 0.05,
        mensagem: 'Lendo arquivo de dados...',
      );

      final jsonString = await rootBundle.loadString(assetPath);
      if (jsonString.isEmpty) {
        yield SyncProgress(
          etapa: 'concluido',
          atual: 100,
          total: 100,
          percentual: 1.0,
          mensagem: 'Sincronização concluída',
        );
        return;
      }

      // Fase 2: Decodificando JSON
      yield SyncProgress(
        etapa: 'decodificando',
        atual: 5,
        total: 100,
        percentual: 0.10,
        mensagem: 'Processando dados...',
      );

      final Map<String, dynamic> dump = json.decode(jsonString);

      final produtosBox = Hive.box<ProdutoLocal>(HiveBoxes.produtosBox);
      final barrasBox = Hive.box<BarraLocal>(HiveBoxes.barrasBox);

      // Contar totais para progresso correto
      final materiais = (dump['materiais'] as Map?) ?? const {};
      final gases = (dump['gases'] as Map?) ?? const {};
      final barras = (dump['barras'] as Map?) ?? const {};

      final totalMateriais = materiais.length;
      final totalGases = gases.length;
      final totalBarras = barras.length;
      final totalGeral = totalMateriais + totalGases + totalBarras;

      int processados = 0;

      // Fase 3: Processar Materiais
      yield SyncProgress(
        etapa: 'materiais',
        atual: 0,
        total: totalMateriais,
        percentual: 0.15,
        mensagem: 'Importando materiais...',
      );

      final produtosBatch = <String, ProdutoLocal>{};
      for (final entry in materiais.entries) {
        final codigo = entry.key.toString();
        final data = entry.value as Map<String, dynamic>;
        final p = ProdutoLocal(
          codigo: codigo,
          descricao: (data['descricao'] ?? '').toString(),
          unidade: (data['unidade'] ?? '').toString(),
          origem: 'materiais',
          updatedAt: DateTime.tryParse((data['updatedAt'] ?? '').toString()),
        );
        produtosBatch[codigo] = p;
        processados++;

        // ✅ Emitir progresso a cada 100 itens
        if (processados % 100 == 0 || processados == totalMateriais) {
          await produtosBox.putAll(produtosBatch);
          produtosBatch.clear();

          yield SyncProgress(
            etapa: 'materiais',
            atual: processados,
            total: totalGeral,
            percentual: 0.15 + (0.35 * (processados / totalGeral)),
            mensagem: 'Materiais: $processados de $totalMateriais',
          );
        }
      }
      if (produtosBatch.isNotEmpty) {
        await produtosBox.putAll(produtosBatch);
      }

      // Fase 4: Processar Gases
      yield SyncProgress(
        etapa: 'gases',
        atual: processados,
        total: totalGeral,
        percentual: 0.50,
        mensagem: 'Importando gases...',
      );

      final gasesBatch = <String, ProdutoLocal>{};
      for (final entry in gases.entries) {
        final codigo = entry.key.toString();
        final data = entry.value as Map<String, dynamic>;
        final p = ProdutoLocal(
          codigo: codigo,
          descricao: (data['descricao'] ?? '').toString(),
          unidade: (data['unidade'] ?? '').toString(),
          origem: 'gases',
          updatedAt: DateTime.tryParse((data['updatedAt'] ?? '').toString()),
        );
        gasesBatch[codigo] = p;
        processados++;

        // ✅ Emitir progresso a cada 100 itens
        if (processados % 100 == 0 || processados == (totalMateriais + totalGases)) {
          await produtosBox.putAll(gasesBatch);
          gasesBatch.clear();

          yield SyncProgress(
            etapa: 'gases',
            atual: processados,
            total: totalGeral,
            percentual: 0.50 + (0.25 * ((processados - totalMateriais) / totalGases)),
            mensagem: 'Gases: ${processados - totalMateriais} de $totalGases',
          );
        }
      }
      if (gasesBatch.isNotEmpty) {
        await produtosBox.putAll(gasesBatch);
      }

      // Fase 5: Processar Barras
      yield SyncProgress(
        etapa: 'barras',
        atual: processados,
        total: totalGeral,
        percentual: 0.75,
        mensagem: 'Importando códigos de barras...',
      );

      final barrasBatch = <String, BarraLocal>{};
      int barrasProcessadas = 0;
      for (final entry in barras.entries) {
        final tag = entry.key.toString();
        final data = entry.value as Map<String, dynamic>;
        final b = BarraLocal(
          codigo: (data['codigo'] ?? '').toString(),
          lote: (data['lote'] ?? '').toString(),
          tag: tag,
          updatedAt: DateTime.tryParse((data['updatedAt'] ?? '').toString()),
        );
        barrasBatch[tag] = b;
        barrasProcessadas++;
        processados++;

        // ✅ Emitir progresso a cada 100 itens
        if (barrasProcessadas % 100 == 0 || barrasProcessadas == totalBarras) {
          await barrasBox.putAll(barrasBatch);
          barrasBatch.clear();

          yield SyncProgress(
            etapa: 'barras',
            atual: processados,
            total: totalGeral,
            percentual: 0.75 + (0.20 * (barrasProcessadas / totalBarras)),
            mensagem: 'Códigos de barras: $barrasProcessadas de $totalBarras',
          );
        }
      }
      if (barrasBatch.isNotEmpty) {
        await barrasBox.putAll(barrasBatch);
      }

      // Fase 6: Concluído
      yield SyncProgress(
        etapa: 'concluido',
        atual: totalGeral,
        total: totalGeral,
        percentual: 1.0,
        mensagem: 'Sincronização concluída com sucesso!',
      );

      log('[SEED] Importado de $assetPath; produtos=${totalMateriais + totalGases} barras=$totalBarras');

    } catch (e, st) {
      log('[SEED] Erro ao importar JSON de $assetPath: $e', stackTrace: st);

      yield SyncProgress(
        etapa: 'erro',
        atual: 0,
        total: 100,
        percentual: 0.0,
        mensagem: 'Erro ao sincronizar: $e',
      );
    }
  }

  /// ⚠️ MANTER: Versão antiga sem progresso (para compatibilidade)
  Future<void> importFromAssetJson(String assetPath) async {
    await for (final _ in importFromAssetJsonWithProgress(assetPath)) {
      // Consome stream mas não faz nada com progresso
    }
  }
}