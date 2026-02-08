// lib/ui/desktop/widgets/balanco_summary_widget.dart

import 'package:flutter/material.dart';
import 'package:lego/models/balanco_financeiro.dart';

/// Widget que mostra o resumo do balanço financeiro
/// Atualiza em tempo real via StreamBuilder
class BalancoSummaryWidget extends StatelessWidget {
  final BalancoFinanceiro balanco;

  const BalancoSummaryWidget({
    super.key,
    required this.balanco,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Balanço Financeiro',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Status badge
                _StatusBadge(balanco: balanco),
              ],
            ),
            const SizedBox(height: 20),

            // Grid de valores
            LayoutBuilder(
              builder: (context, constraints) {
                // Usa grid responsivo
                final usarGrid = constraints.maxWidth > 600;

                if (usarGrid) {
                  return Row(
                    children: [
                      Expanded(
                        child: _ValorCard(
                          label: 'Sobras',
                          valor: balanco.totalSobras,
                          quantidade: balanco.quantidadeSobras,
                          cor: Colors.green,
                          icon: Icons.trending_up,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ValorCard(
                          label: 'Faltas',
                          valor: balanco.totalFaltas,
                          quantidade: balanco.quantidadeFaltas,
                          cor: Colors.red,
                          icon: Icons.trending_down,
                          subtitulo: 'Inclui imposto (21.95%)',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ValorCard(
                          label: 'Saldo Líquido',
                          valor: balanco.saldoLiquido,
                          cor: balanco.isPrejuizo
                              ? Colors.red
                              : balanco.isLucro
                              ? Colors.green
                              : Colors.grey,
                          icon: balanco.isPrejuizo
                              ? Icons.arrow_downward
                              : balanco.isLucro
                              ? Icons.arrow_upward
                              : Icons.remove,
                          destaque: true,
                        ),
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      _ValorCard(
                        label: 'Sobras',
                        valor: balanco.totalSobras,
                        quantidade: balanco.quantidadeSobras,
                        cor: Colors.green,
                        icon: Icons.trending_up,
                      ),
                      const SizedBox(height: 12),
                      _ValorCard(
                        label: 'Faltas',
                        valor: balanco.totalFaltas,
                        quantidade: balanco.quantidadeFaltas,
                        cor: Colors.red,
                        icon: Icons.trending_down,
                        subtitulo: 'Inclui imposto (21.95%)',
                      ),
                      const SizedBox(height: 12),
                      _ValorCard(
                        label: 'Saldo Líquido',
                        valor: balanco.saldoLiquido,
                        cor: balanco.isPrejuizo
                            ? Colors.red
                            : balanco.isLucro
                            ? Colors.green
                            : Colors.grey,
                        icon: balanco.isPrejuizo
                            ? Icons.arrow_downward
                            : balanco.isLucro
                            ? Icons.arrow_upward
                            : Icons.remove,
                        destaque: true,
                      ),
                    ],
                  );
                }
              },
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),

            // Estatísticas adicionais
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _MiniStat(
                  label: 'Total de itens',
                  valor: balanco.totalItens.toString(),
                  icon: Icons.inventory_2,
                ),
                _MiniStat(
                  label: 'Itens OK',
                  valor: balanco.itensOk.toString(),
                  icon: Icons.check_circle,
                  cor: Colors.green,
                ),
                if (balanco.itensNaoEncontrados > 0)
                  _MiniStat(
                    label: 'Não encontrados',
                    valor: balanco.itensNaoEncontrados.toString(),
                    icon: Icons.error_outline,
                    cor: Colors.red,
                  ),
                if (balanco.itensAguardandoC3 > 0)
                  _MiniStat(
                    label: 'Aguardando C3',
                    valor: balanco.itensAguardandoC3.toString(),
                    icon: Icons.hourglass_empty,
                    cor: Colors.orange,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Card de valor individual
class _ValorCard extends StatelessWidget {
  final String label;
  final double valor;
  final int? quantidade;
  final Color cor;
  final IconData icon;
  final String? subtitulo;
  final bool destaque;

  const _ValorCard({
    required this.label,
    required this.valor,
    this.quantidade,
    required this.cor,
    required this.icon,
    this.subtitulo,
    this.destaque = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: destaque ? cor.withOpacity(0.1) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: destaque ? cor : Colors.grey.shade300,
          width: destaque ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cor, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            BalancoFinanceiro.zero().formatarValor(valor),
            style: TextStyle(
              fontSize: destaque ? 24 : 20,
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
          if (quantidade != null) ...[
            const SizedBox(height: 4),
            Text(
              '$quantidade ${quantidade == 1 ? 'item' : 'itens'}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
          if (subtitulo != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitulo!,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Badge de status do balanço
class _StatusBadge extends StatelessWidget {
  final BalancoFinanceiro balanco;

  const _StatusBadge({required this.balanco});

  @override
  Widget build(BuildContext context) {
    final cor = balanco.isPrejuizo
        ? Colors.red
        : balanco.isLucro
        ? Colors.green
        : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            balanco.statusEmoji,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 6),
          Text(
            balanco.statusDescricao,
            style: TextStyle(
              color: cor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini estatística
class _MiniStat extends StatelessWidget {
  final String label;
  final String valor;
  final IconData icon;
  final Color? cor;

  const _MiniStat({
    required this.label,
    required this.valor,
    required this.icon,
    this.cor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: cor ?? Colors.grey[600]),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[700],
          ),
        ),
        Text(
          valor,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: cor ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}