// lib/services/seed_bootstrap.dart
import 'package:hive/hive.dart';
import 'package:lego/data/local/hive_boxes.dart';
import 'package:lego/services/seed_importer.dart';

class SeedBootstrap {
  static const _stateBox = HiveBoxes.appStateBox;
  static const _seedFlagKey = 'seed_v1_done';

  /// ✅ NOVO: Versão COM progresso via Stream
  static Stream<SyncProgress> ensureSeedOnceWithProgress({
    String assetPath = 'assets/firestore_dump.json',
  }) async* {
    // 1) Adapters ANTES de abrir qualquer box
    HiveBoxes.ensureAdapters();

    // 2) Abrir boxes necessárias
    final produtos = await HiveBoxes.openProdutos();
    final barras = await HiveBoxes.openBarras();

    // 3) Estado do app (flag idempotente)
    final state = await (Hive.isBoxOpen(_stateBox)
        ? Future.value(Hive.box(_stateBox))
        : Hive.openBox(_stateBox));

    final already = state.get(_seedFlagKey) == true;

    // Se já importou e as boxes têm dados, retorna concluído imediatamente
    if (already && produtos.isNotEmpty && barras.isNotEmpty) {
      yield SyncProgress(
        etapa: 'concluido',
        atual: 100,
        total: 100,
        percentual: 1.0,
        mensagem: 'Dados já sincronizados',
      );
      return;
    }

    // 4) Se estiver vazio OU flag não marcada, importa COM progresso
    try {
      await for (final progress in SeedImporter().importFromAssetJsonWithProgress(assetPath)) {
        yield progress;

        // Se concluiu, marca flag
        if (progress.percentual >= 1.0 && progress.etapa == 'concluido') {
          await state.put(_seedFlagKey, true);
          await state.flush();
        }
      }
    } catch (e) {
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
  static Future<void> ensureSeedOnce({
    String assetPath = 'assets/firestore_dump.json',
  }) async {
    await for (final _ in ensureSeedOnceWithProgress(assetPath: assetPath)) {
      // Consome stream mas não faz nada com progresso
    }
  }
}