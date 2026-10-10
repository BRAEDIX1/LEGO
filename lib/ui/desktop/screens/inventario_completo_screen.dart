// lib/ui/desktop/screens/inventario_completo_screen.dart
//
// Painel do analista no desktop (Inventário Completo, fluxo 2).
// Esquerda: as etapas e ações (o MESMO PainelAnalista do celular).
// Direita: o relatório em abas (o MESMO do .xlsx), recarregado sozinho quando
// uma etapa muda ou um item da C3 sincroniza.
// Topo: qual inventário acompanhar (o ativo e os Completos recentes).
//
// O Inventário Completo é aberto pelo celular (Completa → tipo); aqui ele é
// acompanhado e conduzido.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/services/c3.dart';
import 'package:lego/services/analista_service.dart';
import 'package:lego/services/c3_service.dart';
import 'package:lego/services/comparativo.dart';
import 'package:lego/services/inventario_service.dart';
import 'package:lego/services/monitor_service.dart';
import 'package:lego/ui/analista/painel_analista.dart';
import 'package:lego/ui/analista/relatorio_view.dart';

class InventarioCompletoScreen extends StatefulWidget {
  const InventarioCompletoScreen({super.key});

  @override
  State<InventarioCompletoScreen> createState() =>
      _InventarioCompletoScreenState();
}

class _InventarioCompletoScreenState extends State<InventarioCompletoScreen> {
  final _inventarios = InventarioService();
  final _fmtData = DateFormat('dd/MM/yyyy');

  bool _carregando = true;
  String? _erro;
  /// Item 8: só o analista conduz o inventário (as regras também barram).
  bool? _analista;
  List<Inventario> _lista = const [];
  String? _ativoId;
  String? _selId;
  Stream<Inventario?>? _streamSel;
  /// Relatório em tela cheia (painel de etapas escondido).
  bool _relatorioCheio = false;

  /// Tempo real: quando o celular abre um Completo novo (ou o atual é
  /// encerrado/cancelado), a trava muda e a lista se refaz sozinha.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _trava;
  static const Object _sentinela = Object();
  Object? _travaVista = _sentinela; // ainda não leu

  @override
  void initState() {
    super.initState();
    _carregarLista();
    _trava = FirebaseFirestore.instance
        .collection('sistema')
        .doc('contadores')
        .snapshots()
        .listen((snap) {
      final id = snap.data()?['inventario_completo_ativo_id'];
      final primeira = identical(_travaVista, _sentinela);
      if (!primeira && id != _travaVista && _analista == true) {
        // Novo ativo: seleciona ele; ativo saiu: mantém a seleção atual.
        if (id is String) _selId = null;
        _carregarLista();
      }
      _travaVista = id;
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _trava?.cancel();
    super.dispose();
  }

  Future<void> _carregarLista() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final analista = await AnalistaService().souAnalista();
      if (!analista) {
        if (!mounted) return;
        setState(() {
          _analista = false;
          _carregando = false;
        });
        return;
      }
      _analista = true;
      final ativo =
          await _inventarios.buscarInventarioCompletoAtivo(propagarErros: true);
      final recentes = await _inventarios.listarCompletosRecentes();
      final lista = <Inventario>[
        if (ativo != null) ativo,
        ...recentes.where((i) => i.id != ativo?.id),
      ];
      if (!mounted) return;
      setState(() {
        _lista = lista;
        _ativoId = ativo?.id;
        if (_selId == null || !lista.any((i) => i.id == _selId)) {
          _selecionar(lista.isEmpty ? null : lista.first.id);
        }
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível ler os inventários (precisa de internet): $e';
        _carregando = false;
      });
    }
  }

  void _selecionar(String? id) {
    _selId = id;
    _streamSel = id == null ? null : MonitorService().streamInventario(id);
  }

  String _rotulo(Inventario i) {
    final tipo = NaturezaRotulo.deNome(i.naturezaContagem);
    return 'Inventário ${i.numeroFormatado}'
        '${tipo != null ? ' · ${tipo.rotulo}' : ''}'
        ' · ${_fmtData.format(i.dataInicio)}'
        '${i.id == _ativoId ? ' · ativo' : ''}';
  }

