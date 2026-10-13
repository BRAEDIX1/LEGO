// test/c3_consolidado_test.dart
// P0 (12/10): C3 CONSOLIDADA por produto × C3 BRUTA por linha.
// Rodar com: flutter test test/c3_consolidado_test.dart
import 'dart:convert';

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lego/services/comparativo.dart';
import 'package:lego/services/relatorio_inventario.dart';
import 'package:lego/services/relatorio_inventario_xlsx.dart';

TotaisRodada t(double q, {bool naoEncontrado = false}) => TotaisRodada(
    quantidade: q, cheio: q, volume: q * 10, naoEncontrado: naoEncontrado);

/// Linha de Gás do produto [cod] no [local]. [c3] = recontagem (se houve).
LinhaComparativo linha(
  String local,
  double? c1,
  double? c2, {
  String cod = 'P1',
  String lote = 'L1',
  double? c3,
  bool naoEncontrado = false,
  bool foraDaC3 = false,
}) {
  final emAnalise = c1 == null || c2 == null || c1 != c2;
  return LinhaComparativo(
    chave: 'GAS:$cod|$lote|$local',
    natureza: Natureza.gas,
    codigo: cod,
    lote: lote,
    descricao: 'DESC $cod',
    localId: local,
    localNome: 'AREA_$local',
    c1: c1 == null ? null : t(c1),
    c2: c2 == null ? null : t(c2),
    resultado: emAnalise ? ResultadoLinha.emAnalise : ResultadoLinha.encerrada,
    motivo: emAnalise ? MotivoAnalise.divergente : null,
    c3: c3 == null ? null : t(c3, naoEncontrado: naoEncontrado),
    c3Status: c3 == null ? null : 'sincronizada',
    foraDaC3: foraDaC3,
  );
}

/// Documento como está no Firestore (o `c3` é gravado à parte da linha).
Map<String, dynamic> doc(LinhaComparativo l) =>
    {...l.toMap(), if (l.c3 != null) 'c3': l.c3!.toMap()};

ConsolidadoProduto prod(List<LinhaComparativo> ls,
        [String cod = 'P1', String lote = 'L1']) =>
    consolidarPorProduto(ls, Natureza.gas)
        .firstWhere((p) => p.identificacao == cod && p.lote == lote);

AbaRelatorio aba(List<LinhaComparativo> ls, String nome) => montarRelatorio(
      numero: '007',
      tipo: Natureza.gas,
      geradoEm: DateTime(2026, 10, 13),
      lancsC1: const [],
      lancsC2: const [],
      resumoC1: const [],
      resumoC2: const [],
      comparativo: ls,
    ).firstWhere((a) => a.nome == nome || a.nome == '$nome Gases');

