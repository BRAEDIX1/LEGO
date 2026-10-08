// lib/ui/mobile/screens/c3_screen.dart
//
// Entrega 3 (teste acelerado): "Minhas tarefas C3" do operador.
// - Trabalha com as tarefas guardadas no aparelho: funciona SEM internet.
// - Contagem às cegas: não mostra C1 nem C2.
// - "Sincronizar" envia o que foi concluído quando houver rede.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lego/services/c3.dart';
import 'package:lego/services/c3_service.dart';
import 'package:lego/services/comparativo.dart';

class C3Screen extends StatelessWidget {
  // Mantido por compatibilidade de chamada; a tela lê do aparelho.
  final String? inventarioId;
  final String? numeroFormatado;
  const C3Screen({super.key, this.inventarioId, this.numeroFormatado});

  @override
  Widget build(BuildContext context) => const MinhasTarefasC3Screen();
}

class MinhasTarefasC3Screen extends StatefulWidget {
  const MinhasTarefasC3Screen({super.key});

  @override
  State<MinhasTarefasC3Screen> createState() => _MinhasTarefasC3ScreenState();
}

class _MinhasTarefasC3ScreenState extends State<MinhasTarefasC3Screen> {
  final _c3 = C3Service();
  bool _carregando = true;
  bool _ocupado = false;
  String? _numero;
  List<TarefaC3Local> _tarefas = const [];

  @override
  void initState() {
    super.initState();
    _carregar(sincronizarDepois: true);
  }

  Future<void> _carregar({bool sincronizarDepois = false}) async {
    final (inv, numero, lista) = await _c3.lerLocal();
    if (!mounted) return;
    setState(() {
      _numero = numero;
      _tarefas = inv == null ? const [] : lista;
      _carregando = false;
    });
    if (sincronizarDepois) _sincronizar(silencioso: true);
  }

