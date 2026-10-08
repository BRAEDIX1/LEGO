// lib/ui/mobile/screens/monitor_screen.dart
//
// Entrega 3 (teste acelerado): Monitor mínimo do analista, dentro do app de
// homologação. As regras ficam nos serviços (monitor_service, comparativo_
// service, c3_service); aqui só tela e confirmações.

import 'package:flutter/material.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/services/c3.dart';
import 'package:lego/services/c3_service.dart';
import 'package:lego/services/comparativo.dart';
import 'package:lego/services/comparativo_rodadas_service.dart';
import 'package:lego/services/inventario_service.dart';
import 'package:lego/services/monitor_service.dart';
import 'package:lego/ui/mobile/screens/comparativo_screen.dart';

class MonitorScreen extends StatefulWidget {
  final String inventarioId;
  const MonitorScreen({super.key, required this.inventarioId});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  final _monitor = MonitorService();
  final _comparativo = ComparativoRodadasService();
  final _c3 = C3Service();
  final _inventarios = InventarioService();

  bool _ocupado = false;
  Map<String, Map<String, int>> _sinc = const {}; // rodada → uid → qtd

  @override
  void initState() {
    super.initState();
    _atualizarSincronizados();
  }

  Future<void> _atualizarSincronizados() async {
    try {
      final c1 = await _monitor.sincronizadosPorUsuario(
          widget.inventarioId, Rodadas.c1);
      final c2 = await _monitor.sincronizadosPorUsuario(
          widget.inventarioId, Rodadas.c2);
      if (mounted) setState(() => _sinc = {Rodadas.c1: c1, Rodadas.c2: c2});
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // helpers
  // ------------------------------------------------------------------

  void _snack(String m, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: erro ? Colors.red : null));
  }

