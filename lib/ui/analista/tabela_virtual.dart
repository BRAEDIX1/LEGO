// lib/ui/analista/tabela_virtual.dart
//
// Item 6 (03/11) — tabela do relatório com rolagem PREGUIÇOSA: só as linhas
// visíveis são desenhadas. Substitui a DataTable, que montava todas as linhas
// de uma vez (inv. 007: ~3.250 linhas × 18 colunas ≈ 58 mil células na aba
// C1 Lançamentos).
//
// Comportamento mantido: preenche a largura da área, barras de rolagem
// sempre visíveis, arrasto com o mouse, cabeçalho em negrito, cor por linha.
// Novo: o cabeçalho fica fixo ao rolar para baixo.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'package:lego/services/relatorio_inventario.dart' show AbaRelatorio;

class TabelaVirtual extends StatefulWidget {
  final AbaRelatorio aba;
  final String Function(Object? valor) formatar;
  final Color? Function(List<Object?> linha)? corDaLinha;

  const TabelaVirtual({
    super.key,
    required this.aba,
    required this.formatar,
    this.corDaLinha,
  });

  /// Altura fixa da linha: permite ao ListView pular direto para qualquer
  /// posição sem medir as linhas anteriores.
  static const double alturaLinha = 30;
  static const double alturaCabecalho = 36;
  static const double _barra = 14; // espaço das barras de rolagem

  /// Largura estimada de cada coluna pelo texto mais longo (cabeçalho e
  /// linhas; em abas muito grandes, uma amostra espalhada).
  static List<double> largurasPara(
      List<Object?> cabecalho,
      List<List<Object?>> dados,
      String Function(Object?) formatar) {
    const porCaractere = 7.2;
    const margem = 20.0;
    const minimo = 56.0;
    const maximo = 420.0;
    final n = cabecalho.length;
    final maiores = [
      for (final c in cabecalho) ('${c ?? ''}'.length * 1.1),
    ];
    const amostraMax = 3000;
    final passo = dados.length <= amostraMax
        ? 1
        : (dados.length / amostraMax).ceil();
    for (var r = 0; r < dados.length; r += passo) {
      final l = dados[r];
      for (var i = 0; i < n && i < l.length; i++) {
        final t = formatar(l[i]).length.toDouble();
        if (t > maiores[i]) maiores[i] = t;
      }
    }
    return [
      for (final m in maiores)
        (m * porCaractere + margem).clamp(minimo, maximo).toDouble(),
    ];
  }

  @override
  State<TabelaVirtual> createState() => _TabelaVirtualState();
}

class _TabelaVirtualState extends State<TabelaVirtual> {
  final _h = ScrollController();
  final _v = ScrollController();
  late List<List<Object?>> _dados;
  late List<double> _larguras;

  @override
  void initState() {
    super.initState();
    _preparar();
  }

  @override
  void didUpdateWidget(covariant TabelaVirtual old) {
    super.didUpdateWidget(old);
    // Só refaz o cálculo quando os DADOS mudaram (não a cada redesenho).
    if (!identical(old.aba.linhas, widget.aba.linhas) ||
        old.aba.linhaCabecalho != widget.aba.linhaCabecalho) {
      _preparar();
    }
  }

  void _preparar() {
    _dados = widget.aba.dados;
    _larguras = TabelaVirtual.largurasPara(
        widget.aba.cabecalho, _dados, widget.formatar);
  }

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cab = widget.aba.cabecalho;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      }),
      child: LayoutBuilder(builder: (context, c) {
        // Tabela estreita: as colunas esticam até a largura da área.
        final soma = _larguras.fold(0.0, (s, w) => s + w);
        final disponivel = c.maxWidth - TabelaVirtual._barra;
        final fator = soma > 0 && soma < disponivel ? disponivel / soma : 1.0;
        final larguras = [for (final w in _larguras) w * fator];
        final largura = soma * fator;
        final altura = c.maxHeight - TabelaVirtual._barra;
        if (altura <= TabelaVirtual.alturaCabecalho) {
          return const SizedBox.shrink();
        }
        final borda = BorderSide(color: Colors.grey.shade300, width: 0.6);
        return Scrollbar(
          controller: _h,
          thumbVisibility: true,
          trackVisibility: true,
          child: SingleChildScrollView(
            controller: _h,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: TabelaVirtual._barra),
            child: SizedBox(
              width: largura + TabelaVirtual._barra,
              height: altura,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabeçalho fixo.
                  Container(
                    height: TabelaVirtual.alturaCabecalho,
                    width: largura,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border(bottom: borda),
                    ),
                    child: Row(children: [
                      for (var i = 0; i < cab.length; i++)
                        _celula(
                          '${cab[i] ?? ''}',
                          larguras[i],
                          const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.black87),
                        ),
                    ]),
                  ),
                  Expanded(
                    child: Scrollbar(
                      controller: _v,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _v,
                        padding:
                            const EdgeInsets.only(right: TabelaVirtual._barra),
                        itemExtent: TabelaVirtual.alturaLinha,
                        itemCount: _dados.length,
                        itemBuilder: (context, r) {
                          final l = _dados[r];
                          return Container(
                            decoration: BoxDecoration(
                              color: widget.corDaLinha?.call(l),
                              border: Border(bottom: borda),
                            ),
                            child: Row(children: [
                              for (var i = 0; i < cab.length; i++)
                                _celula(
                                  widget.formatar(i < l.length ? l[i] : null),
                                  larguras[i],
                                  const TextStyle(fontSize: 12),
                                ),
                            ]),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _celula(String texto, double largura, TextStyle estilo) => SizedBox(
        width: largura,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(texto,
                style: estilo, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      );
}
