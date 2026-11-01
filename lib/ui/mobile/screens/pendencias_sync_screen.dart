// lib/ui/mobile/screens/pendencias_sync_screen.dart
//
// Pacote 1 (fila offline): painel de diagnóstico do coletor.
// Lê SÓ o Hive/SharedPreferences do aparelho — abre e funciona sem internet.
// - cada lançamento não sincronizado, com produto, código, lote, área,
//   quantidades, data/hora, id local, situação, tentativas e motivo da falha;
// - exclusões antigas pendentes (registro já fora do aparelho);
// - histórico das tentativas de cada um;
// - REENVIO (falhas de envio) individual, dos selecionados ou de todos, com o
//   resultado de cada;
// - RECUPERAÇÃO (recusados em definitivo): só garante a cópia na
//   Recuperação do analista; nunca reenvia à coleção oficial (rev1);
// - exportação em CSV (salvar no aparelho).
// rev1: atualiza também quando só o estado de sincronização (sync_meta) muda.

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lego/data/local/registro_sync.dart';
import 'package:lego/data/repositories/lancamentos_repository.dart';
import 'package:lego/models/inventario.dart' show Rodadas;
import 'package:lego/services/mobile_sync_service.dart';
import 'package:lego/services/sincronizacao/motor_sincronizacao.dart';
import 'package:lego/services/sincronizacao/observador_pendencias.dart';
import 'package:lego/services/sincronizacao/pendencias_sync.dart';
import 'package:lego/services/sincronizacao/status_sync_aparelho.dart';
import 'package:lego/services/sync_service.dart';

bool _rejeitado(SituacaoPendencia s) =>
    s == SituacaoPendencia.rejeitado ||
    s == SituacaoPendencia.exclusaoRejeitada;

class PendenciasSyncScreen extends StatefulWidget {
  final String uid;
  const PendenciasSyncScreen({super.key, required this.uid});

  @override
  State<PendenciasSyncScreen> createState() => _PendenciasSyncScreenState();
}

class _PendenciasSyncScreenState extends State<PendenciasSyncScreen> {
  late final LancamentosRepository _repo =
      LancamentosRepository(uid: widget.uid);
  late final RegistroSync _reg = RegistroSync(widget.uid);
  StreamSubscription<QuadroPendencias>? _sub;

  QuadroPendencias _quadro = const QuadroPendencias([]);
  final Set<String> _sel = {};
  final Map<String, ResultadoItem> _ultimoResultado = {};
  bool _soProblemas = false;
  bool _carregando = true;
  bool _enviando = false;
  String? _erroLeitura;

