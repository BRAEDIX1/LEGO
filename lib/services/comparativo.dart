// lib/services/comparativo.dart
//
// Entrega 1 (teste em campo): comparativo C1 × C2. Funções PURAS (sem
// Firebase), testáveis.
//
// Chave do item (D10, decisão provisória para teste):
//   - lançamento COM tag  → o cilindro (`TAG:<tag>`). Lançamentos repetidos
//     da mesma tag na mesma rodada contam como UM cilindro (duas pessoas
//     leram o mesmo); a repetição fica registrada em `ocorrencias`.
//   - lançamento SEM tag  → Material + Lote (`MAT:<codigo>|<lote>`), somando
//     quantidade, cheio e vazio de todos os lançamentos da rodada.
//
// Resultado de cada linha:
//   - igual nas duas rodadas            → encerrada (consenso)
//   - só em C1, só em C2 ou diferente   → em_analise (vai para a C3)

import 'dart:convert';

enum TipoChave { tag, material }

enum ResultadoLinha { encerrada, emAnalise }

/// conflito (A3): a mesma TAG foi lida como CHEIO e como VAZIO na mesma rodada.
enum MotivoAnalise { soC1, soC2, divergente, conflito }

/// Um lançamento já reduzido ao que o comparativo usa.
class LancResumo {
  final String? tag;
  final String codigo;
  final String? lote;
  final String descricao;
  final double quantidade;
  final double cheio;
  final double vazio;
  final String? quem;

  const LancResumo({
    this.tag,
    required this.codigo,
    this.lote,
    this.descricao = '',
    this.quantidade = 0,
    this.cheio = 0,
    this.vazio = 0,
    this.quem,
  });

  /// Lê um documento de `lancamentos`. Devolve null se não houver nem tag
  /// nem código (lançamento sem identificação não entra no comparativo).
  static LancResumo? deMapa(Map<String, dynamic> d) {
    String? txt(Object? v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    double num_(Object? v) =>
        v is num ? v.toDouble() : (double.tryParse('$v') ?? 0.0);

    final tag = txt(d['tag']);
    final codigo = txt(d['codigo']);
    if (tag == null && codigo == null) return null;
    return LancResumo(
      tag: tag,
      codigo: codigo ?? '',
      lote: txt(d['lote']),
      descricao: txt(d['descricao']) ?? '',
      quantidade: num_(d['quantidade']),
      cheio: num_(d['cheio']),
      vazio: num_(d['vazio']),
      quem: txt(d['nickname']) ?? txt(d['uid']),
    );
  }

  TipoChave get tipo => tag != null ? TipoChave.tag : TipoChave.material;

  String get chave =>
      tag != null ? 'TAG:$tag' : 'MAT:$codigo|${lote ?? ''}';
}

/// Totais de um item numa rodada.
class TotaisRodada {
  final double quantidade;
  final double cheio;
  final double vazio;
  final int ocorrencias;
  final Set<String> quem;
  /// A3: leituras contraditórias da mesma TAG (cheio e vazio).
  final bool conflito;
  /// C3: tarefa concluída como "NÃO encontrado".
  final bool naoEncontrado;
  /// B63: códigos de material vistos para este item na rodada.
  final Set<String> codigos;

  const TotaisRodada({
    this.quantidade = 0,
    this.cheio = 0,
    this.vazio = 0,
    this.ocorrencias = 0,
    this.quem = const <String>{},
    this.conflito = false,
    this.naoEncontrado = false,
    this.codigos = const <String>{},
  });

  Map<String, dynamic> toMap() => {
        'quantidade': quantidade,
        'cheio': cheio,
        'vazio': vazio,
        'ocorrencias': ocorrencias,
        'quem': quem.toList()..sort(),
        if (conflito) 'conflito': true,
        if (naoEncontrado) 'nao_encontrado': true,
        if (codigos.isNotEmpty) 'codigos': codigos.toList()..sort(),
      };

