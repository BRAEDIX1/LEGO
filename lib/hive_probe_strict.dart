import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart' as pp;

import 'data/local/hive_boxes.dart';
import 'data/local/produto_local.dart';
import 'data/local/barra_local.dart';

void main() => runApp(const MaterialApp(
  debugShowCheckedModeBanner: false,
  home: HiveProbeStrict(),
));

class HiveProbeStrict extends StatefulWidget {
  const HiveProbeStrict({super.key});
  @override
  State<HiveProbeStrict> createState() => _HiveProbeStrictState();
}

class _HiveProbeStrictState extends State<HiveProbeStrict> {
  String _log = '...';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final buff = StringBuffer();
    try {
      WidgetsFlutterBinding.ensureInitialized();

      // (apenas informativo) diretório padrão de documentos do app
      try {
        final dir = await pp.getApplicationDocumentsDirectory();
        buff.writeln('App documents dir: ${dir.path}');
      } catch (e, st) {
        buff.writeln('WARN: getApplicationDocumentsDirectory -> $e\n$st');
      }

      await Hive.initFlutter();

      // 1) Adapters
      try {
        HiveBoxes.ensureAdapters();
        buff.writeln('Adapters registered? '
            '31=${Hive.isAdapterRegistered(31)}, '
            '32=${Hive.isAdapterRegistered(32)}, '
            '41=${Hive.isAdapterRegistered(41)}, '
            '42=${Hive.isAdapterRegistered(42)}');
      } catch (e, st) {
        buff.writeln('ERROR: ensureAdapters -> $e\n$st');
      }

      // 2) Box simples (tipos primitivos) – prova de vida do Hive
      try {
        final ping = await Hive.openBox<String>('__probe__');
        await ping.put('k', 'ok');
        final got = ping.get('k');
        buff.writeln("Probe box('__probe__'): len=${ping.length}, get('k')=$got");
        await ping.close();
      } catch (e, st) {
        buff.writeln("ERROR: probe box('__probe__') -> $e\n$st");
      }

      // 3) Abrir boxes tipadas
      Box<ProdutoLocal>? produtos;
      Box<BarraLocal>? barras;
      try {
        produtos = await HiveBoxes.openProdutos();
        barras   = await HiveBoxes.openBarras();
        buff.writeln("Open produtos: len=${produtos.length}");
        buff.writeln("Open barras  : len=${barras.length}");
      } catch (e, st) {
        buff.writeln('ERROR: open produtos/barras -> $e\n$st');
      }

      // 4) Tentar escrever amostras
      try {
        if (produtos != null && barras != null) {
          if (produtos.isEmpty) {
            await produtos.put('40000008', ProdutoLocal(
              codigo: '40000008', descricao: 'CIL O2 10L', unidade: 'UN', origem: 'gases',
            ));
            await produtos.put('12345', ProdutoLocal(
              codigo: '12345', descricao: 'REGULADOR', unidade: 'UN', origem: 'materiais',
            ));
            await produtos.flush();
          }
          if (barras.isEmpty) {
            await barras.put('TAG-ABC-001', BarraLocal(
              tag: 'TAG-ABC-001', codigo: '40000008', lote: 'L-TESTE',
            ));
            await barras.flush();
          }
          buff.writeln('After sample writes: produtos=${produtos.length}, barras=${barras.length}');
        }
      } catch (e, st) {
        buff.writeln('ERROR: writing samples -> $e\n$st');
      }

      // 5) Ler primeiras chaves/itens
      try {
        if (produtos != null) {
          final keys = produtos.keys.take(10).toList();
          buff.writeln('Produtos keys: $keys');
          if (produtos.isNotEmpty) {
            buff.writeln('Produtos[0]: ${produtos.getAt(0)}');
          }
        }
        if (barras != null) {
          final keys = barras.keys.take(10).toList();
          buff.writeln('Barras keys: $keys');
          if (barras.isNotEmpty) {
            buff.writeln('Barras[0]: ${barras.getAt(0)}');
          }
        }
      } catch (e, st) {
        buff.writeln('ERROR: reading first items -> $e\n$st');
      }
    } catch (e, st) {
      buff.writeln('FATAL: $e\n$st');
    }

    setState(() {
      _log = buff.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hive Probe (strict)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          _log,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ),
    );
  }
}
