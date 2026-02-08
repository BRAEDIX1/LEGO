// lib/ui/desktop/screens/participantes_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'package:lego/models/participante.dart';
import 'package:lego/models/inventario.dart';
import 'package:lego/services/inventario_service.dart';

/// Tela de gestão de participantes com filtros e ações
class ParticipantesScreen extends StatefulWidget {
  final String inventarioId;

  const ParticipantesScreen({
    super.key,
    required this.inventarioId,
  });

  @override
  State<ParticipantesScreen> createState() => _ParticipantesScreenState();
}

class _ParticipantesScreenState extends State<ParticipantesScreen> {
  final _inventarioService = InventarioService();
  final _formatoData = DateFormat('dd/MM HH:mm');

  // Filtros
  String _filtroContagem = 'todos';
  String _filtroStatus = 'todos';
  String _busca = '';

  // Seleção para ações em lote
  final Set<String> _selecionados = {};

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('inventarios')
          .doc(widget.inventarioId)
          .snapshots(),
      builder: (context, invSnapshot) {
        final inventario = invSnapshot.hasData
            ? Inventario.fromFirestore(invSnapshot.data!)
            : null;

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('inventarios')
              .doc(widget.inventarioId)
              .collection('participantes')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text('Erro ao carregar participantes: ${snapshot.error}'),
              );
            }

            final todosParticipantes = snapshot.hasData
                ? snapshot.data!.docs
                .map((doc) => Participante.fromFirestore(
              doc as DocumentSnapshot<Map<String, dynamic>>,
              null,
            ))
                .toList()
                : <Participante>[];

            // Aplica filtros
            final participantes = _aplicarFiltros(todosParticipantes);

            // Ordena: pendentes primeiro, depois por nome
            participantes.sort((a, b) {
              if (a.status == 'solicitacao_pendente' && b.status != 'solicitacao_pendente') return -1;
              if (a.status != 'solicitacao_pendente' && b.status == 'solicitacao_pendente') return 1;
              return a.displayName.compareTo(b.displayName);
            });

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context, todosParticipantes, inventario),
                  const SizedBox(height: 16),
                  _buildFiltros(todosParticipantes),
                  const SizedBox(height: 16),
                  if (_selecionados.isNotEmpty)
                    _buildBarraAcoesLote(inventario),
                  if (participantes.isEmpty)
                    _buildEmptyState(todosParticipantes.isEmpty)
                  else
                    _buildTabelaParticipantes(context, participantes, inventario),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<Participante> _aplicarFiltros(List<Participante> participantes) {
    return participantes.where((p) {
      // Filtro de busca
      if (_busca.isNotEmpty) {
        final buscaLower = _busca.toLowerCase();
        if (!p.displayName.toLowerCase().contains(buscaLower) &&
            !(p.email?.toLowerCase().contains(buscaLower) ?? false)) {
          return false;
        }
      }

      // Filtro de contagem
      if (_filtroContagem != 'todos') {
        if (p.contagemAtual != _filtroContagem) return false;
      }

      // Filtro de status
      if (_filtroStatus != 'todos') {
        switch (_filtroStatus) {
          case 'pendentes':
            if (p.status != 'solicitacao_pendente') return false;
            break;
          case 'ativos':
            if (p.statusC1 != 'em_andamento' &&
                p.statusC2 != 'em_andamento' &&
                p.statusC3 != 'em_andamento') return false;
            break;
          case 'finalizados':
            if (p.statusC1 != 'finalizada' &&
                p.statusC2 != 'finalizada' &&
                p.statusC3 != 'finalizada') return false;
            break;
          case 'aguardando':
            final aguardando = (p.statusC1 == 'finalizada' && !p.liberadoParaC2) ||
                (p.statusC2 == 'finalizada' && !p.liberadoParaC3);
            if (!aguardando) return false;
            break;
        }
      }

      return true;
    }).toList();
  }

  Widget _buildHeader(
      BuildContext context,
      List<Participante> participantes,
      Inventario? inventario,
      ) {
    final totalParticipantes = participantes.length;
    final pendentes = participantes.where((p) => p.status == 'solicitacao_pendente').length;
    final online = participantes.where((p) => _isOnline(p.ultimoAcesso)).length;
    final aguardandoLiberacao = participantes.where((p) =>
    (p.statusC1 == 'finalizada' && !p.liberadoParaC2) ||
        (p.statusC2 == 'finalizada' && !p.liberadoParaC3)).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.people, color: Colors.white, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gestão de Participantes',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    inventario?.codigo ?? 'Carregando...',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            _buildStatChip('Total', totalParticipantes, Colors.blue),
            const SizedBox(width: 12),
            _buildStatChip('Online', online, Colors.green, icon: Icons.circle),
            const SizedBox(width: 12),
            if (pendentes > 0) ...[
              _buildStatChip('Pendentes', pendentes, Colors.orange, icon: Icons.pending),
              const SizedBox(width: 12),
            ],
            if (aguardandoLiberacao > 0)
              _buildStatChip('Aguardando', aguardandoLiberacao, Colors.purple, icon: Icons.hourglass_empty),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, int valor, Color cor, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: cor),
            const SizedBox(width: 6),
          ],
          Column(
            children: [
              Text(
                valor.toString(),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: cor,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros(List<Participante> participantes) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Busca
            Expanded(
              flex: 2,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Buscar por nome ou email...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _busca = value),
              ),
            ),
            const SizedBox(width: 16),

            // Filtro por contagem
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _filtroContagem,
                decoration: InputDecoration(
                  labelText: 'Contagem',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'todos', child: Text('Todas')),
                  DropdownMenuItem(value: 'contagem_1', child: Text('C1')),
                  DropdownMenuItem(value: 'contagem_2', child: Text('C2')),
                  DropdownMenuItem(value: 'contagem_3', child: Text('C3')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _filtroContagem = value);
                },
              ),
            ),
            const SizedBox(width: 16),

            // Filtro por status
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _filtroStatus,
                decoration: InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'todos', child: Text('Todos')),
                  DropdownMenuItem(value: 'pendentes', child: Text('Pendentes')),
                  DropdownMenuItem(value: 'ativos', child: Text('Em Contagem')),
                  DropdownMenuItem(value: 'finalizados', child: Text('Finalizados')),
                  DropdownMenuItem(value: 'aguardando', child: Text('Aguardando Lib.')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _filtroStatus = value);
                },
              ),
            ),
            const SizedBox(width: 16),

            // Limpar filtros
            if (_busca.isNotEmpty || _filtroContagem != 'todos' || _filtroStatus != 'todos')
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _busca = '';
                    _filtroContagem = 'todos';
                    _filtroStatus = 'todos';
                  });
                },
                icon: const Icon(Icons.clear),
                label: const Text('Limpar'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarraAcoesLote(Inventario? inventario) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.check_box, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            Text(
              '${_selecionados.length} selecionado(s)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
            const SizedBox(width: 16),
            TextButton.icon(
              onPressed: () => setState(() => _selecionados.clear()),
              icon: const Icon(Icons.close),
              label: const Text('Limpar seleção'),
            ),
            const Spacer(),
            // Ações em lote
            FilledButton.icon(
              onPressed: () => _liberarEmLote('contagem_2'),
              icon: const Icon(Icons.lock_open),
              label: const Text('Liberar para C2'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _liberarEmLote('contagem_3'),
              icon: const Icon(Icons.lock_open),
              label: const Text('Liberar para C3'),
              style: FilledButton.styleFrom(backgroundColor: Colors.purple),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool semNenhum) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              semNenhum ? Icons.people_outline : Icons.filter_list_off,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              semNenhum
                  ? 'Nenhum participante ainda'
                  : 'Nenhum resultado para os filtros aplicados',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            if (!semNenhum) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _busca = '';
                    _filtroContagem = 'todos';
                    _filtroStatus = 'todos';
                  });
                },
                child: const Text('Limpar filtros'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTabelaParticipantes(
      BuildContext context,
      List<Participante> participantes,
      Inventario? inventario,
      ) {
    final scrollController = ScrollController();

    return Card(
      child: Scrollbar(
        controller: scrollController,
        thumbVisibility: true,
        thickness: 12,
        child: SingleChildScrollView(
          controller: scrollController,
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 56,
            dataRowMinHeight: 72,
            dataRowMaxHeight: 80,
            showCheckboxColumn: true,
            columns: [
              const DataColumn(label: Text('Participante')),
              const DataColumn(label: Text('Status')),
              const DataColumn(label: Text('Contagem')),
              const DataColumn(label: Text('C1'), numeric: true),
              const DataColumn(label: Text('C2'), numeric: true),
              if (inventario?.isCompleta ?? true)
                const DataColumn(label: Text('C3'), numeric: true),
              const DataColumn(label: Text('Último Acesso')),
              const DataColumn(label: Text('Ações')),
            ],
            rows: participantes.map((p) {
              final isSelected = _selecionados.contains(p.uid);
              final isOnline = _isOnline(p.ultimoAcesso);

              return DataRow(
                selected: isSelected,
                onSelectChanged: (selected) {
                  setState(() {
                    if (selected == true) {
                      _selecionados.add(p.uid);
                    } else {
                      _selecionados.remove(p.uid);
                    }
                  });
                },
                cells: [
                  // Participante
                  DataCell(
                    Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.blue.shade100,
                              child: Text(
                                p.displayName.isNotEmpty
                                    ? p.displayName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: isOnline ? Colors.green : Colors.grey,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              p.displayName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            if (p.email != null)
                              Text(
                                p.email!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Status geral
                  DataCell(_buildStatusGeral(p)),

                  // Contagem atual
                  DataCell(_buildContagemAtualChip(p.contagemAtual)),

                  // C1
                  DataCell(_buildCelulaContagem(p.statusC1, p.totalLancamentosC1)),

                  // C2
                  DataCell(_buildCelulaContagem(p.statusC2, p.totalLancamentosC2)),

                  // C3
                  if (inventario?.isCompleta ?? true)
                    DataCell(_buildCelulaContagem(p.statusC3, p.totalLancamentosC3)),

                  // Último acesso
                  DataCell(
                    Text(
                      _formatarUltimoAcesso(p.ultimoAcesso),
                      style: TextStyle(
                        color: isOnline ? Colors.green : Colors.grey[600],
                        fontWeight: isOnline ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),

                  // Ações
                  DataCell(_buildAcoes(context, p, inventario)),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusGeral(Participante p) {
    if (p.status == 'solicitacao_pendente') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.shade100,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.orange),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pending, size: 14, color: Colors.orange.shade800),
            const SizedBox(width: 4),
            Text(
              'Pendente',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    // Verifica se aguarda liberação
    if ((p.statusC1 == 'finalizada' && !p.liberadoParaC2) ||
        (p.statusC2 == 'finalizada' && !p.liberadoParaC3)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.purple.shade100,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.purple),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_empty, size: 14, color: Colors.purple.shade800),
            const SizedBox(width: 4),
            Text(
              'Aguardando',
              style: TextStyle(
                fontSize: 12,
                color: Colors.purple.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    // Em andamento
    if (p.statusC1 == 'em_andamento' ||
        p.statusC2 == 'em_andamento' ||
        p.statusC3 == 'em_andamento') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.shade100,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.blue),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit, size: 14, color: Colors.blue.shade800),
            const SizedBox(width: 4),
            Text(
              'Contando',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return const Text('-');
  }

  Widget _buildContagemAtualChip(String? contagem) {
    Color cor;
    String label;

    switch (contagem) {
      case 'contagem_1':
        cor = Colors.blue;
        label = 'C1';
        break;
      case 'contagem_2':
        cor = Colors.green;
        label = 'C2';
        break;
      case 'contagem_3':
        cor = Colors.purple;
        label = 'C3';
        break;
      default:
        cor = Colors.grey;
        label = '-';
    }

    return Chip(
      label: Text(label, style: TextStyle(fontSize: 12, color: cor)),
      backgroundColor: cor.withOpacity(0.1),
      side: BorderSide(color: cor),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildCelulaContagem(String? status, int lancamentos) {
    IconData icon;
    Color cor;

    switch (status) {
      case 'em_andamento':
        icon = Icons.edit;
        cor = Colors.blue;
        break;
      case 'finalizada':
        icon = Icons.check_circle;
        cor = Colors.green;
        break;
      case 'bloqueada':
        icon = Icons.lock;
        cor = Colors.grey;
        break;
      case 'nao_participou':
        icon = Icons.remove_circle_outline;
        cor = Colors.grey;
        break;
      default:
        icon = Icons.remove;
        cor = Colors.grey;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: cor),
        const SizedBox(width: 4),
        Text(
          lancamentos.toString(),
          style: TextStyle(
            fontWeight: status == 'em_andamento' || status == 'finalizada'
                ? FontWeight.bold
                : FontWeight.normal,
            color: cor,
          ),
        ),
      ],
    );
  }

  Widget _buildAcoes(BuildContext context, Participante p, Inventario? inventario) {
    // Solicitação pendente
    if (p.status == 'solicitacao_pendente') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Aprovar para ${p.contagemSolicitada ?? "contagem"}',
            child: IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              onPressed: () => _aprovarSolicitacao(p),
            ),
          ),
          Tooltip(
            message: 'Rejeitar',
            child: IconButton(
              icon: const Icon(Icons.cancel, color: Colors.red),
              onPressed: () => _rejeitarSolicitacao(p),
            ),
          ),
        ],
      );
    }

    // Ações de liberação
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Liberar C2
        if (p.statusC1 == 'finalizada' && !p.liberadoParaC2)
          Tooltip(
            message: 'Liberar para C2',
            child: IconButton(
              icon: const Icon(Icons.lock_open, color: Colors.green),
              onPressed: () => _liberarContagem(p, 'contagem_2'),
            ),
          ),

        // Liberar C3
        if (p.statusC2 == 'finalizada' && !p.liberadoParaC3 && (inventario?.isCompleta ?? true))
          Tooltip(
            message: 'Liberar para C3',
            child: IconButton(
              icon: const Icon(Icons.lock_open, color: Colors.purple),
              onPressed: () => _liberarContagem(p, 'contagem_3'),
            ),
          ),

        // Detalhes
        Tooltip(
          message: 'Ver detalhes',
          child: IconButton(
            icon: Icon(Icons.info_outline, color: Colors.grey[600]),
            onPressed: () => _mostrarDetalhes(p),
          ),
        ),
      ],
    );
  }

  // ==================== HELPERS ====================

  bool _isOnline(DateTime? ultimoAcesso) {
    if (ultimoAcesso == null) return false;
    return DateTime.now().difference(ultimoAcesso).inMinutes < 5;
  }

  String _formatarUltimoAcesso(DateTime? data) {
    if (data == null) return 'Nunca';

    final diff = DateTime.now().difference(data);
    if (diff.inMinutes < 1) return 'Agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return _formatoData.format(data);
  }

  // ==================== AÇÕES ====================

  Future<void> _liberarContagem(Participante p, String proximaContagem) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Liberar Contagem'),
        content: Text(
          'Liberar ${p.displayName} para iniciar ${proximaContagem.replaceAll('contagem_', 'Contagem ')}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Liberar'),
          ),
        ],
      ),
    );

    if (confirma != true) return;

    try {
      await _inventarioService.liberarProximaContagem(
        widget.inventarioId,
        p.uid,
        proximaContagem,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${p.displayName} liberado para ${proximaContagem.replaceAll('contagem_', 'C')}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _liberarEmLote(String proximaContagem) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Liberar em Lote'),
        content: Text(
          'Liberar ${_selecionados.length} participante(s) para ${proximaContagem.replaceAll('contagem_', 'Contagem ')}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Liberar Todos'),
          ),
        ],
      ),
    );

    if (confirma != true) return;

    int sucesso = 0;
    int erro = 0;

    for (final uid in _selecionados) {
      try {
        await _inventarioService.liberarProximaContagem(
          widget.inventarioId,
          uid,
          proximaContagem,
        );
        sucesso++;
      } catch (e) {
        erro++;
      }
    }

    setState(() => _selecionados.clear());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$sucesso liberado(s), $erro erro(s)'),
          backgroundColor: erro == 0 ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  Future<void> _aprovarSolicitacao(Participante p) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar Solicitação'),
        content: Text(
          'Aprovar ${p.displayName} para ${p.contagemSolicitada ?? "contagem"}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Aprovar'),
          ),
        ],
      ),
    );

    if (confirma != true) return;

    try {
      await _inventarioService.aprovarParticipacao(
        widget.inventarioId,
        p.uid,
        p.contagemSolicitada ?? 'contagem_1',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${p.displayName} aprovado!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rejeitarSolicitacao(Participante p) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeitar Solicitação'),
        content: Text(
          'Rejeitar solicitação de ${p.displayName}?\n\nO participante poderá solicitar novamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );

    if (confirma != true) return;

    try {
      await _inventarioService.rejeitarParticipacao(widget.inventarioId, p.uid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitação rejeitada'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _mostrarDetalhes(Participante p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.displayName),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.email != null) _buildDetalheItem('Email', p.email!),
              _buildDetalheItem('Primeiro acesso', _formatarData(p.primeiroAcesso)),
              _buildDetalheItem('Último acesso', _formatarData(p.ultimoAcesso)),
              const Divider(),
              const Text('Contagem 1', style: TextStyle(fontWeight: FontWeight.bold)),
              _buildDetalheItem('Status', p.statusC1 ?? '-'),
              _buildDetalheItem('Lançamentos', p.totalLancamentosC1.toString()),
              _buildDetalheItem('Iniciou', _formatarData(p.iniciouC1Em)),
              _buildDetalheItem('Finalizou', _formatarData(p.finalizouC1Em)),
              const Divider(),
              const Text('Contagem 2', style: TextStyle(fontWeight: FontWeight.bold)),
              _buildDetalheItem('Status', p.statusC2 ?? '-'),
              _buildDetalheItem('Lançamentos', p.totalLancamentosC2.toString()),
              _buildDetalheItem('Liberado', p.liberadoParaC2 ? 'Sim' : 'Não'),
              const Divider(),
              const Text('Contagem 3', style: TextStyle(fontWeight: FontWeight.bold)),
              _buildDetalheItem('Status', p.statusC3 ?? '-'),
              _buildDetalheItem('Lançamentos', p.totalLancamentosC3.toString()),
              _buildDetalheItem('Liberado', p.liberadoParaC3 ? 'Sim' : 'Não'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetalheItem(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: Colors.grey[600])),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }

  String _formatarData(DateTime? data) {
    if (data == null) return '-';
    return DateFormat('dd/MM/yyyy HH:mm').format(data);
  }
}