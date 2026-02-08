// lib/data/local/hive_boxes.dart
import 'package:hive/hive.dart';

import 'package:lego/data/local/lanc_local.dart';
import 'package:lego/data/local/produto_local.dart';
import 'package:lego/data/local/barra_local.dart';

class HiveBoxes {
  static const String produtosBox = 'produtos';
  static const String barrasBox = 'barras';
  static const String appStateBox = 'app_state';

  static void ensureAdapters() {
    if (!Hive.isAdapterRegistered(41)) Hive.registerAdapter(LancStatusAdapter());
    if (!Hive.isAdapterRegistered(42)) Hive.registerAdapter(LancLocalAdapter());
    if (!Hive.isAdapterRegistered(43)) Hive.registerAdapter(TipoRegistroAdapter()); // NOVA LINHA
    if (!Hive.isAdapterRegistered(31)) Hive.registerAdapter(ProdutoLocalAdapter());
    if (!Hive.isAdapterRegistered(32)) Hive.registerAdapter(BarraLocalAdapter());
  }

  static Future<Box<ProdutoLocal>> openProdutos() async {
    if (Hive.isBoxOpen(produtosBox)) return Hive.box<ProdutoLocal>(produtosBox);
    return Hive.openBox<ProdutoLocal>(produtosBox);
  }

  static Future<Box<BarraLocal>> openBarras() async {
    if (Hive.isBoxOpen(barrasBox)) return Hive.box<BarraLocal>(barrasBox);
    return Hive.openBox<BarraLocal>(barrasBox);
  }

  static Future<Box<LancLocal>> openUserLancamentos(String uid) async {
    final name = 'lancamentos_$uid';
    if (Hive.isBoxOpen(name)) return Hive.box<LancLocal>(name);
    return Hive.openBox<LancLocal>(name);
  }

  static Box<LancLocal> lancamentosBox(String uid) {
    return Hive.box<LancLocal>('lancamentos_$uid');
  }

  static Future<void> closeUserLancamentos(String uid) async {
    final name = 'lancamentos_$uid';
    if (Hive.isBoxOpen(name)) {
      await Hive.box(name).close();
    }
  }
}
