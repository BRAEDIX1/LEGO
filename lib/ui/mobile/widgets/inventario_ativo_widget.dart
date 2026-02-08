// lib/ui/mobile/widgets/inventario_ativo_widget.dart

import 'package:flutter/material.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/services/mobile_sync_service.dart';
import 'package:lego/ui/mobile/screens/modo_operacao_screen.dart';

/// Widget que mostra status do modo de operação e inventário ativo
/// Para usar na tela principal do mobile
class InventarioAtivoWidget extends StatefulWidget {
  final VoidCallback? onModoAlterado;

  const InventarioAtivoWidget({
    super.key,
    this.onModoAlterado,
  });

  @override
  State<InventarioAtivoWidget> createState() => _InventarioAtivoWidgetState();
}

class _InventarioAtivoWidgetState extends State<InventarioAtivoWidget> {
  final _syncService = MobileSyncService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<InfoModoControlado?>(
      stream: _syncService.inventarioStream,
      builder: (context, snapshot) {
        // Modo autônomo
        if (_syncService.isAutonomo) {
          return _buildCardAutonomo();
        }

        // Modo controlado
        final info = snapshot.data;
        if (info == null) {
          return _buildCardCarregando();
        }

        return _buildCardControlado(info);
      },
    );
  }

  Widget _buildCardAutonomo() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: InkWell(
        onTap: _abrirModoOperacao,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.smartphone, color: Colors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Modo Autônomo',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Operando localmente',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _abrirModoOperacao,
                child: const Text('Alterar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardCarregando() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Conectando ao inventário...',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardControlado(InfoModoControlado info) {
    final inv = info.inventario;
    final podeContar = info.podeContar;

    // Cor baseada no status
    Color cor;
    IconData icone;
    String statusLabel;

    switch (info.statusParticipacao) {
      case StatusParticipacao.aguardandoAprovacao:
        cor = Colors.orange;
        icone = Icons.hourglass_empty;
        statusLabel = 'Aguardando aprovação';
        break;
      case StatusParticipacao.aprovado:
        cor = Colors.green;
        icone = Icons.check_circle;
        statusLabel = podeContar ? 'Pronto para contar' : 'Aprovado';
        break;
      case StatusParticipacao.rejeitado:
        cor = Colors.red;
        icone = Icons.cancel;
        statusLabel = 'Participação rejeitada';
        break;
      default:
        cor = Colors.grey;
        icone = Icons.help_outline;
        statusLabel = 'Status desconhecido';
    }

    return Card(
      margin: const EdgeInsets.all(12),
      color: cor.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cor.withOpacity(0.3)),
      ),
      child: InkWell(
        onTap: _abrirModoOperacao,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icone, color: cor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              inv.codigo,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: cor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                inv.contagemAtivaLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          statusLabel,
                          style: TextStyle(fontSize: 12, color: cor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: _abrirModoOperacao,
                    tooltip: 'Configurar modo',
                  ),
                ],
              ),

              // Stats
              if (info.statusParticipacao == StatusParticipacao.aprovado) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildStat('Meus Lanç.', info.meusLancamentos.toString(), Colors.blue),
                    const SizedBox(width: 16),
                    _buildStat('Itens', inv.totalItensEstoque.toString(), Colors.grey),
                    const SizedBox(width: 16),
                    _buildStat(
                      'Status',
                      inv.status == StatusInventario.emAndamento ? 'Ativo' : 'Aguardando',
                      inv.status == StatusInventario.emAndamento ? Colors.green : Colors.orange,
                    ),
                  ],
                ),
              ],

              // Aviso se não pode contar
              if (info.statusParticipacao == StatusParticipacao.aguardandoAprovacao) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Aguarde o analista aprovar sua participação',
                          style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (info.statusParticipacao == StatusParticipacao.rejeitado) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sua participação foi rejeitada. Fale com o analista.',
                          style: TextStyle(fontSize: 12, color: Colors.red[800]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String label, String valor, Color cor) {
    return Column(
      children: [
        Text(
          valor,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: cor,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Future<void> _abrirModoOperacao() async {
    final resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ModoOperacaoScreen()),
    );

    if (resultado == true) {
      widget.onModoAlterado?.call();
    }
  }
}

/// Widget compacto para AppBar
class ModoOperacaoChip extends StatelessWidget {
  final VoidCallback? onTap;

  const ModoOperacaoChip({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final syncService = MobileSyncService();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: syncService.isControlado
              ? Colors.green.withOpacity(0.2)
              : Colors.blue.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              syncService.isControlado ? Icons.cloud_done : Icons.smartphone,
              size: 14,
              color: syncService.isControlado ? Colors.green : Colors.blue,
            ),
            const SizedBox(width: 4),
            Text(
              syncService.isControlado ? 'Online' : 'Local',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: syncService.isControlado ? Colors.green : Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner para mostrar quando aguardando aprovação
class AguardandoAprovacaoBanner extends StatelessWidget {
  const AguardandoAprovacaoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange,
      child: Row(
        children: [
          const Icon(Icons.hourglass_empty, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Aguardando aprovação do analista para iniciar contagem',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () {
              // Recarrega status
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero,
            ),
            child: const Text('Atualizar'),
          ),
        ],
      ),
    );
  }
}
