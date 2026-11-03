// lib/ui/desktop/screens/dashboard_desktop_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'package:lego/ui/desktop/screens/relatorio_do_inventario_screen.dart';
import 'package:lego/models/inventario.dart';
import 'package:lego/services/inventario_service.dart';

// ⭐ Telas das fases
import 'package:lego/ui/desktop/screens/criar_inventario_screen.dart';      // Fase 1
import 'package:lego/ui/desktop/screens/controle_contagem_screen.dart';     // Fase 2
import 'package:lego/ui/desktop/screens/participantes_screen.dart';         // Fase 2
import 'package:lego/ui/desktop/screens/historico_screen.dart';             // Fase 4
import 'package:lego/ui/desktop/screens/comparativo_inventarios_screen.dart'; // Fase 6
import 'package:lego/ui/desktop/screens/inventario_completo_screen.dart';   // Entrega 3 (fluxo 2)
import 'package:lego/ui/desktop/screens/contagem_simples_screen.dart';     // Contagem Simples

/// Dashboard principal do Desktop - integra todas as fases
class DashboardDesktopScreen extends StatefulWidget {
  const DashboardDesktopScreen({super.key});

  @override
  State<DashboardDesktopScreen> createState() => _DashboardDesktopScreenState();
}

class _DashboardDesktopScreenState extends State<DashboardDesktopScreen> {
  final _inventarioService = InventarioService();
  final _formatoData = DateFormat('dd/MM/yyyy HH:mm');

  Inventario? _inventarioAtivo;
  bool _carregando = true;
  String? _erro;

  // Navegação. 0 = Inventário Completo (fluxo 2, painel do analista);
  // 1 = Contagem Simples; 2..7 = telas legadas (Painel, Controle,
  // Participantes, Relatórios, Histórico, Comparativo).
  int _menuIndex = 0;
  bool get _secaoCompleto => _menuIndex == 0;
  bool get _secaoSimples => _menuIndex == 1;
  bool get _secaoNova => _secaoCompleto || _secaoSimples;

  @override
  void initState() {
    super.initState();
    _carregarInventarioAtivo();
  }

  Future<void> _carregarInventarioAtivo() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final inventario = await _inventarioService.buscarInventarioAtivo();
      if (mounted) {
        setState(() {
          _inventarioAtivo = inventario;
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = 'Erro: $e';
          _carregando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // ==================== SIDEBAR ====================
          NavigationRail(
            extended: true,
            minExtendedWidth: 220,
            selectedIndex: _menuIndex,
            onDestinationSelected: (index) => setState(() => _menuIndex = index),
            leading: _buildSidebarHeader(),
            trailing: _buildSidebarFooter(),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.fact_check_outlined),
                selectedIcon: Icon(Icons.fact_check),
                label: Text('Inventário Completo'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.playlist_add_check_outlined),
                selectedIcon: Icon(Icons.playlist_add_check),
                label: Text('Contagem Simples'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Painel'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.checklist_outlined),
                selectedIcon: Icon(Icons.checklist),
                label: Text('Controle'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: Text('Participantes'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.assessment_outlined),
                selectedIcon: Icon(Icons.assessment),
                label: Text('Relatórios'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: Text('Histórico'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.compare_arrows_outlined),
                selectedIcon: Icon(Icons.compare_arrows),
                label: Text('Comparativo'),
              ),
            ],
          ),

          const VerticalDivider(width: 1),

          // ==================== CONTEÚDO ====================
          Expanded(
            child: Column(
              children: [
                // AppBar
                _buildAppBar(),
                
                // Conteúdo
                Expanded(
                  child: _carregando
                      ? const Center(child: CircularProgressIndicator())
                      : _buildConteudo(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.inventory_2, size: 32, color: Colors.blue),
          ),
          const SizedBox(height: 8),
          const Text(
            'LEGO Inventário',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(
            'Desktop',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          const Divider(),
        ],
      ),
    );
  }

  Widget _buildSidebarFooter() {
    return Expanded(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(),
              const SizedBox(height: 8),
              Text(
                FirebaseAuth.instance.currentUser?.email ?? '',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Sair'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          // Título da seção
          Text(
            _getTituloSecao(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 24),

          // Inventário ativo (legado; a seção Completo tem cabeçalho próprio)
          if (_secaoNova)
            const SizedBox.shrink()
          else if (_inventarioAtivo != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.circle, size: 8, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    _inventarioAtivo!.codigo,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _inventarioAtivo!.contagemAtivaLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey),
                  SizedBox(width: 8),
                  Text('Nenhum inventário ativo'),
                ],
              ),
            ),
          ],

          const Spacer(),

          // Botão criar inventário (legado). O Completo nasce no celular.
          if (!_secaoNova) ...[
            FilledButton.icon(
              onPressed: _abrirCriarInventario,
              icon: const Icon(Icons.add),
              label: const Text('Novo Inventário'),
            ),

            const SizedBox(width: 8),

            // Botão atualizar
            IconButton(
              onPressed: _carregarInventarioAtivo,
              icon: const Icon(Icons.refresh),
              tooltip: 'Atualizar',
            ),
          ],
        ],
      ),
    );
  }

