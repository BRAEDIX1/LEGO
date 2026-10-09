// lib/ui/mobile/screens/c3_screen.dart
//
// "Minhas tarefas C3" do operador (lista de itens divergentes).
// - Trabalha com as tarefas guardadas no aparelho: funciona SEM internet.
// - Contagem às cegas: não mostra C1 nem C2.
// - Item 6 (Djalma 09/10): tocar no item abre a TELA PADRÃO de lançamento
//   (LancamentoC3Page, na home_page) com o item e a localização fixados.
// - Sincronização automática (ao abrir, ao voltar de um lançamento, quando a
//   rede volta e a cada 20 s enquanto houver pendência). Sem botão atualizar.
// - "Finalizar minha C3" só habilita com 100% das tarefas sincronizadas.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import 'package:lego/models/sessao_contagem.dart';
import 'package:lego/services/c3.dart';
import 'package:lego/services/c3_service.dart';
import 'package:lego/ui/home_page.dart' show LancamentoC3Page;

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
  bool _sincronizando = false;
  bool _finalizando = false;
  String? _numero;
  List<TarefaC3Local> _tarefas = const [];
  StreamSubscription<List<ConnectivityResult>>? _redeSub;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _carregar(sincronizarDepois: true);
    // Rede voltou → sincroniza sozinho.
    _redeSub = Connectivity().onConnectivityChanged.listen((r) {
      if (r.any((x) => x != ConnectivityResult.none)) _sincronizar();
    });
    // Rede "presa" (Wi-Fi sem internet): tenta de novo periodicamente.
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_pendentes > 0) _sincronizar();
    });
  }

  @override
  void dispose() {
    _redeSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  int get _pendentes => _tarefas
      .where((t) =>
          t.estado == EstadoLocalC3.atribuida ||
          t.estado == EstadoLocalC3.concluidaLocal)
      .length;

  int get _faltaEnviar => _tarefas
      .where((t) => t.estado == EstadoLocalC3.concluidaLocal)
      .length;

  Future<void> _carregar({bool sincronizarDepois = false}) async {
    final (inv, numero, lista) = await _c3.lerLocal();
    if (!mounted) return;
    setState(() {
      _numero = numero;
      _tarefas = inv == null ? const [] : lista;
      _carregando = false;
    });
    if (sincronizarDepois) _sincronizar();
  }

  /// Silenciosa: o estado de cada item na lista já mostra o resultado.
  Future<void> _sincronizar() async {
    if (_faltaEnviar == 0 || _sincronizando || !mounted) return;
    setState(() => _sincronizando = true);
    try {
      final r = await _c3.sincronizar();
      await _carregar();
      if (r.recusadas > 0) {
        _snack('${r.recusadas} item(ns) recusado(s) pelo servidor — veja o '
            'motivo na lista.');
      }
    } catch (_) {
      // sem rede: tenta de novo depois
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  void _snack(String m, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: erro ? Colors.red : null));
  }

  String _local(TarefaC3Local t) => t.localNome ?? t.localId ?? '';

  String get _cabecalho {
    final tipo = _tarefas.isEmpty
        ? ''
        : ' | ${SessaoContagem.rotuloNatureza(_tarefas.first.tipo)}';
    return 'Inventário ${_numero ?? '—'}$tipo | C3';
  }

  Future<void> _abrir(TarefaC3Local t) async {
    final gravou = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => LancamentoC3Page(tarefa: t, cabecalho: _cabecalho),
    ));
    await _carregar();
    if (gravou == true) _sincronizar();
  }

  Future<void> _finalizar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar minha C3?'),
        content: const Text('Todos os itens estão sincronizados. Depois de '
            'finalizar, as tarefas saem deste aparelho.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Finalizar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _finalizando = true);
    try {
      await _c3.finalizarMinhaC3();
      if (!mounted) return;
      _snack('C3 finalizada. Obrigado!');
      Navigator.of(context).pop();
    } catch (e) {
      _snack('Não foi possível finalizar (precisa de internet): $e',
          erro: true);
    } finally {
      if (mounted) setState(() => _finalizando = false);
    }
  }

  (IconData, Color?, String) _visual(TarefaC3Local t) => switch (t.estado) {
        EstadoLocalC3.atribuida => (Icons.radio_button_unchecked, null, 'a contar'),
        EstadoLocalC3.concluidaLocal =>
          (Icons.cloud_upload_outlined, Colors.orange, 'contado · enviando…'),
        EstadoLocalC3.sincronizada =>
          (Icons.cloud_done, Colors.green, 'sincronizado'),
        EstadoLocalC3.recusada =>
          (Icons.block, Colors.red, 'recusado: ${t.motivoRecusa ?? ''}'),
      };

  @override
  Widget build(BuildContext context) {
    final aContar =
        _tarefas.where((t) => t.estado == EstadoLocalC3.atribuida).length;
    final enviadas =
        _tarefas.where((t) => t.estado == EstadoLocalC3.sincronizada).length;
    final podeFinalizar = todasSincronizadas(_tarefas);
    // Agrupadas por local, para percorrer área por área.
    final lista = [..._tarefas]..sort((a, b) {
        final c = _local(a).compareTo(_local(b));
        return c != 0 ? c : a.codigo.compareTo(b.codigo);
      });

    return Scaffold(
      appBar: AppBar(
        title: Text('Minhas tarefas C3'
            '${_numero != null ? ' · Inv. $_numero' : ''}'),
        actions: [
          if (_sincronizando)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _tarefas.isEmpty
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nenhuma tarefa C3 neste aparelho.'),
                ))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'A contar: $aContar · enviando: $_faltaEnviar · '
                        'sincronizados: $enviadas de ${_tarefas.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: lista.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final t = lista[i];
                          final (icone, cor, legenda) = _visual(t);
                          final editavel = !_finalizando &&
                              (t.estado == EstadoLocalC3.atribuida ||
                                  t.estado == EstadoLocalC3.concluidaLocal);
                          return ListTile(
                            leading: Icon(icone, color: cor),
                            title: Text('${t.codigo}'
                                '${(t.lote ?? '').isNotEmpty ? ' · lote ${t.lote}' : ''}'),
                            subtitle: Text([
                              if (_local(t).isNotEmpty)
                                '📍 ${_local(t)}'
                                '${t.prateleira.isNotEmpty ? ' · prat. ${t.prateleira}' : ''}',
                              if (t.descricao.isNotEmpty) t.descricao,
                              legenda,
                            ].join('\n')),
                            isThreeLine: true,
                            trailing:
                                editavel ? const Icon(Icons.chevron_right) : null,
                            onTap: editavel ? () => _abrir(t) : null,
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.orange,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14)),
                            onPressed: podeFinalizar && !_finalizando
                                ? _finalizar
                                : null,
                            icon: const Icon(Icons.check_circle),
                            label: Text(podeFinalizar
                                ? 'Finalizar minha C3'
                                : 'Finalizar minha C3 · faltam $_pendentes '
                                    'item(ns) sincronizar'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
