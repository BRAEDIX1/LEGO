// lib/services/sincronizacao/pendencias_sync.dart
//
// Pacote 1 (fila offline): visão das pendências de envio, montada só com o
// que está no aparelho (Hive). Função PURA — usada pelo painel do coletor,
// pela exportação e pelo resumo que o aparelho transmite ao Desktop.

import 'package:lego/data/local/lanc_local.dart';
import 'package:lego/data/local/registro_sync.dart';
import 'package:lego/models/sessao_contagem.dart' show kDeletePending;
import 'package:lego/services/sincronizacao/falha_sync.dart';

enum SituacaoPendencia {
  /// Ainda não tentou ou tentou sem falha registrada.
  pendente,
  /// Falhou por rede ou motivo passageiro; o aparelho tenta de novo sozinho.
  aguardandoReenvio,
  /// Passageiro que esgotou as tentativas automáticas: reenvio manual.
  erroReenvioManual,
  /// O servidor recusou (ex.: rodada encerrada). Fica no aparelho.
  rejeitado,
  /// Exclusão que o servidor recusou (o registro remoto continua lá).
  exclusaoRejeitada,
  /// Erro antigo, de antes deste controle (sem motivo registrado).
  erroSemMotivo,
}

extension SituacaoPendenciaRotulo on SituacaoPendencia {
  String get rotulo => switch (this) {
        SituacaoPendencia.pendente => 'Pendente',
        SituacaoPendencia.aguardandoReenvio => 'Aguardando reenvio',
        SituacaoPendencia.erroReenvioManual => 'Erro: reenviar manualmente',
        SituacaoPendencia.rejeitado => 'Rejeitado pelo servidor',
        SituacaoPendencia.exclusaoRejeitada => 'Exclusão rejeitada',
        SituacaoPendencia.erroSemMotivo => 'Erro (motivo não registrado)',
      };
}

/// Chave do escopo do lançamento: `simples` ou `<inventarioId>__<rodada>`.
String escopoDe(LancLocal l) {
  final inv = l.inventarioId ?? '';
  return inv.isEmpty ? 'simples' : '${inv}__${l.contagemId ?? ''}';
}

class Pendencia {
  final LancLocal lanc;
  final EstadoSync? estado;
  final SituacaoPendencia situacao;
  const Pendencia(this.lanc, this.estado, this.situacao);

  bool get exclusao => lanc.errorCode == kDeletePending;
  String get escopo => escopoDe(lanc);
}

/// Null = sincronizado (não é pendência).
SituacaoPendencia? situacaoDe(LancLocal l, EstadoSync? e) {
  if (l.status == LancStatus.synced) return null;
  final exclusao = l.errorCode == kDeletePending;
  if (e?.definitivo == true) {
    return exclusao
        ? SituacaoPendencia.exclusaoRejeitada
        : SituacaoPendencia.rejeitado;
  }
  if (l.status == LancStatus.error) {
    if (e == null || e.tipo == null) return SituacaoPendencia.erroSemMotivo;
    return SituacaoPendencia.erroReenvioManual;
  }
  // pending
  if (e != null &&
      (e.tipo == TipoFalhaSync.rede || e.tipo == TipoFalhaSync.transitorio)) {
    return e.esgotado
        ? SituacaoPendencia.erroReenvioManual
        : SituacaoPendencia.aguardandoReenvio;
  }
  return SituacaoPendencia.pendente;
}

/// Todas as pendências do aparelho, mais antigas primeiro.
List<Pendencia> montarPendencias(
    Iterable<LancLocal> lancs, Map<String, EstadoSync> estados) {
  final out = <Pendencia>[];
  for (final l in lancs) {
    final e = estados[l.idLocal];
    final s = situacaoDe(l, e);
    if (s != null) out.add(Pendencia(l, e, s));
  }
  out.sort((a, b) => a.lanc.createdAtLocal.compareTo(b.lanc.createdAtLocal));
  return out;
}

/// rev2: pendência sem escopo identificado (ex.: exclusão antiga cujo
/// documento oficial não pôde ser lido). O Desktop a trata como "não
/// classificada" — bloqueia o encerramento até decisão do analista.
const String kEscopoNaoClassificado = 'nao_classificado';

/// Exclusão remota pendente do mecanismo ANTIGO (SharedPreferences
/// `delete_pending`): o lançamento já saiu do Hive, só resta o id do
/// documento no servidor. Antes do Pacote 1 nada processava essa lista.
class ExclusaoLegada {
  final String docId;
  final EstadoSync? estado;
  const ExclusaoLegada(this.docId, this.estado);

