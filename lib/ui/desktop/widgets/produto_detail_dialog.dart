// lib/ui/desktop/widgets/produto_detail_dialog.dart

import 'package:flutter/material.dart';
import 'package:lego/models/produto_consolidado.dart';
import 'package:lego/models/balanco_financeiro.dart';

/// Dialog com detalhes completos do produto
/// Mostra histórico de todas as contagens e breakdown por localização
class ProdutoDetailDialog extends StatelessWidget {
  final ProdutoConsolidado produto;

  const ProdutoDetailDialog({
    super.key,
    required this.produto,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2,
                    size: 32,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          produto.codigo,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          produto.descricao,
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer
                                .withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Conteúdo
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Resumo geral
                    _buildResumoCard(context),
                    const SizedBox(height: 20),

                    // Breakdown por contagem
                    if (produto.contagem1PorLocal != null)
                      _buildContagemCard(
                        context,
                        'Contagem 1',
                        produto.contagem1PorLocal!,
                        Colors.blue,
                      ),
                    const SizedBox(height: 12),

                    if (produto.contagem2PorLocal != null)
                      _buildContagemCard(
                        context,
                        'Contagem 2',
                        produto.contagem2PorLocal!,
                        Colors.green,
                      ),
                    const SizedBox(height: 12),

                    if (produto.contagem3PorLocal != null)
                      _buildContagemCard(
                        context,
                        'Contagem 3',
                        produto.contagem3PorLocal!,
                        Colors.purple,
                      ),

                    // Alerta se aguardando C3
                    if (produto.status == StatusProduto.aguardandoC3) ...[
                      const SizedBox(height: 20),
                      _buildAlertaC3(context),
                    ],

                    // Locais divergentes
                    if (produto.temDivergencia) ...[
                      const SizedBox(height: 20),
                      _buildLocaisDivergentes(context),
                    ],
                  ],
                ),
              ),
            ),

            // Footer com ações
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumoCard(BuildContext context) {
    return Card(
      color: Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumo',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    'Sistema',
                    '${produto.quantidadeSistema.toStringAsFixed(1)} ${produto.unidade}',
                    Icons.storage,
                    Colors.grey,
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    'Contado',
                    produto.quantidadeContada != null
                        ? '${produto.quantidadeContada!.toStringAsFixed(1)} ${produto.unidade}'
                        : 'Aguardando C3',
                    Icons.inventory,
                    produto.quantidadeContada != null
                        ? Colors.blue
                        : Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    'Variação',
                    produto.variacao != null
                        ? '${produto.variacao! >= 0 ? '+' : ''}${produto.variacao!.toStringAsFixed(1)} ${produto.unidade}'
                        : '-',
                    Icons.compare_arrows,
                    produto.variacao != null
                        ? (produto.variacao! > 0
                        ? Colors.green
                        : produto.variacao! < 0
                        ? Colors.red
                        : Colors.grey)
                        : Colors.grey,
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    'Impacto Financeiro',
                    produto.impactoFinanceiro != null
                        ? BalancoFinanceiro.zero()
                        .formatarValor(produto.impactoFinanceiro!)
                        : '-',
                    Icons.attach_money,
                    produto.impactoFinanceiro != null
                        ? (produto.impactoFinanceiro! > 0
                        ? Colors.green
                        : produto.impactoFinanceiro! < 0
                        ? Colors.red
                        : Colors.grey)
                        : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    'Valor Unitário',
                    'R\$ ${produto.valorUnitario.toStringAsFixed(2)}',
                    Icons.local_offer,
                    Colors.grey,
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    'Status',
                    '${produto.status.emoji} ${produto.status.label}',
                    Icons.info_outline,
                    _getStatusColor(produto.status),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(
      String label,
      String valor,
      IconData icon,
      Color cor,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: cor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          valor,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: cor,
          ),
        ),
      ],
    );
  }

  Widget _buildContagemCard(
      BuildContext context,
      String titulo,
      Map<String, double> locais,
      Color cor,
      ) {
    final total = locais.values.fold(0.0, (sum, qtd) => sum + qtd);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: cor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Chip(
                  label: Text(
                    'Total: ${total.toStringAsFixed(1)} ${produto.unidade}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: cor.withOpacity(0.1),
                  side: BorderSide(color: cor),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: locais.entries.map((entry) {
                return Chip(
                  label: Text(
                    '${entry.key}: ${entry.value.toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: Colors.grey.shade100,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertaC3(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_empty, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Aguardando Contagem 3',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'C1 ≠ C2. Produto precisa ser recontado nas localizações '
                      'divergentes: ${produto.locaisDivergentes.join(', ')}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocaisDivergentes(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red),
              SizedBox(width: 8),
              Text(
                'Localizações Divergentes',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: produto.locaisDivergentes.map((local) {
              return Chip(
                label: Text(local),
                backgroundColor: Colors.red.shade100,
                side: BorderSide(color: Colors.red.shade300),
              );
            }).toList(),
          ),
        ],
      ),
    );
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
}