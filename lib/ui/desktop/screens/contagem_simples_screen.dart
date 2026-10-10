// lib/ui/desktop/screens/contagem_simples_screen.dart
//
// Contagem Simples no desktop: analisar os lançamentos e extrair o relatório.
// A Contagem Simples não pertence a inventário (D1): aqui ela é filtrada por
// período e operador. Tempo real (escuta do Firestore). Abas no formato do
// modelo: Lançamentos + um consolidado por natureza que tiver linhas.
// Exportar .xlsx com "Salvar como".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:lego/services/analista_service.dart';
import 'package:lego/services/comparativo.dart';
import 'package:lego/services/comparativo_rodadas_service.dart';
import 'package:lego/services/relatorio_inventario.dart';
import 'package:lego/services/relatorio_inventario_xlsx.dart';
import 'package:lego/ui/analista/painel_analista.dart'
    show avisar, salvarXlsxComo;
import 'package:lego/ui/analista/relatorio_view.dart';

class ContagemSimplesScreen extends StatefulWidget {
  const ContagemSimplesScreen({super.key});

  @override
  State<ContagemSimplesScreen> createState() => _ContagemSimplesScreenState();
}

class _ContagemSimplesScreenState extends State<ContagemSimplesScreen> {
  final _cmp = ComparativoRodadasService();
  final _fmt = DateFormat('dd/MM/yyyy');

  bool? _analista;
  late DateTimeRange _periodo;
  String? _operador; // null = todos

