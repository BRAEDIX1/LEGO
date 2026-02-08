// lib/ui/desktop/screens/analise_patrimonial_screen.dart

import 'package:flutter/material.dart';
import 'package:lego/models/produto_consolidado.dart';
import 'package:lego/models/balanco_financeiro.dart';
import 'package:lego/services/consolidation_service.dart';
import 'package:lego/ui/desktop/widgets/balanco_summary_widget.dart';
import 'package:lego/ui/desktop/widgets/filtros_bar_widget.dart';
import 'package:lego/ui/desktop/widgets/tabela_produtos_widget.dart';
import 'package:lego/ui/desktop/widgets/alerta_badge_widget.dart';

/// Aba principal: Análise Patrimonial
/// Mostra TODOS os itens com comparação Físico vs Sistema
class AnalisePatrimonialScreen extends StatefulWidget {
  final String inventarioId;

  const AnalisePatrimonialScreen({
    super.key,
    required this.inventarioId,
  });

  @override
  State<AnalisePatrimonialScreen> createState() =>
      _AnalisePatrimonialScreenState();
}

class _AnalisePatrimonialScreenState extends State<AnalisePatrimonialScreen> {
  final _consolidationService = ConsolidationService();

  // Estado dos filtros
  StatusProduto? _filtroStatus;
  String _textoBusca = '';
  OrdenacaoCriterio _criterioOrdenacao = OrdenacaoCriterio.codigo;
  bool _ordenacaoCrescente = true;

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
                Text('Carregando produtos...'),
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
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar Novamente'),
                ),
              ],
            ),
          );
        }

        // Sem dados
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.inbox, size: 100, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Nenhum produto encontrado',
                  style: TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  'Os lançamentos dos tablets aparecerão aqui em tempo real',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        // Dados carregados
        final todosProdutos = snapshot.data!;
        final balanco = _consolidationService.calcularBalanco(todosProdutos);

        // Aplica filtros
        var produtosFiltrados = todosProdutos;

        // Filtro por status
        if (_filtroStatus != null) {
          produtosFiltrados = _consolidationService.filtrarPorStatus(
            produtosFiltrados,
            _filtroStatus!,
          );
        }

        // Filtro por busca
        if (_textoBusca.isNotEmpty) {
          produtosFiltrados = _consolidationService.filtrarPorBusca(
            produtosFiltrados,
            _textoBusca,
          );
        }

        // Ordenação
        produtosFiltrados = _consolidationService.ordenar(
          produtosFiltrados,
          _criterioOrdenacao,
          crescente: _ordenacaoCrescente,
        );

        return Column(
          children: [
            // Alertas críticos (se houver)
            if (balanco.itensNaoEncontrados > 0 ||
                balanco.itensAguardandoC3 > 0)
              _buildAlertasBar(balanco),

            // Conteúdo scrollável
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Balanço financeiro
                    BalancoSummaryWidget(balanco: balanco),

                    const SizedBox(height: 20),

                    // Filtros
                    FiltrosBarWidget(
                      filtroAtivo: _filtroStatus,
                      onFiltroChanged: (status) {
                        setState(() => _filtroStatus = status);
                      },
                      textoBusca: _textoBusca.isNotEmpty ? _textoBusca : null,
                      onBuscaChanged: (texto) {
                        setState(() => _textoBusca = texto);
                      },
                      criterioOrdenacao: _criterioOrdenacao,
                      ordenacaoCrescente: _ordenacaoCrescente,
                      onOrdenacaoChanged: (criterio) {
                        setState(() => _criterioOrdenacao = criterio);
                      },
                      onToggleOrdem: () {
                        setState(() => _ordenacaoCrescente = !_ordenacaoCrescente);
                      },
                    ),

                    const SizedBox(height: 12),

                    // Contador de resultados
                    _buildContadorResultados(
                      todosProdutos.length,
                      produtosFiltrados.length,
                    ),

                    const SizedBox(height: 12),

                    // Tabela de produtos
                    SizedBox(
                      height: 600,
                      child: TabelaProdutosWidget(
                        produtos: produtosFiltrados,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAlertasBar(BalancoFinanceiro balanco) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.red.shade200, width: 2),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          if (balanco.itensNaoEncontrados > 0)
            AlertaBadgeWidget(
              count: balanco.itensNaoEncontrados,
              label: 'itens não encontrados',
              cor: Colors.red,
              icon: Icons.error,
              piscar: true,
              tooltip: 'Itens com C1=0 e C2=0 (CRÍTICO)',
            ),
          if (balanco.itensAguardandoC3 > 0)
            AlertaBadgeWidget(
              count: balanco.itensAguardandoC3,
              label: 'aguardando C3',
              cor: Colors.orange,
              icon: Icons.hourglass_empty,
              tooltip: 'Itens com C1≠C2 que precisam ser recontados',
            ),
        ],
      ),
    );
  }

  Widget _buildContadorResultados(int total, int filtrados) {
    if (total == filtrados) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'Mostrando $total ${total == 1 ? 'produto' : 'produtos'}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            'Mostrando $filtrados de $total produtos',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _filtroStatus = null;
                _textoBusca = '';
              });
            },
            icon: const Icon(Icons.clear, size: 16),
            label: const Text('Limpar filtros'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}