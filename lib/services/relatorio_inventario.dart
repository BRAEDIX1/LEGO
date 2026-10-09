// lib/services/relatorio_inventario.dart
//
// Relatório do inventário no formato do modelo do Djalma (relatorio_lego.xlsx,
// 09/10/2026). Funções PURAS: montam as abas como tabelas; quem grava o .xlsx
// é o relatorio_inventario_xlsx.dart.
//
// Abas:
//   C1 Lançamentos · C1 Consolidado [tipo] · C2 Lançamentos ·
//   C2 Consolidado [tipo] · C3 · Final [tipo]
//
// Colunas dos consolidados (Djalma, 09/10):
//   Materiais: Código, Descrição, Quantidade, Prateleira
//   Gases:     Código, Descrição, Lote, Cilindros cheios, Volume contado,
//              Localização
//   Cilindros: Código, Descrição, Cheios, Vazios, Localização
//
// Final = linhas fechadas (C1 = C2) + o que a C3 resolveu. Divergências que
// não passaram pela C3 (informativas) ficam só na aba C3, marcadas.

import 'package:lego/services/comparativo.dart';

/// Uma aba do relatório: linhas (a de cabeçalho é [linhaCabecalho], base 0).
class AbaRelatorio {
  final String nome;
  final List<List<Object?>> linhas;
  final int linhaCabecalho;
  const AbaRelatorio(this.nome, this.linhas, {this.linhaCabecalho = 0});

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
  'Divergência', 'C1', 'C2', 'C3', 'Situação', 'Responsável',
];

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
  return AbaRelatorio('C3', [
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
  ]);
}

/// Aba "Final" de uma natureza: fechadas (C1 = C2) + resolvidas na C3.
AbaRelatorio abaFinal({
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
    abaC3(comparativo),
    for (final n in naturezas)
      abaFinal(
        nome: umSo ? 'Final' : 'Final ${n.rotulo}',
        natureza: n,
        linhas: comparativo,
      ),
  ];
}
