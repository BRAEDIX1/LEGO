// test/c3_consolidado_test.dart
// P0 (12/10): C3 CONSOLIDADA por produto × C3 BRUTA por linha.
// Rodar com: flutter test test/c3_consolidado_test.dart
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

ConsolidadoProduto prod(List<LinhaComparativo> ls, [String cod = 'P1']) =>
    consolidarPorProduto(ls, Natureza.gas)
        .firstWhere((p) => p.identificacao == cod);

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
      expect(cons.cabecalho[4], 'C3 consolidada');
      expect(cons.dados.single.sublist(0, 10),
          ['P1', 'DESC P1', 21, 20, 20, 20, 'completa', 2, 1, 0]);
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
    expect(cons.dados.single[4], isNull); // coluna C3 consolidada vazia
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

  test('T-C3-005 — vários lotes e locais: só as recontadas são trocadas', () {
    final ls = [
      linha('A', 10, 10, lote: 'L1'),
      linha('A', 4, 3, lote: 'L2', c3: 3),
      linha('B', 5, 6, lote: 'L1', c3: 6),
      linha('B', 2, 2, lote: 'L2'),
    ];
    final p = prod(ls);
    expect(p.c1!.quantidade, 21);
    expect(p.c2!.quantidade, 21);
    expect(p.c3Consolidada!.quantidade, 10 + 3 + 6 + 2);
    expect(p.linhasConsenso, 2);
    expect(p.linhasPelaC3, 2);
    // produto separado não se mistura
    final outro = consolidarPorProduto(
        [...ls, linha('A', 1, 1, cod: 'P2')], Natureza.gas);
    expect(outro.map((x) => x.identificacao), ['P1', 'P2']);
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
    expect(v(r, 2), tela.dados.single[2]); // C1 21
    expect(v(r, 3), tela.dados.single[3]); // C2 20
    expect(v(r, 4), tela.dados.single[4]); // C3 consolidada 20
    expect(v(r, 4), 20);
    expect(v(r, 5), tela.dados.single[5]); // Final 20
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
