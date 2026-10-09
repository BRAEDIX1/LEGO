// lib/ui/mobile/screens/comparativo_screen.dart
//
// Relatório do inventário NA TELA, igual ao .xlsx (modelo do Djalma, 09/10):
// abas C1 Lançamentos · C1 Consolidado · C2 Lançamentos · C2 Consolidado ·
// C3 · Final. As abas vêm do mesmo montador do arquivo
// (relatorio_inventario.dart), então tela e planilha nunca divergem.

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/services/comparativo.dart';
import 'package:lego/services/comparativo_rodadas_service.dart';
import 'package:lego/services/relatorio_inventario.dart';
import 'package:lego/services/relatorio_inventario_service.dart';

class ComparativoScreen extends StatefulWidget {
  final String inventarioId;
  final String numeroFormatado;
  /// Tipo do inventário (define as abas; null = antigo: os três).
  final Natureza? tipo;
  /// Consolidado da C3 (para o resumo; num inventário com tipo é o tipo).
  final Natureza? naturezaC3;

  const ComparativoScreen({
    super.key,
    required this.inventarioId,
    required this.numeroFormatado,
    this.tipo,
    this.naturezaC3,
  });

  @override
  State<ComparativoScreen> createState() => _ComparativoScreenState();
}

class _ComparativoScreenState extends State<ComparativoScreen> {
  final _cmp = ComparativoRodadasService();
  bool _carregando = true;
  bool _exportando = false;
  String? _erro;
  List<AbaRelatorio> _abas = const [];
  List<LinhaComparativo> _linhas = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final (raw1, res1) =
          await _cmp.carregarRodadaCompleta(widget.inventarioId, Rodadas.c1);
      final (raw2, res2) =
          await _cmp.carregarRodadaCompleta(widget.inventarioId, Rodadas.c2);
      final linhas = await _cmp.lerComparativo(widget.inventarioId);
      final abas = montarRelatorio(
        numero: widget.numeroFormatado,
        tipo: widget.tipo, // igual ao .xlsx
        geradoEm: DateTime.now(),
        lancsC1: raw1,
        lancsC2: raw2,
        resumoC1: res1,
        resumoC2: res2,
        comparativo: linhas,
      );
      if (!mounted) return;
      setState(() {
        _abas = abas;
        _linhas = linhas;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar o relatório (precisa de internet): $e';
        _carregando = false;
      });
    }
  }

  Future<void> _exportar() async {
    setState(() => _exportando = true);
    try {
      final caminho =
          await RelatorioInventarioService().exportar(widget.inventarioId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Planilha salva: $caminho')));
      await OpenFilex.open(caminho);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao exportar: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando || _erro != null || _abas.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Relatório ${widget.numeroFormatado}')),
        body: Center(
          child: _carregando
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_erro ?? 'Sem dados.',
                        style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 12),
                    OutlinedButton(
                        onPressed: _carregar,
                        child: const Text('Tentar de novo')),
                  ]),
                ),
        ),
      );
    }
    return DefaultTabController(
      length: _abas.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Relatório ${widget.numeroFormatado}'
              '${widget.tipo != null ? ' · ${widget.tipo!.rotulo}' : ''}'),
          actions: [
            IconButton(
              tooltip: 'Exportar planilha (.xlsx)',
              onPressed: _exportando ? null : _exportar,
              icon: _exportando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_download),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final a in _abas) Tab(text: a.nome)],
          ),
        ),
        body: TabBarView(
          children: [for (final a in _abas) _aba(a)],
        ),
      ),
    );
  }

  Widget _aba(AbaRelatorio a) {
    final topo = a.linhas
        .take(a.linhaCabecalho)
        .where((l) => l.isNotEmpty)
        .map((l) => l.first?.toString() ?? '')
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final t in topo)
                Text(t,
                    style: TextStyle(
                        fontWeight: t == topo.first
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: t == topo.first ? 14 : 12)),
              if (a.nome == 'C3' || a.nome.startsWith('Final')) _resumo(),
              Text('${a.dados.length} linha(s)',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        Expanded(
          child: a.dados.isEmpty
              ? const Center(child: Text('Nenhuma linha.'))
              : SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 36,
                      dataRowMinHeight: 30,
                      dataRowMaxHeight: 44,
                      columnSpacing: 16,
                      headingTextStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.black87),
                      columns: [
                        for (final c in a.cabecalho)
                          DataColumn(label: Text('${c ?? ''}')),
                      ],
                      rows: [
                        for (final l in a.dados)
                          DataRow(
                            color: WidgetStateProperty.resolveWith(
                                (_) => _corLinha(a, l)),
                            cells: [
                              for (var i = 0; i < a.cabecalho.length; i++)
                                DataCell(Text(
                                    _fmt(i < l.length ? l[i] : null),
                                    style: const TextStyle(fontSize: 12))),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// Aba C3: pendente em laranja, informativo em cinza.
  Color? _corLinha(AbaRelatorio a, List<Object?> l) {
    if (a.nome != 'C3') return null;
    final s = l.length > 10 ? '${l[10]}' : '';
    if (s.startsWith('pendente')) return Colors.orange.withValues(alpha: 0.10);
    if (s.startsWith('informativo')) return Colors.grey.withValues(alpha: 0.12);
    return null;
  }

  Widget _resumo() {
    final r = resumoPorNatureza(_linhas, widget.naturezaC3).values.where(
        (rn) => rn.selecionada || _linhas.any((l) => l.natureza == rn.natureza));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.naturezaC3 != null)
            Text('C3: ${widget.naturezaC3!.rotulo}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          for (final rn in r)
            Text(rn.texto, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  String _fmt(Object? v) {
    if (v == null) return '';
    if (v is DateTime) {
      String d(int x) => x.toString().padLeft(2, '0');
      return '${d(v.day)}/${d(v.month)}/${v.year}';
    }
    if (v is double) {
      return v.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(
          RegExp(r'\.$'), '').replaceAll('.', ',');
    }
    return v.toString();
  }
}
