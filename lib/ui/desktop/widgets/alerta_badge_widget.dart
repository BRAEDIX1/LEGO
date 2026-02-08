// lib/ui/desktop/widgets/alerta_badge_widget.dart

import 'package:flutter/material.dart';

/// Badge de alerta para itens críticos
/// Pode piscar quando crítico
class AlertaBadgeWidget extends StatefulWidget {
  final int count;
  final String label;
  final Color cor;
  final IconData icon;
  final bool piscar;
  final String? tooltip;

  const AlertaBadgeWidget({
    super.key,
    required this.count,
    required this.label,
    required this.cor,
    required this.icon,
    this.piscar = false,
    this.tooltip,
  });

  @override
  State<AlertaBadgeWidget> createState() => _AlertaBadgeWidgetState();
}

class _AlertaBadgeWidgetState extends State<AlertaBadgeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    if (widget.piscar) {
      _controller = AnimationController(
        duration: const Duration(milliseconds: 1000),
        vsync: this,
      )..repeat(reverse: true);

      _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      );
    }
  }

  @override
  void dispose() {
    if (widget.piscar) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.cor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: widget.cor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.icon,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            '${widget.count} ${widget.label}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );

    if (widget.piscar) {
      return AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Opacity(
            opacity: _animation.value,
            child: badge,
          );
        },
      );
    }

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child: badge,
      );
    }

    return badge;
  }
}

/// Badge simples sem animação
class SimpleBadge extends StatelessWidget {
  final String text;
  final Color? cor;
  final IconData? icon;

  const SimpleBadge({
    super.key,
    required this.text,
    this.cor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final corFinal = cor ?? Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: corFinal.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: corFinal),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: corFinal),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: corFinal,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}