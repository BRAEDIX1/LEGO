// lib/ui/mobile/screens/modo_operacao_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/services/mobile_sync_service.dart';

/// Tela de seleção do modo de operação (Mobile)
class ModoOperacaoScreen extends StatefulWidget {
  const ModoOperacaoScreen({super.key});

  @override
  State<ModoOperacaoScreen> createState() => _ModoOperacaoScreenState();
}

class _ModoOperacaoScreenState extends State<ModoOperacaoScreen> {
  final _syncService = MobileSyncService();
  final _formatoData = DateFormat('dd/MM/yyyy HH:mm');

  bool _carregando = true;
  Inventario? _inventarioAtivo;
  String? _erro;
  bool _processando = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final inv = await _syncService.buscarInventarioAtivo();
      setState(() {
        _inventarioAtivo = inv;
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modo de Operação'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? _buildErro()
              : _buildConteudo(),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text('Erro: $_erro'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _carregarDados,
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildConteudo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status atual
          _buildStatusAtual(),
          const SizedBox(height: 24),

          // Opções
          const Text(
            'Escolha como deseja operar:',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Card Modo Autônomo
          _buildCardModo(
            titulo: 'Modo Autônomo',
            descricao: 'Contagem independente, sem vínculo com inventário central. '
                'Os dados ficam apenas neste dispositivo.',
            icone: Icons.smartphone,
            cor: Colors.blue,
            selecionado: _syncService.isAutonomo,
            onTap: _selecionarAutonomo,
            badges: const ['Offline', 'Local'],
          ),
          const SizedBox(height: 16),

          // Card Modo Controlado
          _buildCardModoControlado(),
        ],
      ),
    );
  }

  Widget _buildStatusAtual() {
    final modo = _syncService.modoAtual;
    final cor = modo == ModoOperacao.controlado ? Colors.green : Colors.blue;
    final label = modo == ModoOperacao.controlado ? 'CONTROLADO' : 'AUTÔNOMO';

    return Card(
      color: cor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              modo == ModoOperacao.controlado ? Icons.cloud_done : Icons.smartphone,
              color: cor,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Modo atual',
                    style: TextStyle(fontSize: 12),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: cor,
                    ),
                  ),
                  if (modo == ModoOperacao.controlado && _syncService.inventarioVinculadoId != null)
                    Text(
                      'Vinculado: ${_syncService.inventarioVinculadoId}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardModo({
    required String titulo,
    required String descricao,
    required IconData icone,
    required Color cor,
    required bool selecionado,
    required VoidCallback onTap,
    List<String> badges = const [],
  }) {
    return Card(
      elevation: selecionado ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selecionado ? cor : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: _processando ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: cor, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (selecionado) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.check_circle, color: cor, size: 20),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      descricao,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                    if (badges.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: badges.map((badge) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(fontSize: 11, color: cor),
                          ),
                        )).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              if (!selecionado)
                Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardModoControlado() {
    final temInventarioAtivo = _inventarioAtivo != null;
    final cor = temInventarioAtivo ? Colors.green : Colors.grey;

    return Card(
      elevation: _syncService.isControlado ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _syncService.isControlado ? cor : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: temInventarioAtivo && !_processando
                ? () => _selecionarControlado(_inventarioAtivo!)
                : null,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.cloud_sync, color: cor, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Modo Controlado',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_syncService.isControlado) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.check_circle, color: cor, size: 20),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          temInventarioAtivo
                              ? 'Vincular a inventário ativo. Os dados sincronizam com o servidor.'
                              : 'Nenhum inventário ativo no momento.',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Online',
                                style: TextStyle(fontSize: 11, color: cor),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Sincronizado',
                                style: TextStyle(fontSize: 11, color: cor),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (temInventarioAtivo && !_syncService.isControlado)
                    Icon(Icons.chevron_right, color: Colors.grey[400]),
                ],
              ),
            ),
          ),

          // Detalhes do inventário ativo
          if (temInventarioAtivo) ...[
            const Divider(height: 1),
            _buildDetalhesInventario(_inventarioAtivo!),
          ] else ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[400]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aguarde o analista criar e iniciar um inventário para usar este modo.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetalhesInventario(Inventario inv) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.green.withOpacity(0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2, size: 20, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                'Inventário Ativo',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildLinhaDetalhe('Código', inv.codigo),
          _buildLinhaDetalhe('Status', inv.statusLabel),
          _buildLinhaDetalhe('Contagem', inv.contagemAtivaLabel),
          if (inv.tipoMaterial != null)
            _buildLinhaDetalhe('Material', TiposMaterial.label(inv.tipoMaterial!)),
          _buildLinhaDetalhe('Itens', '${inv.totalItensEstoque}'),
          _buildLinhaDetalhe('Início', _formatoData.format(inv.dataInicio)),
        ],
      ),
    );
  }

  Widget _buildLinhaDetalhe(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ),
          Expanded(
            child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ==================== AÇÕES ====================

  Future<void> _selecionarAutonomo() async {
    if (_syncService.isAutonomo) return;

    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mudar para Autônomo'),
        content: const Text(
          'Deseja desconectar do inventário e operar de forma independente?\n\n'
          'Os lançamentos feitos neste modo ficarão apenas neste dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirma != true) return;

    setState(() => _processando = true);

    await _syncService.setModoAutonomo();

    setState(() => _processando = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modo Autônomo ativado'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  Future<void> _selecionarControlado(Inventario inv) async {
    if (_syncService.isControlado && _syncService.inventarioVinculadoId == inv.id) {
      return;
    }

    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vincular ao Inventário'),
        content: Text(
          'Deseja vincular este dispositivo ao inventário ${inv.codigo}?\n\n'
          'Você precisará de aprovação do analista para começar a contar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Vincular'),
          ),
        ],
      ),
    );

    if (confirma != true) return;

    setState(() => _processando = true);

    final resultado = await _syncService.setModoControlado(inv.id);

    setState(() => _processando = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resultado.mensagem),
          backgroundColor: resultado.sucesso ? Colors.green : Colors.red,
        ),
      );

      if (resultado.sucesso) {
        Navigator.pop(context, true);
      }
    }
  }
}