  Future<bool> _confirmar(String titulo, String texto, String botao,
      {bool perigo = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: SingleChildScrollView(child: Text(texto)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              style: perigo
                  ? FilledButton.styleFrom(backgroundColor: Colors.red)
                  : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(botao)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _rodar(Future<void> Function() acao) async {
    setState(() => _ocupado = true);
    try {
      await acao();
    } on OperacaoNaoPermitidaException catch (e) {
      _snack(e.motivo, erro: true);
    } catch (e) {
      _snack('Erro: $e', erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ------------------------------------------------------------------
  // ações
  // ------------------------------------------------------------------

  Future<void> _encerrar(Inventario inv, String rodada) async {
    final rot = Rodadas.rotulo(rodada);
    if (!await _confirmar('Encerrar a $rot?',
        'Depois de encerrar, ninguém mais lança na $rot do Inventário '
            '${inv.numeroFormatado}.',
        'Encerrar $rot')) {
      return;
    }
    await _rodar(() async {
      try {
        await _monitor.encerrarRodada(inv.id, rodada);
        _snack('$rot encerrada.');
      } on PendentesLocaisException catch (e) {
        // A2: segundo nível explícito.
        final forcar = await _confirmar(
          'Lançamentos não sincronizados',
          'Existem lançamentos locais ainda não sincronizados:\n'
              '${e.quem.join('\n')}\n\n'
              'O comparativo pode nascer incompleto. Peça para essas pessoas '
              'ficarem online e sincronizarem.\n\nEncerrar mesmo assim?',
          'Encerrar mesmo assim',
          perigo: true,
        );
        if (forcar) {
          await _monitor.encerrarRodada(inv.id, rodada, forcar: true);
          _snack('$rot encerrada (forçado).');
        }
      }
    });
    _atualizarSincronizados();
  }

  Future<void> _gerar(Inventario inv, {bool refazer = false}) async {
    if (refazer &&
        !await _confirmar('Refazer o comparativo?',
            'As linhas atuais serão regeradas com os lançamentos de agora.',
            'Refazer')) {
      return;
    }
    await _rodar(() async {
      final r = await _comparativo.gerarComparativo(inv.id, refazer: refazer);
      _snack('Comparativo: ${r.total} itens, ${r.emAnalise} para a C3.');
    });
  }

  void _abrirComparativo(Inventario inv) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ComparativoScreen(
          inventarioId: inv.id, numeroFormatado: inv.numeroFormatado),
    ));
  }

  Future<void> _chamarC3(Inventario inv) async {
    await _rodar(() async {
      await _c3.chamarParticipantes(inv.id);
      _snack('C3 aberta: os operadores já podem tocar em "Estou pronto".');
    });
  }

  Future<void> _iniciarC3(Inventario inv, int prontos, int tarefas) async {
    final base = prontos == 0 ? 0 : tarefas ~/ prontos;
    final resto = prontos == 0 ? 0 : tarefas % prontos;
    if (!await _confirmar(
        'Iniciar a C3?',
        '$tarefas tarefa(s) para $prontos participante(s): '
            '${resto > 0 ? '$resto com ${base + 1} e ${prontos - resto} com $base' : 'cada um com $base'}.\n\n'
            'A lista de participantes fica congelada. Quem confirmar depois '
            'só entra com "Redistribuir pendentes".',
        'Iniciar C3')) {
      return;
    }
    await _rodar(() async {
      final dist = await _c3.iniciarC3(inv.id);
      _snack('C3 iniciada: ${dist.entries.map((e) => '${e.key} ${e.value}').join(', ')}');
    });
  }

  Future<void> _redistribuir(Inventario inv) async {
    if (!await _confirmar(
        'Redistribuir pendentes?',
        'Só as tarefas ainda NÃO sincronizadas mudam de responsável, entre os '
            'participantes prontos de agora. Resultados antigos dessas tarefas '
            'que chegarem depois serão recusados.',
        'Redistribuir')) {
      return;
    }
    await _rodar(() async {
      final dist = await _c3.redistribuirPendentes(inv.id);
      _snack('Redistribuído: ${dist.entries.map((e) => '${e.key} ${e.value}').join(', ')}');
    });
  }

  Future<void> _encerrarC3(Inventario inv) async {
    if (!await _confirmar('Encerrar a C3?',
        'Todas as tarefas estão sincronizadas. O resultado final fica fechado.',
        'Encerrar C3')) {
      return;
    }
    await _rodar(() async {
      await _c3.encerrarC3(inv.id);
      _snack('C3 encerrada.');
    });
  }

  Future<void> _cancelar(Inventario inv) async {
    if (!await _confirmar(
        'Cancelar o Inventário ${inv.numeroFormatado}?',
        'Uso de teste: libera um novo Inventário Completo. Os dados ficam '
            'guardados, mas o inventário não pode ser reaberto.',
        'Cancelar inventário',
        perigo: true)) {
      return;
    }
    await _rodar(() async {
      await _inventarios.cancelarInventario(inv.id,
          motivo: 'Teste cancelado pelo monitor (lego-teste)');
      _snack('Inventário cancelado.');
      if (mounted) Navigator.of(context).pop();
    });
  }

  // ------------------------------------------------------------------
  // tela
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Inventario?>(
      stream: _monitor.streamInventario(widget.inventarioId),
      builder: (context, invSnap) {
        final inv = invSnap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(inv == null
                ? 'Monitor'
                : 'Monitor · Inventário ${inv.numeroFormatado}'),
            actions: [
              IconButton(
                tooltip: 'Atualizar lançamentos sincronizados',
                onPressed: _ocupado ? null : _atualizarSincronizados,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: inv == null
              ? const Center(child: CircularProgressIndicator())
              : AbsorbPointer(
                  absorbing: _ocupado,
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _monitor.streamParticipantes(inv.id),
                    builder: (context, pSnap) {
                      final parts = pSnap.data ?? const [];
                      return ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          if (_ocupado) const LinearProgressIndicator(),
                          Text('Status: ${inv.statusLabel}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          _cardRodada(inv, Rodadas.c1, parts),
                          _cardRodada(inv, Rodadas.c2, parts),
                          _cardComparativo(inv),
                          _cardC3(inv),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red),
                            icon: const Icon(Icons.delete_forever),
                            label: Text(
                                'Cancelar Inventário ${inv.numeroFormatado} (teste)'),
                            onPressed: inv.isAtivo ? () => _cancelar(inv) : null,
                          ),
                        ],
                      );
                    },
                  ),
                ),
        );
      },
    );
  }

  Widget _card(String titulo, String status, List<Widget> filhos) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Text(titulo,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(status),
              ]),
              const Divider(),
              ...filhos,
            ],
          ),
        ),
      );

  Widget _cardRodada(
      Inventario inv, String rodada, List<Map<String, dynamic>> parts) {
    final rot = Rodadas.rotulo(rodada);
    final lista = _monitor.participantesDaRodada(
        parts, rodada, _sinc[rodada] ?? const {});
    final encerrada = inv.rodadaEncerrada(rodada);
    final finalizaram = lista.where((p) => p.finalizou).length;
    final pend = lista.fold<int>(0, (s, p) => s + p.pendentesLocais);
    return _card(rot, StatusRodada.rotulo(inv.statusRodada(rodada)), [
      Text('${lista.length} participante(s) · $finalizaram finalizaram'
          '${pend > 0 ? ' · $pend pendente(s) local(is) conhecido(s)' : ''}'),
      const SizedBox(height: 4),
      for (final p in lista)
        Text(
          '• ${p.nome}: ${p.finalizou ? 'finalizou' : 'em andamento'}'
          ' · ${p.sincronizados} no servidor'
          '${p.pendentesLocais > 0 ? ' · ${p.pendentesLocais} no aparelho' : ''}',
          style: TextStyle(
              color: p.pendentesLocais > 0 ? Colors.orange.shade800 : null),
        ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: encerrada || !inv.isAtivo ? null : () => _encerrar(inv, rodada),
        child: Text(encerrada ? '$rot encerrada' : 'Encerrar $rot'),
      ),
    ]);
  }

  Widget _cardComparativo(Inventario inv) {
    final rec = inv.reconciliacao ?? const ReconciliacaoInfo();
    final ambas =
        inv.rodadaEncerrada(Rodadas.c1) && inv.rodadaEncerrada(Rodadas.c2);
    final c3 = inv.statusRodada(Rodadas.c3);
    // Refazer só antes de a C3 ser chamada.
    final c3Comecou = c3 != null &&
        c3 != StatusRodada.pendente &&
        c3 != StatusRodada.naoNecessaria;
    if (!rec.concluida) {
      return _card(
          'Comparativo',
          rec.status == StatusReconciliacao.executando
              ? 'gerando…'
              : 'não gerado',
          [
            FilledButton(
              onPressed: ambas && rec.status != StatusReconciliacao.executando
                  ? () => _gerar(inv)
                  : null,
              child: Text(ambas
                  ? 'Gerar comparativo C1 × C2'
                  : 'Encerre C1 e C2 para gerar'),
            ),
          ]);
    }
    return StreamBuilder<List<LinhaComparativo>>(
      stream: _c3.streamLinhas(inv.id),
      builder: (context, s) {
        final r = ResumoComparativo.de(s.data ?? const []);
        return _card('Comparativo', 'gerado', [
          Text('${r.total} itens · ${r.encerradas} consenso'),
          Text('Só C1: ${r.soC1} · Só C2: ${r.soC2} · '
              'Divergentes: ${r.divergentes} · Conflitos: ${r.conflitos}'),
          Text('Requerem C3: ${r.emAnalise}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => _abrirComparativo(inv),
            child: Text(c3 == StatusRodada.encerrada
                ? 'Ver resultado final'
                : 'Abrir comparativo / resultado'),
          ),
          if (!c3Comecou)
            TextButton(
                onPressed: () => _gerar(inv, refazer: true),
                child: const Text('Refazer comparativo')),
        ]);
      },
    );
  }

  Widget _cardC3(Inventario inv) {
    final c3 = inv.statusRodada(Rodadas.c3);
    if (c3 == null || c3 == StatusRodada.naoNecessaria) {
      return _card('C3', c3 == null ? '—' : 'não necessária', const [
        Text('A C3 só existe depois do comparativo, se houver itens em análise.'),
      ]);
    }
    return StreamBuilder<List<ProntoC3>>(
      stream: _c3.streamProntos(inv.id),
      builder: (context, ps) {
        final prontos = ps.data ?? const <ProntoC3>[];
        return StreamBuilder<List<LinhaComparativo>>(
          stream: _c3.streamLinhas(inv.id),
          builder: (context, ls) {
            final tarefas =
                (ls.data ?? const <LinhaComparativo>[]).where((l) => l.emAnalise).toList();
            final sinc = tarefas
                .where((l) => l.c3Status == StatusTarefaC3.sincronizada)
                .length;
            final filhos = <Widget>[];

            if (c3 == StatusRodada.pendente) {
              filhos.addAll([
                Text('${tarefas.length} item(ns) para recontar.'),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => _chamarC3(inv),
                  child: const Text('Chamar participantes da C3'),
                ),
              ]);
            }

            if (c3 == StatusRodada.aguardandoParticipantes) {
              filhos.addAll([
                Text('${tarefas.length} tarefa(s) · ${prontos.length} '
                    'participante(s) pronto(s):'),
                for (final p in prontos) Text('• ${p.nome}'),
                if (prontos.isEmpty)
                  const Text('Ninguém confirmou ainda. No celular: '
                      'tela de escolha → "Estou pronto para a C3".'),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: prontos.isEmpty
                      ? null
                      : () => _iniciarC3(inv, prontos.length, tarefas.length),
                  child: const Text('Iniciar C3 (congela e distribui)'),
                ),
              ]);
            }

            if (c3 == StatusRodada.distribuindo ||
                c3 == StatusRodada.redistribuindo) {
              filhos.addAll([
                const Text('Gravando a distribuição. Os aparelhos só baixam '
                    'tarefas quando terminar. Se demorar (app fechado, rede '
                    'caiu), retome:'),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _rodar(() async {
                    await _c3.retomarDistribuicao(inv.id);
                    _snack('Distribuição concluída.');
                  }),
                  child: const Text('Retomar distribuição'),
                ),
              ]);
            }

            if (c3 == StatusRodada.emAndamento ||
                c3 == StatusRodada.encerrada) {
              // Todos os congelados aparecem, inclusive com zero tarefas.
              final porResp = <String, List<LinhaComparativo>>{
                for (final u in inv.contagens[Rodadas.c3]?.usuarios ??
                    const <String>[])
                  u: <LinhaComparativo>[],
              };
              for (final t in tarefas) {
                porResp
                    .putIfAbsent(t.c3ResponsavelUid ?? '(sem responsável)',
                        () => [])
                    .add(t);
              }
              final infoAparelho = {for (final p in prontos) p.uid: p};
              filhos.addAll([
                LinearProgressIndicator(
                    value: tarefas.isEmpty ? 0 : sinc / tarefas.length),
                const SizedBox(height: 4),
                Text('$sinc de ${tarefas.length} sincronizadas · '
                    '${tarefas.length - sinc} pendentes',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                for (final e in porResp.entries)
                  Builder(builder: (_) {
                    final nome = e.value.isNotEmpty
                        ? (e.value.first.c3ResponsavelNome ?? e.key)
                        : (infoAparelho[e.key]?.nome ?? e.key);
                    final s = e.value
                        .where((l) => l.c3Status == StatusTarefaC3.sincronizada)
                        .length;
                    final ap = infoAparelho[e.key];
                    return Text('• $nome: ${e.value.length} tarefa(s) · $s '
                        'sincronizada(s)'
                        '${ap != null ? ' · ${ap.concluidasLocais} concluída(s) no aparelho' : ''}');
                  }),
                if (c3 == StatusRodada.emAndamento) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed:
                        sinc < tarefas.length ? () => _redistribuir(inv) : null,
                    child: const Text('Redistribuir pendentes'),
                  ),
                  FilledButton(
                    onPressed: tarefas.isNotEmpty && sinc == tarefas.length
                        ? () => _encerrarC3(inv)
                        : null,
                    child: const Text('Encerrar C3'),
                  ),
                ],
              ]);
            }

            return _card('C3', StatusRodada.rotulo(c3), filhos);
          },
        );
      },
    );
  }
}