  static TotaisRodada? deMapa(Object? m) {
    if (m is! Map) return null;
    double n(Object? v) => v is num ? v.toDouble() : 0.0;
    return TotaisRodada(
      quantidade: n(m['quantidade']),
      cheio: n(m['cheio']),
      vazio: n(m['vazio']),
      ocorrencias: (m['ocorrencias'] as num?)?.toInt() ?? 0,
      quem: (m['quem'] is List)
          ? (m['quem'] as List).map((e) => e.toString()).toSet()
          : const <String>{},
      conflito: m['conflito'] == true,
      naoEncontrado: m['nao_encontrado'] == true,
      codigos: (m['codigos'] is List)
          ? (m['codigos'] as List).map((e) => e.toString()).toSet()
          : const <String>{},
    );
  }

  static const double _eps = 0.0001;

  bool mesmoValor(TotaisRodada o) =>
      (quantidade - o.quantidade).abs() < _eps &&
      (cheio - o.cheio).abs() < _eps &&
      (vazio - o.vazio).abs() < _eps;
}

/// Uma linha do comparativo.
class LinhaComparativo {
  final String chave;
  final TipoChave tipo;
  final String? tag;
  final String codigo;
  final String? lote;
  final String descricao;
  final TotaisRodada? c1;
  final TotaisRodada? c2;
  final ResultadoLinha resultado;
  final MotivoAnalise? motivo;

  // Entrega 2/3: recontagem na C3 (só linhas em análise).
  final TotaisRodada? c3;
  final String? c3Quem;
  final DateTime? c3Em;
  // Entrega 3: tarefa distribuída.
  final String? c3ResponsavelUid;
  final String? c3ResponsavelNome;
  final int? c3Versao;
  final String? c3Status; // StatusTarefaC3

  const LinhaComparativo({
    required this.chave,
    required this.tipo,
    this.tag,
    required this.codigo,
    this.lote,
    this.descricao = '',
    this.c1,
    this.c2,
    required this.resultado,
    this.motivo,
    this.c3,
    this.c3Quem,
    this.c3Em,
    this.c3ResponsavelUid,
    this.c3ResponsavelNome,
    this.c3Versao,
    this.c3Status,
  });

  bool get emAnalise => resultado == ResultadoLinha.emAnalise;

  /// Linha em análise que já foi recontada na C3.
  bool get contadaNaC3 => emAnalise && c3 != null;

  /// A1: a divergência ORIGINAL (C1×C2) fica em [emAnalise]/[motivo];
  /// a pendência ATUAL é esta: divergiu e ainda não tem C3.
  bool get pendenteAtual => emAnalise && c3 == null;

  /// A1: linha com valor final definido (consenso ou C3).
  bool get resolvida => !pendenteAtual;

  /// Valor final do item: consenso C1=C2 (encerrada) ou o valor da C3.
  /// Null enquanto a linha em análise não foi recontada.
  TotaisRodada? get valorFinal => emAnalise ? c3 : (c1 ?? c2);

  /// Origem do valor final, para o relatório.
  String get origemFinal => !emAnalise
      ? 'C1 = C2'
      : (c3 == null
          ? 'pendente na C3'
          : (c3!.naoEncontrado ? 'C3: não encontrado' : 'C3'));

  /// ID seguro para documento do Firestore (a chave pode ter '/').
  String get docId => idDocumento(chave);

  Map<String, dynamic> toMap() => {
        'chave': chave,
        'tipo': tipo.name,
        'tag': tag,
        'codigo': codigo,
        'lote': lote,
        'descricao': descricao,
        'c1': c1?.toMap(),
        'c2': c2?.toMap(),
        'resultado':
            resultado == ResultadoLinha.encerrada ? 'encerrada' : 'em_analise',
        'motivo': motivo?.name,
      };

  static LinhaComparativo deMapa(Map<String, dynamic> m) {
    final motivoTxt = m['motivo'] as String?;
    return LinhaComparativo(
      chave: (m['chave'] ?? '').toString(),
      tipo: m['tipo'] == 'tag' ? TipoChave.tag : TipoChave.material,
      tag: m['tag'] as String?,
      codigo: (m['codigo'] ?? '').toString(),
      lote: m['lote'] as String?,
      descricao: (m['descricao'] ?? '').toString(),
      c1: TotaisRodada.deMapa(m['c1']),
      c2: TotaisRodada.deMapa(m['c2']),
      resultado: m['resultado'] == 'encerrada'
          ? ResultadoLinha.encerrada
          : ResultadoLinha.emAnalise,
      motivo: motivoTxt == null
          ? null
          : MotivoAnalise.values.firstWhere((e) => e.name == motivoTxt,
              orElse: () => MotivoAnalise.divergente),
      c3: TotaisRodada.deMapa(m['c3']),
      c3Quem: m['c3_quem'] as String?,
      c3Em: _data(m['c3_em']),
      c3ResponsavelUid: m['c3_responsavel_uid'] as String?,
      c3ResponsavelNome: m['c3_responsavel_nome'] as String?,
      c3Versao: (m['c3_versao'] as num?)?.toInt(),
      c3Status: m['c3_status'] as String?,
    );
  }

