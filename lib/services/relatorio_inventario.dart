// lib/services/relatorio_inventario.dart
//
// Relatório do inventário no formato do modelo do Djalma (relatorio_lego.xlsx,
// 09/10/2026). Funções PURAS: montam as abas como tabelas; quem grava o .xlsx
// é o relatorio_inventario_xlsx.dart.
//
// Abas:
//   C1 Lançamentos · C1 Consolidado [tipo] · C2 Lançamentos ·
//   C2 Consolidado [tipo] · C3 Consolidado [tipo] · C3 Recontagem ·
//   Final [tipo] · Final por Local [tipo]
//
// P0 (12/10): "C3 Consolidado" = saldo completo do PRODUTO após a C3
// (consenso nas linhas C1 = C2 + C3 nas linhas recontadas), calculado por
// consolidarPorProduto (comparativo.dart). "C3 Recontagem" = evidência por
// linha (C3 bruta). Nunca apresentar a C3 bruta como consolidado.
//
// Colunas dos consolidados (Djalma, 09/10):
//   Materiais: Código, Descrição, Quantidade, Prateleira
//   Gases:     Código, Descrição, Lote, Cilindros cheios, Volume contado,
//              Localização
//   Cilindros: Código, Descrição, Cheios, Vazios, Localização
//
// Final = UMA linha por produto e lote (Gás), somando os locais: linhas
// fechadas (C1 = C2) + o que a C3 encontrou nas que divergiram. "Final por
// Local" = o mesmo, linha a linha. Divergências fora da C3 aparecem só como
// PARCIAL (marcado na Origem) e na aba C3 Recontagem.

import 'package:lego/services/comparativo.dart';

/// Uma aba do relatório: linhas (a de cabeçalho é [linhaCabecalho], base 0).
class AbaRelatorio {
  final String nome;
  final List<List<Object?>> linhas;
  final int linhaCabecalho;

  /// Fórmulas do .xlsx por célula (linha, coluna; base 0, mesmas coordenadas
  /// de [linhas]), sem o "=". A tela e os testes usam o valor já calculado de
  /// [linhas]; só o .xlsx grava a fórmula, para que a correção manual da C3
  /// recalcule as abas de encerramento.
  final Map<(int, int), String> formulas;

  const AbaRelatorio(this.nome, this.linhas,
      {this.linhaCabecalho = 0, this.formulas = const {}});

  List<Object?> get cabecalho => linhas[linhaCabecalho];
  List<List<Object?>> get dados => linhas.sublist(linhaCabecalho + 1);
}