  StreamSubscription<(List<Map<String, dynamic>>, List<LancResumo>)>? _escuta;
  List<Map<String, dynamic>> _brutos = const [];
  List<AbaRelatorio> _abas = const [];
  bool _carregando = true;
  bool _exportando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    final hoje = DateTime.now();
    final d = DateTime(hoje.year, hoje.month, hoje.day);
    _periodo = DateTimeRange(start: d, end: d);
    _iniciar();
  }

  @override
  void dispose() {
    _escuta?.cancel();
    super.dispose();
  }

  Future<void> _iniciar() async {
    final a = await AnalistaService().souAnalista();
    if (!mounted) return;
    setState(() => _analista = a);
    if (a) _escutar();
  }

  /// Fim do período é inclusivo na tela; na consulta vira o dia seguinte.
  void _escutar() {
    _escuta?.cancel();
    setState(() {
      _carregando = true;
      _erro = null;
    });
    final inicio = _periodo.start;
    final fim = _periodo.end.add(const Duration(days: 1));
    _escuta = _cmp.streamSimples(inicio, fim).listen((r) {
      if (!mounted) return;
      _brutos = r.$1;
      _montar();
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() {
        _erro = '$e'.contains('index')
            ? 'Falta um índice no Firestore (lancamentos: inventarioId ↑, '
                'createdAt ↓). Detalhe: $e'
            : 'Erro ao ler a Contagem Simples: $e';
        _carregando = false;
      });
    });
  }

  String _nomeOperador(Map<String, dynamic> l) {
    String? t(Object? v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return t(l['nomeCompleto']) ?? t(l['nickname']) ?? t(l['uid']) ?? '?';
  }

  String _uidDe(Map<String, dynamic> l) => (l['uid'] ?? '?').toString();

  /// Operadores do período: valor = uid, rótulo = nome (dois "João Silva"
  /// com uids diferentes não se misturam).
  List<(String, String)> get _operadores {
    final m = <String, String>{};
    for (final l in _brutos) {
      m.putIfAbsent(_uidDe(l), () => _nomeOperador(l));
    }
    final nomes = <String, int>{};
    for (final n in m.values) {
      nomes[n] = (nomes[n] ?? 0) + 1;
    }
    final out = [
      for (final e in m.entries)
        (
          e.key,
          (nomes[e.value] ?? 0) > 1
              ? '${e.value} (${e.key.length > 6 ? e.key.substring(0, 6) : e.key})'
              : e.value,
        ),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return out;
  }

  String? get _nomeOperadorSel {
    final op = _operador;
    if (op == null) return null;
    for (final o in _operadores) {
      if (o.$1 == op) return o.$2;
    }
    return op;
  }

  String get _rotuloPeriodo => _periodo.start == _periodo.end
      ? _fmt.format(_periodo.start)
      : '${_fmt.format(_periodo.start)} a ${_fmt.format(_periodo.end)}';

  Future<void> _montar() async {
    final op = _operador;
    final brutos = op == null
        ? _brutos
        : _brutos.where((l) => _uidDe(l) == op).toList();
    final resumo = await _cmp.classificarBrutos(brutos);
    if (!mounted || op != _operador) return;
    setState(() {
      _abas = montarRelatorioSimples(
        periodo: _rotuloPeriodo,
        filtro: op == null
            ? 'Todos os operadores'
            : 'Operador: ${_nomeOperadorSel ?? op}',
        geradoEm: DateTime.now(),
        lancs: brutos,
        resumo: resumo,
      );
      _carregando = false;
    });
  }

  Future<void> _escolherPeriodo() async {
    final hoje = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(hoje.year, hoje.month, hoje.day),
      initialDateRange: _periodo,
      helpText: 'Período da Contagem Simples',
    );
    if (r == null) return;
    setState(() {
      _periodo = r;
      _operador = null;
    });
    _escutar();
  }

  Future<void> _exportar() async {
    setState(() => _exportando = true);
    try {
      final bytes = gerarXlsx(_abas);
      if (bytes == null) throw Exception('não foi possível gerar o .xlsx');
      String dd(int v) => v.toString().padLeft(2, '0');
      String d(DateTime x) => '${x.year}${dd(x.month)}${dd(x.day)}';
      final nome = 'LEGO_Contagem_Simples_${d(_periodo.start)}'
          '${_periodo.start == _periodo.end ? '' : '_a_${d(_periodo.end)}'}'
          '${_operador == null ? '' : '_${(_nomeOperadorSel ?? _operador!).replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}'}'
          '.xlsx';
      final caminho = await salvarXlsxComo(nome, bytes,
          titulo: 'Salvar relatório da Contagem Simples');
      if (caminho != null && mounted) avisar(context, 'Planilha salva: $caminho');
    } catch (e) {
      if (mounted) avisar(context, 'Erro ao exportar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_analista == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_analista == false) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline, size: 56, color: Colors.grey[500]),
          const SizedBox(height: 12),
          const Text('Acesso exclusivo do analista.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: () {
                setState(() => _analista = null);
                _iniciar();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Verificar de novo')),
        ]),
      );
    }

    final ops = _operadores;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Período:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              OutlinedButton.icon(
                onPressed: _escolherPeriodo,
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(_rotuloPeriodo),
              ),
              const SizedBox(width: 8),
              const Text('Operador:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<String?>(
                value: ops.any((o) => o.$1 == _operador) ? _operador : null,
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Todos')),
                  for (final o in ops)
                    DropdownMenuItem<String?>(value: o.$1, child: Text(o.$2)),
                ],
                onChanged: (v) {
                  setState(() => _operador = v);
                  _montar();
                },
              ),
              Text('${_brutos.length} lançamento(s) no período',
                  style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_erro != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(_erro!,
                style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: _abas.isEmpty
              ? Center(
                  child: _carregando
                      ? const CircularProgressIndicator()
                      : const Text('Nenhum lançamento no período.'))
              : AbasRelatorioView(
                  abas: _abas,
                  carregando: _carregando,
                  acoes: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: OutlinedButton.icon(
                        onPressed: _exportando || _brutos.isEmpty
                            ? null
                            : _exportar,
                        icon: _exportando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.file_download, size: 18),
                        label: const Text('Exportar .xlsx'),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
