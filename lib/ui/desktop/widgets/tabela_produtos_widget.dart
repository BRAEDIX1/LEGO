// lib/ui/desktop/widgets/tabela_produtos_widget.dart

import 'package:flutter/material.dart';
import 'package:lego/models/produto_consolidado.dart';
import 'package:lego/models/balanco_financeiro.dart';
import 'package:lego/ui/desktop/widgets/produto_detail_dialog.dart';

/// Tabela completa de produtos com paginação
class TabelaProdutosWidget extends StatefulWidget {
  final List<ProdutoConsolidado> produtos;

  const TabelaProdutosWidget({
    super.key,
    required this.produtos,
  });

  @override
  State<TabelaProdutosWidget> createState() => _TabelaProdutosWidgetState();
}

class _TabelaProdutosWidgetState extends State<TabelaProdutosWidget> {
  static const int _itensPorPagina = 50;
  int _paginaAtual = 0;

  @override
  Widget build(BuildContext context) {
    final totalPaginas = (widget.produtos.length / _itensPorPagina).ceil();
    final inicio = _paginaAtual * _itensPorPagina;
    final fim = (inicio + _itensPorPagina).clamp(0, widget.produtos.length);
    final produtosPagina = widget.produtos.sublist(inicio, fim);

    return Column(
      children: [
        // Tabela
        Expanded(
          child: Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 24,
                  headingRowHeight: 56,
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 64,
                  columns: const [
                    DataColumn(label: Text('Código')),
                    DataColumn(label: Text('Descrição')),
                    DataColumn(label: Text('Unidade')),
                    DataColumn(label: Text('Sistema'), numeric: true),
                    DataColumn(label: Text('Contado'), numeric: true),
                    DataColumn(label: Text('Variação'), numeric: true),
                    DataColumn(label: Text('Unitário'), numeric: true),
                    DataColumn(label: Text('Impacto R\$'), numeric: true),
                    DataColumn(label: Text('Status')),
                  ],
                  rows: produtosPagina.map((produto) {
                    return DataRow(
                      onSelectChanged: (_) => _mostrarDetalhes(context, produto),
                      color: MaterialStateProperty.resolveWith<Color?>(
                            (states) => _getRowColor(produto),
                      ),
                      cells: [
                        DataCell(Text(
                          produto.codigo,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        )),
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: Text(
                              produto.descricao,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(Text(produto.unidade)),
                        DataCell(Text(produto.quantidadeSistema.toStringAsFixed(1))),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                produto.quantidadeContada != null
                                    ? produto.quantidadeContada!.toStringAsFixed(1)
                                    : '-',
                              ),
                              if (produto.status == StatusProduto.aguardandoC3)
                                const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(
                                    Icons.hourglass_empty,
                                    size: 16,
                                    color: Colors.orange,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        DataCell(
                          Text(
                            produto.variacao != null
                                ? '${produto.variacao! >= 0 ? '+' : ''}${produto.variacao!.toStringAsFixed(1)}'
                                : '-',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: produto.variacao != null
                                  ? (produto.variacao! > 0
                                  ? Colors.green
                                  : produto.variacao! < 0
                                  ? Colors.red
                                  : Colors.grey)
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        DataCell(Text(
                          'R\$ ${produto.valorUnitario.toStringAsFixed(2)}',
                        )),
                        DataCell(
                          Text(
                            produto.impactoFinanceiro != null
                                ? BalancoFinanceiro.zero()
                                .formatarValor(produto.impactoFinanceiro!)
                                : '-',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: produto.impactoFinanceiro != null
                                  ? (produto.impactoFinanceiro! > 0
                                  ? Colors.green
                                  : produto.impactoFinanceiro! < 0
                                  ? Colors.red
                                  : Colors.grey)
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(produto.status.emoji),
                              const SizedBox(width: 4),
                              Text(
                                produto.status.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _getStatusColor(produto.status),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (produto.status == StatusProduto.naoEncontrado)
                                const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(
                                    Icons.warning,
                                    size: 16,
                                    color: Colors.red,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),

        // Controles de paginação
        if (totalPaginas > 1)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Mostrando ${inicio + 1}-$fim de ${widget.produtos.length} itens',
                  style: const TextStyle(fontSize: 14),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.first_page),
                      onPressed: _paginaAtual > 0
                          ? () => setState(() => _paginaAtual = 0)
                          : null,
                      tooltip: 'Primeira página',
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _paginaAtual > 0
                          ? () => setState(() => _paginaAtual--)
                          : null,
                      tooltip: 'Página anterior',
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Página ${_paginaAtual + 1} de $totalPaginas',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _paginaAtual < totalPaginas - 1
                          ? () => setState(() => _paginaAtual++)
                          : null,
                      tooltip: 'Próxima página',
                    ),
                    IconButton(
                      icon: const Icon(Icons.last_page),
                      onPressed: _paginaAtual < totalPaginas - 1
                          ? () => setState(() => _paginaAtual = totalPaginas - 1)
                          : null,
                      tooltip: 'Última página',
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color? _getRowColor(ProdutoConsolidado produto) {
    switch (produto.status) {
      case StatusProduto.naoEncontrado:
        return Colors.red.shade50;
      case StatusProduto.aguardandoC3:
        return Colors.amber.shade50;
      default:
        return null;
    }
  }

  Color _getStatusColor(StatusProduto status) {
    switch (status) {
      case StatusProduto.ok:
        return Colors.green;
      case StatusProduto.sobra:
        return Colors.blue;
      case StatusProduto.falta:
        return Colors.red;
      case StatusProduto.naoEncontrado:
        return Colors.red.shade900;
      case StatusProduto.aguardandoC3:
        return Colors.orange;
    }
  }

  void _mostrarDetalhes(BuildContext context, ProdutoConsolidado produto) {
    showDialog(
      context: context,
      builder: (context) => ProdutoDetailDialog(produto: produto),
    );
  }
}