// lib/ui/mobile/screens/comparativo_screen.dart
//
// Entrega 1 (teste em campo): tela do comparativo C1 × C2.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'package:lego/services/comparativo.dart';
import 'package:lego/services/comparativo_rodadas_service.dart';

class ComparativoScreen extends StatefulWidget {
  final String inventarioId;
  final String numeroFormatado;

  const ComparativoScreen({
    super.key,
    required this.inventarioId,
    required this.numeroFormatado,
  });

  @override
  State<ComparativoScreen> createState() => _ComparativoScreenState();
}

enum _Filtro { emAnalise, encerradas, todas }

class _ComparativoScreenState extends State<ComparativoScreen> {
  final _service = ComparativoRodadasService();
  bool _carregando = true;
  String? _erro;
  List<LinhaComparativo> _linhas = const [];
  _Filtro _filtro = _Filtro.emAnalise;
  String _busca = '';

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
      final linhas = await _service.lerComparativo(widget.inventarioId);
      if (!mounted) return;
      setState(() {
        _linhas = linhas;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao ler o comparativo: $e';
        _carregando = false;
      });
    }
  }

  Future<void> _exportar() async {
    try {
      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final agora = DateTime.now();
      String dd(int v) => v.toString().padLeft(2, '0');
      final nome = 'LEGO_resultado_${widget.numeroFormatado}_'
          '${agora.year}${dd(agora.month)}${dd(agora.day)}_'
          '${dd(agora.hour)}${dd(agora.minute)}.csv';
      final arq = File('${dir.path}/$nome');
      // BOM para o Excel abrir acentos corretamente.
      await arq.writeAsString('\uFEFF${resultadoCsv(_linhas)}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Planilha salva: ${arq.path}')));
      await OpenFilex.open(arq.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao exportar: $e'), backgroundColor: Colors.red));
    }
  }

  List<LinhaComparativo> get _visiveis {
    final q = _busca.trim().toLowerCase();
    return _linhas.where((l) {
      final passaFiltro = switch (_filtro) {
        _Filtro.emAnalise => l.emAnalise,
        _Filtro.encerradas => !l.emAnalise,
        _Filtro.todas => true,
      };
      if (!passaFiltro) return false;
      if (q.isEmpty) return true;
      return l.codigo.toLowerCase().contains(q) ||
          (l.tag ?? '').toLowerCase().contains(q) ||
          (l.lote ?? '').toLowerCase().contains(q) ||
          l.descricao.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final r = ResumoComparativo.de(_linhas);
    return Scaffold(
      appBar: AppBar(
        title: Text('Resultado ${widget.numeroFormatado}'),
        actions: [
          IconButton(
            tooltip: 'Exportar planilha (CSV)',
            onPressed: _carregando || _linhas.isEmpty ? null : _exportar,
            icon: const Icon(Icons.file_download),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erro!, style: const TextStyle(color: Colors.red)),
                  ),
                )
              : Column(
                  children: [
                    _resumo(r),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Buscar código, tag, lote ou descrição',
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _busca = v),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: SegmentedButton<_Filtro>(
                        segments: [
                          ButtonSegment(
                              value: _Filtro.emAnalise,
                              label: Text('Divergências (${r.emAnalise})')),
                          ButtonSegment(
                              value: _Filtro.encerradas,
                              label: Text('Consenso (${r.encerradas})')),
                          ButtonSegment(
                              value: _Filtro.todas,
                              label: Text('Todas (${r.total})')),
                        ],
                        selected: {_filtro},
                        onSelectionChanged: (s) =>
                            setState(() => _filtro = s.first),
                      ),
                    ),
                    Expanded(child: _lista()),
                  ],
                ),
    );
  }

  Widget _resumo(ResumoComparativo r) {
    Widget bloco(String rotulo, int valor, Color cor) => Expanded(
          child: Column(
            children: [
              Text('$valor',
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, color: cor)),
              Text(rotulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
        );
    final c3 = ResumoC3.de(_linhas);
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(
          children: [
            Row(
              children: [
                bloco('Itens', r.total, Colors.black87),
                bloco('Encerradas', r.encerradas, Colors.green.shade700),
                bloco('Divergentes', r.divergentes + r.conflitos,
                Colors.orange.shade800),
                bloco('Só C1', r.soC1, Colors.red.shade700),
                bloco('Só C2', r.soC2, Colors.red.shade700),
              ],
            ),
            if (c3.total > 0) ...[
              const SizedBox(height: 8),
              Text('C3: ${c3.contadas} de ${c3.total} recontados',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _lista() {
    final itens = _visiveis;
    if (itens.isEmpty) {
      return const Center(child: Text('Nenhum item neste filtro.'));
    }
    return ListView.separated(
      itemCount: itens.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _linha(itens[i]),
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  String _valores(TotaisRodada? t) {
    if (t == null) return '—';
    if (t.naoEncontrado) return 'NÃO encontrado';
    if (t.conflito) return 'CONFLITO (leituras contraditórias)';
    final partes = <String>['qtd ${_fmt(t.quantidade)}'];
    if (t.cheio > 0 || t.vazio > 0) {
      partes.add('cheio ${_fmt(t.cheio)}');
      partes.add('vazio ${_fmt(t.vazio)}');
    }
    if (t.ocorrencias > 1) partes.add('${t.ocorrencias} leituras');
    return partes.join(' · ');
  }

  Widget _linha(LinhaComparativo l) {
    final (corOrig, seloOrig) = switch (l.motivo) {
      MotivoAnalise.soC1 => (Colors.red.shade700, 'SÓ C1'),
      MotivoAnalise.soC2 => (Colors.red.shade700, 'SÓ C2'),
      MotivoAnalise.divergente => (Colors.orange.shade800, 'DIVERGE'),
      MotivoAnalise.conflito => (Colors.purple.shade700, 'CONFLITO'),
      null => (Colors.green.shade700, 'OK'),
    };
    // A1: divergência original × pendência atual.
    final resolvidaPelaC3 = l.emAnalise && l.c3 != null;
    final cor = resolvidaPelaC3 ? Colors.blue.shade800 : corOrig;
    final selo = resolvidaPelaC3 ? 'C3 ✓' : seloOrig;
    final titulo = l.tipo == TipoChave.tag
        ? 'TAG ${l.tag} · ${l.codigo}'
        : '${l.codigo}${(l.lote ?? '').isNotEmpty ? ' · lote ${l.lote}' : ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(selo,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: cor, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
          if (l.descricao.isNotEmpty)
            Text(l.descricao, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (resolvidaPelaC3)
            Text('Divergência original: $seloOrig',
                style: TextStyle(color: corOrig, fontSize: 12)),
          Text('C1: ${_valores(l.c1)}'),
          Text('C2: ${_valores(l.c2)}'),
          if (l.emAnalise)
            Text(l.c3 != null
                ? 'C3: ${_valores(l.c3)} (${l.c3Quem ?? '?'})'
                : 'C3: pendente'
                    '${l.c3ResponsavelNome != null ? ' (${l.c3ResponsavelNome})' : ''}',
                style: TextStyle(
                    color: l.c3 != null ? Colors.blue.shade800 : Colors.grey)),
          if (l.valorFinal != null)
            Text('Final: ${_valores(l.valorFinal)} · ${l.origemFinal}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