  String _getTituloSecao() {
    switch (_menuIndex) {
      case 0: return 'Inventário Completo';
      case 1: return 'Contagem Simples';
      case 2: return 'Painel';
      case 3: return 'Controle de Contagem';
      case 4: return 'Participantes';
      case 5: return 'Relatórios';
      case 6: return 'Histórico';
      case 7: return 'Comparativo';
      default: return 'LEGO Inventário';
    }
  }

  Widget _buildConteudo() {
    if (_secaoCompleto) return const InventarioCompletoScreen();
    if (_secaoSimples) return const ContagemSimplesScreen();

    // Verifica se precisa de inventário ativo (telas legadas)
    if (_menuIndex <= 5 && _inventarioAtivo == null) {
      return _buildSemInventario();
    }

    switch (_menuIndex) {
      case 2:
        return _buildPainel();
      case 3:
        return ControleContagemScreen(inventarioId: _inventarioAtivo!.id);
      case 4:
        return ParticipantesScreen(inventarioId: _inventarioAtivo!.id);
      case 5:
        return RelatorioDoInventarioScreen(inventarioId: _inventarioAtivo!.id);
      case 6:
        return const HistoricoScreen();
      case 7:
        return const ComparativoInventariosScreen();
      default:
        return const Center(child: Text('Seção não encontrada'));
    }
  }

  Widget _buildSemInventario() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 100, color: Colors.grey[400]),
          const SizedBox(height: 24),
          const Text(
            'Nenhum inventário ativo',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Crie um novo inventário ou acesse o histórico',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: _abrirCriarInventario,
                icon: const Icon(Icons.add),
                label: const Text('Criar Novo'),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () => setState(() => _menuIndex = 6),
                icon: const Icon(Icons.history),
                label: const Text('Ver Histórico'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPainel() {
    final inv = _inventarioAtivo!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cards de resumo
          Row(
            children: [
              Expanded(
                child: _buildCardResumo(
                  'Status',
                  inv.statusLabel,
                  Icons.info,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildCardResumo(
                  'Contagem Ativa',
                  inv.contagemAtivaLabel,
                  Icons.format_list_numbered,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildCardResumo(
                  'Total de Itens',
                  inv.totalItensEstoque.toString(),
                  Icons.inventory_2,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildCardResumo(
                  'Valor Total',
                  NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                      .format(inv.valorTotalEstoque),
                  Icons.attach_money,
                  Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Informações do inventário
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Informações do Inventário',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  _buildLinhaInfo('Código', inv.codigo),
                  _buildLinhaInfo('Tipo', inv.tipoContagemLabel),
                  if (inv.tipoMaterial != null)
                    _buildLinhaInfo('Material', TiposMaterial.label(inv.tipoMaterial!)),
                  if (inv.deposito != null)
                    _buildLinhaInfo('Depósito', inv.deposito!),
                  _buildLinhaInfo('Data Início', _formatoData.format(inv.dataInicio)),
                  if (inv.descricao != null && inv.descricao!.isNotEmpty)
                    _buildLinhaInfo('Descrição', inv.descricao!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Ações rápidas
          const Text(
            'Ações Rápidas',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildBotaoAcao(
                'Controle de Contagem',
                Icons.checklist,
                Colors.blue,
                () => setState(() => _menuIndex = 3),
              ),
              _buildBotaoAcao(
                'Participantes',
                Icons.people,
                Colors.green,
                () => setState(() => _menuIndex = 4),
              ),
              _buildBotaoAcao(
                'Relatórios',
                Icons.assessment,
                Colors.orange,
                () => setState(() => _menuIndex = 5),
              ),
              _buildBotaoAcao(
                'Avançar Contagem',
                Icons.skip_next,
                Colors.purple,
                _avancarContagem,
              ),
              _buildBotaoAcao(
                'Finalizar Inventário',
                Icons.check_circle,
                Colors.red,
                _finalizarInventario,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardResumo(String titulo, String valor, IconData icone, Color cor) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: cor, size: 24),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            Text(titulo, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              valor,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: cor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinhaInfo(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildBotaoAcao(String label, IconData icone, Color cor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cor.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: cor, size: 20),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: cor, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // ==================== AÇÕES ====================

  Future<void> _abrirCriarInventario() async {
    final resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CriarInventarioScreen()),
    );

    if (resultado == true) {
      _carregarInventarioAtivo();
    }
  }

  Future<void> _avancarContagem() async {
    if (_inventarioAtivo == null) return;

    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Avançar Contagem'),
        content: Text(
          'Deseja avançar para a próxima contagem?\n\n'
          'Contagem atual: ${_inventarioAtivo!.contagemAtivaLabel}',
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
      await _inventarioService.avancarParaProximaContagem(_inventarioAtivo!.id);
      _carregarInventarioAtivo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contagem avançada com sucesso')),
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

  Future<void> _finalizarInventario() async {
    if (_inventarioAtivo == null) return;

    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Inventário'),
        content: const Text(
          'Deseja finalizar este inventário?\n\n'
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );

    if (confirma != true) return;

    try {
      await _inventarioService.finalizarInventario(_inventarioAtivo!.id);
      _carregarInventarioAtivo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inventário finalizado')),
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
}