/// Hora "HH:mm:ss" do modelo.
String _hora(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'
    ':${d.second.toString().padLeft(2, '0')}';

String _dataHora(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/'
    '${d.year} ${_hora(d).substring(0, 5)}';

/// Número "limpo": inteiro quando não tem fração.
Object? _n(double? v) {
  if (v == null) return null;
  return v == v.roundToDouble() ? v.toInt() : v;
}

String? _txt(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

double? _dbl(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

String _aspas(String s) => s.replaceAll('"', '""');

/// Número como literal de fórmula (sem notação científica, ponto decimal).
String _lit(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Volume = quantidade × unitário só vira fórmula se reproduz o valor gravado.
double? _unidadeConfiavel(ConsolidadoProduto p, TotaisRodada? t) {
  final u = p.volumeUnitario;
  if (u == null || t == null || t.volume == null) return null;
  return ((u * t.quantidade) - t.volume!).abs() < 1e-6 ? u : null;
}

const cabecalhoLancamentos = [
  'Data', 'Hora', 'Localização', 'Código', 'Descrição', 'Unidade',
  'Volume Unitário', 'Cheio', 'Volume Cheio', 'Vazio', 'TAG', 'Lote',
  'Operador', 'Registro', 'Quantidade', 'Comentário', 'Prateleira',
  'Ordem de Serviço',
];

/// Aba "Cx Lançamentos" no formato do modelo: título, fonte, linha em branco
/// e o cabeçalho na 4ª linha. [lancs]: documentos de `lancamentos` com
/// `createdAt` já convertido para DateTime (hora local).
AbaRelatorio abaLancamentos({
  required String nome,
  required String titulo,
  required String fonte,
  required List<Map<String, dynamic>> lancs,
}) {
  final ordenados = [...lancs]..sort((a, b) {
      final da = a['createdAt'] as DateTime?;
      final db = b['createdAt'] as DateTime?;
      if (da == null || db == null) return 0;
      return db.compareTo(da); // mais recente primeiro, como no modelo
    });
  final linhas = <List<Object?>>[
    [titulo],
    [fonte],
    [],
    cabecalhoLancamentos,
  ];
  for (final l in ordenados) {
    final d = l['createdAt'] as DateTime?;
    final vol = _dbl(l['volume']);
    final cheio = _dbl(l['cheio']) ?? 0;
    linhas.add([
      d == null ? null : DateTime(d.year, d.month, d.day),
      d == null ? null : _hora(d),
      _txt(l['localizacaoNome']) ?? _txt(l['localizacaoId']),
      _txt(l['codigo']),
      _txt(l['descricao']),
      _txt(l['unidade']),
      _n(vol),
      _n(cheio),
      vol == null ? null : _n(cheio * vol),
      _n(_dbl(l['vazio']) ?? 0),
      _txt(l['tag']),
      _txt(l['lote']),
      _txt(l['nomeCompleto']) ?? _txt(l['nickname']),
      _txt(l['registro']),
      _n(_dbl(l['quantidade']) ?? 0),
      _txt(l['comentario']),
      _txt(l['prateleira']),
      _txt(l['ordemServico']),
    ]);
  }
  return AbaRelatorio(nome, linhas, linhaCabecalho: 3);
}

/// Cabeçalho do consolidado de cada natureza.
List<String> cabecalhoConsolidado(Natureza n) => switch (n) {
      Natureza.material => ['Código', 'Descrição', 'Quantidade', 'Prateleira'],
      Natureza.gas => [
          'Código', 'Descrição', 'Lote', 'Cilindros cheios',
          'Volume contado', 'Localização',
        ],
      Natureza.cilindro => [
          'Código', 'Descrição', 'Cheios', 'Vazios', 'Localização',
        ],
    };

/// Uma linha de consolidado a partir de uma linha do comparativo e dos
/// totais escolhidos (C1, C2 ou final).
List<Object?> linhaConsolidado(LinhaComparativo l, TotaisRodada t) =>
    switch (l.natureza) {
      Natureza.material => [
          l.codigo, l.descricao, _n(t.quantidade), l.prateleira,
        ],
      Natureza.gas => [
          l.codigo, l.descricao, l.lote, _n(t.quantidade), _n(t.volume),
          l.localFinal,
        ],
      Natureza.cilindro => [
          l.identificacao, l.descricao, _n(t.cheio), _n(t.vazio),
          l.localFinal,
        ],
    };

/// Consolidado de UMA rodada para uma natureza ([lancs] já classificados).
AbaRelatorio abaConsolidado({
  required String nome,
  required Natureza natureza,
  required List<LancResumo> lancs,
}) {
  final linhas = compararC1C2(lancs, const [])
      .where((l) => l.natureza == natureza && l.c1 != null)
      .toList()
    ..sort(_ordemConsolidado);
  return AbaRelatorio(nome, [
    cabecalhoConsolidado(natureza),
    for (final l in linhas) linhaConsolidado(l, l.c1!),
  ]);
}

int _ordemConsolidado(LinhaComparativo a, LinhaComparativo b) {
  final c = a.identificacao.compareTo(b.identificacao);
  if (c != 0) return c;
  final p = a.prateleira.compareTo(b.prateleira);
  if (p != 0) return p;
  final lo = (a.lote ?? '').compareTo(b.lote ?? '');
  if (lo != 0) return lo;
  return a.localFinal.compareTo(b.localFinal);
}

const cabecalhoC3 = [
  'Natureza', 'Código', 'Descrição', 'Lote', 'Prateleira', 'Localização',
  'Divergência', 'C1', 'C2', 'C3 recontada (linha)', 'Situação', 'Responsável',
];

/// Versão da regra da C3 consolidada (aparece no relatório: identifica os
/// relatórios gerados com a correção P0).
const versaoCalculoC3 = 'C3 consolidada v3 (correção P0 de 13/10/2026: produto + lote)';

/// Nome da aba de evidência da C3 (linha a linha).
const nomeAbaC3Recontagem = 'C3 Recontagem';

/// Cabeçalho do consolidado da C3 por produto.
List<String> cabecalhoC3Consolidado(Natureza n) => [
      'Código', 'Descrição',
      if (n == Natureza.gas) 'Lote',
      if (n == Natureza.material) 'Prateleiras',
      'C1', 'C2', 'C3 consolidada', 'Final',
      'Situação da C3', 'Linhas por consenso (C1 = C2)', 'Linhas pela C3',
      'Linhas pendentes ou sem C3',
      if (n == Natureza.gas) 'Volume final',
    ];

/// Aba "C3 Consolidado" de uma natureza: um produto por linha, com C1, C2 e
/// a C3 CONSOLIDADA (consenso + recontagem), nunca a C3 bruta.
AbaRelatorio abaC3Consolidado({
  required String nome,
  required Natureza natureza,
  required List<LinhaComparativo> linhas,
}) {
  final prods = consolidarPorProduto(linhas, natureza);
  // Gás: "Final" e "Volume final" são fórmulas no .xlsx. Quem corrige a
  // "C3 consolidada" à mão vê o Final, o volume e a aba Final se atualizarem.
  final formulas = <(int, int), String>{};
  if (natureza == Natureza.gas) {
    for (var i = 0; i < prods.length; i++) {
      final p = prods[i];
      final r = 5 + i; // índice em linhas (cabeçalho = 4)
      final n = r + 1; // linha do Excel
      final f = p.c3Consolidada?.quantidade;
      final base = p.situacao == SituacaoC3Produto.naoAplicavel ? 'D$n' : '""';
      formulas[(r, 6)] = 'IF(F$n<>"",F$n,$base)';
      final s0 = _aspas(p.situacao.rotulo);
      formulas[(r, 7)] = f != null
          ? 'IF(F$n=${_lit(f)},"$s0","C3 ajustada manualmente")'
          : 'IF(F$n="","$s0","C3 informada manualmente")';
      final u = _unidadeConfiavel(p, p.valorFinal);
      if (u != null) formulas[(r, 11)] = 'IF(G$n="","",G$n*${_lit(u)})';
    }
  }
  return AbaRelatorio(
    nome,
    [
      ['C3 Consolidado — resultado completo de cada produto após a terceira contagem'],
      ['Linhas com C1 = C2 entram pelo consenso; linhas recontadas entram pelo '
          'valor da C3 (substitui C1/C2 nessa linha). C1, C2 e C3 não são somados '
          'entre si. A recontagem linha a linha está na aba $nomeAbaC3Recontagem.'],
      ['Métrica: ${natureza.metrica} · Cálculo: $versaoCalculoC3'],
      [],
      cabecalhoC3Consolidado(natureza),
      for (final p in prods)
        [
          p.identificacao,
          p.descricao,
          if (natureza == Natureza.gas) p.lote,
          if (natureza == Natureza.material) p.prateleira,
          _n(p.c1?.quantidade),
          _n(p.c2?.quantidade),
          _n(p.c3Consolidada?.quantidade),
          _n(p.valorFinal?.quantidade),
          p.situacao.rotulo,
          p.linhasConsenso,
          p.linhasPelaC3,
          p.linhasPendentes + p.linhasSemC3,
          if (natureza == Natureza.gas) _n(p.valorFinal?.volume),
        ],
    ],
    linhaCabecalho: 4,
    formulas: formulas,
  );
}

String _motivo(MotivoAnalise? m) => switch (m) {
      MotivoAnalise.soC1 => 'só na C1',
      MotivoAnalise.soC2 => 'só na C2',
      MotivoAnalise.divergente => 'C1 ≠ C2',
      _ => '',
    };

/// Situação da linha divergente, para a aba C3.
String situacaoC3(LinhaComparativo l) {
  if (l.foraDaC3) return 'informativo (fora da C3)';
  if (l.c3 == null) return 'pendente na C3';
  return l.c3!.naoEncontrado ? 'recontado: não encontrado' : 'recontado';
}

/// Aba "C3": todas as divergências (C1 × C2). As da C3 primeiro; as
/// informativas (outro consolidado do mesmo inventário) depois.
AbaRelatorio abaC3(List<LinhaComparativo> linhas) {
  final div = linhas.where((l) => l.emAnalise).toList()
    ..sort((a, b) {
      if (a.foraDaC3 != b.foraDaC3) return a.foraDaC3 ? 1 : -1;
      final n = a.natureza.index.compareTo(b.natureza.index);
      return n != 0 ? n : _ordemConsolidado(a, b);
    });
  return AbaRelatorio(nomeAbaC3Recontagem, [
    ['C3 Recontagem — valor recontado em cada linha divergente (evidência)'],
    ['Esta aba NÃO é o resultado do produto. O resultado completo após a C3 '
        'está na aba C3 Consolidado.'],
    [],
    cabecalhoC3,
    for (final l in div)
      [
        l.natureza.rotulo,
        l.identificacao,
        l.descricao,
        l.lote,
        l.prateleira.isEmpty ? null : l.prateleira,
        l.localFinal,
        _motivo(l.motivo),
        _n(l.c1?.quantidade),
        _n(l.c2?.quantidade),
        _n(l.c3?.quantidade),
        situacaoC3(l),
        l.c3ResponsavelNome ?? l.c3Quem,
      ],
  ], linhaCabecalho: 3);
}

/// Cabeçalho da aba Final (resultado por produto e lote).
List<String> cabecalhoFinal(Natureza n) => switch (n) {
      Natureza.material => [
          'Código', 'Descrição', 'Quantidade', 'Prateleiras',
          'Linhas por consenso (C1 = C2)', 'Linhas pela C3', 'Origem',
        ],
      Natureza.gas => [
          'Código', 'Descrição', 'Lote', 'Cilindros cheios', 'Volume contado',
          'Linhas por consenso (C1 = C2)', 'Linhas pela C3', 'Origem',
        ],
      Natureza.cilindro => [
          'Código', 'Descrição', 'Cheios', 'Vazios',
          'Linhas por consenso (C1 = C2)', 'Linhas pela C3', 'Origem',
        ],
    };

/// Origem do valor final de um produto/lote.
String origemProduto(ConsolidadoProduto p) {
  if (p.situacao == SituacaoC3Produto.semC3) {
    return 'PARCIAL: divergência fora da C3 não incluída';
  }
  if (p.linhasPelaC3 == 0) return 'C1 = C2';
  if (p.linhasConsenso == 0) return 'C3';
  return 'C1 = C2 + C3';
}

/// Aba "Final" de uma natureza: UMA linha por produto e lote (Gás), com o
/// resultado final = linhas que fecharam (C1 = C2) + o que a C3 encontrou nas
/// linhas que divergiram, somando todos os locais. Produto/lote com C3
/// pendente não entra (ainda não é final). O detalhe por local está em
/// "Final por Local".
AbaRelatorio abaFinal({
  required String nome,
  required Natureza natureza,
  required List<LinhaComparativo> linhas,
  /// Aba "C3 Consolidado" da mesma natureza: o Final do Gás lê dela (fórmula
  /// no .xlsx), então corrigir a C3 consolidada atualiza o Final sozinho.
  AbaRelatorio? c3Consolidado,
}) {
  final dados = <List<Object?>>[];
  final formulas = <(int, int), String>{};
  final usarFormula = natureza == Natureza.gas &&
      c3Consolidado != null &&
      c3Consolidado.dados.isNotEmpty;
  final ref = usarFormula ? "'${c3Consolidado.nome}'!" : '';
  final a = usarFormula ? c3Consolidado.linhaCabecalho + 2 : 0;
  final z = usarFormula ? c3Consolidado.linhas.length : 0;
  String rng(String col) => '$ref\$$col\$$a:\$$col\$$z';
  for (final p in consolidarPorProduto(linhas, natureza)) {
    if (p.situacao == SituacaoC3Produto.pendente) continue;
    final final_ = p.valorFinal;
    final t = final_ ?? p.parcial; // parcial só com a marca na Origem
    if (t == null) continue;
    final origem = origemProduto(p);
    final r = 5 + dados.length; // índice em linhas (cabeçalho = 4)
    final n = r + 1; // linha do Excel
    dados.add([
      p.identificacao,
      p.descricao,
      ...switch (natureza) {
        Natureza.material => [_n(t.quantidade), p.prateleira],
        Natureza.gas => [p.lote, _n(t.quantidade), _n(t.volume)],
        Natureza.cilindro => [_n(t.cheio), _n(t.vazio)],
      },
      p.linhasConsenso,
      p.linhasPelaC3,
      origem,
    ]);
    if (usarFormula && final_ != null) {
      final chave = '(${rng('A')}=A$n)*(${rng('C')}=C$n)';
      formulas[(r, 3)] = 'SUMPRODUCT($chave,${rng('G')})';
      if (_unidadeConfiavel(p, final_) != null) {
        formulas[(r, 4)] = 'SUMPRODUCT($chave,${rng('L')})';
      }
      formulas[(r, 7)] =
          'IF(D$n=${_lit(final_.quantidade)},"${_aspas(origem)}","AJUSTE MANUAL DA C3")';
    }
  }
  return AbaRelatorio(
    nome,
    [
      ['Final ${natureza.rotulo} — resultado final por produto e lote'],
      ['Final = linhas que fecharam (C1 = C2) + o valor da C3 nas linhas que '
          'divergiram, somando todos os locais. O detalhe por local está em '
          'Final por Local.'],
      ['Métrica: ${natureza.metrica} · Cálculo: $versaoCalculoC3'],
      [],
      cabecalhoFinal(natureza),
      ...dados,
    ],
    linhaCabecalho: 4,
    formulas: formulas,
  );
}

/// A linha (de "C3 Consolidado" ou "Final") teve a C3 entrando no resultado?
/// Usada para destacar a linha na tela e no .xlsx (mesma regra nos dois).
bool linhaComC3(AbaRelatorio a, List<Object?> linha) {
  if (!(a.nome.startsWith('C3 Consolidado') ||
      (a.nome.startsWith('Final') && !a.nome.startsWith('Final por Local')))) {
    return false;
  }
  final i = a.cabecalho.indexOf('Linhas pela C3');
  if (i < 0 || i >= linha.length) return false;
  final v = linha[i];
  return v is num && v > 0;
}

/// Aba "Final por Local": o final linha a linha (produto + lote + local),
/// fechadas (C1 = C2) + resolvidas na C3. Detalhe; o resultado do produto/lote
/// está em "Final".
AbaRelatorio abaFinalPorLocal({
  required String nome,
  required Natureza natureza,
  required List<LinhaComparativo> linhas,
}) {
  final finais = linhas
      .where((l) => l.natureza == natureza && l.resolvida && l.valorFinal != null)
      .toList()
    ..sort(_ordemConsolidado);
  return AbaRelatorio(nome, [
    [...cabecalhoConsolidado(natureza), 'Origem'],
    for (final l in finais)
      [...linhaConsolidado(l, l.valorFinal!), l.origemFinal],
  ]);
}

/// Monta o relatório completo do inventário.
/// [tipo]: natureza do inventário (null = antigo: os três consolidados).
List<AbaRelatorio> montarRelatorio({
  required String numero,
  required Natureza? tipo,
  required DateTime geradoEm,
  required List<Map<String, dynamic>> lancsC1,
  required List<Map<String, dynamic>> lancsC2,
  required List<LancResumo> resumoC1,
  required List<LancResumo> resumoC2,
  required List<LinhaComparativo> comparativo,
}) {
  final naturezas = consolidadosDoTipo(tipo).toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  final umSo = naturezas.length == 1;
  String nomeCons(String r, Natureza n) =>
      umSo ? '$r Consolidado' : '$r Consolidado ${n.rotulo}';
  final c3Abas = {
    for (final n in naturezas)
      n: abaC3Consolidado(
        nome: umSo ? 'C3 Consolidado' : 'C3 Consolidado ${n.rotulo}',
        natureza: n,
        linhas: comparativo,
      ),
  };
  final rotuloTipo = tipo?.rotulo ?? 'sem tipo';
  final fonte =
      'Fonte: Firestore | Tipo: $rotuloTipo | Gerado em ${_dataHora(geradoEm)}';

  return [
    for (final (r, raw, res) in [
      ('C1', lancsC1, resumoC1),
      ('C2', lancsC2, resumoC2),
    ]) ...[
      abaLancamentos(
        nome: '$r Lançamentos',
        titulo: 'Relatório de Lançamentos LEGO — Inventário $numero · $r',
        fonte: fonte,
        lancs: raw,
      ),
      for (final n in naturezas)
        abaConsolidado(nome: nomeCons(r, n), natureza: n, lancs: res),
    ],
    for (final n in naturezas) c3Abas[n]!,
    abaC3(comparativo),
    for (final n in naturezas)
      abaFinal(
        nome: umSo ? 'Final' : 'Final ${n.rotulo}',
        natureza: n,
        linhas: comparativo,
        c3Consolidado: c3Abas[n],
      ),
    for (final n in naturezas)
      abaFinalPorLocal(
        nome: umSo ? 'Final por Local' : 'Final por Local ${n.rotulo}',
        natureza: n,
        linhas: comparativo,
      ),
  ];
}

/// Contagem Simples (sem inventário): aba de lançamentos no formato do modelo
/// e um consolidado por natureza que tiver linhas (Materiais por código +
/// prateleira; Gases por código + lote + localização; Cilindros por código +
/// localização — as mesmas chaves do Completo).
List<AbaRelatorio> montarRelatorioSimples({
  required String periodo,
  required String filtro,
  required DateTime geradoEm,
  required List<Map<String, dynamic>> lancs,
  required List<LancResumo> resumo,
}) {
  final fonte = 'Fonte: Firestore | Contagem Simples | $filtro | '
      'Gerado em ${_dataHora(geradoEm)}';
  return [
    abaLancamentos(
      nome: 'Lançamentos',
      titulo: 'Relatório de Lançamentos LEGO — Contagem Simples · $periodo',
      fonte: fonte,
      lancs: lancs,
    ),
    for (final n in Natureza.values)
      abaConsolidado(
          nome: 'Consolidado ${n.rotulo}', natureza: n, lancs: resumo),
  ].where((a) => a.nome == 'Lançamentos' || a.dados.isNotEmpty).toList();
}