  Future<void> _sincronizar({bool silencioso = false}) async {
    if (_tarefas.isEmpty) return;
    setState(() => _ocupado = true);
    try {
      final r = await _c3.sincronizar();
      await _carregar();
      if (!silencioso || r.enviadas > 0 || r.recusadas > 0) {
        _snack('Enviadas: ${r.enviadas}'
            '${r.recusadas > 0 ? ' · recusadas: ${r.recusadas}' : ''}'
            '${r.falhas > 0 ? ' · sem rede: ${r.falhas} (ficam no aparelho)' : ''}');
      }
    } catch (e) {
      if (!silencioso) _snack('Erro ao sincronizar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _concluir(TarefaC3Local t, TotaisRodada v) async {
    // B61: só grava no aparelho. O envio é pelo botão Sincronizar (ou ao
    // reabrir a tela), numa sincronização única por vez.
    final nova = await _c3.concluirLocal(t, v);
    if (!mounted) return;
    setState(() => _tarefas = nova);
  }

  Future<void> _contarTag(TarefaC3Local t) async {
    final escolha = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('TAG ${t.tag}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${t.codigo} ${t.descricao}'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('Encontrado CHEIO'),
              onTap: () => Navigator.pop(ctx, 'cheio'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.check_circle_outline, color: Colors.blue),
              title: const Text('Encontrado VAZIO'),
              onTap: () => Navigator.pop(ctx, 'vazio'),
            ),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.red),
              title: const Text('NÃO encontrado'),
              onTap: () => Navigator.pop(ctx, 'nao'),
            ),
          ],
        ),
      ),
    );
    if (escolha == null) return;
    final v = switch (escolha) {
      'cheio' => const TotaisRodada(quantidade: 1, cheio: 1, ocorrencias: 1),
      'vazio' => const TotaisRodada(quantidade: 1, vazio: 1, ocorrencias: 1),
      _ => const TotaisRodada(ocorrencias: 1, naoEncontrado: true),
    };
    await _concluir(t, v);
  }

  Future<void> _contarMaterial(TarefaC3Local t) async {
    final qtd = TextEditingController();
    final cheio = TextEditingController();
    final vazio = TextEditingController();
    double ler(TextEditingController c) =>
        double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0.0;
    final fmt = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    const teclado = TextInputType.numberWithOptions(decimal: true);

    final ok = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${t.codigo}'
            '${(t.lote ?? '').isNotEmpty ? ' · lote ${t.lote}' : ''}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (t.descricao.isNotEmpty) Text(t.descricao),
              TextField(
                  controller: qtd,
                  autofocus: true,
                  keyboardType: teclado,
                  inputFormatters: fmt,
                  decoration: const InputDecoration(labelText: 'Quantidade')),
              TextField(
                  controller: cheio,
                  keyboardType: teclado,
                  inputFormatters: fmt,
                  decoration:
                      const InputDecoration(labelText: 'Cheios (se houver)')),
              TextField(
                  controller: vazio,
                  keyboardType: teclado,
                  inputFormatters: fmt,
                  decoration:
                      const InputDecoration(labelText: 'Vazios (se houver)')),
              const SizedBox(height: 8),
              const Text('Em branco conta como zero.',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'nao'),
              child: const Text('NÃO encontrado')),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'ok'),
              child: const Text('Gravar')),
        ],
      ),
    );
    if (ok == null) return;
    await _concluir(
      t,
      ok == 'nao'
          ? const TotaisRodada(ocorrencias: 1, naoEncontrado: true)
          : TotaisRodada(
              quantidade: ler(qtd),
              cheio: ler(cheio),
              vazio: ler(vazio),
              ocorrencias: 1),
    );
  }

  (IconData, Color?, String) _visual(TarefaC3Local t) => switch (t.estado) {
        EstadoLocalC3.atribuida => (Icons.radio_button_unchecked, null, 'a fazer'),
        EstadoLocalC3.concluidaLocal =>
          (Icons.check_circle_outline, Colors.orange, 'concluída · falta enviar'),
        EstadoLocalC3.sincronizada =>
          (Icons.cloud_done, Colors.green, 'enviada'),
        EstadoLocalC3.recusada =>
          (Icons.block, Colors.red, 'recusada: ${t.motivoRecusa ?? ''}'),
      };

  @override
  Widget build(BuildContext context) {
    final aFazer =
        _tarefas.where((t) => t.estado == EstadoLocalC3.atribuida).length;
    final faltaEnviar =
        _tarefas.where((t) => t.estado == EstadoLocalC3.concluidaLocal).length;
    final enviadas =
        _tarefas.where((t) => t.estado == EstadoLocalC3.sincronizada).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Minhas tarefas C3'
            '${_numero != null ? ' · Inv. $_numero' : ''}'),
        actions: [
          IconButton(
            tooltip: 'Sincronizar',
            onPressed: _ocupado ? null : () => _sincronizar(),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _tarefas.isEmpty
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nenhuma tarefa C3 neste aparelho. Com internet, '
                      'use "Baixar minhas tarefas C3" na tela de escolha.'),
                ))
              : AbsorbPointer(
                  // B61: sem edição durante a sincronização.
                  absorbing: _ocupado,
                  child: Column(
                  children: [
                    if (_ocupado) const LinearProgressIndicator(),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'A fazer: $aFazer · falta enviar: $faltaEnviar · '
                        'enviadas: $enviadas',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Pode trabalhar sem internet. Com rede, toque no '
                        'botão sincronizar (no topo) para enviar o que está '
                        'em "falta enviar".',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _tarefas.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final t = _tarefas[i];
                          final (icone, cor, legenda) = _visual(t);
                          final editavel = t.estado == EstadoLocalC3.atribuida ||
                              t.estado == EstadoLocalC3.concluidaLocal;
                          return ListTile(
                            leading: Icon(icone, color: cor),
                            title: Text(t.tipo == 'tag'
                                ? 'TAG ${t.tag} · ${t.codigo}'
                                : '${t.codigo}'
                                    '${(t.lote ?? '').isNotEmpty ? ' · lote ${t.lote}' : ''}'),
                            subtitle: Text(
                                '${t.descricao.isNotEmpty ? '${t.descricao}\n' : ''}$legenda'),
                            isThreeLine: t.descricao.isNotEmpty,
                            trailing: editavel ? const Icon(Icons.edit) : null,
                            onTap: !editavel
                                ? null
                                : () => t.tipo == 'tag'
                                    ? _contarTag(t)
                                    : _contarMaterial(t),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                ),
    );
  }
}
