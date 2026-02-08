// lib/ui/desktop/screens/controle_contagem_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/models/participante.dart';
import 'package:lego/services/inventario_service.dart';

/// Tela de controle e monitoramento de contagem em tempo real
class ControleContagemScreen extends StatefulWidget {
  final String inventarioId;

  const ControleContagemScreen({
    super.key,
    required this.inventarioId,
  });

  @override
  State<ControleContagemScreen> createState() => _ControleContagemScreenState();
}

class _ControleContagemScreenState extends State<ControleContagemScreen> {
  final _inventarioService = InventarioService();
  final _formatoHora = DateFormat('HH:mm');
  final _formatoData = DateFormat('dd/MM HH:mm');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('inventarios')
          .doc(widget.inventarioId)
          .snapshots(),
      builder: (context, invSnapshot) {
        if (!invSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final inventario = Inventario.fromFirestore(invSnapshot.data!);

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('inventarios')
              .doc(widget.inventarioId)
              .collection('participantes')
              .snapshots(),
          builder: (context, partSnapshot) {
            final participantes = partSnapshot.hasData
                ? partSnapshot.data!.docs
                .map((doc) => Participante.fromFirestore(
              doc as DocumentSnapshot<Map<String, dynamic>>,
              null,
            ))
                .toList()
                : <Participante>[];

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderInventario(inventario),
                  const SizedBox(height: 24),
                  _buildProgressoGeral(inventario, participantes),
                  const SizedBox(height: 24),
                  _buildPainelContagens(inventario, participantes),
                  const SizedBox(height: 24),
                  _buildAtividadeRecente(participantes),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeaderInventario(Inventario inventario) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getCorStatus(inventario.status),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getIconeStatus(inventario.status),
                color: Colors.white,
                size: 32,
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildChipStatus(inventario.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildInfoItem(
                        Icons.category,
                        inventario.tipoMaterial != null
                            ? TiposMaterial.label(inventario.tipoMaterial!)
                            : 'Não definido',
                      ),
                      const SizedBox(width: 24),
                      _buildInfoItem(
                        Icons.repeat,
                        inventario.tipoContagemLabel,
                      ),
                      const SizedBox(width: 24),
                      _buildInfoItem(
                        Icons.inventory_2,
                        '${inventario.totalItensEstoque} itens',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Ações
            _buildAcoesInventario(inventario),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: Colors.grey[700])),
      ],
    );
  }

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
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildAcoesInventario(Inventario inventario) {
    return Row(
      children: [
        // Botão iniciar (se aguardando)
        if (inventario.status == StatusInventario.aguardando)
          FilledButton.icon(
            onPressed: () => _iniciarInventario(inventario),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Iniciar Contagem'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
          ),

        // Botão avançar contagem (se em andamento e não é última)
        if (inventario.status == StatusInventario.emAndamento &&
            !inventario.isUltimaContagem)
          FilledButton.icon(
            onPressed: () => _avancarContagem(inventario),
            icon: const Icon(Icons.skip_next),
            label: Text('Avançar para ${inventario.proximaContagem()?.replaceAll('contagem_', 'C') ?? ''}'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
          ),

        // Botão finalizar (se última contagem)
        if (inventario.status == StatusInventario.emAndamento &&
            inventario.isUltimaContagem)
          FilledButton.icon(
            onPressed: () => _finalizarInventario(inventario),
            icon: const Icon(Icons.check_circle),
            label: const Text('Finalizar Inventário'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
          ),
      ],
    );
  }

  Widget _buildProgressoGeral(Inventario inventario, List<Participante> participantes) {
    // Calcula estatísticas
    final totalParticipantes = participantes.length;
    final pendentes = participantes.where((p) => p.status == 'solicitacao_pendente').length;

    // Por contagem
    final emC1 = participantes.where((p) => p.contagemAtual == 'contagem_1' && p.statusC1 == 'em_andamento').length;
    final finalizaramC1 = participantes.where((p) => p.statusC1 == 'finalizada').length;
    final emC2 = participantes.where((p) => p.contagemAtual == 'contagem_2' && p.statusC2 == 'em_andamento').length;
    final finalizaramC2 = participantes.where((p) => p.statusC2 == 'finalizada').length;
    final emC3 = participantes.where((p) => p.contagemAtual == 'contagem_3' && p.statusC3 == 'em_andamento').length;
    final finalizaramC3 = participantes.where((p) => p.statusC3 == 'finalizada').length;

    // Total de lançamentos
    final lancamentosC1 = participantes.fold<int>(0, (sum, p) => sum + p.totalLancamentosC1);
    final lancamentosC2 = participantes.fold<int>(0, (sum, p) => sum + p.totalLancamentosC2);
    final lancamentosC3 = participantes.fold<int>(0, (sum, p) => sum + p.totalLancamentosC3);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card de participantes
        Expanded(
          flex: 1,
          child: _buildCardEstatistica(
            'Participantes',
            Icons.people,
            Colors.blue,
            [
              _buildLinhaEstat('Total', totalParticipantes.toString()),
              if (pendentes > 0)
                _buildLinhaEstat('Pendentes', pendentes.toString(), cor: Colors.orange),
              _buildLinhaEstat('Ativos em C1', emC1.toString()),
              _buildLinhaEstat('Ativos em C2', emC2.toString()),
              _buildLinhaEstat('Ativos em C3', emC3.toString()),
            ],
          ),
        ),
        const SizedBox(width: 16),

        // Card de progresso
        Expanded(
          flex: 2,
          child: _buildCardEstatistica(
            'Progresso das Contagens',
            Icons.trending_up,
            Colors.green,
            [
              _buildBarraProgresso('Contagem 1', finalizaramC1, totalParticipantes, lancamentosC1,
                  inventario.contagemAtiva == 'contagem_1'),
              const SizedBox(height: 12),
              _buildBarraProgresso('Contagem 2', finalizaramC2, totalParticipantes, lancamentosC2,
                  inventario.contagemAtiva == 'contagem_2'),
              if (!inventario.isSimples) ...[
                const SizedBox(height: 12),
                _buildBarraProgresso('Contagem 3', finalizaramC3, totalParticipantes, lancamentosC3,
                    inventario.contagemAtiva == 'contagem_3'),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),

        // Card de lançamentos
        Expanded(
          flex: 1,
          child: _buildCardEstatistica(
            'Lançamentos',
            Icons.edit_note,
            Colors.purple,
            [
              _buildLinhaEstat('C1', lancamentosC1.toString()),
              _buildLinhaEstat('C2', lancamentosC2.toString()),
              if (!inventario.isSimples)
                _buildLinhaEstat('C3', lancamentosC3.toString()),
              const Divider(),
              _buildLinhaEstat(
                'Total',
                (lancamentosC1 + lancamentosC2 + lancamentosC3).toString(),
                fontWeight: FontWeight.bold,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCardEstatistica(
      String titulo,
      IconData icon,
      Color cor,
      List<Widget> children,
      ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: cor, size: 20),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildLinhaEstat(String label, String valor, {Color? cor, FontWeight? fontWeight}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(
            valor,
            style: TextStyle(
              fontWeight: fontWeight ?? FontWeight.w500,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarraProgresso(
      String label,
      int concluidos,
      int total,
      int lancamentos,
      bool ativa,
      ) {
    final progresso = total > 0 ? concluidos / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: ativa ? FontWeight.bold : FontWeight.normal,
                    color: ativa ? Colors.blue : null,
                  ),
                ),
                if (ativa) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(8),
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
            Text(
              '$concluidos/$total ($lancamentos lanç.)',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progresso,
            minHeight: 8,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation(
              ativa ? Colors.blue : Colors.green,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPainelContagens(Inventario inventario, List<Participante> participantes) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Contadores por Fase',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Contagem ativa: ${inventario.contagemAtivaLabel}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Coluna C1
                Expanded(
                  child: _buildColunaContagem(
                    'Contagem 1',
                    Colors.blue,
                    participantes.where((p) =>
                    p.contagemAtual == 'contagem_1' ||
                        (p.statusC1 != null && p.statusC1 != 'bloqueada' && p.statusC1 != 'nao_participou')
                    ).toList(),
                    inventario.contagemAtiva == 'contagem_1',
                  ),
                ),
                const SizedBox(width: 12),
                // Coluna C2
                Expanded(
                  child: _buildColunaContagem(
                    'Contagem 2',
                    Colors.green,
                    participantes.where((p) =>
                    p.contagemAtual == 'contagem_2' ||
                        (p.statusC2 != null && p.statusC2 != 'bloqueada' && p.statusC2 != 'nao_participou')
                    ).toList(),
                    inventario.contagemAtiva == 'contagem_2',
                  ),
                ),
                if (!inventario.isSimples) ...[
                  const SizedBox(width: 12),
                  // Coluna C3
                  Expanded(
                    child: _buildColunaContagem(
                      'Contagem 3',
                      Colors.purple,
                      participantes.where((p) =>
                      p.contagemAtual == 'contagem_3' ||
                          (p.statusC3 != null && p.statusC3 != 'bloqueada' && p.statusC3 != 'nao_participou')
                      ).toList(),
                      inventario.contagemAtiva == 'contagem_3',
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColunaContagem(
      String titulo,
      Color cor,
      List<Participante> participantes,
      bool ativa,
      ) {
    return Container(
      decoration: BoxDecoration(
        color: cor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ativa ? cor : Colors.transparent,
          width: 2,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: cor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cor,
                ),
              ),
              const Spacer(),
              Text(
                '${participantes.length}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cor,
                ),
              ),
            ],
          ),
          const Divider(),
          if (participantes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'Nenhum contador',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            )
          else
            ...participantes.map((p) => _buildParticipanteItem(p, cor)),
        ],
      ),
    );
  }

  Widget _buildParticipanteItem(Participante p, Color cor) {
    final isOnline = _isOnline(p.ultimoAcesso);
    final statusAtual = _getStatusAtualParticipante(p);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar com indicador online
          Stack(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: cor.withOpacity(0.2),
                child: Text(
                  p.displayName.isNotEmpty ? p.displayName[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: cor,
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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  statusAtual,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          // Lançamentos
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _getLancamentosContagem(p).toString(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cor,
                ),
              ),
              Text(
                'lanç.',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAtividadeRecente(List<Participante> participantes) {
    // Ordena por último acesso
    final recentes = [...participantes]
      ..sort((a, b) => (b.ultimoAcesso ?? DateTime(2000))
          .compareTo(a.ultimoAcesso ?? DateTime(2000)));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Atividade Recente',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Icon(Icons.circle, size: 8, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  '${participantes.where((p) => _isOnline(p.ultimoAcesso)).length} online',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (recentes.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nenhuma atividade recente'),
                ),
              )
            else
              ...recentes.take(8).map((p) => _buildLinhaAtividade(p)),
          ],
        ),
      ),
    );
  }

  Widget _buildLinhaAtividade(Participante p) {
    final isOnline = _isOnline(p.ultimoAcesso);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: isOnline ? Colors.green : Colors.grey[400],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p.displayName,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            p.contagemAtual?.replaceAll('contagem_', 'C') ?? '-',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(width: 16),
          Text(
            _formatarUltimoAcesso(p.ultimoAcesso),
            style: TextStyle(
              fontSize: 12,
              color: isOnline ? Colors.green : Colors.grey[500],
            ),
          ),
        ],
      ),
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
    if (diff.inMinutes < 60) return '${diff.inMinutes}min atrás';
    if (diff.inHours < 24) return '${diff.inHours}h atrás';
    return _formatoData.format(data);
  }

  String _getStatusAtualParticipante(Participante p) {
    if (p.status == 'solicitacao_pendente') return 'Aguardando aprovação';

    switch (p.contagemAtual) {
      case 'contagem_1':
        if (p.statusC1 == 'em_andamento') return 'Contando...';
        if (p.statusC1 == 'finalizada') return 'C1 finalizada';
        return 'Aguardando';
      case 'contagem_2':
        if (p.statusC2 == 'em_andamento') return 'Contando...';
        if (p.statusC2 == 'finalizada') return 'C2 finalizada';
        return 'Aguardando';
      case 'contagem_3':
        if (p.statusC3 == 'em_andamento') return 'Contando...';
        if (p.statusC3 == 'finalizada') return 'C3 finalizada';
        return 'Aguardando';
      default:
        return '-';
    }
  }

  int _getLancamentosContagem(Participante p) {
    switch (p.contagemAtual) {
      case 'contagem_1':
        return p.totalLancamentosC1;
      case 'contagem_2':
        return p.totalLancamentosC2;
      case 'contagem_3':
        return p.totalLancamentosC3;
      default:
        return 0;
    }
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

  // ==================== AÇÕES ====================

  Future<void> _iniciarInventario(Inventario inventario) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Iniciar Inventário'),
        content: Text(
          'Deseja iniciar as contagens do inventário ${inventario.codigo}?\n\n'
              'Os participantes poderão começar a contar após esta ação.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Iniciar'),
          ),
        ],
      ),
    );

    if (confirma != true) return;

    try {
      await _inventarioService.iniciarInventario(widget.inventarioId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Inventário iniciado!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao iniciar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _avancarContagem(Inventario inventario) async {
    final proxima = inventario.proximaContagem();
    if (proxima == null) return;

    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Avançar Contagem'),
        content: Text(
          'Deseja finalizar ${inventario.contagemAtivaLabel} e iniciar ${proxima.replaceAll('contagem_', 'Contagem ')}?\n\n'
              'Os participantes que ainda não finalizaram serão marcados como incompletos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Avançar'),
          ),
        ],
      ),
    );

    if (confirma != true) return;

    try {
      await _inventarioService.avancarParaProximaContagem(widget.inventarioId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Avançou para ${proxima.replaceAll('contagem_', 'Contagem ')}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao avançar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _finalizarInventario(Inventario inventario) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Inventário'),
        content: Text(
          'Deseja finalizar o inventário ${inventario.codigo}?\n\n'
              'Esta ação não pode ser desfeita. Os dados serão preservados para consulta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );

    if (confirma != true) return;

    try {
      await _inventarioService.finalizarInventario(widget.inventarioId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Inventário finalizado!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao finalizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}