  Future<void> _cancelar(Inventario inv) async {
    if (await cancelarInventarioComConfirmacao(context, inv)) _carregarLista();
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando && _lista.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_analista == false) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline, size: 56, color: Colors.grey[500]),
          const SizedBox(height: 12),
          const Text('Acesso exclusivo do analista.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Peça para incluir o seu e-mail na lista de analistas.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: _carregarLista,
              icon: const Icon(Icons.refresh),
              label: const Text('Verificar de novo')),
        ]),
      );
    }
    if (_erro != null && _lista.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_erro!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed: _carregarLista, child: const Text('Tentar de novo')),
        ]),
      );
    }
    if (_lista.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 12),
          const Text('Nenhum Inventário Completo ainda.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Ele é aberto pelo celular: Completa → tipo da contagem.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: _carregarLista,
              icon: const Icon(Icons.refresh),
              label: const Text('Procurar de novo')),
        ]),
      );
    }

    final sel = _selId!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabecalho(sel),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final larguraPainel = c.maxWidth < 1200 ? 400.0 : 460.0;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Offstage mantém o painel vivo (streams e estado) enquanto
                // o relatório está em tela cheia.
                Offstage(
                  offstage: _relatorioCheio,
                  child: SizedBox(
                    width: larguraPainel,
                    child: PainelAnalista(
                      key: ValueKey('painel/$sel'),
                      inventarioId: sel,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
                if (!_relatorioCheio) const VerticalDivider(width: 1),
                Expanded(child: _RelatorioAoLado(inventarioId: sel)),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _cabecalho(String sel) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        const Text('Inventário:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 12),
        DropdownButton<String>(
          value: sel,
          underline: const SizedBox.shrink(),
          items: [
            for (final i in _lista)
              DropdownMenuItem(value: i.id, child: Text(_rotulo(i))),
          ],
          onChanged: (id) {
            if (id != null && id != _selId) setState(() => _selecionar(id));
          },
        ),
        const SizedBox(width: 12),
        StreamBuilder<Inventario?>(
          stream: _streamSel,
          builder: (context, s) {
            final inv = s.data;
            if (inv == null) return const SizedBox.shrink();
            return Chip(
              label: Text(inv.statusLabel),
              backgroundColor: inv.isAtivo
                  ? Colors.green.withValues(alpha: 0.12)
                  : Colors.grey.withValues(alpha: 0.12),
              side: BorderSide.none,
            );
          },
        ),
        const Spacer(),
        if (_carregando)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        TextButton.icon(
          onPressed: () => setState(() => _relatorioCheio = !_relatorioCheio),
          icon: Icon(_relatorioCheio ? Icons.view_sidebar : Icons.open_in_full),
          label: Text(_relatorioCheio ? 'Mostrar etapas' : 'Relatório em tela cheia'),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Procurar inventários de novo',
          onPressed: _carregando ? null : _carregarLista,
          icon: const Icon(Icons.refresh),
        ),
        StreamBuilder<Inventario?>(
          stream: _streamSel,
          builder: (context, s) {
            final inv = s.data;
            return PopupMenuButton<String>(
              tooltip: 'Mais',
              enabled: inv != null,
              onSelected: (v) {
                if (v == 'cancelar' && inv != null) _cancelar(inv);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'cancelar',
                  enabled: inv?.isAtivo ?? false,
                  child: const Text('Cancelar inventário',
                      style: TextStyle(color: Colors.red)),
                ),
              ],
            );
          },
        ),
      ]),
    );
  }
}

/// Relatório ao lado do painel. Observa o inventário e as linhas do
/// comparativo e avisa a RelatorioInventarioView quando recarregar:
/// - etapa mudou (C1/C2 encerrada, comparativo gerado, C3 mudou de estado)
///   → relê tudo;
/// - item da C3 sincronizou → relê só o comparativo.
class _RelatorioAoLado extends StatefulWidget {
  final String inventarioId;
  const _RelatorioAoLado({required this.inventarioId});

  @override
  State<_RelatorioAoLado> createState() => _RelatorioAoLadoState();
}

class _RelatorioAoLadoState extends State<_RelatorioAoLado> {
  late Stream<Inventario?> _inv;
  late Stream<List<LinhaComparativo>> _linhas;
  /// Tempo real: total de lançamentos de C1 e C2 (mesma escuta do painel;
  /// o Firestore compartilha). Mudou → o relatório relê do cache local.
  late Stream<Map<String, int>> _totC1;
  late Stream<Map<String, int>> _totC2;

  @override
  void initState() {
    super.initState();
    _assinar(); // B81: sem isto, o 1º build usa streams não iniciados
  }

  @override
  void didUpdateWidget(covariant _RelatorioAoLado old) {
    super.didUpdateWidget(old);
    if (old.inventarioId != widget.inventarioId) _assinar();
  }

  void _assinar() {
    final m = MonitorService();
    _inv = m.streamInventario(widget.inventarioId);
    _linhas = C3Service().streamLinhas(widget.inventarioId);
    _totC1 = m.streamSincronizadosPorUsuario(widget.inventarioId, Rodadas.c1);
    _totC2 = m.streamSincronizadosPorUsuario(widget.inventarioId, Rodadas.c2);
  }

  int _soma(Map<String, int>? m) =>
      m == null ? 0 : m.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Inventario?>(
      stream: _inv,
      builder: (context, iSnap) {
        final inv = iSnap.data;
        if (inv == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return StreamBuilder<Map<String, int>>(
         stream: _totC1,
         builder: (context, t1) => StreamBuilder<Map<String, int>>(
          stream: _totC2,
          builder: (context, t2) => StreamBuilder<List<LinhaComparativo>>(
          stream: _linhas,
          builder: (context, lSnap) {
            final linhas = lSnap.data ?? const <LinhaComparativo>[];
            final rec = inv.reconciliacao ?? const ReconciliacaoInfo();
            final chaveLanc = [
              inv.statusRodada(Rodadas.c1),
              inv.statusRodada(Rodadas.c2),
              rec.status,
            ].join('|');
            final chaveContagem = '${_soma(t1.data)}|${_soma(t2.data)}';
            final sincC3 = linhas
                .where((l) =>
                    l.naC3 && l.c3Status == StatusTarefaC3.sincronizada)
                .length;
            final chaveCmp = [
              inv.statusRodada(Rodadas.c3),
              linhas.length,
              sincC3,
            ].join('|');
            return RelatorioInventarioView(
              key: ValueKey('relatorio/${inv.id}'),
              inventarioId: inv.id,
              numeroFormatado: inv.numeroFormatado,
              tipo: NaturezaRotulo.deNome(inv.naturezaContagem),
              naturezaC3: NaturezaRotulo.deNome(
                  inv.contagens[Rodadas.c3]?.natureza ??
                      inv.naturezaContagem),
              chaveLancamentos: chaveLanc,
              chaveContagem: chaveContagem,
              chaveComparativo: chaveCmp,
              barraDeAcoes: true,
            );
          },
         ),
         ),
        );
      },
    );
  }
}
