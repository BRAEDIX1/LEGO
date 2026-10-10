// lib/ui/mobile/screens/comparativo_screen.dart
//
// Relatório do inventário no celular. O conteúdo (abas iguais ao .xlsx) é o
// mesmo do desktop: RelatorioInventarioView.

import 'package:flutter/material.dart';

import 'package:lego/services/comparativo.dart';
import 'package:lego/ui/analista/painel_analista.dart' show avisar, exportarRelatorioXlsx;
import 'package:lego/ui/analista/relatorio_view.dart';

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
  bool _exportando = false;

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
    return Scaffold(
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
      ),
      body: RelatorioInventarioView(
        inventarioId: widget.inventarioId,
        numeroFormatado: widget.numeroFormatado,
        tipo: widget.tipo,
        naturezaC3: widget.naturezaC3,
      ),
    );
  }
}
