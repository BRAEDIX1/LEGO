// lib/ui/desktop/screens/relatorio_do_inventario_screen.dart
//
// 03/11: "Relatórios" (menu) e "Ver relatório" (Histórico e Detalhe) abriam
// SEMPRE o relatório antigo (fluxo 1), que lê `inventarios/{id}/estoque`.
// No Inventário Completo (fluxo 2) essa subcoleção não existe e as regras
// não a liberam → "permission-denied". Agora cada inventário abre o seu
// relatório: fluxo 2 → o mesmo relatório do painel (abas C1/C2/C3/Final,
// exporta .xlsx); fluxo 1 → o relatório antigo, como antes.

import 'package:flutter/material.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/services/comparativo.dart';
import 'package:lego/services/monitor_service.dart';
import 'package:lego/ui/analista/relatorio_view.dart';
import 'package:lego/ui/desktop/screens/relatorio_screen.dart';

class RelatorioDoInventarioScreen extends StatefulWidget {
  final String inventarioId;
  const RelatorioDoInventarioScreen({super.key, required this.inventarioId});

  @override
  State<RelatorioDoInventarioScreen> createState() =>
      _RelatorioDoInventarioScreenState();
}

class _RelatorioDoInventarioScreenState
    extends State<RelatorioDoInventarioScreen> {
  late Stream<Inventario?> _inv;

  @override
  void initState() {
    super.initState();
    _inv = MonitorService().streamInventario(widget.inventarioId);
  }

  @override
  void didUpdateWidget(covariant RelatorioDoInventarioScreen old) {
    super.didUpdateWidget(old);
    if (old.inventarioId != widget.inventarioId) {
      _inv = MonitorService().streamInventario(widget.inventarioId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Inventario?>(
      stream: _inv,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Relatório')),
            body: Center(child: Text('Erro ao abrir o inventário: ${snap.error}')),
          );
        }
        final inv = snap.data;
        if (inv == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Relatório')),
            body: Center(
              child: snap.connectionState == ConnectionState.waiting
                  ? const CircularProgressIndicator()
                  : const Text('Inventário não encontrado.'),
            ),
          );
        }
        if (!inv.isFluxoMaquinaEstados) {
          return RelatorioScreen(inventarioId: inv.id);
        }
        return Scaffold(
          appBar: AppBar(
              title: Text('Relatório · Inventário ${inv.numeroFormatado}')),
          body: RelatorioInventarioView(
            key: ValueKey('relatorio-cheio/${inv.id}'),
            inventarioId: inv.id,
            numeroFormatado: inv.numeroFormatado,
            tipo: NaturezaRotulo.deNome(inv.naturezaContagem),
            naturezaC3: NaturezaRotulo.deNome(
                inv.contagens[Rodadas.c3]?.natureza ?? inv.naturezaContagem),
            barraDeAcoes: true,
          ),
        );
      },
    );
  }
}
