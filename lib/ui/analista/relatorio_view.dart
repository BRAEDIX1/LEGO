// lib/ui/analista/relatorio_view.dart
//
// Relatório do inventário em abas, igual ao .xlsx (modelo do Djalma):
// C1 Lançamentos · C1 Consolidado · C2 Lançamentos · C2 Consolidado · C3 ·
// Final. As abas vêm do mesmo montador do arquivo (relatorio_inventario.dart),
// então tela e planilha nunca divergem.
//
// UM código para o celular (ComparativoScreen) e o desktop (ao lado do painel).
// Recarga sem botão quando o dono avisa que algo mudou:
//   [chaveLancamentos] mudou → relê lançamentos e comparativo (servidor);
//   [chaveContagem] mudou → relê os lançamentos do CACHE (o dono mantém uma
//     escuta nessa consulta), no máximo a cada 5 s — custo zero;
//   [chaveComparativo] mudou → relê só o comparativo (barato: C3 andando).

import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/services/comparativo.dart';
import 'package:lego/services/comparativo_rodadas_service.dart';
import 'package:lego/services/relatorio_inventario.dart';
import 'package:lego/ui/analista/painel_analista.dart' show avisar, exportarRelatorioXlsx;

class RelatorioInventarioView extends StatefulWidget {
  final String inventarioId;
  final String numeroFormatado;
  /// Tipo do inventário (define as abas; null = antigo: os três).
  final Natureza? tipo;
  /// Consolidado da C3 (para o resumo; num inventário com tipo é o tipo).
  final Natureza? naturezaC3;
  final Object? chaveLancamentos;
  final Object? chaveContagem;
  final Object? chaveComparativo;
  /// Desktop: barra com "Atualizar" e "Exportar .xlsx" ao lado das abas.
  final bool barraDeAcoes;

  const RelatorioInventarioView({
    super.key,
    required this.inventarioId,
    required this.numeroFormatado,
    this.tipo,
    this.naturezaC3,
    this.chaveLancamentos,
    this.chaveContagem,
    this.chaveComparativo,
    this.barraDeAcoes = false,
  });

  @override
  State<RelatorioInventarioView> createState() =>
      _RelatorioInventarioViewState();
}

class _RelatorioInventarioViewState extends State<RelatorioInventarioView> {
  final _cmp = ComparativoRodadasService();
  bool _carregando = true;
  bool _exportando = false;
  String? _erro;
  List<AbaRelatorio> _abas = const [];
  List<LinhaComparativo> _linhas = const [];
  // lançamentos em cache (recarga só do comparativo reaproveita)
  (List<Map<String, dynamic>>, List<LancResumo>)? _c1;
  (List<Map<String, dynamic>>, List<LancResumo>)? _c2;
  int _geracao = 0; // descarta respostas de cargas antigas
  Timer? _espera; // agrupa lançamentos que chegam em sequência

  @override
  void initState() {
    super.initState();
    _carregar(tudo: true);
  }

  @override
  void dispose() {
    _espera?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RelatorioInventarioView old) {
    super.didUpdateWidget(old);
    if (old.inventarioId != widget.inventarioId) {
      _abas = const [];
      _linhas = const [];
      _c1 = _c2 = null;
      _carregar(tudo: true);
    } else if (old.chaveLancamentos != widget.chaveLancamentos ||
        old.tipo != widget.tipo) {
      _carregar(tudo: true);
    } else if (old.chaveContagem != widget.chaveContagem) {
      _espera?.cancel();
      _espera = Timer(const Duration(seconds: 5),
          () => _carregar(tudo: true, doCache: true));
    } else if (old.chaveComparativo != widget.chaveComparativo) {
      _carregar(tudo: false);
    }
  }

  Future<void> _carregar({required bool tudo, bool doCache = false}) async {
    final ger = ++_geracao;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final id = widget.inventarioId;
      if (tudo || _c1 == null || _c2 == null) {
        _c1 = await _cmp.carregarRodadaCompleta(id, Rodadas.c1,
            doCache: doCache);
        _c2 = await _cmp.carregarRodadaCompleta(id, Rodadas.c2,
            doCache: doCache);
      }
      final linhas = await _cmp.lerComparativo(id);
      final abas = montarRelatorio(
        numero: widget.numeroFormatado,
        tipo: widget.tipo, // igual ao .xlsx
        geradoEm: DateTime.now(),
        lancsC1: _c1!.$1,
        lancsC2: _c2!.$1,
        resumoC1: _c1!.$2,
        resumoC2: _c2!.$2,
        comparativo: linhas,
      );
      if (!mounted || ger != _geracao) return;
      setState(() {
        _abas = abas;
        _linhas = linhas;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted || ger != _geracao) return;
      setState(() {
        _erro = 'Erro ao carregar o relatório (precisa de internet): $e';
        _carregando = false;
      });
    }
  }

