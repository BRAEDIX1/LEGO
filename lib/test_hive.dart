import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'data/local/hive_boxes.dart';
import 'data/local/produto_local.dart';
import 'data/local/barra_local.dart';
import 'services/seed_importer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  // 1) REGISTRAR adapters ANTES de abrir
  HiveBoxes.ensureAdapters();

  // 2) Abrir boxes
  final produtos = await HiveBoxes.openProdutos();
  final barras = await HiveBoxes.openBarras();

  print('===== HIVE (ANTES) =====');
  print('Produtos: ${produtos.length}');
  print('Barras  : ${barras.length}');

  // 3) Se estiver vazio, tentar importar seed de alguns caminhos típicos
  if (produtos.isEmpty || barras.isEmpty) {
    final importer = SeedImporter();
    final candidates = <String>[
      'assets/seed/offline.json',
      'assets/seed/seed.json',
      'assets/seed/dump.json',
      'assets/seed/produtos_barras.json',
      'assets/seed/data.json',
    ];

    bool imported = false;
    for (final path in candidates) {
      try {
        print('[SEED] Tentando $path ...');
        await importer.importFromAssetJson(path);
        imported = true;
        print('[SEED] OK em $path');
        break;
      } catch (e) {
        print('[SEED] Falhou em $path: $e');
      }
    }

    if (!imported) {
      print('[SEED] Nenhum caminho padrão funcionou. CONFIRME o caminho do seu JSON e rode de novo:');
      print('       SeedImporter().importFromAssetJson(\'<seu-path>\')');
    }
  }

  print('===== HIVE (DEPOIS) =====');
  print('Produtos: ${produtos.length}');
  if (produtos.isNotEmpty) {
    final p0 = produtos.getAt(0);
    if (p0 is ProdutoLocal) {
      print('Primeiro produto: {codigo=${p0.codigo}, desc=${p0.descricao}, unid=${p0.unidade}, origem=${p0.origem}}');
    } else {
      print('Primeiro produto: $p0');
    }
  }

  print('Barras  : ${barras.length}');
  if (barras.isNotEmpty) {
    final b0 = barras.getAt(0);
    if (b0 is BarraLocal) {
      print('Primeira barra: {tag=${b0.tag}, codigo=${b0.codigo}, lote=${b0.lote ?? ''}}');
    } else {
      print('Primeira barra: $b0');
    }
  }

  // UI simples só para não fechar o app
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Teste Hive/Seed – veja o console')))));
}