  @override
  void initState() {
    super.initState();
    _sub = observarPendencias(widget.uid, _repo, _reg).listen((q) {
      if (!mounted) return;
      setState(() {
        _quadro = q;
        final ids = {
          for (final p in q.lancamentos) p.lanc.idLocal,
          for (final x in q.exclusoesLegadas) x.chave,
        };
        _sel.removeWhere((id) => !ids.contains(id));
        _carregando = false;
        _erroLeitura = null;
      });
    }, onError: (Object e) {
      // rev3: falha de leitura não deixa a tela "carregando" para sempre.
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erroLeitura = '$e';
      });
    });
    unawaited(StatusSyncAparelho.publicar(widget.uid, forcar: true));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _recarregar() async {
    final q = await lerQuadroPendencias(widget.uid, _repo, _reg);
    if (mounted) setState(() => _quadro = q);
  }

  List<Pendencia> get _visiveis => _soProblemas
      ? _quadro.lancamentos
          .where((p) => p.situacao != SituacaoPendencia.pendente)
          .toList()
      : _quadro.lancamentos;

  /// Ids de tudo que admite REENVIO (exclui recusados em definitivo).
  List<String> get _reenviaveis => [
        for (final p in _quadro.lancamentos)
          if (!_rejeitado(p.situacao)) p.lanc.idLocal,
        for (final x in _quadro.exclusoesLegadas)
          if (!_rejeitado(x.situacao)) x.chave,
      ];

  List<String> get _rejeitados => [
        for (final p in _quadro.lancamentos)
          if (_rejeitado(p.situacao)) p.lanc.idLocal,
        for (final x in _quadro.exclusoesLegadas)
          if (_rejeitado(x.situacao)) x.chave,
      ];

  String _escopo(Pendencia p) {
    final inv = p.lanc.inventarioId ?? '';
    if (inv.isEmpty) return 'Contagem Simples';
    final s = MobileSyncService().sessaoAtual;
    final rod = Rodadas.rotulo(p.lanc.contagemId ?? '');
    final nome = s?.inventarioId == inv
        ? 'Inventário ${s!.numeroFormatado}'
        : 'Inventário ${inv.length > 6 ? inv.substring(0, 6) : inv}…';
    return '$nome · $rod';
  }

  Color _cor(SituacaoPendencia s) => switch (s) {
        SituacaoPendencia.pendente => Colors.blueGrey,
        SituacaoPendencia.aguardandoReenvio => Colors.orange.shade800,
        SituacaoPendencia.erroReenvioManual => Colors.red.shade700,
        SituacaoPendencia.erroSemMotivo => Colors.red.shade700,
        SituacaoPendencia.rejeitado => Colors.purple.shade700,
        SituacaoPendencia.exclusaoRejeitada => Colors.purple.shade700,
      };

  String _num(double v) =>
      (v == v.roundToDouble() ? v.toInt().toString() : v.toString())
          .replaceAll('.', ',');

  String _quantidades(Pendencia p) {
    final l = p.lanc;
    final partes = <String>[
      if (l.quantidade != 0) 'qtd ${_num(l.quantidade)}',
      if (l.cheio != 0) '${_num(l.cheio)} cheio(s)',
      if (l.vazio != 0) '${_num(l.vazio)} vazio(s)',
    ];
    return partes.isEmpty ? 'sem quantidade' : partes.join(' · ');
  }

  Future<void> _executar(
      String titulo, Future<List<ResultadoItem>> Function() acao) async {
    setState(() => _enviando = true);
    try {
      final r = await acao();
      if (!mounted) return;
      for (final x in r) {
        _ultimoResultado[x.idLocal] = x;
      }
      final ok = r.where((x) => x.resultado.sucesso).length;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titulo),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$ok de ${r.length} concluído(s).'),
                if (r.any((x) =>
                    x.resultado == ResultadoEnvio.rejeitadoNaoReenviado))
                  const Text(
                      'Recusados pelo servidor não são reenviados: use '
                      '"Enviar à Recuperação".'),
                const Divider(),
                for (final x in r)
                  Text(
                    '${_rotuloCurto(x.idLocal)}: ${x.resultado.rotulo}'
                    '${x.codigo == null ? '' : ' (${x.codigo})'}',
                    style: TextStyle(
                        fontSize: 12,
                        color: x.resultado.sucesso
                            ? Colors.green.shade800
                            : null),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      _snack('Falha: $e', erro: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
      await _recarregar();
    }
  }

  Future<void> _reenviar(List<String>? ids) => _executar('Resultado do reenvio',
      () => SyncService.reenviar(widget.uid, ids ?? _reenviaveis));

  Future<void> _recuperar(List<String>? ids) =>
      _executar('Resultado da Recuperação',
          () => SyncService.recuperar(widget.uid, ids ?? _rejeitados));

  String _rotuloCurto(String id) {
    if (id.startsWith('del:')) return 'Exclusão antiga';
    for (final p in _quadro.lancamentos) {
      if (p.lanc.idLocal == id) {
        return '${p.lanc.codigo} ${p.lanc.lote ?? ''}'.trim();
      }
    }
    return id.length > 8 ? id.substring(0, 8) : id;
  }

  Future<void> _exportar() async {
    final lista = _visiveis;
    final ex = _quadro.exclusoesLegadas;
    if (lista.isEmpty && ex.isEmpty) {
      _snack('Nada a exportar.');
      return;
    }
    final agora = DateTime.now();
    String dd(int v) => v.toString().padLeft(2, '0');
    final nome = 'LEGO_pendencias_${agora.year}${dd(agora.month)}${dd(agora.day)}'
        '_${dd(agora.hour)}${dd(agora.minute)}.csv';
    final csv = pendenciasCsv(lista, ex);
    final bytes = Uint8List.fromList(utf8.encode(csv));
    try {
      final caminho = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar pendências',
        fileName: nome,
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: bytes,
      );
      if (caminho != null) _snack('Arquivo salvo: $caminho');
    } catch (e) {
      // Sem seletor de arquivos: copia o conteúdo.
      await Clipboard.setData(ClipboardData(text: csv));
      _snack('Não foi possível salvar ($e). Conteúdo copiado.', erro: true);
    }
  }

  Future<void> _historico(String chave, String titulo) async {
    final h = await _reg.historico(idLocal: chave);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
              SelectableText('Id: $chave', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              if (h.isEmpty) const Text('Nenhuma tentativa registrada ainda.'),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in h)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          e.resultado == 'ok'
                              ? Icons.check_circle
                              : Icons.error_outline,
                          color: e.resultado == 'ok' ? Colors.green : Colors.red,
                        ),
                        title: Text('${dataBr(e.em)} ${horaBr(e.em)} · '
                            '${e.acao} · ${e.resultado}'
                            '${e.manual ? ' (manual)' : ''}'),
                        subtitle: e.codigo == null && e.mensagem == null
                            ? null
                            : Text('${e.codigo ?? ''} ${e.mensagem ?? ''}'
                                .trim()),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _snack(String m, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: erro ? Colors.red : null));
  }

  Widget _contador(String rotulo, int n, Color cor) => Chip(
        visualDensity: VisualDensity.compact,
        label: Text('$rotulo: $n'),
        backgroundColor: n > 0 ? cor.withValues(alpha: 0.15) : null,
        labelStyle: TextStyle(
            color: n > 0 ? cor : Colors.grey.shade700,
            fontWeight: n > 0 ? FontWeight.bold : FontWeight.normal),
      );

  List<String> _linhasEstado(EstadoSync? e) {
    if (e == null) return const [];
    final prox = e.proximaTentativa;
    final ult = e.ultimaTentativa;
    final rec = e.recuperacaoEnviadaEm;
    final recErro = e.recuperacaoErro;
    return [
      if (e.codigo != null)
        'Motivo: ${e.codigo}${e.mensagem == null ? '' : ' — ${e.mensagem}'}',
      if (e.tentativas > 0)
        '${e.tentativas} tentativa(s)'
            '${ult == null ? '' : ' · última às ${horaBr(ult)}'}'
            '${prox == null ? '' : ' · próxima às ${horaBr(prox)}'}',
      if (rec != null) 'Cópia na Recuperação (${dataBr(rec)} ${horaBr(rec)})',
      if (recErro != null) 'Recuperação: $recErro',
    ];
  }

  Widget _cartao({
    required String chave,
    required String titulo,
    required SituacaoPendencia situacao,
    required List<String> linhas,
  }) {
    final r = _ultimoResultado[chave];
    final rejeitado = _rejeitado(situacao);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onLongPress: () => _historico(chave, titulo),
        onTap: () => setState(
            () => _sel.contains(chave) ? _sel.remove(chave) : _sel.add(chave)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _sel.contains(chave),
                onChanged: _enviando
                    ? null
                    : (v) => setState(
                        () => v == true ? _sel.add(chave) : _sel.remove(chave)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(situacao.rotulo,
                        style: TextStyle(
                            color: _cor(situacao),
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    for (final t in linhas)
                      Text(t, style: const TextStyle(fontSize: 12)),
                    if (r != null)
                      Text(
                        'Última ação: ${r.resultado.rotulo}'
                        '${r.codigo == null ? '' : ' (${r.codigo})'}',
                        style: TextStyle(
                            fontSize: 12,
                            color: r.resultado.sucesso
                                ? Colors.green.shade800
                                : Colors.red.shade700),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Histórico de tentativas',
                icon: const Icon(Icons.history),
                onPressed: () => _historico(chave, titulo),
              ),
              rejeitado
                  ? IconButton(
                      tooltip: 'Enviar à Recuperação',
                      icon: const Icon(Icons.inventory_2_outlined),
                      onPressed: _enviando ? null : () => _recuperar([chave]),
                    )
                  : IconButton(
                      tooltip: 'Reenviar este',
                      icon: const Icon(Icons.send),
                      onPressed: _enviando ? null : () => _reenviar([chave]),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(Pendencia p) {
    final l = p.lanc;
    return _cartao(
      chave: l.idLocal,
      titulo: '${l.codigo} · ${l.descricao}',
      situacao: p.situacao,
      linhas: [
        [
          if ((l.lote ?? '').isNotEmpty) 'Lote ${l.lote}',
          if ((l.tag ?? '').isNotEmpty) 'TAG ${l.tag}',
          _quantidades(p),
        ].join(' · '),
        '${l.localizacaoNome ?? l.localizacaoId ?? 'sem área'} · '
            '${dataBr(l.createdAtLocal)} ${horaBr(l.createdAtLocal)}',
        _escopo(p),
        if (p.exclusao) 'Exclusão aguardando o servidor',
        if (p.situacao == SituacaoPendencia.erroSemMotivo &&
            (l.errorCode ?? '').isNotEmpty)
          'Erro antigo: ${l.errorCode}',
        ..._linhasEstado(p.estado),
        'Id local: ${l.idLocal}',
      ],
    );
  }

  Widget _itemExclusao(ExclusaoLegada x) => _cartao(
        chave: x.chave,
        titulo: 'Exclusão antiga pendente',
        situacao: x.situacao,
        linhas: [
          'O lançamento já saiu do aparelho; falta apagar no servidor.',
          'Documento: ${x.docId}',
          ..._linhasEstado(x.estado),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final c = _quadro.contagem;
    final vis = _visiveis;
    final ex = _quadro.exclusoesLegadas;
    final reenv = _reenviaveis.length;
    final rej = _rejeitados.length;
    final selReenv = _sel.where((id) => _reenviaveis.contains(id)).toList();
    final selRej = _sel.where((id) => _rejeitados.contains(id)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pendências de envio'),
        actions: [
          IconButton(
            tooltip: 'Exportar CSV',
            icon: const Icon(Icons.file_download),
            onPressed: _enviando ? null : _exportar,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_enviando) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              _contador('Pendentes', c.pendentes, Colors.blueGrey),
              _contador('Aguardando reenvio', c.aguardandoReenvio,
                  Colors.orange.shade800),
              _contador('Erro', c.erroManual, Colors.red.shade700),
              _contador('Rejeitados', c.rejeitados, Colors.purple.shade700),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              const Expanded(
                child: Text(
                  'Dados deste aparelho (funciona sem internet). '
                  'Toque para selecionar; segure para ver o histórico.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              FilterChip(
                label: const Text('Só com problema'),
                selected: _soProblemas,
                onSelected: (v) => setState(() => _soProblemas = v),
              ),
            ]),
          ),
          const Divider(height: 8),
          if (_erroLeitura != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('Falha ao ler os dados do aparelho: $_erroLeitura',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : vis.isEmpty && ex.isEmpty
                    ? const Center(
                        child: Text('Nenhuma pendência. Tudo sincronizado.'))
                    : ListView(
                        children: [
                          for (final p in vis) _item(p),
                          for (final x in ex) _itemExclusao(x),
                        ],
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _quadro.vazio
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    if (selReenv.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _enviando ? null : () => _reenviar(selReenv),
                        icon: const Icon(Icons.send),
                        label: Text('Reenviar selecionados (${selReenv.length})'),
                      ),
                    if (selRej.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _enviando ? null : () => _recuperar(selRej),
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: Text('Recuperação dos selecionados '
                            '(${selRej.length})'),
                      ),
                    if (rej > 0)
                      OutlinedButton.icon(
                        onPressed: _enviando ? null : () => _recuperar(null),
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: Text('Enviar rejeitados à Recuperação ($rej)'),
                      ),
                    FilledButton.icon(
                      onPressed: _enviando || reenv == 0
                          ? null
                          : () => _reenviar(null),
                      icon: const Icon(Icons.sync),
                      label: Text('Reenviar todos ($reenv)'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
