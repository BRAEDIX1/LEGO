import 'dart:developer';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lego/data/local/hive_boxes.dart';
import 'package:lego/services/seed_importer.dart';
import 'package:lego/services/fixed_collections_sync.dart';
import 'package:lego/services/connectivity_service.dart';

/// Garante que o aparelho está pronto para trabalhar 100% offline
/// antes do primeiro lançamento do usuário.
/// - Abre as caixas Hive necessárias
/// - Carrega o seed de assets (materiais + gases + barras)
/// - Faz um full sync das coleções fixas quando houver internet
/// - Inicia o serviço de conectividade (que por sua vez aciona o SyncService)
class OfflineBootstrap {
  static bool _ran = false;

  static Future<void> run(User user) async {
    if (_ran) return;
    _ran = true;

    // Abre as caixas (sem erro se já estiverem abertas)
    await _openBoxes(user.uid);

    // 1) Preenche a partir do JSON de assets (funciona 100% offline)
    await SeedImporter().importFromAssetJson('assets/firestore_dump.json');

    // 2) Se houver internet, completa/atualiza a base local puxando do Firestore
    try {
      await FixedCollectionsSync().fullSync();
    } catch (e) {
      log('[BOOT] fullSync falhou (sem rede?): $e');
    }

    // 3) Começa a escutar conectividade (reenvio de pendentes etc.)
    ConnectivityService().start();
  }

  static Future<void> _openBoxes(String uid) async {
    try { await HiveBoxes.openProdutos(); } catch (_) {}
    try { await HiveBoxes.openBarras(); } catch (_) {}
    try { await HiveBoxes.openUserLancamentos(uid); } catch (_) {}
  }
}
