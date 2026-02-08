// lib/ui/desktop/screens/dashboard_screen.dart
import 'package:lego/ui/desktop/screens/participantes_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lego/models/inventario.dart';
import 'package:lego/services/inventario_service.dart';
import 'package:lego/ui/desktop/widgets/sidebar_navigation.dart';
// Importar as outras screens quando estiverem criadas:
import 'package:lego/ui/desktop/screens/analise_patrimonial_screen.dart';
import 'package:lego/ui/desktop/screens/comparativo_contagens_screen.dart';
import 'package:lego/ui/desktop/screens/importar_estoque_screen.dart';

/// Tela principal do desktop - Container das abas
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _inventarioService = InventarioService();

  int _abaAtiva = 2;
  Inventario? _inventarioAtivo;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    // ✅ Aguardar montagem do widget
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _carregarInventarioAtivo();
      }
    });
  }

  Future<void> _carregarInventarioAtivo() async {
    // ✅ Verificar se ainda montado
    if (!mounted) return;

    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final inventario = await _inventarioService.buscarInventarioAtivo();

      // ✅ SEMPRE verificar mounted antes de setState
      if (!mounted) return;

      setState(() {
        _inventarioAtivo = inventario;
        _carregando = false;
      });

      if (inventario == null) {
        if (!mounted) return; // ✅ Verificar novamente
        setState(() {
          _erro = 'Nenhum inventário ativo encontrado';
        });
      }
    } catch (e) {
      if (!mounted) return; // ✅ Verificar antes de setState no catch
      setState(() {
        _erro = 'Erro ao carregar inventário: $e';
        _carregando = false;
      });
    }
  }

  Future<void> _criarNovoInventario() async {
    try {
      await _inventarioService.criarInventario();

      // ✅ Verificar mounted antes de chamar método que usa setState
      if (mounted) {
        _carregarInventarioAtivo();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inventário criado com sucesso')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao criar inventário: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.inventory_2),
            const SizedBox(width: 8),
            const Text('LEGO Inventário - Desktop'),
            if (_inventarioAtivo != null) ...[
              const SizedBox(width: 16),
              const Text('•', style: TextStyle(color: Colors.grey)),
              const SizedBox(width: 16),
              Chip(
                label: Text(
                  _inventarioAtivo!.codigo,
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.blue.shade50,
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  _inventarioAtivo!.contagemAtiva.toUpperCase(),
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.green.shade50,
              ),
            ],
          ],
        ),
        actions: [
          // Botão criar inventário
          if (_inventarioAtivo == null)
            TextButton.icon(
              onPressed: _criarNovoInventario,
              icon: const Icon(Icons.add),
              label: const Text('Criar Inventário'),
            ),

          // Botão finalizar
          if (_inventarioAtivo != null)
            TextButton.icon(
              onPressed: _finalizarInventario,
              icon: const Icon(Icons.check_circle),
              label: const Text('Finalizar'),
              style: TextButton.styleFrom(foregroundColor: Colors.green),
            ),

          const SizedBox(width: 16),

          // Usuário logado
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                FirebaseAuth.instance.currentUser?.email ?? 'Usuário',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),

          // Botão sair
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),

          const SizedBox(width: 8),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
          ? _buildErroView()
          : _inventarioAtivo == null
          ? _buildSemInventarioView()
          : _buildConteudoPrincipal(),
    );
  }

  Widget _buildErroView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _erro!,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _carregarInventarioAtivo,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar Novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildSemInventarioView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inventory_2, size: 100, color: Colors.grey),
          const SizedBox(height: 24),
          const Text(
            'Nenhum inventário ativo',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Crie um novo inventário para começar',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _criarNovoInventario,
            icon: const Icon(Icons.add),
            label: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text('Criar Novo Inventário'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConteudoPrincipal() {
    return Row(
      children: [
        // Sidebar
        SidebarNavigation(
          abaAtiva: _abaAtiva,
          onAbaChanged: (aba) => setState(() => _abaAtiva = aba),
          // TODO: Passar contadores reais quando implementar
          totalDivergencias: null,
          itensNaoEncontrados: null,
          itensAguardandoC3: null,
        ),

        // Conteúdo principal
        Expanded(
          child: _buildConteudoAba(),
        ),
      ],
    );
  }

  Widget _buildConteudoAba() {
    // TODO: Descomentar quando as screens estiverem criadas
    switch (_abaAtiva) {
      case 0:
        return AnalisePatrimonialScreen(
          inventarioId: _inventarioAtivo!.id,
        );
      case 1:
        return ComparativoContagensScreen(
          inventarioId: _inventarioAtivo!.id,
        );
      case 2:
        return ImportarEstoqueScreen();

      case 3: // ⭐ ADICIONAR ESTE CASE
        return ParticipantesScreen(
          inventarioId: _inventarioAtivo!.id,
        );
      default:
        return const Center(child: Text('Aba inválida'));
    }

    // Temporariamente, mostra placeholder
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.construction, size: 80, color: Colors.orange),
          const SizedBox(height: 16),
          Text(
            'Aba ${_abaAtiva + 1} em construção',
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            'Inventário: ${_inventarioAtivo!.codigo}',
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Future<void> _avancarContagem() async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text('Avançar Contagem'),
            content: Text(
              'Deseja avançar de ${_inventarioAtivo!.contagemAtiva} '
                  'para ${_inventarioAtivo!.proximaContagem()}?\n\n'
                  'Esta ação finalizará a contagem atual.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmar'),
              ),
            ],
          ),
    );

    if (confirma != true) return;

    try {
      final sucesso = await _inventarioService.avancarParaProximaContagem(
        _inventarioAtivo!.id,
      );

      if (sucesso) {
        // ✅ Verificar mounted antes de chamar método que usa setState
        if (mounted) {
          _carregarInventarioAtivo();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Contagem avançada com sucesso')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao avançar contagem: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _finalizarInventario() async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text('Finalizar Inventário'),
            content: const Text(
              'Deseja finalizar este inventário?\n\n'
                  'Esta ação não pode ser desfeita.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Finalizar'),
              ),
            ],
          ),
    );

    if (confirma != true) return;

    try {
      await _inventarioService.finalizarInventario(_inventarioAtivo!.id);

      // ✅ Verificar mounted antes de chamar método que usa setState
      if (mounted) {
        _carregarInventarioAtivo();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inventário finalizado com sucesso')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao finalizar inventário: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
