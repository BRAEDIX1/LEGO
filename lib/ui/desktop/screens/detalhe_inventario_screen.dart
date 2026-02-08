// lib/ui/desktop/screens/detalhe_inventario_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/models/participante.dart';
import 'package:lego/services/relatorio_service.dart';
import 'package:lego/ui/desktop/screens/relatorio_screen.dart';

/// Tela de detalhes de um inventário específico
class DetalheInventarioScreen extends StatefulWidget {
  final String inventarioId;

  const DetalheInventarioScreen({
    super.key,
    required this.inventarioId,
  });

  @override
  State<DetalheInventarioScreen> createState() => _DetalheInventarioScreenState();
}

class _DetalheInventarioScreenState extends State<DetalheInventarioScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _formatoData = DateFormat('dd/MM/yyyy');
  final _formatoDataHora = DateFormat('dd/MM/yyyy HH:mm');
  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _formatoNumero = NumberFormat.decimalPattern('pt_BR');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('inventarios')
          .doc(widget.inventarioId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Inventário')),
            body: const Center(
              child: Text('Inventário não encontrado'),
            ),
          );
        }

        final inventario = Inventario.fromFirestore(snapshot.data!);

        return Scaffold(
          appBar: AppBar(
            title: Text(inventario.codigo),
            actions: [
              FilledButton.icon(
                onPressed: () => _abrirRelatorio(inventario),
                icon: const Icon(Icons.assessment),
                label: const Text('Ver Relatório'),
              ),
              const SizedBox(width: 16),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.info), text: 'Geral'),
                Tab(icon: Icon(Icons.people), text: 'Participantes'),
                Tab(icon: Icon(Icons.inventory_2), text: 'Estoque'),
                Tab(icon: Icon(Icons.timeline), text: 'Timeline'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildTabGeral(inventario),
              _buildTabParticipantes(inventario),
              _buildTabEstoque(inventario),
              _buildTabTimeline(inventario),
            ],
          ),
        );
      },
    );
  }

  // ==================== TAB GERAL ====================

  Widget _buildTabGeral(Inventario inventario) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card de status
          _buildCardStatus(inventario),
          const SizedBox(height: 20),

          // Informações gerais
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildCardInformacoes(inventario)),
              const SizedBox(width: 20),
              Expanded(child: _buildCardContagens(inventario)),
            ],
          ),
          const SizedBox(height: 20),

          // Estatísticas de estoque
          _buildCardEstatisticasEstoque(inventario),
        ],
      ),
    );
  }

  Widget _buildCardStatus(Inventario inventario) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getCorStatus(inventario.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                _getIconeStatus(inventario.status),
                color: _getCorStatus(inventario.status),
                size: 40,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        inventario.codigo,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildChipStatus(inventario.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (inventario.descricao != null && inventario.descricao!.isNotEmpty)
                    Text(
                      inventario.descricao!,
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                ],
              ),
            ),
            // Duração
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Início: ${_formatoDataHora.format(inventario.dataInicio)}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (inventario.dataFim != null)
                  Text(
                    'Fim: ${_formatoDataHora.format(inventario.dataFim!)}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                const SizedBox(height: 8),
                Text(
                  _calcularDuracao(inventario),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardInformacoes(Inventario inventario) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 8),
                const Text(
                  'Informações',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(),
            _buildLinhaInfo('Tipo de Material',
                inventario.tipoMaterial != null ? TiposMaterial.label(inventario.tipoMaterial!) : '-'),
            _buildLinhaInfo('Tipo de Contagem', inventario.tipoContagemLabel),
            _buildLinhaInfo('Depósito', inventario.deposito ?? '-'),
            _buildLinhaInfo('Criado por', inventario.criadoPor ?? '-'),
            _buildLinhaInfo('Total de Itens', _formatoNumero.format(inventario.totalItensEstoque)),
            _buildLinhaInfo('Valor Total', _formatoMoeda.format(inventario.valorTotalEstoque)),
          ],
        ),
      ),
    );
  }

  Widget _buildCardContagens(Inventario inventario) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.format_list_numbered),
                const SizedBox(width: 8),
                const Text(
                  'Contagens',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(),
            _buildLinhaContagem(
              'Contagem 1',
              inventario.contagens['contagem_1']?.toMap(),
              Colors.blue,
              inventario.contagemAtiva == 'contagem_1',
            ),
            _buildLinhaContagem(
              'Contagem 2',
              inventario.contagens['contagem_2']?.toMap(),
              Colors.green,
              inventario.contagemAtiva == 'contagem_2',
            ),
            if (inventario.isCompleta)
              _buildLinhaContagem(
                'Contagem 3',
                inventario.contagens['contagem_3']?.toMap(),
                Colors.purple,
                inventario.contagemAtiva == 'contagem_3',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinhaContagem(
      String label,
      Map<String, dynamic>? dados,
      Color cor,
      bool ativa,
      ) {
    // Deriva status dos timestamps
    final iniciadaEm = dados?['iniciada_em'] as Timestamp?;
    final finalizadaEm = dados?['finalizada_em'] as Timestamp?;

    String status;
    if (finalizadaEm != null) {
      status = 'finalizada';
    } else if (iniciadaEm != null) {
      status = 'em_andamento';
    } else {
      status = 'pendente';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: status == 'finalizada' ? cor : cor.withOpacity(0.3),
              shape: BoxShape.circle,
              border: ativa ? Border.all(color: cor, width: 3) : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: ativa ? FontWeight.bold : FontWeight.normal,
                        color: ativa ? cor : null,
                      ),
                    ),
                    if (ativa) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'ATIVA',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (iniciadaEm != null)
                  Text(
                    'Início: ${_formatoDataHora.format(iniciadaEm.toDate())}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                if (finalizadaEm != null)
                  Text(
                    'Fim: ${_formatoDataHora.format(finalizadaEm.toDate())}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          _buildChipStatusContagem(status),
        ],
      ),
    );
  }

  Widget _buildChipStatusContagem(String status) {
    Color cor;
    String label;

    switch (status) {
      case 'finalizada':
        cor = Colors.green;
        label = 'Finalizada';
        break;
      case 'em_andamento':
        cor = Colors.blue;
        label = 'Em Andamento';
        break;
      default:
        cor = Colors.grey;
        label = 'Pendente';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildCardEstatisticasEstoque(Inventario inventario) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory),
                const SizedBox(width: 8),
                const Text(
                  'Estoque Base',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Total de Itens',
                    _formatoNumero.format(inventario.totalItensEstoque),
                    Icons.inventory_2,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    'Valor Total',
                    _formatoMoeda.format(inventario.valorTotalEstoque),
                    Icons.attach_money,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    'Valor Médio',
                    inventario.totalItensEstoque > 0
                        ? _formatoMoeda.format(inventario.valorTotalEstoque / inventario.totalItensEstoque)
                        : '-',
                    Icons.calculate,
                    Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String valor, IconData icone, Color cor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icone, color: cor, size: 28),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: cor,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildLinhaInfo(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: TextStyle(color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  // ==================== TAB PARTICIPANTES ====================

  Widget _buildTabParticipantes(Inventario inventario) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('inventarios')
          .doc(widget.inventarioId)
          .collection('participantes')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final participantes = snapshot.data!.docs
            .map((doc) => Participante.fromFirestore(
          doc as DocumentSnapshot<Map<String, dynamic>>,
          null,
        ))
            .toList();

        if (participantes.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Nenhum participante',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        // Estatísticas
        final totalLancs = participantes.fold<int>(
            0, (sum, p) => sum + p.totalLancamentosC1 + p.totalLancamentosC2 + p.totalLancamentosC3);

        return Column(
          children: [
            // Header com estatísticas
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _buildMiniStat('Participantes', participantes.length, Colors.blue),
                    const SizedBox(width: 24),
                    _buildMiniStat('Lançamentos', totalLancs, Colors.green),
                    const SizedBox(width: 24),
                    _buildMiniStat(
                      'Finalizaram C1',
                      participantes.where((p) => p.statusC1 == 'finalizada').length,
                      Colors.orange,
                    ),
                  ],
                ),
              ),
            ),

            // Lista
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: participantes.length,
                itemBuilder: (context, index) {
                  final p = participantes[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(p.displayName.isNotEmpty ? p.displayName[0] : '?'),
                      ),
                      title: Text(p.displayName),
                      subtitle: Text(p.email ?? '-'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildBadgeLanc('C1', p.totalLancamentosC1, Colors.blue),
                          const SizedBox(width: 8),
                          _buildBadgeLanc('C2', p.totalLancamentosC2, Colors.green),
                          if (inventario.isCompleta) ...[
                            const SizedBox(width: 8),
                            _buildBadgeLanc('C3', p.totalLancamentosC3, Colors.purple),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMiniStat(String label, int valor, Color cor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            valor.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: cor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildBadgeLanc(String label, int valor, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: valor > 0 ? cor.withOpacity(0.1) : Colors.grey[100],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $valor',
        style: TextStyle(
          color: valor > 0 ? cor : Colors.grey,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ==================== TAB ESTOQUE ====================

  Widget _buildTabEstoque(Inventario inventario) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('inventarios')
          .doc(widget.inventarioId)
          .collection('estoque')
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final itens = snapshot.data!.docs;

        if (itens.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Nenhum item no estoque',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Exibindo ${itens.length} de ${inventario.totalItensEstoque} itens',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

            // Tabela
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Código')),
                    DataColumn(label: Text('Descrição')),
                    DataColumn(label: Text('Lote')),
                    DataColumn(label: Text('Quantidade'), numeric: true),
                    DataColumn(label: Text('Valor Unit.'), numeric: true),
                    DataColumn(label: Text('Valor Total'), numeric: true),
                  ],
                  rows: itens.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return DataRow(cells: [
                      DataCell(Text(data['codigo']?.toString() ?? '-')),
                      DataCell(SizedBox(
                        width: 200,
                        child: Text(
                          data['descricao']?.toString() ?? '-',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                      DataCell(Text(data['lote']?.toString() ?? '-')),
                      DataCell(Text(_formatoNumero.format(data['quantidade'] ?? 0))),
                      DataCell(Text(_formatoMoeda.format(data['valor_unitario'] ?? 0))),
                      DataCell(Text(_formatoMoeda.format(data['valor_total'] ?? 0))),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ==================== TAB TIMELINE ====================

  Widget _buildTabTimeline(Inventario inventario) {
    final eventos = <Map<String, dynamic>>[];

    // Criação
    eventos.add({
      'data': inventario.dataInicio,
      'titulo': 'Inventário criado',
      'descricao': 'Código: ${inventario.codigo}',
      'icone': Icons.add_circle,
      'cor': Colors.blue,
    });

    // Contagem 1
    final c1 = inventario.contagens['contagem_1'];
    if (c1?.iniciadaEm != null) {
      eventos.add({
        'data': c1!.iniciadaEm!,
        'titulo': 'Contagem 1 iniciada',
        'descricao': 'Primeira contagem iniciada',
        'icone': Icons.play_circle,
        'cor': Colors.blue,
      });
    }
    if (c1?.finalizadaEm != null) {
      eventos.add({
        'data': c1!.finalizadaEm!,
        'titulo': 'Contagem 1 finalizada',
        'descricao': 'Primeira contagem concluída',
        'icone': Icons.check_circle,
        'cor': Colors.green,
      });
    }

    // Contagem 2
    final c2 = inventario.contagens['contagem_2'];
    if (c2?.iniciadaEm != null) {
      eventos.add({
        'data': c2!.iniciadaEm!,
        'titulo': 'Contagem 2 iniciada',
        'descricao': 'Segunda contagem iniciada',
        'icone': Icons.play_circle,
        'cor': Colors.blue,
      });
    }
    if (c2?.finalizadaEm != null) {
      eventos.add({
        'data': c2!.finalizadaEm!,
        'titulo': 'Contagem 2 finalizada',
        'descricao': 'Segunda contagem concluída',
        'icone': Icons.check_circle,
        'cor': Colors.green,
      });
    }

    // Contagem 3
    final c3 = inventario.contagens['contagem_3'];
    if (c3?.iniciadaEm != null) {
      eventos.add({
        'data': c3!.iniciadaEm!,
        'titulo': 'Contagem 3 iniciada',
        'descricao': 'Recontagem iniciada',
        'icone': Icons.play_circle,
        'cor': Colors.purple,
      });
    }
    if (c3?.finalizadaEm != null) {
      eventos.add({
        'data': c3!.finalizadaEm!,
        'titulo': 'Contagem 3 finalizada',
        'descricao': 'Recontagem concluída',
        'icone': Icons.check_circle,
        'cor': Colors.green,
      });
    }

    // Finalização
    if (inventario.dataFim != null) {
      eventos.add({
        'data': inventario.dataFim!,
        'titulo': 'Inventário finalizado',
        'descricao': 'Processo concluído',
        'icone': Icons.flag,
        'cor': Colors.green,
      });
    }

    // Ordena por data
    eventos.sort((a, b) => (a['data'] as DateTime).compareTo(b['data'] as DateTime));

    if (eventos.isEmpty) {
      return const Center(child: Text('Nenhum evento registrado'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: eventos.length,
      itemBuilder: (context, index) {
        final evento = eventos[index];
        final isLast = index == eventos.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha do tempo
              Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (evento['cor'] as Color).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      evento['icone'] as IconData,
                      color: evento['cor'] as Color,
                      size: 20,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: Colors.grey[300],
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),

              // Conteúdo
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        evento['titulo'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        evento['descricao'] as String,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatoDataHora.format(evento['data'] as DateTime),
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== HELPERS ====================

  Widget _buildChipStatus(StatusInventario status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _getCorStatus(status).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _getCorStatus(status)),
      ),
      child: Text(
        _getLabelStatus(status),
        style: TextStyle(
          color: _getCorStatus(status),
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

  String _calcularDuracao(Inventario inventario) {
    final fim = inventario.dataFim ?? DateTime.now();
    final duracao = fim.difference(inventario.dataInicio);

    if (duracao.inDays > 0) {
      return 'Duração: ${duracao.inDays} dia(s)';
    } else if (duracao.inHours > 0) {
      return 'Duração: ${duracao.inHours} hora(s)';
    } else {
      return 'Duração: ${duracao.inMinutes} minuto(s)';
    }
  }

  void _abrirRelatorio(Inventario inventario) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RelatorioScreen(inventarioId: inventario.id),
      ),
    );
  }
}