  /// Chave do estado em `sync_meta_<uid>`.
  static String chaveDe(String docId) => 'del:$docId';
  String get chave => chaveDe(docId);

  /// rev2: escopo identificado (lido do documento oficial quando possível)
  /// ou [kEscopoNaoClassificado]. Nunca presume a rodada atual.
  String get escopo => estado?.escopo ?? kEscopoNaoClassificado;

  SituacaoPendencia get situacao {
    final e = estado;
    if (e?.definitivo == true) return SituacaoPendencia.exclusaoRejeitada;
    if (e?.tipo != null) {
      return e!.esgotado
          ? SituacaoPendencia.erroReenvioManual
          : SituacaoPendencia.aguardandoReenvio;
    }
    return SituacaoPendencia.pendente;
  }
}

/// Tudo o que está pendente no aparelho para um usuário.
class QuadroPendencias {
  final List<Pendencia> lancamentos;
  final List<ExclusaoLegada> exclusoesLegadas;
  /// rev2: escopos que o aparelho VERIFICOU (tem lançamentos dele, a sessão
  /// ativa, ou exclusões classificadas nele). Escopo verificado sem
  /// pendência = "zero confirmado"; escopo fora desta lista = sem
  /// informação.
  final Set<String> escoposVerificados;
  const QuadroPendencias(this.lancamentos,
      [this.exclusoesLegadas = const [], this.escoposVerificados = const {}]);

  bool get vazio => lancamentos.isEmpty && exclusoesLegadas.isEmpty;
  int get total => lancamentos.length + exclusoesLegadas.length;

  ContagemPendencias get contagem => ContagemPendencias.deSituacoes([
        for (final p in lancamentos) p.situacao,
        for (final x in exclusoesLegadas) x.situacao,
      ]);

  /// Contagem por escopo, incluindo os verificados com zero (rev2) e as
  /// exclusões antigas no escopo identificado (ou em `nao_classificado`).
  Map<String, ContagemPendencias> get porEscopo {
    final situacoes = <String, List<SituacaoPendencia>>{
      for (final e in escoposVerificados) e: [],
    };
    for (final p in lancamentos) {
      situacoes.putIfAbsent(p.escopo, () => []).add(p.situacao);
    }
    for (final x in exclusoesLegadas) {
      situacoes.putIfAbsent(x.escopo, () => []).add(x.situacao);
    }
    return {
      for (final e in situacoes.entries)
        e.key: ContagemPendencias.deSituacoes(e.value),
    };
  }

  /// Escopos com informação explícita (verificados + os que têm pendência).
  Set<String> get escoposInformados => porEscopo.keys.toSet();
}

/// Exclusões antigas pendentes deste usuário ([docIds] = lista inteira do
/// aparelho; só as `<uid>_...` são dele).
List<ExclusaoLegada> montarExclusoesLegadas(String uid,
        Iterable<String> docIds, Map<String, EstadoSync> estados) =>
    [
      for (final d in docIds.toSet())
        if (d.startsWith('${uid}_'))
          ExclusaoLegada(d, estados[ExclusaoLegada.chaveDe(d)]),
    ]..sort((a, b) => a.docId.compareTo(b.docId));

class ContagemPendencias {
  final int pendentes;
  final int aguardandoReenvio;
  final int erroManual;
  final int rejeitados;
  const ContagemPendencias({
    this.pendentes = 0,
    this.aguardandoReenvio = 0,
    this.erroManual = 0,
    this.rejeitados = 0,
  });

  int get total => pendentes + aguardandoReenvio + erroManual + rejeitados;

  static ContagemPendencias de(Iterable<Pendencia> ps) =>
      deSituacoes(ps.map((x) => x.situacao));

  static ContagemPendencias deSituacoes(Iterable<SituacaoPendencia> ss) {
    var p = 0, a = 0, m = 0, r = 0;
    for (final x in ss) {
      switch (x) {
        case SituacaoPendencia.pendente:
          p++;
        case SituacaoPendencia.aguardandoReenvio:
          a++;
        case SituacaoPendencia.erroReenvioManual:
        case SituacaoPendencia.erroSemMotivo:
          m++;
        case SituacaoPendencia.rejeitado:
        case SituacaoPendencia.exclusaoRejeitada:
          r++;
      }
    }
    return ContagemPendencias(
        pendentes: p, aguardandoReenvio: a, erroManual: m, rejeitados: r);
  }

