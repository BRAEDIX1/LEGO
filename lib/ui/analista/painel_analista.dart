// lib/ui/analista/painel_analista.dart
//
// Painel do analista: etapas em ordem (C1 → C2 → Comparativo → C3 → Final),
// cada uma com o estado, QUEM está nela (em andamento / finalizou) e UMA ação
// principal. Tudo por escuta em tempo real (inclusive os lançamentos no
// servidor por pessoa).
//
// UM código para os dois lugares: o celular (MonitorScreen, acesso de
// intervenção) e o desktop (InventarioCompletoScreen, uso normal). Regras de
// negócio ficam nos serviços (monitor, comparativo, C3); aqui só tela e
// confirmações.

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/services/c3.dart';
import 'package:lego/services/c3_service.dart';
import 'package:lego/services/comparativo.dart';
import 'package:lego/services/comparativo_rodadas_service.dart';
import 'package:lego/services/inventario_service.dart';
import 'package:lego/services/monitor_service.dart';
import 'package:lego/services/relatorio_inventario_service.dart';

// ---------------------------------------------------------------------------
// Ações compartilhadas (celular e desktop)
// ---------------------------------------------------------------------------

void avisar(BuildContext context, String m, {bool erro = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: erro ? Colors.red : null));
}

Future<bool> confirmarAcao(
    BuildContext context, String titulo, String texto, String botao,
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

bool get _ehDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Gera o .xlsx. Celular: grava no aparelho e abre. Desktop: janela
/// "Salvar como" e abre. Devolve o caminho (null = cancelou o "Salvar como").
Future<String?> exportarRelatorioXlsx(String inventarioId) async {
  final svc = RelatorioInventarioService();
  if (!_ehDesktop) {
    final caminho = await svc.exportar(inventarioId);
    await OpenFilex.open(caminho);
    return caminho;
  }
  final (nome, bytes) = await svc.gerar(inventarioId);
  return salvarXlsxComo(nome, bytes);
}

/// Desktop: janela "Salvar como" para um .xlsx já montado, e abre o arquivo.
/// Devolve o caminho (null = cancelou).
Future<String?> salvarXlsxComo(String nome, List<int> bytes,
    {String titulo = 'Salvar relatório'}) async {
  var destino = await FilePicker.platform.saveFile(
    dialogTitle: titulo,
    fileName: nome,
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
  );
  if (destino == null) return null;
  if (!destino.toLowerCase().endsWith('.xlsx')) destino = '$destino.xlsx';
  await File(destino).writeAsBytes(bytes, flush: true);
  try {
    await OpenFilex.open(destino);
  } catch (_) {} // salvou; abrir é cortesia
  return destino;
}

/// Cancela o inventário (ação do analista). Devolve true se cancelou.
Future<bool> cancelarInventarioComConfirmacao(
    BuildContext context, Inventario inv) async {
  if (!await confirmarAcao(
      context,
      'Cancelar o Inventário ${inv.numeroFormatado}?',
      'O inventário fica CANCELADO (não vira resultado) e um novo Inventário '
          'Completo pode ser aberto. Os dados ficam guardados, mas ele não '
          'pode ser reaberto.\n\nPara terminar um inventário normalmente, use '
          '"Encerrar inventário" no Resultado final.',
      'Cancelar inventário',
      perigo: true)) {
    return false;
  }
  try {
    await InventarioService().cancelarInventario(inv.id,
        motivo: 'Cancelado pelo analista (painel)');
    if (context.mounted) avisar(context, 'Inventário cancelado.');
    return true;
  } on OperacaoNaoPermitidaException catch (e) {
    if (context.mounted) avisar(context, e.motivo, erro: true);
  } catch (e) {
    if (context.mounted) avisar(context, 'Erro: $e', erro: true);
  }
  return false;
}

// ---------------------------------------------------------------------------
// Painel
// ---------------------------------------------------------------------------

class PainelAnalista extends StatefulWidget {
  final String inventarioId;
  /// Celular: abre o relatório numa tela. Desktop: null (o relatório já está
  /// ao lado) e os botões "Ver relatório" somem.
  final void Function(Inventario inv)? onAbrirRelatorio;
  final EdgeInsetsGeometry padding;

  const PainelAnalista({
    super.key,
    required this.inventarioId,
    this.onAbrirRelatorio,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  State<PainelAnalista> createState() => _PainelAnalistaState();
}

class _PainelAnalistaState extends State<PainelAnalista> {
  final _monitor = MonitorService();
  final _comparativo = ComparativoRodadasService();
  final _c3 = C3Service();

  late Stream<Inventario?> _streamInv;
  late Stream<List<Map<String, dynamic>>> _streamParts;
  late Stream<List<LinhaComparativo>> _streamLinhas;

  bool _ocupado = false;
  /// Inventário antigo (sem tipo): consolidado escolhido para a C3.
  Natureza? _naturezaC3;
  Map<String, Map<String, int>> _sinc = const {}; // rodada → uid → qtd
  final List<StreamSubscription<Map<String, int>>> _escutaSinc = [];

  @override
  void initState() {
    super.initState();
    _assinar();
  }

  @override
  void didUpdateWidget(covariant PainelAnalista old) {
    super.didUpdateWidget(old);
    if (old.inventarioId != widget.inventarioId) {
      _naturezaC3 = null;
      _sinc = const {};
      _assinar();
    }
  }

  void _assinar() {
    _streamInv = _monitor.streamInventario(widget.inventarioId);
    _streamParts = _monitor.streamParticipantes(widget.inventarioId);
    _streamLinhas = _c3.streamLinhas(widget.inventarioId);
    _escutarSincronizados();
  }

  /// Lançamentos no servidor por pessoa, em tempo real (C1 e C2).
  void _escutarSincronizados() {
    for (final e in _escutaSinc) {
      e.cancel();
    }
    _escutaSinc.clear();
    final id = widget.inventarioId;
    for (final rodada in Rodadas.base) {
      _escutaSinc.add(_monitor
          .streamSincronizadosPorUsuario(id, rodada)
          .listen((porUid) {
        if (!mounted || id != widget.inventarioId) return;
        setState(() => _sinc = {..._sinc, rodada: porUid});
      }, onError: (_) {}));
    }
  }

  @override
  void dispose() {
    for (final e in _escutaSinc) {
      e.cancel();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------
  // helpers
  // ------------------------------------------------------------------

  void _snack(String m, {bool erro = false}) {
    if (!mounted) return;
    avisar(context, m, erro: erro);
  }

  Future<bool> _confirmar(String titulo, String texto, String botao,
          {bool perigo = false}) =>
      confirmarAcao(context, titulo, texto, botao, perigo: perigo);

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

  Natureza? _tipo(Inventario inv) => NaturezaRotulo.deNome(inv.naturezaContagem);

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
          'Existem lançamentos ainda nos aparelhos:\n'
              '${e.quem.join('\n')}\n\n'
              'O comparativo pode nascer incompleto. Peça para essas pessoas '
              'ficarem online.\n\nEncerrar mesmo assim?',
          'Encerrar mesmo assim',
          perigo: true,
        );
        if (forcar) {
          await _monitor.encerrarRodada(inv.id, rodada, forcar: true);
          _snack('$rot encerrada (forçado).');
        }
      }
    });
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
      final tipo = _tipo(inv);
      final paraC3 =
          tipo == null ? r.emAnalise : (r.divergenciasPor[tipo] ?? 0);
      final info = r.emAnalise - paraC3;
      _snack('Comparativo: ${r.encerradas} fecharam · $paraC3 para a C3'
          '${info > 0 ? ' · $info informativa(s)' : ''}.');
    });
  }

  void _abrirRelatorio(Inventario inv) => widget.onAbrirRelatorio?.call(inv);

  Future<void> _exportar(Inventario inv) async {
    await _rodar(() async {
      final caminho = await exportarRelatorioXlsx(inv.id);
      if (caminho != null) _snack('Planilha salva: $caminho');
    });
  }

  Future<void> _chamarC3(Inventario inv, Natureza natureza, int qtd,
      {bool doTipo = false}) async {
    if (!await _confirmar(
        'Chamar participantes da C3?',
        doTipo
            ? '$qtd item(ns) de ${natureza.rotulo} para recontar.'
            : 'Só os $qtd item(ns) de ${natureza.rotulo} vão para a C3. Os '
                'outros consolidados ficam informativos. A escolha não pode '
                'ser trocada depois.',
        'Chamar participantes')) {
      return;
    }
    await _rodar(() async {
      await _c3.chamarParticipantes(inv.id, natureza);
      _snack('C3 aberta: os operadores tocam em "Estou pronto para a C3".');
    });
  }

  Future<void> _iniciarC3(Inventario inv, int prontos, int tarefas) async {
    final base = prontos == 0 ? 0 : tarefas ~/ prontos;
    final resto = prontos == 0 ? 0 : tarefas % prontos;
    if (!await _confirmar(
        'Iniciar a C3?',
        '$tarefas item(ns) para $prontos participante(s): '
            '${resto > 0 ? '$resto com ${base + 1} e ${prontos - resto} com $base' : 'cada um com $base'}.\n\n'
            'A lista de participantes fica congelada.',
        'Iniciar C3')) {
      return;
    }
    await _rodar(() async {
      await _c3.iniciarC3(inv.id);
      _snack('C3 iniciada. Os itens já estão nos aparelhos dos participantes.');
    });
  }

  Future<void> _redistribuir(Inventario inv) async {
    if (!await _confirmar(
        'Redistribuir pendentes?',
        'ATENÇÃO (B64): use só se TODOS os participantes já sincronizaram o '
            'que contaram. Itens contados offline e ainda não enviados podem '
            'ser perdidos.\n\nSó os itens ainda NÃO sincronizados mudam de '
            'responsável, entre os participantes prontos de agora.',
        'Redistribuir',
        perigo: true)) {
      return;
    }
    await _rodar(() async {
      await _c3.redistribuirPendentes(inv.id);
      _snack('Pendentes redistribuídos.');
    });
  }

  Future<void> _encerrarC3(Inventario inv) async {
    if (!await _confirmar('Encerrar a C3?',
        'Todos os itens estão sincronizados. O resultado final fica fechado.',
        'Encerrar C3')) {
      return;
    }
    await _rodar(() async {
      await _c3.encerrarC3(inv.id);
      _snack('C3 encerrada. Resultado final pronto.');
    });
  }

  // ------------------------------------------------------------------
  // tela
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Inventario?>(
      stream: _streamInv,
      builder: (context, invSnap) {
        final inv = invSnap.data;
        if (inv == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return AbsorbPointer(
          absorbing: _ocupado,
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _streamParts,
            builder: (context, pSnap) {
              final parts = pSnap.data ?? const [];
              return StreamBuilder<List<LinhaComparativo>>(
                stream: _streamLinhas,
                builder: (context, lSnap) {
                  final linhas = lSnap.data ?? const <LinhaComparativo>[];
                  return ListView(
                    padding: widget.padding,
                    children: [
                      if (_ocupado) const LinearProgressIndicator(),
                      _etapas(inv),
                      const SizedBox(height: 8),
                      _cardRodada(inv, Rodadas.c1, parts),
                      _cardRodada(inv, Rodadas.c2, parts),
                      _cardComparativo(inv, linhas),
                      _cardC3(inv, linhas),
                      _cardFinal(inv),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  // ---------------- etapas ----------------

  /// 0 = C1/C2, 1 = comparativo, 2 = C3, 3 = final.
  int _etapaAtual(Inventario inv) {
    final ambas =
        inv.rodadaEncerrada(Rodadas.c1) && inv.rodadaEncerrada(Rodadas.c2);
    final rec = inv.reconciliacao ?? const ReconciliacaoInfo();
    final c3 = inv.statusRodada(Rodadas.c3);
    if (!ambas) return 0;
    if (!rec.concluida) return 1;
    if (c3 == StatusRodada.encerrada || c3 == StatusRodada.naoNecessaria) {
      return 3;
    }
    return 2;
  }

  Widget _etapas(Inventario inv) {
    final atual = _etapaAtual(inv);
    const nomes = ['C1 e C2', 'Comparativo', 'C3', 'Final'];
    return Row(
      children: [
        for (var i = 0; i < nomes.length; i++) ...[
          Expanded(
            child: Column(children: [
              Icon(
                i < atual
                    ? Icons.check_circle
                    : i == atual
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                color: i < atual
                    ? Colors.green
                    : i == atual
                        ? Colors.deepPurple
                        : Colors.grey,
              ),
              Text(nomes[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          i == atual ? FontWeight.bold : FontWeight.normal)),
            ]),
          ),
          if (i < nomes.length - 1)
            const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
        ],
      ],
    );
  }

  // ---------------- blocos ----------------

  Widget _card(String titulo, String status, Color corStatus,
          List<Widget> filhos) =>
      Card(
        margin: const EdgeInsets.only(bottom: 10),
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: corStatus.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(status,
                      style: TextStyle(
                          color: corStatus,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 8),
              ...filhos,
            ],
          ),
        ),
      );

  Widget _pessoa(
          {required bool finalizou,
          required String nome,
          required String detalhe,
          Color? corDetalhe}) =>
      ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        leading: Icon(finalizou ? Icons.check_circle : Icons.timelapse,
            color: finalizou ? Colors.green : Colors.orange),
        title: Text(nome),
        subtitle: Text(
            '${finalizou ? 'finalizou' : 'em andamento'} · $detalhe',
            style: TextStyle(color: corDetalhe)),
      );

  Color _corStatus(String? st) => switch (st) {
        StatusRodada.encerrada => Colors.green,
        StatusRodada.emAndamento => Colors.orange,
        StatusRodada.naoNecessaria => Colors.grey,
        null => Colors.grey,
        _ => Colors.deepPurple,
      };

  Widget _cardRodada(
      Inventario inv, String rodada, List<Map<String, dynamic>> parts) {
    final rot = Rodadas.rotulo(rodada);
    final lista = _monitor.participantesDaRodada(
        parts, rodada, _sinc[rodada] ?? const {});
    final st = inv.statusRodada(rodada);
    final encerrada = inv.rodadaEncerrada(rodada);
    final finalizaram = lista.where((p) => p.finalizou).length;
    final andamento = lista.length - finalizaram;
    return _card(rot, StatusRodada.rotulo(st), _corStatus(st), [
      Text(lista.isEmpty
          ? 'Ninguém entrou ainda.'
          : '${lista.length} pessoa(s): $andamento em andamento · '
              '$finalizaram finalizou(aram)'),
      for (final p in lista)
        _pessoa(
          finalizou: p.finalizou,
          nome: p.nome,
          detalhe: '${p.sincronizados} lançamento(s) no servidor'
              '${p.pendentesLocais > 0 ? ' · ${p.pendentesLocais} ainda no aparelho' : ''}',
          corDetalhe: p.pendentesLocais > 0 ? Colors.orange.shade800 : null,
        ),
      if (!encerrada) ...[
        const SizedBox(height: 4),
        FilledButton(
          onPressed: inv.isAtivo ? () => _encerrar(inv, rodada) : null,
          child: Text('Encerrar $rot'),
        ),
      ],
    ]);
  }

  Widget _cardComparativo(Inventario inv, List<LinhaComparativo> linhas) {
    final rec = inv.reconciliacao ?? const ReconciliacaoInfo();
    final ambas =
        inv.rodadaEncerrada(Rodadas.c1) && inv.rodadaEncerrada(Rodadas.c2);
    final c3 = inv.statusRodada(Rodadas.c3);
    final c3Comecou = c3 != null &&
        c3 != StatusRodada.pendente &&
        c3 != StatusRodada.naoNecessaria;
    if (!rec.concluida) {
      final gerando = rec.status == StatusReconciliacao.executando;
      return _card('Comparativo', gerando ? 'gerando…' : 'aguardando',
          Colors.grey, [
        Text(ambas
            ? 'C1 e C2 encerradas. Gere o comparativo.'
            : 'Encerre a C1 e a C2 para gerar.'),
        const SizedBox(height: 4),
        FilledButton(
          onPressed: ambas && !gerando ? () => _gerar(inv) : null,
          child: const Text('Gerar comparativo C1 × C2'),
        ),
      ]);
    }
    final tipo = _tipo(inv);
    final r = ResumoComparativo.de(linhas);
    final paraC3 = divergenciasParaC3(linhas, tipo);
    final info = r.emAnalise - paraC3;
    return _card('Comparativo', 'gerado', Colors.green, [
      Text('${r.encerradas} item(ns) fecharam (C1 = C2)'),
      Text('$paraC3 item(ns) divergentes vão para a C3',
          style: const TextStyle(fontWeight: FontWeight.bold)),
      if (info > 0)
        Text('$info divergência(s) informativa(s) (fora da C3)',
            style: const TextStyle(color: Colors.grey)),
      const SizedBox(height: 6),
      Row(children: [
        if (widget.onAbrirRelatorio != null) ...[
          Expanded(
            child: OutlinedButton(
                onPressed: () => _abrirRelatorio(inv),
                child: const Text('Ver relatório')),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: OutlinedButton.icon(
              onPressed: () => _exportar(inv),
              icon: const Icon(Icons.file_download, size: 18),
              label: const Text('.xlsx')),
        ),
      ]),
      if (!c3Comecou)
        TextButton(
            onPressed: () => _gerar(inv, refazer: true),
            child: const Text('Refazer comparativo')),
    ]);
  }

  Widget _cardC3(Inventario inv, List<LinhaComparativo> linhas) {
    final c3 = inv.statusRodada(Rodadas.c3);
    final tipo = _tipo(inv);
    final rec = inv.reconciliacao ?? const ReconciliacaoInfo();
    if (!rec.concluida || c3 == null) {
      return _card('C3', 'aguardando', Colors.grey,
          const [Text('A C3 nasce do comparativo, se houver divergência.')]);
    }
    if (c3 == StatusRodada.naoNecessaria) {
      return _card('C3', 'não necessária', Colors.grey, [
        Text(tipo != null
            ? 'Nenhuma divergência de ${tipo.rotulo}.'
            : 'Nenhuma divergência.'),
      ]);
    }
    return StreamBuilder<List<ProntoC3>>(
      stream: _c3.streamProntos(inv.id),
      builder: (context, ps) {
        final prontos = ps.data ?? const <ProntoC3>[];
        final tarefas = linhas.where((l) => l.naC3).toList();
        final filhos = <Widget>[];

        if (c3 == StatusRodada.pendente) {
          final porNatureza = {
            for (final n in Natureza.values)
              n: linhas.where((l) => l.emAnalise && l.natureza == n).length,
          };
          if (tipo != null) {
            final n = porNatureza[tipo]!;
            filhos.addAll([
              Text('$n item(ns) de ${tipo.rotulo} para recontar.'),
              const SizedBox(height: 4),
              FilledButton(
                onPressed: n == 0
                    ? null
                    : () => _chamarC3(inv, tipo, n, doTipo: true),
                child: const Text('Chamar participantes'),
              ),
            ]);
          } else {
            // Inventário antigo, sem tipo: o analista escolhe um consolidado.
            final sel = _naturezaC3;
            filhos.add(const Text('Inventário sem tipo: escolha o que a C3 '
                'vai recontar.'));
            for (final n in Natureza.values) {
              filhos.add(RadioListTile<Natureza>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: n,
                groupValue: sel,
                onChanged: porNatureza[n]! > 0
                    ? (v) => setState(() => _naturezaC3 = v)
                    : null,
                title: Text('${n.rotulo}: ${porNatureza[n]} item(ns)'),
              ));
            }
            filhos.add(FilledButton(
              onPressed: sel == null || porNatureza[sel]! == 0
                  ? null
                  : () => _chamarC3(inv, sel, porNatureza[sel]!),
              child: const Text('Chamar participantes'),
            ));
          }
        }

        if (c3 == StatusRodada.aguardandoParticipantes) {
          filhos.addAll([
            Text('${tarefas.length} item(ns) para recontar.'),
            Text(prontos.isEmpty
                ? 'Ninguém confirmou ainda. No celular: "Estou pronto para a C3".'
                : '${prontos.length} pronto(s):'),
            for (final p in prontos)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                leading: const Icon(Icons.how_to_reg, color: Colors.deepPurple),
                title: Text(p.nome),
              ),
            FilledButton(
              onPressed: prontos.isEmpty
                  ? null
                  : () => _iniciarC3(inv, prontos.length, tarefas.length),
              child: const Text('Iniciar C3'),
            ),
          ]);
        }

        if (c3 == StatusRodada.distribuindo ||
            c3 == StatusRodada.redistribuindo) {
          filhos.addAll([
            const Text('Gravando a distribuição. Se o app fechou ou a rede '
                'caiu no meio, retome:'),
            OutlinedButton(
              onPressed: () => _rodar(() async {
                await _c3.retomarDistribuicao(inv.id);
                _snack('Distribuição concluída.');
              }),
              child: const Text('Retomar distribuição'),
            ),
          ]);
        }

        if (c3 == StatusRodada.emAndamento || c3 == StatusRodada.encerrada) {
          final sinc = tarefas
              .where((l) => l.c3Status == StatusTarefaC3.sincronizada)
              .length;
          final porResp = <String, List<LinhaComparativo>>{
            for (final u
                in inv.contagens[Rodadas.c3]?.usuarios ?? const <String>[])
              u: <LinhaComparativo>[],
          };
          for (final t in tarefas) {
            porResp.putIfAbsent(t.c3ResponsavelUid ?? '?', () => []).add(t);
          }
          final info = {for (final p in prontos) p.uid: p};
          filhos.addAll([
            LinearProgressIndicator(
                value: tarefas.isEmpty ? 0 : sinc / tarefas.length),
            const SizedBox(height: 4),
            Text('$sinc de ${tarefas.length} item(ns) sincronizados',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            for (final e in porResp.entries)
              Builder(builder: (_) {
                final p = info[e.key];
                final nome = p?.nome ??
                    (e.value.isNotEmpty
                        ? (e.value.first.c3ResponsavelNome ?? e.key)
                        : e.key);
                final s = e.value
                    .where((l) => l.c3Status == StatusTarefaC3.sincronizada)
                    .length;
                return _pessoa(
                  finalizou: p?.finalizado ?? false,
                  nome: nome,
                  detalhe: '$s de ${e.value.length} item(ns) sincronizados',
                );
              }),
            if (c3 == StatusRodada.emAndamento) ...[
              const SizedBox(height: 4),
              FilledButton(
                onPressed: tarefas.isNotEmpty && sinc == tarefas.length
                    ? () => _encerrarC3(inv)
                    : null,
                child: Text(sinc == tarefas.length
                    ? 'Encerrar C3'
                    : 'Encerrar C3 · faltam ${tarefas.length - sinc}'),
              ),
              if (sinc < tarefas.length)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () => _redistribuir(inv),
                  child: const Text('Redistribuir pendentes (exceção)'),
                ),
            ],
          ]);
        }

        return _card(
            tipo != null ? 'C3 · ${tipo.rotulo}' : 'C3',
            StatusRodada.rotulo(c3),
            _corStatus(c3),
            filhos);
      },
    );
  }

  Future<void> _encerrarInventario(Inventario inv) async {
    if (!await _confirmar(
        'Encerrar o Inventário ${inv.numeroFormatado}?',
        'O resultado final fica fechado e um novo Inventário Completo pode '
            'ser aberto. O inventário não pode ser reaberto.',
        'Encerrar inventário')) {
      return;
    }
    await _rodar(() async {
      try {
        await InventarioService().encerrarInventarioCompleto(inv.id);
        _snack('Inventário ${inv.numeroFormatado} encerrado.');
      } on EncerramentoBloqueadoException catch (e) {
        _snack('Ainda não dá para encerrar: ${e.pendencias.join(' · ')}',
            erro: true);
      }
    });
  }

  Widget _cardFinal(Inventario inv) {
    final pronto = _etapaAtual(inv) == 3;
    final encerrado = inv.isFinalizado;
    return _card(
        'Resultado final',
        encerrado
            ? 'inventário encerrado'
            : pronto
                ? 'pronto'
                : 'aguardando',
        pronto || encerrado ? Colors.green : Colors.grey, [
      Text(pronto
          ? 'Itens fechados na C1 = C2 e os resolvidos na C3.'
          : 'Fica pronto quando a C3 for encerrada (ou não for necessária).'),
      if (pronto) ...[
        const SizedBox(height: 4),
        Row(children: [
          if (widget.onAbrirRelatorio != null) ...[
            Expanded(
              child: FilledButton(
                  onPressed: () => _abrirRelatorio(inv),
                  child: const Text('Ver relatório')),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: OutlinedButton.icon(
                onPressed: () => _exportar(inv),
                icon: const Icon(Icons.file_download, size: 18),
                label: const Text('.xlsx')),
          ),
        ]),
        if (inv.isAtivo) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            onPressed: () => _encerrarInventario(inv),
            icon: const Icon(Icons.lock_outline),
            label: const Text('Encerrar inventário'),
          ),
        ],
      ],
    ]);
  }
}
