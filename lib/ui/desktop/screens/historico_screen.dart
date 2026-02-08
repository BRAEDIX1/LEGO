// lib/ui/desktop/screens/historico_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/services/inventario_service.dart';
import 'package:lego/ui/desktop/screens/detalhe_inventario_screen.dart';
import 'package:lego/ui/desktop/screens/relatorio_screen.dart';

/// Tela de histórico de inventários
class HistoricoScreen extends StatefulWidget {
  const HistoricoScreen({super.key});

  @override
  State<HistoricoScreen> createState() => _HistoricoScreenState();
}

class _HistoricoScreenState extends State<HistoricoScreen> {
  final _inventarioService = InventarioService();

  // Filtros
  String _filtroStatus = 'todos';
  String _filtroTipoMaterial = 'todos';
  String _filtroPeriodo = 'todos';
  String _busca = '';

  // Paginação
  int _limite = 20;
  bool _carregandoMais = false;

  final _formatoData = DateFormat('dd/MM/yyyy');
  final _formatoDataHora = DateFormat('dd/MM/yyyy HH:mm');
  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Inventários'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtros
          _buildBarraFiltros(),
          const Divider(height: 1),

          // Lista
          Expanded(
            child: _buildListaInventarios(),
          ),
        ],
      ),
    );
  }

  Widget _buildBarraFiltros() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                // Busca
                Expanded(
                  flex: 2,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Buscar por código ou descrição...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _busca = v),
                  ),
                ),
                const SizedBox(width: 16),

                // Filtro de status
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _filtroStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'todos', child: Text('Todos')),
                      DropdownMenuItem(value: 'emAndamento', child: Text('Em Andamento')),
                      DropdownMenuItem(value: 'finalizado', child: Text('Finalizados')),
                      DropdownMenuItem(value: 'cancelado', child: Text('Cancelados')),
                    ],
                    onChanged: (v) => setState(() => _filtroStatus = v ?? 'todos'),
                  ),
                ),
                const SizedBox(width: 16),

                // Filtro de tipo de material
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _filtroTipoMaterial,
                    decoration: const InputDecoration(
                      labelText: 'Tipo Material',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: 'todos', child: Text('Todos')),
                      ...TiposMaterial.todos.map((tipo) => DropdownMenuItem(
                        value: tipo,
                        child: Text(TiposMaterial.label(tipo)),
                      )),
                    ],
                    onChanged: (v) => setState(() => _filtroTipoMaterial = v ?? 'todos'),
                  ),
                ),
                const SizedBox(width: 16),

                // Filtro de período
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _filtroPeriodo,
                    decoration: const InputDecoration(
                      labelText: 'Período',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'todos', child: Text('Todos')),
                      DropdownMenuItem(value: '7dias', child: Text('Últimos 7 dias')),
                      DropdownMenuItem(value: '30dias', child: Text('Últimos 30 dias')),
                      DropdownMenuItem(value: '90dias', child: Text('Últimos 90 dias')),
                      DropdownMenuItem(value: 'ano', child: Text('Este ano')),
                    ],
                    onChanged: (v) => setState(() => _filtroPeriodo = v ?? 'todos'),
                  ),
                ),
              ],
            ),

            // Chips de filtros ativos
            if (_temFiltrosAtivos()) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Filtros ativos: ', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 8),
                  if (_filtroStatus != 'todos')
                    _buildChipFiltro('Status: $_filtroStatus', () => setState(() => _filtroStatus = 'todos')),
                  if (_filtroTipoMaterial != 'todos')
                    _buildChipFiltro('Tipo: ${TiposMaterial.label(_filtroTipoMaterial)}', () => setState(() => _filtroTipoMaterial = 'todos')),
                  if (_filtroPeriodo != 'todos')
                    _buildChipFiltro('Período: $_filtroPeriodo', () => setState(() => _filtroPeriodo = 'todos')),
                  if (_busca.isNotEmpty)
                    _buildChipFiltro('Busca: $_busca', () => setState(() => _busca = '')),
                  const Spacer(),
                  TextButton(
                    onPressed: _limparFiltros,
                    child: const Text('Limpar todos'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChipFiltro(String label, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        deleteIcon: const Icon(Icons.close, size: 16),
        onDeleted: onRemove,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  bool _temFiltrosAtivos() {
    return _filtroStatus != 'todos' ||
        _filtroTipoMaterial != 'todos' ||
        _filtroPeriodo != 'todos' ||
        _busca.isNotEmpty;
  }

  void _limparFiltros() {
    setState(() {
      _filtroStatus = 'todos';
      _filtroTipoMaterial = 'todos';
      _filtroPeriodo = 'todos';
      _busca = '';
    });
  }

  Widget _buildListaInventarios() {
    return StreamBuilder<QuerySnapshot>(
      stream: _buildQuery().snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Erro: ${snapshot.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          );
        }

        var inventarios = snapshot.data?.docs
            .map((doc) => Inventario.fromFirestore(doc))
            .toList() ?? [];

        // Aplica filtros locais (busca)
        if (_busca.isNotEmpty) {
          final buscaLower = _busca.toLowerCase();
          inventarios = inventarios.where((inv) =>
          inv.codigo.toLowerCase().contains(buscaLower) ||
              (inv.descricao?.toLowerCase().contains(buscaLower) ?? false) ||
              (inv.deposito?.toLowerCase().contains(buscaLower) ?? false)
          ).toList();
        }

        if (inventarios.isEmpty) {
          return _buildEmptyState();
        }

        // Agrupa por mês/ano
        final agrupados = _agruparPorMes(inventarios);

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: agrupados.length,
          itemBuilder: (context, index) {
            final grupo = agrupados[index];
            return _buildGrupoMes(grupo['label'], grupo['inventarios']);
          },
        );
      },
    );
  }

  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('inventarios')
        .orderBy('data_inicio', descending: true)
        .limit(_limite);

    // Filtro de status
    if (_filtroStatus != 'todos') {
      query = query.where('status', isEqualTo: _filtroStatus);
    }

    // Filtro de tipo de material
    if (_filtroTipoMaterial != 'todos') {
      query = query.where('tipo_material', isEqualTo: _filtroTipoMaterial);
    }

    // Filtro de período
    if (_filtroPeriodo != 'todos') {
      DateTime dataLimite;
      switch (_filtroPeriodo) {
        case '7dias':
          dataLimite = DateTime.now().subtract(const Duration(days: 7));
          break;
        case '30dias':
          dataLimite = DateTime.now().subtract(const Duration(days: 30));
          break;
        case '90dias':
          dataLimite = DateTime.now().subtract(const Duration(days: 90));
          break;
        case 'ano':
          dataLimite = DateTime(DateTime.now().year, 1, 1);
          break;
        default:
          dataLimite = DateTime(2000);
      }
      query = query.where('data_inicio', isGreaterThanOrEqualTo: Timestamp.fromDate(dataLimite));
    }

    return query;
  }

  List<Map<String, dynamic>> _agruparPorMes(List<Inventario> inventarios) {
    final grupos = <String, List<Inventario>>{};
    final formatoMes = DateFormat('MMMM yyyy', 'pt_BR');

    for (final inv in inventarios) {
      final label = formatoMes.format(inv.dataInicio);
      grupos.putIfAbsent(label, () => []).add(inv);
    }

    return grupos.entries.map((e) => {
      'label': e.key,
      'inventarios': e.value,
    }).toList();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _temFiltrosAtivos()
                ? 'Nenhum inventário encontrado com os filtros aplicados'
                : 'Nenhum inventário registrado',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          if (_temFiltrosAtivos()) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: _limparFiltros,
              child: const Text('Limpar filtros'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrupoMes(String label, List<Inventario> inventarios) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${inventarios.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Expanded(child: Divider(indent: 12)),
            ],
          ),
        ),
        ...inventarios.map((inv) => _buildCardInventario(inv)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCardInventario(Inventario inv) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _abrirDetalhe(inv),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Ícone de status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getCorStatus(inv.status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getIconeStatus(inv.status),
                  color: _getCorStatus(inv.status),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),

              // Informações principais
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          inv.codigo,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildChipStatus(inv.status),
                        if (inv.tipoContagem == TipoContagem.simples) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'SIMPLES',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (inv.tipoMaterial != null) ...[
                          Icon(Icons.category, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            TiposMaterial.label(inv.tipoMaterial!),
                            style: TextStyle(color: Colors.grey[600], fontSize: 13),
                          ),
                          const SizedBox(width: 16),
                        ],
                        if (inv.deposito != null) ...[
                          Icon(Icons.warehouse, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            inv.deposito!,
                            style: TextStyle(color: Colors.grey[600], fontSize: 13),
                          ),
                          const SizedBox(width: 16),
                        ],
                        Icon(Icons.inventory_2, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${inv.totalItensEstoque} itens',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ),
                    if (inv.descricao != null && inv.descricao!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        inv.descricao!,
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Datas e valor
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatoData.format(inv.dataInicio),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (inv.dataFim != null)
                    Text(
                      'até ${_formatoData.format(inv.dataFim!)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  const SizedBox(height: 4),
                  if (inv.valorTotalEstoque > 0)
                    Text(
                      _formatoMoeda.format(inv.valorTotalEstoque),
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),

              // Ações
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (action) => _executarAcao(action, inv),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'detalhes',
                    child: ListTile(
                      leading: Icon(Icons.visibility),
                      title: Text('Ver detalhes'),
                      dense: true,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'relatorio',
                    child: ListTile(
                      leading: Icon(Icons.assessment),
                      title: Text('Ver relatório'),
                      dense: true,
                    ),
                  ),
                  if (inv.status != StatusInventario.finalizado &&
                      inv.status != StatusInventario.cancelado)
                    const PopupMenuItem(
                      value: 'continuar',
                      child: ListTile(
                        leading: Icon(Icons.play_arrow),
                        title: Text('Continuar'),
                        dense: true,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChipStatus(StatusInventario status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _getCorStatus(status).withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _getCorStatus(status)),
      ),
      child: Text(
        _getLabelStatus(status),
        style: TextStyle(
          color: _getCorStatus(status),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getCorStatus(StatusInventario status) {
    switch (status) {
      case StatusInventario.rascunho:
        return Colors.grey;
      case StatusInventario.aguardando:
        return Colors.orange;
      case StatusInventario.emAndamento:
        return Colors.blue;
      case StatusInventario.finalizado:
        return Colors.green;
      case StatusInventario.cancelado:
        return Colors.red;
    }
  }

  IconData _getIconeStatus(StatusInventario status) {
    switch (status) {
      case StatusInventario.rascunho:
        return Icons.edit_note;
      case StatusInventario.aguardando:
        return Icons.hourglass_empty;
      case StatusInventario.emAndamento:
        return Icons.play_circle;
      case StatusInventario.finalizado:
        return Icons.check_circle;
      case StatusInventario.cancelado:
        return Icons.cancel;
    }
  }

  String _getLabelStatus(StatusInventario status) {
    switch (status) {
      case StatusInventario.rascunho:
        return 'Rascunho';
      case StatusInventario.aguardando:
        return 'Aguardando';
      case StatusInventario.emAndamento:
        return 'Em Andamento';
      case StatusInventario.finalizado:
        return 'Finalizado';
      case StatusInventario.cancelado:
        return 'Cancelado';
    }
  }

  void _abrirDetalhe(Inventario inv) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetalheInventarioScreen(inventarioId: inv.id),
      ),
    );
  }

  void _executarAcao(String action, Inventario inv) {
    switch (action) {
      case 'detalhes':
        _abrirDetalhe(inv);
        break;
      case 'relatorio':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RelatorioScreen(inventarioId: inv.id),
          ),
        );
        break;
      case 'continuar':
      // Volta para controle de contagem
        Navigator.of(context).pop(inv);
        break;
    }
  }
}