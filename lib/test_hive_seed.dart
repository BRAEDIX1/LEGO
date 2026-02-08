import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';
import 'data/local/hive_boxes.dart';
import 'data/local/produto_local.dart';
import 'data/local/barra_local.dart';
import 'services/seed_importer.dart';

void main() => runApp(const MaterialApp(
  debugShowCheckedModeBanner: false,
  home: TestHiveSeedPage(),
));

class TestHiveSeedPage extends StatefulWidget {
  const TestHiveSeedPage({super.key});
  @override
  State<TestHiveSeedPage> createState() => _TestHiveSeedPageState();
}

class _TestHiveSeedPageState extends State<TestHiveSeedPage> {
  late final Future<_Probe> _future = _run();

  Future<_Probe> _run() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Hive.initFlutter();

    // 1) REGISTRAR adapters ANTES de abrir
    HiveBoxes.ensureAdapters();

    // 2) Abrir boxes
    final produtos = await HiveBoxes.openProdutos();
    final barras   = await HiveBoxes.openBarras();

    // 3) TENTAR importar seed se estiver vazio (com auto-descoberta de asset)
    if (produtos.isEmpty || barras.isEmpty) {
      final importer = SeedImporter();

      // (a) tenta caminhos comuns
      final candidates = <String>[
        'assets/seed/offline.json',
        'assets/seed/seed.json',
        'assets/seed/dump.json',
        'assets/seed/produtos_barras.json',
        'assets/seed/data.json',
      ];
      bool imported = false;

      for (final p in candidates) {
        try {
          await importer.importFromAssetJson(p);
          imported = true;
          debugPrint('[SEED] OK: $p');
          break;
        } catch (_) {}
      }

      // (b) se ainda não, ler o AssetManifest e procurar qualquer .json sob assets/seed/
      if (!imported) {
        try {
          final manifest = await rootBundle.loadString('AssetManifest.json');
          final Map<String, dynamic> map = json.decode(manifest);
          final seeds = map.keys.where((k) =>
          k.toLowerCase().startsWith('assets/seed/') &&
              k.toLowerCase().endsWith('.json')).toList();
          for (final k in seeds) {
            try {
              await importer.importFromAssetJson(k);
              imported = true;
              debugPrint('[SEED] OK via manifest: $k');
              break;
            } catch (_) {}
          }
        } catch (_) {}
      }

      // (c) se continuar vazio, GRAVA EXEMPLOS (prova de escrita/leitura)
      if (!imported && (produtos.isEmpty || barras.isEmpty)) {
        debugPrint('[SEED] Nenhum asset de seed encontrado. Criando amostras locais.');
        await _writeSamples(produtos, barras);
      }
    }

    // 4) Coletar resultados
    final prodKeys = produtos.keys.take(10).toList();
    final barKeys  = barras.keys.take(10).toList();

    List<Map<String, dynamic>> prodSample = [];
    for (var i = 0; i < (produtos.length < 5 ? produtos.length : 5); i++) {
      final p = produtos.getAt(i);
      if (p is ProdutoLocal) {
        prodSample.add({
          'codigo': p.codigo,
          'descricao': p.descricao,
          'unidade': p.unidade,
          'origem': p.origem,
        });
      }
    }

    List<Map<String, dynamic>> barSample = [];
    for (var i = 0; i < (barras.length < 5 ? barras.length : 5); i++) {
      final b = barras.getAt(i);
      if (b is BarraLocal) {
        barSample.add({
          'tag': b.tag,
          'codigo': b.codigo,
          'lote': b.lote ?? '',
        });
      }
    }

    return _Probe(
      produtosCount: produtos.length,
      barrasCount: barras.length,
      produtosKeys: prodKeys,
      barrasKeys: barKeys,
      produtosSample: prodSample,
      barrasSample: barSample,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hive / Seed – Verificador')),
      body: FutureBuilder<_Probe>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText('ERRO: ${snap.error}\n${snap.stackTrace}'),
            );
          }
          final d = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _stat('Produtos', d.produtosCount),
              _stat('Barras', d.barrasCount),
              const SizedBox(height: 12),
              _section('Chaves de Produtos (até 10)', d.produtosKeys),
              _section('Chaves de Barras (até 10)', d.barrasKeys),
              const SizedBox(height: 12),
              _section('Amostra de Produtos (até 5)', d.produtosSample),
              _section('Amostra de Barras (até 5)', d.barrasSample),
              const SizedBox(height: 24),
              const Text(
                'Se agora aparecem itens, o Hive está OK.\n'
                    'Se as contagens continuam 0/0, ou o asset não está listado no pubspec.yaml, '
                    'ou você está rodando em um ambiente sem o seed empacotado.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _writeSamples(Box<ProdutoLocal> produtos, Box<BarraLocal> barras) async {
    // grava 2 produtos e 1 barra mapeando para um deles
    await produtos.put('40000008', ProdutoLocal(
      codigo: '40000008', descricao: 'CILINDRO OXIGÊNIO 10L', unidade: 'UN', origem: 'gases',
    ));
    await produtos.put('12345', ProdutoLocal(
      codigo: '12345', descricao: 'REGULADOR PRESSÃO', unidade: 'UN', origem: 'materiais',
    ));
    await barras.put('TAG-ABC-001', BarraLocal(
      tag: 'TAG-ABC-001', codigo: '40000008', lote: 'L-TESTE',
    ));
    await produtos.flush();
    await barras.flush();
  }

  Widget _stat(String label, int value) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 18))),
        Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _section(String title, Object data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          '$title:\n$data',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ),
    );
  }
}

class _Probe {
  final int produtosCount;
  final int barrasCount;
  final List<dynamic> produtosKeys;
  final List<dynamic> barrasKeys;
  final List<Map<String, dynamic>> produtosSample;
  final List<Map<String, dynamic>> barrasSample;

  _Probe({
    required this.produtosCount,
    required this.barrasCount,
    required this.produtosKeys,
    required this.barrasKeys,
    required this.produtosSample,
    required this.barrasSample,
  });
}