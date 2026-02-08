// lib/ui/desktop/widgets/sidebar_navigation.dart

import 'package:flutter/material.dart';

/// Sidebar de navegação com abas do sistema
class SidebarNavigation extends StatelessWidget {
  final int abaAtiva;
  final Function(int) onAbaChanged;
  final int? totalDivergencias;
  final int? itensNaoEncontrados;
  final int? itensAguardandoC3;

  const SidebarNavigation({
    super.key,
    required this.abaAtiva,
    required this.onAbaChanged,
    this.totalDivergencias,
    this.itensNaoEncontrados,
    this.itensAguardandoC3,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.inventory_2,
                      size: 32,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'LEGO',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Análise de Inventário',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _MenuItem(
                  index: 0,
                  icon: Icons.analytics,
                  label: 'Análise Patrimonial',
                  isActive: abaAtiva == 0,
                  onTap: () => onAbaChanged(0),
                  badge: itensNaoEncontrados != null && itensNaoEncontrados! > 0
                      ? _Badge(
                    count: itensNaoEncontrados!,
                    color: Colors.red,
                    tooltip: '$itensNaoEncontrados itens não encontrados',
                  )
                      : null,
                ),
                _MenuItem(
                  index: 1,
                  icon: Icons.compare_arrows,
                  label: 'Divergências Contagens',
                  isActive: abaAtiva == 1,
                  onTap: () => onAbaChanged(1),
                  badge: totalDivergencias != null && totalDivergencias! > 0
                      ? _Badge(
                    count: totalDivergencias!,
                    color: Colors.orange,
                    tooltip: '$totalDivergencias divergências',
                  )
                      : null,
                ),
                _MenuItem(
                  index: 2,
                  icon: Icons.upload_file,
                  label: 'Importar Estoque',
                  isActive: abaAtiva == 2,
                  onTap: () => onAbaChanged(2),
                ),
                _MenuItem(
                  index: 3,
                  icon: Icons.people,
                  label: 'Participantes',
                  isActive: abaAtiva == 3,
                  onTap: () => onAbaChanged(3),
                ),
              ],
            ),
          ),

          // Footer com info adicional
          if (itensAguardandoC3 != null && itensAguardandoC3! > 0)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_empty, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$itensAguardandoC3 itens aguardando C3',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Item de menu individual
class _MenuItem extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final Widget? badge;

  const _MenuItem({
    required this.index,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isActive ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isActive
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface.withOpacity(0.6),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      color: isActive
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                if (badge != null) badge!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Badge de notificação
class _Badge extends StatelessWidget {
  final int count;
  final Color color;
  final String? tooltip;

  const _Badge({
    required this.count,
    required this.color,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        child: badge,
      );
    }

    return badge;
  }
}