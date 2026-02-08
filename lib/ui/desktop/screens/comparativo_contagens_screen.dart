// lib/ui/desktop/screens/comparativo_contagens_screen.dart

import 'package:flutter/material.dart';
import 'package:lego/models/divergencia.dart';
import 'package:lego/models/produto_consolidado.dart';
import 'package:lego/services/consolidation_service.dart';
import 'package:lego/services/inventario_service.dart';
import 'package:lego/ui/desktop/widgets/divergencia_card_widget.dart';

/// Aba de Divergências: Comparação C1 vs C2
/// Mostra APENAS produtos onde C1 ≠ C2
class ComparativoContagensScreen extends StatefulWidget {
  final String inventarioId;

  const ComparativoContagensScreen({
    super.key,
    required this.inventarioId,
  });

  @override
  State<ComparativoContagensScreen> createState() =>
      _ComparativoContagensScreenState();
}

class _ComparativoContagensScreenState
    extends State<ComparativoContagensScreen> {
  final _consolidationService = ConsolidationService();
  final _inventarioService = InventarioService();

  // IDs marcados para C3 (localmente, até salvar)
  final Set<String> _marcadosParaC3 = {};
  bool _salvandoMarcacoes = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProdutoConsolidado>>(
      stream: _consolidationService.streamProdutosConsolidados(
        widget.inventarioId,
      ),
      builder: (context, snapshot) {
        // Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Carregando divergências...'),
              ],
            ),
          );
        }

        // Erro
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Erro ao carregar dados: ${snapshot.error}'),
              ],
            ),
          );
        }

        // Sem dados
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox, size: 100, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Nenhum produto encontrado',
                  style: TextStyle(fontSize: 20),
                ),
              ],
            ),
          );
        }

        // Extrai divergências
        final todosProdutos = snapshot.data!;
        final divergencias = _consolidationService.extrairDivergencias(
          todosProdutos,
        );

        // Sem divergências
        if (divergencias.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 100, color: Colors.green.shade400),
                const SizedBox(height: 16),
                const Text(
                  '🎉 Nenhuma divergência encontrada!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Todas as contagens C1 e C2 estão de acordo',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        // Tem divergências
        return Column(
          children: [
            // Header com resumo
            _buildHeader(divergencias),

            // Lista de divergências
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: divergencias.length,
                itemBuilder: (context, index) {
                  final div = divergencias[index];
                  return DivergenciaCardWidget(
                    divergencia: div,
                    jaMarcado: _marcadosParaC3.contains(div.codigo),
                    onMarcarParaC3: () => _marcarParaC3(div.codigo),
                  );
                },
              ),
            ),

            // Footer com ações
            if (_marcadosParaC3.isNotEmpty) _buildFooterAcoes(divergencias),
          ],
        );
      },
    );
  }

  Widget _buildHeader(List<Divergencia> divergencias) {
    final totalDivergencias = divergencias.length;
    final divergenciasSignificativas = divergencias
        .where((d) => d.isSignificativa)
        .length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.orange.shade200, width: 2),
        ),
      ),
      child: Row(
        children: [
          // Ícone
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.compare_arrows,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Divergências Entre Contagens',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$totalDivergencias ${totalDivergencias == 1 ? 'produto divergente' : 'produtos divergentes'} '
                      '($divergenciasSignificativas significativas)',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
          ),

          // Estatísticas
          _buildStatCard(
            'Total C1 ≠ C2',
            totalDivergencias.toString(),
            Colors.orange,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Marcados para C3',
            _marcadosParaC3.length.toString(),
            Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String valor, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor),
      ),
      child: Column(
        children: [
          Text(
            valor,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterAcoes(List<Divergencia> divergencias) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_marcadosParaC3.length} ${_marcadosParaC3.length == 1 ? 'item marcado' : 'itens marcados'} para C3',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Estes itens serão recontados pelo Grupo C',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          // Botões
          TextButton.icon(
            onPressed: () {
              setState(() => _marcadosParaC3.clear());
            },
            icon: const Icon(Icons.clear),
            label: const Text('Limpar'),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _marcadosParaC3.clear();
                _marcadosParaC3.addAll(divergencias.map((d) => d.codigo));
              });
            },
            icon: const Icon(Icons.select_all),
            label: const Text('Marcar Todos'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _salvandoMarcacoes ? null : _salvarMarcacoesC3,
            icon: _salvandoMarcacoes
                ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.save),
            label: const Text('Salvar Marcações'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _marcarParaC3(String codigo) {
    setState(() {
      if (_marcadosParaC3.contains(codigo)) {
        _marcadosParaC3.remove(codigo);
      } else {
        _marcadosParaC3.add(codigo);
      }
    });
  }

  Future<void> _salvarMarcacoesC3() async {
    if (_marcadosParaC3.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum item marcado'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _salvandoMarcacoes = true);

    try {
      await _inventarioService.marcarItensParaC3(
        widget.inventarioId,
        _marcadosParaC3.toList(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_marcadosParaC3.length} ${_marcadosParaC3.length == 1 ? 'item marcado' : 'itens marcados'} para C3',
            ),
            backgroundColor: Colors.green,
          ),
        );

        setState(() => _marcadosParaC3.clear());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar marcações: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _salvandoMarcacoes = false);
      }
    }
  }
}