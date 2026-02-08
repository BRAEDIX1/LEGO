// lib/ui/desktop/screens/comparativo_inventarios_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/services/comparativo_service.dart';

/// Tela de comparativo entre dois inventários
class ComparativoInventariosScreen extends StatefulWidget {
  const ComparativoInventariosScreen({super.key});

  @override
  State<ComparativoInventariosScreen> createState() => _ComparativoInventariosScreenState();
}

class _ComparativoInventariosScreenState extends State<ComparativoInventariosScreen>
    with SingleTickerProviderStateMixin {
  final _comparativoService = ComparativoService();
  late TabController _tabController;

  final _formatoData = DateFormat('dd/MM/yyyy');
  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _formatoNumero = NumberFormat.decimalPattern('pt_BR');
  final _formatoPct = NumberFormat.decimalPercentPattern(locale: 'pt_BR', decimalDigits: 1);

  // Seleção
  List<Inventario> _inventariosDisponiveis = [];
  Inventario? _inventarioA;
  Inventario? _inventarioB;
  bool _carregandoLista = true;

  // Resultado
  ResultadoComparativo? _resultado;
  bool _gerando = false;
  String? _erro;

  // Filtros
  String _filtroTipo = 'todos';
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _carregarInventarios();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _carregarInventarios() async {
    setState(() => _carregandoLista = true);
    
    try {
      final lista = await _comparativoService.listarInventariosParaComparacao(
        limite: 50,
      );
      setState(() {
        _inventariosDisponiveis = lista;
        _carregandoLista = false;
      });
    } catch (e) {
      setState(() {
        _erro = e.toString();
        _carregandoLista = false;
      });
    }
  }

  Future<void> _gerarComparativo() async {
    if (_inventarioA == null || _inventarioB == null) return;
    if (_inventarioA!.id == _inventarioB!.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione inventários diferentes')),
      );
      return;
    }

    setState(() {
      _gerando = true;
      _erro = null;
    });

    try {
      final resultado = await _comparativoService.gerarComparativo(
        _inventarioA!.id,
        _inventarioB!.id,
      );
      setState(() {
        _resultado = resultado;
        _gerando = false;
      });
    } catch (e) {
      setState(() {
        _erro = e.toString();
        _gerando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comparativo de Inventários'),
        bottom: _resultado != null
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.dashboard), text: 'Resumo'),
                  Tab(icon: Icon(Icons.add_circle), text: 'Novos'),
                  Tab(icon: Icon(Icons.remove_circle), text: 'Removidos'),
                  Tab(icon: Icon(Icons.change_circle), text: 'Alterados'),
                ],
              )
            : null,
      ),
      body: _resultado != null
          ? TabBarView(
              controller: _tabController,
              children: [
                _buildTabResumo(),
                _buildTabItens(_resultado!.novosItens, 'Novos Itens', Colors.green),
                _buildTabItens(_resultado!.itensRemovidos, 'Itens Removidos', Colors.red),
                _buildTabItens(_resultado!.itensAlterados, 'Itens Alterados', Colors.orange),
              ],
            )
          : _buildSelecao(),
    );
  }

  // ==================== SELEÇÃO ====================

  Widget _buildSelecao() {
    if (_carregandoLista) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_inventariosDisponiveis.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('Nenhum inventário finalizado disponível'),
            const SizedBox(height: 8),
            Text(
              'Finalize inventários para poder compará-los',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Instruções
          Card(
            color: Colors.blue.withOpacity(0.05),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Selecione dois inventários finalizados para comparar a evolução '
                      'do estoque entre eles.',
                      style: TextStyle(color: Colors.blue[800]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Seletores lado a lado
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildSeletorInventario(
                  titulo: 'Inventário Anterior (A)',
                  subtitulo: 'Base de comparação',
                  selecionado: _inventarioA,
                  cor: Colors.blue,
                  onSelecionado: (inv) => setState(() => _inventarioA = inv),
                ),
              ),
              const SizedBox(width: 24),
              // Seta
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Icon(Icons.arrow_forward, size: 32, color: Colors.grey[400]),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildSeletorInventario(
                  titulo: 'Inventário Atual (B)',
                  subtitulo: 'Para comparar',
                  selecionado: _inventarioB,
                  cor: Colors.green,
                  onSelecionado: (inv) => setState(() => _inventarioB = inv),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Botão gerar
          Center(
            child: FilledButton.icon(
              onPressed: _inventarioA != null && _inventarioB != null && !_gerando
                  ? _gerarComparativo
                  : null,
              icon: _gerando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.compare_arrows),
              label: Text(_gerando ? 'Gerando...' : 'Gerar Comparativo'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ),

          if (_erro != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.red.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_erro!, style: const TextStyle(color: Colors.red))),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSeletorInventario({
    required String titulo,
    required String subtitulo,
    required Inventario? selecionado,
    required Color cor,
    required Function(Inventario?) onSelecionado,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(subtitulo, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ],
                ),
              ],
            ),
            const Divider(),

            // Dropdown
            DropdownButtonFormField<Inventario>(
              value: selecionado,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Selecione um inventário',
              ),
              items: _inventariosDisponiveis.map((inv) {
                return DropdownMenuItem(
                  value: inv,
                  child: Text('${inv.codigo} - ${_formatoData.format(inv.dataInicio)}'),
                );
              }).toList(),
              onChanged: onSelecionado,
            ),

            // Detalhes do selecionado
            if (selecionado != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    _buildDetalhe('Código', selecionado.codigo),
                    _buildDetalhe('Material', selecionado.tipoMaterial != null 
                        ? TiposMaterial.label(selecionado.tipoMaterial!) : '-'),
                    _buildDetalhe('Depósito', selecionado.deposito ?? '-'),
                    _buildDetalhe('Itens', _formatoNumero.format(selecionado.totalItensEstoque)),
                    _buildDetalhe('Valor', _formatoMoeda.format(selecionado.valorTotalEstoque)),
                    _buildDetalhe('Data Início', _formatoData.format(selecionado.dataInicio)),
                    if (selecionado.dataFim != null)
                      _buildDetalhe('Data Fim', _formatoData.format(selecionado.dataFim!)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetalhe(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12))),
          Expanded(child: Text(valor, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  // ==================== TAB RESUMO ====================

  Widget _buildTabResumo() {
    final r = _resultado!;
    final resumo = r.resumo;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header com inventários comparados
          _buildHeaderComparacao(),
          const SizedBox(height: 24),

          // Cards de valor
          Row(
            children: [
              Expanded(child: _buildCardValor('Inventário A', resumo.valorTotalA, Colors.blue)),
              const SizedBox(width: 16),
              Expanded(child: _buildCardValor('Inventário B', resumo.valorTotalB, Colors.green)),
              const SizedBox(width: 16),
              Expanded(child: _buildCardDiferenca(resumo)),
            ],
          ),
          const SizedBox(height: 24),

          // Estatísticas de itens
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Análise de Itens', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildStatItem('Total A', resumo.totalItensA, Colors.blue)),
                      Expanded(child: _buildStatItem('Total B', resumo.totalItensB, Colors.green)),
                      Expanded(child: _buildStatItem('Em Comum', resumo.itensEmComum, Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildStatItem('Novos', resumo.itensNovos, Colors.green)),
                      Expanded(child: _buildStatItem('Removidos', resumo.itensRemovidos, Colors.red)),
                      Expanded(child: _buildStatItem('Alterados', resumo.itensAlterados, Colors.orange)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Barra de progresso
                  _buildBarraDistribuicao(resumo),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Top 5 maiores variações
          _buildTopVariacoes(),
          const SizedBox(height: 24),

          // Botão voltar
          Center(
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _resultado = null),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Nova Comparação'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderComparacao() {
    final r = _resultado!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _buildMiniCard(r.inventarioA, 'A', Colors.blue),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Icon(Icons.compare_arrows, color: Colors.grey[400], size: 32),
            ),
            _buildMiniCard(r.inventarioB, 'B', Colors.green),
            const Spacer(),
            Text(
              'Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(r.dataGeracao)}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniCard(Inventario inv, String label, Color cor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: cor,
            radius: 16,
            child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(inv.codigo, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(_formatoData.format(inv.dataInicio), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardValor(String titulo, double valor, Color cor) {
    return Card(
      color: cor.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: TextStyle(color: cor, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(
              _formatoMoeda.format(valor),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardDiferenca(ResumoComparativo resumo) {
    final isPositivo = resumo.diferencaValor >= 0;
    final cor = isPositivo ? Colors.green : Colors.red;
    final icone = isPositivo ? Icons.trending_up : Icons.trending_down;

    return Card(
      color: cor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: cor, size: 20),
                const SizedBox(width: 8),
                Text('Diferença', style: TextStyle(color: cor, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${isPositivo ? '+' : ''}${_formatoMoeda.format(resumo.diferencaValor)}',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cor),
            ),
            Text(
              '${isPositivo ? '+' : ''}${resumo.percentualVariacao.toStringAsFixed(1)}%',
              style: TextStyle(color: cor, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int valor, Color cor) {
    return Column(
      children: [
        Text(
          valor.toString(),
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: cor),
        ),
        Text(label, style: TextStyle(color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildBarraDistribuicao(ResumoComparativo resumo) {
    final total = resumo.totalItensB;
    if (total == 0) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Distribuição dos itens em B:', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: [
              if (resumo.itensSemAlteracao > 0)
                Expanded(
                  flex: resumo.itensSemAlteracao,
                  child: Container(height: 24, color: Colors.grey),
                ),
              if (resumo.itensAlterados > 0)
                Expanded(
                  flex: resumo.itensAlterados,
                  child: Container(height: 24, color: Colors.orange),
                ),
              if (resumo.itensNovos > 0)
                Expanded(
                  flex: resumo.itensNovos,
                  child: Container(height: 24, color: Colors.green),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLegenda('Sem alteração', Colors.grey),
            const SizedBox(width: 16),
            _buildLegenda('Alterados', Colors.orange),
            const SizedBox(width: 16),
            _buildLegenda('Novos', Colors.green),
          ],
        ),
      ],
    );
  }

  Widget _buildLegenda(String label, Color cor) {
    return Row(
      children: [
        Container(width: 12, height: 12, color: cor),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildTopVariacoes() {
    final top5 = _resultado!.itensAlterados.take(5).toList();
    if (top5.isEmpty) return const SizedBox();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top 5 Maiores Variações', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ...top5.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              final isPositivo = item.diferencaValor >= 0;
              final cor = isPositivo ? Colors.green : Colors.red;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: cor.withOpacity(0.1),
                  child: Text('${i + 1}', style: TextStyle(color: cor, fontWeight: FontWeight.bold)),
                ),
                title: Text(item.codigo),
                subtitle: Text(item.descricao, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isPositivo ? '+' : ''}${_formatoMoeda.format(item.diferencaValor)}',
                      style: TextStyle(color: cor, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Qtd: ${item.quantidadeA?.toStringAsFixed(0) ?? 0} → ${item.quantidadeB?.toStringAsFixed(0) ?? 0}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ==================== TABS DE ITENS ====================

  Widget _buildTabItens(List<ItemComparativo> itens, String titulo, Color cor) {
    if (itens.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Nenhum item nesta categoria', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          color: cor.withOpacity(0.1),
          child: Row(
            children: [
              Icon(Icons.list, color: cor),
              const SizedBox(width: 8),
              Text(
                '$titulo (${itens.length})',
                style: TextStyle(fontWeight: FontWeight.bold, color: cor),
              ),
            ],
          ),
        ),

        // Lista
        Expanded(
          child: ListView.builder(
            itemCount: itens.length,
            itemBuilder: (context, index) {
              final item = itens[index];
              return _buildItemTile(item, cor);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildItemTile(ItemComparativo item, Color corBase) {
    final isPositivo = item.diferencaValor >= 0;
    final corVariacao = isPositivo ? Colors.green : Colors.red;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        title: Row(
          children: [
            Text(item.codigo, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (item.lote != null && item.lote!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Lote: ${item.lote}', style: const TextStyle(fontSize: 10)),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.descricao, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: [
                if (item.quantidadeA != null)
                  Text('A: ${_formatoNumero.format(item.quantidadeA)} ', 
                      style: const TextStyle(fontSize: 11)),
                if (item.quantidadeB != null)
                  Text('B: ${_formatoNumero.format(item.quantidadeB)}',
                      style: const TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (item.tipo != TipoAlteracao.removido)
              Text(
                '${isPositivo ? '+' : ''}${_formatoMoeda.format(item.diferencaValor)}',
                style: TextStyle(
                  color: item.tipo == TipoAlteracao.novo ? corBase : corVariacao,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (item.tipo == TipoAlteracao.removido)
              Text(
                '-${_formatoMoeda.format(item.valorTotalA ?? 0)}',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }
}
