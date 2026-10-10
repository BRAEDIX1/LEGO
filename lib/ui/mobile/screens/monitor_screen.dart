// lib/ui/mobile/screens/monitor_screen.dart
//
// Painel do analista no celular (acesso de intervenção). O conteúdo é o
// mesmo do desktop: PainelAnalista. Aqui só a barra do topo e a abertura do
// relatório numa tela própria.

import 'package:flutter/material.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/services/comparativo.dart';
import 'package:lego/services/monitor_service.dart';
import 'package:lego/ui/analista/painel_analista.dart';
import 'package:lego/ui/mobile/screens/comparativo_screen.dart';

class MonitorScreen extends StatefulWidget {
  final String inventarioId;
  const MonitorScreen({super.key, required this.inventarioId});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  late final Stream<Inventario?> _inv =
      MonitorService().streamInventario(widget.inventarioId);

  void _abrirRelatorio(Inventario inv) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ComparativoScreen(
          inventarioId: inv.id,
          numeroFormatado: inv.numeroFormatado,
          tipo: NaturezaRotulo.deNome(inv.naturezaContagem),
          naturezaC3: NaturezaRotulo.deNome(
              inv.contagens[Rodadas.c3]?.natureza ?? inv.naturezaContagem)),
    ));
  }

  Future<void> _cancelar(Inventario inv) async {
    if (await cancelarInventarioComConfirmacao(context, inv) && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Inventario?>(
      stream: _inv,
      builder: (context, snap) {
        final inv = snap.data;
        final tipo =
            inv == null ? null : NaturezaRotulo.deNome(inv.naturezaContagem);
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Painel do analista', style: TextStyle(fontSize: 16)),
                if (inv != null)
                  Text(
                      'Inventário ${inv.numeroFormatado}'
                      '${tipo != null ? ' · ${tipo.rotulo}' : ''}'
                      ' · ${inv.statusLabel}',
                      style: const TextStyle(fontSize: 12)),
              ],
            ),
            actions: [
              if (inv != null)
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'cancelar') _cancelar(inv);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'cancelar',
                      enabled: inv.isAtivo,
                      child: const Text('Cancelar inventário',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
            ],
          ),
          body: PainelAnalista(
            inventarioId: widget.inventarioId,
            onAbrirRelatorio: _abrirRelatorio,
          ),
        );
      },
    );
  }
}