  static DateTime? _data(Object? v) {
    if (v is DateTime) return v;
    try {
      // Timestamp do Firestore sem importar o pacote aqui.
      final dynamic d = v;
      final r = d?.toDate();
      return r is DateTime ? r : null;
    } catch (_) {
      return null;
    }
  }
}

/// base64url sem '=' da chave em UTF-8.
String idDocumento(String chave) =>
    base64Url.encode(utf8.encode(chave)).replaceAll('=', '');

/// Agrupa os lançamentos de UMA rodada por chave.
Map<String, TotaisRodada> totalizarRodada(Iterable<LancResumo> lancs) {
  final acc = <String, _Acumulador>{};
  for (final l in lancs) {
    final a = acc.putIfAbsent(l.chave, () => _Acumulador(l.tipo));
    a.somar(l);
  }
  return acc.map((k, a) => MapEntry(k, a.totais()));
}

class _Acumulador {
  final TipoChave tipo;
  double q = 0.0, c = 0.0, v = 0.0;
  int n = 0;
  final Set<String> quem = {};
  bool viuCheio = false, viuVazio = false;
  final Set<String> codigos = {};
  _Acumulador(this.tipo);

  void somar(LancResumo l) {
    n++;
    if (l.quem != null) quem.add(l.quem!);
    if (l.codigo.isNotEmpty) codigos.add(l.codigo);
    if (tipo == TipoChave.tag) {
      // Mesmo cilindro lido mais de uma vez: conta uma vez (maior valor).
      // A3: leituras contraditórias (cheio numa, vazio noutra) = conflito.
      if (l.cheio > 0) viuCheio = true;
      if (l.vazio > 0) viuVazio = true;
      if (l.quantidade > q) q = l.quantidade;
      if (l.cheio > c) c = l.cheio;
      if (l.vazio > v) v = l.vazio;
    } else {
      q += l.quantidade;
      c += l.cheio;
      v += l.vazio;
    }
  }

  TotaisRodada totais() => TotaisRodada(
      quantidade: q,
      cheio: c,
      vazio: v,
      ocorrencias: n,
      quem: quem,
      codigos: codigos,
      // A3: cheio e vazio; B63: a mesma TAG com códigos diferentes.
      conflito: tipo == TipoChave.tag &&
          ((viuCheio && viuVazio) || codigos.length > 1));
}

/// Compara C1 e C2. Ordem: em análise primeiro, depois por código/tag.
List<LinhaComparativo> compararC1C2(
  List<LancResumo> c1,
  List<LancResumo> c2,
) {
  final t1 = totalizarRodada(c1);
  final t2 = totalizarRodada(c2);

  // Identificação (código, lote, descrição) da primeira ocorrência.
  final ident = <String, LancResumo>{};
  for (final l in [...c1, ...c2]) {
    ident.putIfAbsent(l.chave, () => l);
  }

  final linhas = <LinhaComparativo>[];
  for (final chave in {...t1.keys, ...t2.keys}) {
    final a = t1[chave];
    final b = t2[chave];
    final id = ident[chave]!;

    final ResultadoLinha res;
    MotivoAnalise? motivo;
    final codigoDiverge = id.tipo == TipoChave.tag &&
        a != null &&
        b != null &&
        (a.codigos.length != b.codigos.length ||
            !a.codigos.containsAll(b.codigos));
    if ((a?.conflito ?? false) || (b?.conflito ?? false) || codigoDiverge) {
      // A3/B63: conflito força C3, mesmo que a outra rodada concorde.
      res = ResultadoLinha.emAnalise;
      motivo = MotivoAnalise.conflito;
    } else if (a != null && b != null) {
      if (a.mesmoValor(b)) {
        res = ResultadoLinha.encerrada;
      } else {
        res = ResultadoLinha.emAnalise;
        motivo = MotivoAnalise.divergente;
      }
    } else {
      res = ResultadoLinha.emAnalise;
      motivo = a != null ? MotivoAnalise.soC1 : MotivoAnalise.soC2;
    }

    linhas.add(LinhaComparativo(
      chave: chave,
      tipo: id.tipo,
      tag: id.tag,
      codigo: id.codigo,
      lote: id.lote,
      descricao: id.descricao,
      c1: a,
      c2: b,
      resultado: res,
      motivo: motivo,
    ));
  }

  linhas.sort((x, y) {
    if (x.emAnalise != y.emAnalise) return x.emAnalise ? -1 : 1;
    final c = x.codigo.compareTo(y.codigo);
    if (c != 0) return c;
    return x.chave.compareTo(y.chave);
  });
  return linhas;
}

/// Resumo numérico do comparativo.
class ResumoComparativo {
  final int total;
  final int encerradas;
  final int emAnalise;
  final int soC1;
  final int soC2;
  final int divergentes;
  final int conflitos;