void main() {
  group('T-C3-001 — caso oficial mínimo (8/8, 7/7, 6/5→5)', () {
    final ls = [linha('A', 8, 8), linha('B', 7, 7), linha('C', 6, 5, c3: 5)];
    final p = prod(ls);

    test('C1 = 21, C2 = 20, C3 consolidada = 20', () {
      expect(p.c1!.quantidade, 21);
      expect(p.c2!.quantidade, 20);
      expect(p.c3Consolidada!.quantidade, 20);
      expect(p.valorFinal!.quantidade, 20);
      expect(p.situacao, SituacaoC3Produto.completa);
      expect(p.linhasConsenso, 2);
      expect(p.linhasPelaC3, 1);
    });
    test('C3 bruta da Área C continua 5', () {
      expect(ls[2].c3!.quantidade, 5);
    });
    test('relatório: C3 Consolidado mostra 20; C3 Recontagem mostra 5', () {
      final cons = abaC3Consolidado(
          nome: 'C3 Consolidado', natureza: Natureza.gas, linhas: ls);
      expect(cons.cabecalho[5], 'C3 consolidada');
      expect(cons.dados.single.sublist(0, 11),
          ['P1', 'DESC P1', 'L1', 21, 20, 20, 20, 'completa', 2, 1, 0]);
      final rec = abaC3(ls);
      expect(rec.nome, 'C3 Recontagem');
      expect(rec.cabecalho[9], 'C3 recontada (linha)');
      expect(rec.dados.single[5], 'AREA_C');
      expect(rec.dados.single[9], 5);
    });
  });

  test('T-C3-002 — duas áreas divergentes: 8 + 6 + 4 = 18', () {
    final p = prod([
      linha('A', 8, 8),
      linha('B', 7, 6, c3: 6),
      linha('C', 6, 5, c3: 4),
    ]);
    expect(p.c3Consolidada!.quantidade, 18);
    expect(p.linhasPelaC3, 2);
    expect(p.linhasConsenso, 1);
  });

  test('T-C3-003 — produto sem C3: não inventa terceira contagem', () {
    final p = prod([linha('A', 8, 8), linha('B', 7, 7)]);
    expect(p.situacao, SituacaoC3Produto.naoAplicavel);
    expect(p.c3Consolidada, isNull);
    expect(p.valorFinal!.quantidade, 15); // final = consenso
    final cons = abaC3Consolidado(
        nome: 'C3 Consolidado',
        natureza: Natureza.gas,
        linhas: [linha('A', 8, 8), linha('B', 7, 7)]);
    expect(cons.dados.single[5], isNull); // coluna C3 consolidada vazia
  });

  test('T-C3-004 — C3 pendente: nada de soma parcial como definitiva', () {
    final p = prod([
      linha('A', 8, 8),
      linha('B', 7, 6, c3: 6),
      linha('C', 6, 5), // ainda sem resultado
    ]);
    expect(p.situacao, SituacaoC3Produto.pendente);
    expect(p.c3Consolidada, isNull);
    expect(p.valorFinal, isNull);
    expect(p.linhasPendentes, 1);
  });

  test('T-C3-005 — vários lotes e locais: cada lote tem o seu resultado', () {
    final ls = [
      linha('A', 10, 10, lote: 'L1'),
      linha('A', 4, 3, lote: 'L2', c3: 3),
      linha('B', 5, 6, lote: 'L1', c3: 6),
      linha('B', 2, 2, lote: 'L2'),
    ];
    final l1 = prod(ls, 'P1', 'L1'), l2 = prod(ls, 'P1', 'L2');
    expect(l1.c1!.quantidade, 15);
    expect(l1.c2!.quantidade, 16);
    expect(l1.c3Consolidada!.quantidade, 10 + 6);
    expect(l2.c1!.quantidade, 6);
    expect(l2.c2!.quantidade, 5);
    expect(l2.c3Consolidada!.quantidade, 3 + 2);
    expect(l1.linhasConsenso, 1);
    expect(l1.linhasPelaC3, 1);
    // produto separado não se mistura
    final outro = consolidarPorProduto(
        [...ls, linha('A', 1, 1, cod: 'P2')], Natureza.gas);
    expect(outro.map((x) => '${x.identificacao}/${x.lote}'),
        ['P1/L1', 'P1/L2', 'P2/L1']);
  });

  group('T-FIN — aba Final: produto + lote = consenso + C3 (13/10)', () {
    test('T-FIN-001 — 8 + 7 + 5 = 20 numa única linha do Final', () {
      final f = aba([linha('A', 8, 8), linha('B', 7, 7), linha('C', 6, 5, c3: 5)],
          'Final');
      expect(f.cabecalho, [
        'Código', 'Descrição', 'Lote', 'Cilindros cheios', 'Volume contado',
        'Linhas por consenso (C1 = C2)', 'Linhas pela C3', 'Origem',
      ]);
      expect(f.dados, [
        ['P1', 'DESC P1', 'L1', 20, 200, 2, 1, 'C1 = C2 + C3'],
      ]);
    });
    test('T-FIN-002 — lotes diferentes do mesmo produto: uma linha por lote',
        () {
      final f = aba([
        linha('A', 10, 10, lote: 'L1'),
        linha('B', 5, 6, lote: 'L1', c3: 6),
        linha('A', 4, 3, lote: 'L2', c3: 3),
        linha('B', 2, 2, lote: 'L2'),
      ], 'Final');
      expect(f.dados.map((r) => [r[2], r[3]]), [
        ['L1', 16],
        ['L2', 5],
      ]);
    });
    test('T-FIN-003 — lote com C3 pendente não entra no Final', () {
      final f = aba([linha('A', 8, 8), linha('B', 7, 6)], 'Final');
      expect(f.dados, isEmpty);
    });
    test('T-FIN-004 — lote sem divergência: consenso, origem C1 = C2', () {
      final f = aba([linha('A', 8, 8), linha('B', 7, 7)], 'Final');
      expect(f.dados.single[3], 15);
      expect(f.dados.single.last, 'C1 = C2');
    });
    test('T-FIN-005 — divergência fora da C3: só PARCIAL, marcado', () {
      final f = aba(
          [linha('A', 8, 8), linha('C', 6, 5, foraDaC3: true)], 'Final');
      expect(f.dados.single[3], 8);
      expect(f.dados.single.last, startsWith('PARCIAL'));
    });
    test('T-FIN-006 — "Final por Local" mantém o detalhe linha a linha', () {
      final f = aba([linha('A', 8, 8), linha('B', 7, 7), linha('C', 6, 5, c3: 5)],
          'Final por Local');
      expect(f.dados.map((r) => [r[5], r[3], r.last]), [
        ['AREA_A', 8, 'C1 = C2'],
        ['AREA_B', 7, 'C1 = C2'],
        ['AREA_C', 5, 'C3'],
      ]);
    });
    test('T-FIN-008 — Final tem título e cabeçalho na 5ª linha; destaque só onde a C3 entrou',
        () {
      final ls = [
        linha('A', 8, 8),
        linha('B', 7, 7),
        linha('C', 6, 5, c3: 5),
        linha('A', 3, 3, cod: 'P2'),
      ];
      final f = aba(ls, 'Final');
      expect(f.linhaCabecalho, 4);
      expect(f.linhas[0].first, contains('resultado final por produto e lote'));
      final destacadas = [for (final r in f.dados) linhaComC3(f, r)];
      expect(destacadas, [true, false]); // P1/L1 teve C3; P2/L1 não
      final c = aba(ls, 'C3 Consolidado');
      expect([for (final r in c.dados) linhaComC3(c, r)], [true, false]);
      // abas de detalhe nunca são destacadas
      final d = aba(ls, 'C3 Recontagem');
      expect([for (final r in d.dados) linhaComC3(d, r)], [false]);
    });
    test('T-FIN-007 — soma do Final = soma da C3 Consolidado (gás)', () {
      final ls = [
        linha('A', 8, 8),
        linha('B', 7, 7),
        linha('C', 6, 5, c3: 5),
        linha('A', 3, 3, cod: 'P2'),
      ];
      final fin = aba(ls, 'Final').dados.fold<num>(0, (s, r) => s + (r[3] as num));
      final cons = aba(ls, 'C3 Consolidado')
          .dados
          .fold<num>(0, (s, r) => s + (r[6] as num));
      expect(fin, cons);
      expect(fin, 23);
    });
  });

  test('T-C3-006 — evidência bruta intacta depois de consolidar', () {
    final ls = [linha('A', 8, 8), linha('B', 7, 7), linha('C', 6, 5, c3: 5)];
    final antes = [for (final l in ls) doc(l).toString()];
    consolidarPorProduto(ls, Natureza.gas);
    montarRelatorio(
      numero: '007',
      tipo: Natureza.gas,
      geradoEm: DateTime(2026, 10, 12),
      lancsC1: const [],
      lancsC2: const [],
      resumoC1: const [],
      resumoC2: const [],
      comparativo: ls,
    );
    expect([for (final l in ls) doc(l).toString()], antes);
    expect(ls[2].c1!.quantidade, 6);
    expect(ls[2].c2!.quantidade, 5);
    expect(ls[2].c3!.quantidade, 5);
  });

  test('T-C3-007 — tela e .xlsx: mesmos números (mesma função)', () {
    final ls = [linha('A', 8, 8), linha('B', 7, 7), linha('C', 6, 5, c3: 5)];
    final abas = montarRelatorio(
      numero: '007',
      tipo: Natureza.gas,
      geradoEm: DateTime(2026, 10, 12),
      lancsC1: const [],
      lancsC2: const [],
      resumoC1: const [],
      resumoC2: const [],
      comparativo: ls,
    );
    // A tela mostra exatamente estas abas (RelatorioInventarioView usa
    // montarRelatorio); o .xlsx grava estas mesmas abas.
    final tela = abas.firstWhere((a) => a.nome == 'C3 Consolidado Gases');
    final bytes = gerarXlsx(abas)!;
    final xls = Excel.decodeBytes(bytes);
    final sheet = xls.tables['C3 Consolidado Gases']!;
    Object? v(int r, int c) {
      final cel = sheet.rows[r][c]?.value;
      return switch (cel) {
        IntCellValue i => i.value,
        DoubleCellValue d => d.value,
        TextCellValue s => s.value.text,
        _ => null,
      };
    }

    final r = tela.linhaCabecalho + 1;
    expect(v(r, 0), 'P1');
    expect(v(r, 2), 'L1'); // lote
    expect(v(r, 3), tela.dados.single[3]); // C1 21
    expect(v(r, 4), tela.dados.single[4]); // C2 20
    expect(v(r, 5), tela.dados.single[5]); // C3 consolidada 20
    expect(v(r, 5), 20);
    // (Final e Volume final são fórmulas no .xlsx: ver T-FORM.)
  });

  test('T-C3-008 — reabrir histórico (dados do Firestore) dá o mesmo resultado',
      () {
    final ls = [linha('A', 8, 8), linha('B', 7, 7), linha('C', 6, 5, c3: 5)];
    final relidas = [for (final l in ls) LinhaComparativo.deMapa(doc(l))];
    final a = prod(ls), b = prod(relidas);
    expect(b.c3Consolidada!.quantidade, a.c3Consolidada!.quantidade);
    expect(b.c1!.quantidade, a.c1!.quantidade);
    expect(b.c2!.quantidade, a.c2!.quantidade);
  });

  group('T-FORM — corrigir a C3 consolidada recalcula o encerramento (.xlsx)', () {
    final ls = [
      linha('A', 8, 8),
      linha('B', 7, 7),
      linha('C', 6, 5, c3: 5),
      linha('A', 3, 3, cod: 'P2'),
    ];
    List<AbaRelatorio> relatorio(List<LinhaComparativo> l) => montarRelatorio(
          numero: '007',
          tipo: Natureza.gas,
          geradoEm: DateTime(2026, 10, 13),
          lancsC1: const [],
          lancsC2: const [],
          resumoC1: const [],
          resumoC2: const [],
          comparativo: l,
        );
    final abas = relatorio(ls);
    AbaRelatorio por(String n) => abas.firstWhere((a) => a.nome == n);

    test('T-FORM-001 — C3 Consolidado: Final, Situação e Volume são fórmulas', () {
      final c3 = por('C3 Consolidado Gases');
      expect(c3.formulas[(5, 6)], 'IF(F6<>"",F6,"")'); // P1: completa
      expect(c3.formulas[(6, 6)], 'IF(F7<>"",F7,D7)'); // P2: sem divergência
      expect(c3.formulas[(5, 7)],
          'IF(F6=20,"completa","C3 ajustada manualmente")');
      expect(c3.formulas[(6, 7)],
          'IF(F7="","não aplicável (sem divergência)","C3 informada manualmente")');
      expect(c3.formulas[(5, 11)], 'IF(G6="","",G6*10)');
    });

    test('T-FORM-002 — Final lê a C3 Consolidado por produto + lote', () {
      final f = por('Final Gases');
      expect(
          f.formulas[(5, 3)],
          r"SUMPRODUCT(('C3 Consolidado Gases'!$A$6:$A$7=A6)*('C3 Consolidado Gases'!$C$6:$C$7=C6),'C3 Consolidado Gases'!$G$6:$G$7)");
      expect(f.formulas[(5, 4)], contains(r"'C3 Consolidado Gases'!$L$6:$L$7"));
      expect(f.formulas[(5, 7)],
          'IF(D6=20,"C1 = C2 + C3","AJUSTE MANUAL DA C3")');
    });

    test('T-FORM-003 — parcial (fora da C3) fica sem fórmula no Final', () {
      final f = abaFinal(
        nome: 'Final Gases',
        natureza: Natureza.gas,
        linhas: [linha('A', 8, 8), linha('C', 6, 5, foraDaC3: true)],
        c3Consolidado: abaC3Consolidado(
            nome: 'C3 Consolidado Gases',
            natureza: Natureza.gas,
            linhas: [linha('A', 8, 8), linha('C', 6, 5, foraDaC3: true)]),
      );
      expect(f.dados.single.last, startsWith('PARCIAL'));
      expect(f.formulas, isEmpty);
    });

    test('T-FORM-004 — .xlsx grava fórmulas, cor da aba, painel e filtro', () {
      final bytes = gerarXlsx(abas)!;
      final zip = ZipDecoder().decodeBytes(bytes);
      final xml = [
        for (final f in zip.files)
          if (f.name.startsWith('xl/worksheets/') && f.name.endsWith('.xml'))
            utf8.decode(f.content as List<int>),
      ].join('\n');
      expect(xml, contains('<f>SUMPRODUCT('));
      expect(xml, contains('<f>IF(F6'));
      expect(xml, contains('<tabColor rgb="FFFFFFCC"/>'));
      expect(xml, contains('state="frozen"'));
      expect(xml, contains('<autoFilter ref="A5:L7"/>')); // C3 Consolidado
      expect(xml, contains('<autoFilter ref="A5:H7"/>')); // Final
      // continua sendo um .xlsx legível
      expect(Excel.decodeBytes(bytes).tables.keys, contains('Final Gases'));
    });
  });

  group('regras vigentes preservadas', () {
    test('"não encontrado" entra como o que a C3 registrou (0)', () {
      final p = prod([
        linha('A', 8, 8),
        linha('C', 6, 5, c3: 0, naoEncontrado: true),
      ]);
      expect(p.situacao, SituacaoC3Produto.completa);
      expect(p.c3Consolidada!.quantidade, 8);
      expect(p.linhasPelaC3, 1);
    });
    test('divergência fora da C3: sem valor final, nada inventado', () {
      final p = prod([linha('A', 8, 8), linha('C', 6, 5, foraDaC3: true)]);
      expect(p.situacao, SituacaoC3Produto.semC3);
      expect(p.c3Consolidada, isNull);
      expect(p.valorFinal, isNull);
    });
    test('volume do gás também é consolidado (consenso + C3)', () {
      final p = prod(
          [linha('A', 8, 8), linha('B', 7, 7), linha('C', 6, 5, c3: 5)]);
      expect(p.c3Consolidada!.volume, 200);
    });
  });
}