  Future<void> _exportar() async {
    setState(() => _exportando = true);
    try {
      final caminho = await exportarRelatorioXlsx(widget.inventarioId);
      if (caminho != null && mounted) avisar(context, 'Planilha salva: $caminho');
    } catch (e) {
      if (mounted) avisar(context, 'Erro ao exportar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_abas.isEmpty) {
      return Center(
        child: _carregando
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_erro ?? 'Sem dados.',
                      style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                      onPressed: () => _carregar(tudo: true),
                      child: const Text('Tentar de novo')),
                ]),
              ),
      );
    }
    return DefaultTabController(
      key: ValueKey('${widget.inventarioId}/${_abas.length}'),
      length: _abas.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [for (final a in _abas) Tab(text: a.nome)],
              ),
            ),
            if (widget.barraDeAcoes) ...[
              IconButton(
                tooltip: 'Recarregar o relatório',
                onPressed: _carregando ? null : () => _carregar(tudo: true),
                icon: const Icon(Icons.refresh),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton.icon(
                  onPressed: _exportando ? null : _exportar,
                  icon: _exportando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.file_download, size: 18),
                  label: const Text('Exportar .xlsx'),
                ),
              ),
            ],
          ]),
          SizedBox(
            height: 2,
            child: _carregando ? const LinearProgressIndicator() : null,
          ),
          if (_erro != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_erro!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: TabBarView(
              children: [for (final a in _abas) _aba(a)],
            ),
          ),
        ],
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
              : _TabelaRolavel(
                  key: ValueKey('tabela/${a.nome}'),
                  tabela: DataTable(
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

/// Tabela que preenche a largura da área e tem as duas barras de rolagem
/// sempre visíveis (no desktop o mouse
/// não arrasta lista por padrão). Horizontal por fora: a barra fica no pé da
/// área visível, não no fim das linhas. Arrastar com o mouse também rola.
class _TabelaRolavel extends StatefulWidget {
  final Widget tabela;
  const _TabelaRolavel({super.key, required this.tabela});

  @override
  State<_TabelaRolavel> createState() => _TabelaRolavelState();
}

class _TabelaRolavelState extends State<_TabelaRolavel> {
  final _h = ScrollController();
  final _v = ScrollController();

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      }),
      child: LayoutBuilder(
        builder: (context, c) => Scrollbar(
          controller: _h,
          thumbVisibility: true,
          trackVisibility: true,
          child: SingleChildScrollView(
            controller: _h,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 14), // espaço da barra
            child: Scrollbar(
              controller: _v,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _v,
                padding: const EdgeInsets.only(right: 14),
                // Tabela estreita: colunas esticam até a largura da área.
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      minWidth: c.maxWidth > 14 ? c.maxWidth - 14 : 0.0),
                  child: widget.tabela,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Abas prontas (sem carga própria): usada pela Contagem Simples. Mesma
/// tabela do relatório do inventário (barras sempre visíveis, preenche a
/// largura, arrasto com o mouse).
class AbasRelatorioView extends StatelessWidget {
  final List<AbaRelatorio> abas;
  /// Botões à direita das abas (ex.: exportar).
  final List<Widget> acoes;
  final bool carregando;

  const AbasRelatorioView({
    super.key,
    required this.abas,
    this.acoes = const [],
    this.carregando = false,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      key: ValueKey('abas/${abas.map((a) => a.nome).join('|')}'),
      length: abas.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [for (final a in abas) Tab(text: a.nome)],
              ),
            ),
            ...acoes,
          ]),
          SizedBox(
              height: 2,
              child: carregando ? const LinearProgressIndicator() : null),
          Expanded(
            child: TabBarView(children: [for (final a in abas) _aba(a)]),
          ),
        ],
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
              Text('${a.dados.length} linha(s)',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        Expanded(
          child: a.dados.isEmpty
              ? const Center(child: Text('Nenhuma linha.'))
              : _TabelaRolavel(
                  key: ValueKey('tabela/${a.nome}'),
                  tabela: DataTable(
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
                        DataRow(cells: [
                          for (var i = 0; i < a.cabecalho.length; i++)
                            DataCell(Text(
                                formatarCelula(i < l.length ? l[i] : null),
                                style: const TextStyle(fontSize: 12))),
                        ]),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// Mesmo formato de célula da tela do relatório.
String formatarCelula(Object? v) {
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