  const ResumoComparativo({
    required this.total,
    required this.encerradas,
    required this.emAnalise,
    required this.soC1,
    required this.soC2,
    required this.divergentes,
    this.conflitos = 0,
  });

  factory ResumoComparativo.de(List<LinhaComparativo> linhas) {
    int c(bool Function(LinhaComparativo) f) => linhas.where(f).length;
    return ResumoComparativo(
      total: linhas.length,
      encerradas: c((l) => !l.emAnalise),
      emAnalise: c((l) => l.emAnalise),
      soC1: c((l) => l.motivo == MotivoAnalise.soC1),
      soC2: c((l) => l.motivo == MotivoAnalise.soC2),
      divergentes: c((l) => l.motivo == MotivoAnalise.divergente),
      conflitos: c((l) => l.motivo == MotivoAnalise.conflito),
    );
  }
}

/// Andamento da C3.
class ResumoC3 {
  final int total;   // linhas em análise
  final int contadas;
  int get pendentes => total - contadas;

  const ResumoC3({required this.total, required this.contadas});

  factory ResumoC3.de(List<LinhaComparativo> linhas) {
    final em = linhas.where((l) => l.emAnalise).toList();
    return ResumoC3(
        total: em.length, contadas: em.where((l) => l.c3 != null).length);
  }
}

/// Monta a planilha (CSV, separador ';') do resultado.
String resultadoCsv(List<LinhaComparativo> linhas) {
  String f(double? v) => v == null
      ? ''
      : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(3))
          .replaceAll('.', ',');
  String esc(String? s) {
    final x = (s ?? '').replaceAll('"', '""');
    return (x.contains(';') || x.contains('"') || x.contains('\n'))
        ? '"$x"'
        : x;
  }

  final b = StringBuffer()
    ..writeln([
      'tipo', 'tag', 'codigo', 'lote', 'descricao', 'resultado', 'motivo',
      'c1_qtd', 'c1_cheio', 'c1_vazio',
      'c2_qtd', 'c2_cheio', 'c2_vazio',
      'c3_qtd', 'c3_cheio', 'c3_vazio',
      'final_qtd', 'final_cheio', 'final_vazio', 'origem_final',
      'situacao', 'c3_responsavel',
    ].join(';'));
  for (final l in linhas) {
    final fin = l.valorFinal;
    b.writeln([
      l.tipo.name,
      esc(l.tag),
      esc(l.codigo),
      esc(l.lote),
      esc(l.descricao),
      l.emAnalise ? 'em_analise' : 'encerrada',
      l.motivo?.name ?? '',
      f(l.c1?.quantidade), f(l.c1?.cheio), f(l.c1?.vazio),
      f(l.c2?.quantidade), f(l.c2?.cheio), f(l.c2?.vazio),
      f(l.c3?.quantidade), f(l.c3?.cheio), f(l.c3?.vazio),
      f(fin?.quantidade), f(fin?.cheio), f(fin?.vazio),
      l.origemFinal,
      l.resolvida ? 'resolvida' : 'pendente',
      esc(l.c3ResponsavelNome ?? l.c3Quem),
    ].join(';'));
  }
  return b.toString();
}
