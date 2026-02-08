// lib/ui/desktop/widgets/filtros_bar_widget.dart

import 'package:flutter/material.dart';
import 'package:lego/models/produto_consolidado.dart';
import 'package:lego/services/consolidation_service.dart';

/// Barra de filtros e busca para a tabela de produtos
class FiltrosBarWidget extends StatelessWidget {
  final StatusProduto? filtroAtivo;
  final Function(StatusProduto?) onFiltroChanged;
  final String? textoBusca;
  final Function(String) onBuscaChanged;
  final OrdenacaoCriterio criterioOrdenacao;
  final bool ordenacaoCrescente;
  final Function(OrdenacaoCriterio) onOrdenacaoChanged;
  final Function() onToggleOrdem;

  const FiltrosBarWidget({
    super.key,
    required this.filtroAtivo,
    required this.onFiltroChanged,
    this.textoBusca,
    required this.onBuscaChanged,
    required this.criterioOrdenacao,
    required this.ordenacaoCrescente,
    required this.onOrdenacaoChanged,
    required this.onToggleOrdem,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Campo de busca
            SizedBox(
              width: 400,
              child: TextField(
                onChanged: onBuscaChanged,
                decoration: InputDecoration(
                  hintText: 'Buscar por código ou descrição...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: textoBusca != null && textoBusca!.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => onBuscaChanged(''),
                  )
                      : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Filtros por status
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FiltroChip(
                  label: 'Todos',
                  isSelected: filtroAtivo == null,
                  onTap: () => onFiltroChanged(null),
                ),
                _FiltroChip(
                  label: 'OK',
                  icon: Icons.check_circle,
                  cor: Colors.green,
                  isSelected: filtroAtivo == StatusProduto.ok,
                  onTap: () => onFiltroChanged(StatusProduto.ok),
                ),
                _FiltroChip(
                  label: 'Sobras',
                  icon: Icons.trending_up,
                  cor: Colors.blue,
                  isSelected: filtroAtivo == StatusProduto.sobra,
                  onTap: () => onFiltroChanged(StatusProduto.sobra),
                ),
                _FiltroChip(
                  label: 'Faltas',
                  icon: Icons.trending_down,
                  cor: Colors.red,
                  isSelected: filtroAtivo == StatusProduto.falta,
                  onTap: () => onFiltroChanged(StatusProduto.falta),
                ),
                _FiltroChip(
                  label: 'Não Encontrados',
                  icon: Icons.error_outline,
                  cor: Colors.red.shade900,
                  isSelected: filtroAtivo == StatusProduto.naoEncontrado,
                  onTap: () => onFiltroChanged(StatusProduto.naoEncontrado),
                ),
                _FiltroChip(
                  label: 'Aguardando C3',
                  icon: Icons.hourglass_empty,
                  cor: Colors.orange,
                  isSelected: filtroAtivo == StatusProduto.aguardandoC3,
                  onTap: () => onFiltroChanged(StatusProduto.aguardandoC3),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),

            // Ordenação
            Row(
              children: [
                const Text(
                  'Ordenar por:',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<OrdenacaoCriterio>(
                  value: criterioOrdenacao,
                  onChanged: (valor) {
                    if (valor != null) onOrdenacaoChanged(valor);
                  },
                  items: OrdenacaoCriterio.values.map((criterio) {
                    return DropdownMenuItem(
                      value: criterio,
                      child: Text(criterio.label),
                    );
                  }).toList(),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: Icon(
                    ordenacaoCrescente
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                  ),
                  tooltip: ordenacaoCrescente ? 'Crescente' : 'Decrescente',
                  onPressed: onToggleOrdem,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip de filtro individual
class _FiltroChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? cor;
  final bool isSelected;
  final VoidCallback onTap;

  const _FiltroChip({
    required this.label,
    this.icon,
    this.cor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final corFinal = cor ?? Theme.of(context).colorScheme.primary;

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: isSelected ? Colors.white : corFinal),
            const SizedBox(width: 6),
          ],
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: corFinal,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : corFinal,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? corFinal : corFinal.withOpacity(0.5),
        width: isSelected ? 2 : 1,
      ),
    );
  }
}