  Map<String, dynamic> toMap() => {
        'pendentes': pendentes,
        'aguardando_reenvio': aguardandoReenvio,
        'erro_manual': erroManual,
        'rejeitados': rejeitados,
        'total': total,
      };

  static ContagemPendencias deMapa(Map? m) => ContagemPendencias(
        pendentes: (m?['pendentes'] as num?)?.toInt() ?? 0,
        aguardandoReenvio: (m?['aguardando_reenvio'] as num?)?.toInt() ?? 0,
        erroManual: (m?['erro_manual'] as num?)?.toInt() ?? 0,
        rejeitados: (m?['rejeitados'] as num?)?.toInt() ?? 0,
      );
}

/// Contagem por escopo (`simples`, `<inv>__<rodada>`).
Map<String, ContagemPendencias> contarPorEscopo(Iterable<Pendencia> ps) {
  final g = <String, List<Pendencia>>{};
  for (final p in ps) {
    g.putIfAbsent(p.escopo, () => []).add(p);
  }
  return {for (final e in g.entries) e.key: ContagemPendencias.de(e.value)};
}

String _dd(int v) => v.toString().padLeft(2, '0');
String dataBr(DateTime d) => '${_dd(d.day)}/${_dd(d.month)}/${d.year}';
String horaBr(DateTime d) =>
    '${_dd(d.hour)}:${_dd(d.minute)}:${_dd(d.second)}';

String _num(double v) =>
    (v == v.roundToDouble() ? v.toInt().toString() : v.toString())
        .replaceAll('.', ',');

/// CSV (separador `;`, com BOM para o Excel abrir em UTF-8).
String pendenciasCsv(List<Pendencia> ps,
    [List<ExclusaoLegada> exclusoes = const []]) {
  String c(Object? v) {
    final s = (v ?? '').toString().replaceAll('"', '""');
    return s.contains(';') || s.contains('\n') || s.contains('"')
        ? '"$s"'
        : s;
  }

  final linhas = <String>[
    [
      'id_local', 'situacao', 'escopo', 'inventario_id', 'rodada', 'codigo',
      'descricao', 'lote', 'tag', 'area', 'quantidade', 'cheio', 'vazio',
      'data', 'hora', 'registro', 'tentativas', 'ultima_tentativa',
      'erro_codigo', 'erro_mensagem', 'recuperacao_enviada_em',
    ].join(';'),
  ];
  for (final p in ps) {
    final l = p.lanc;
    final e = p.estado;
    final ult = e?.ultimaTentativa;
    final rec = e?.recuperacaoEnviadaEm;
    linhas.add([
      l.idLocal,
      p.situacao.rotulo,
      p.escopo,
      l.inventarioId ?? '',
      l.contagemId ?? '',
      l.codigo,
      l.descricao,
      l.lote ?? '',
      l.tag ?? '',
      l.localizacaoNome ?? l.localizacaoId ?? '',
      _num(l.quantidade),
      _num(l.cheio),
      _num(l.vazio),
      dataBr(l.createdAtLocal),
      horaBr(l.createdAtLocal),
      l.registro == TipoRegistro.manual ? 'manual' : 'automatico',
      e?.tentativas ?? 0,
      ult == null ? '' : '${dataBr(ult)} ${horaBr(ult)}',
      e?.codigo ?? (p.situacao == SituacaoPendencia.erroSemMotivo
          ? (l.errorCode ?? '')
          : ''),
      e?.mensagem ?? '',
      rec == null ? '' : '${dataBr(rec)} ${horaBr(rec)}',
    ].map(c).join(';'));
  }
  for (final x in exclusoes) {
    final e = x.estado;
    final ult = e?.ultimaTentativa;
    final rec = e?.recuperacaoEnviadaEm;
    linhas.add([
      x.docId,
      '${x.situacao.rotulo} (exclusão antiga)',
      x.escopo,
      '', '', '', 'Exclusão remota pendente (registro já fora do aparelho)',
      '', '', '', '', '', '', '', '', '',
      e?.tentativas ?? 0,
      ult == null ? '' : '${dataBr(ult)} ${horaBr(ult)}',
      e?.codigo ?? '',
      e?.mensagem ?? '',
      rec == null ? '' : '${dataBr(rec)} ${horaBr(rec)}',
    ].map(c).join(';'));
  }
  return '\uFEFF${linhas.join('\r\n')}\r\n';
}
