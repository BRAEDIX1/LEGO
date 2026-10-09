// test/relatorio_test.dart
// Relatório no formato do modelo do Djalma (relatorio_lego.xlsx, 09/10).
// Rodar com: flutter test test/relatorio_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lego/services/c3.dart';
import 'package:lego/services/comparativo.dart';
import 'package:lego/services/relatorio_inventario.dart';

Map<String, dynamic> bruto(String cod,
        {double qtd = 0,
        double cheio = 0,
        double vazio = 0,
        String prat = '',
        String? lote,
        double? volume}) =>
    {
      'createdAt': DateTime(2026, 10, 8, 14, 56, 39),
      'localizacaoId': 'GAIOLA',
      'localizacaoNome': 'GAIOLA_ALMOXARIFADO',
      'codigo': cod,
      'descricao': 'DESC $cod',
      'unidade': 'CDA',
      'quantidade': qtd,
      'cheio': cheio,
      'vazio': vazio,
      'prateleira': prat,
      'lote': lote,
      'volume': volume,
      'nomeCompleto': 'Luiz Henrique',
      'registro': 'automatico',
    };

LancResumo resumo(Map<String, dynamic> m, String origem) =>
    LancResumo.deMapa(m)!.comOrigem(origem);

void main() {
  group('Materiais', () {
    final c1 = [bruto('M1', qtd: 20, prat: '2G2'), bruto('M2', qtd: 5, prat: '2G2')];
    final c2 = [bruto('M1', qtd: 20, prat: '2G2'), bruto('M2', qtd: 4, prat: '2G2')];
    final r1 = [for (final m in c1) resumo(m, origemMateriais)];
    final r2 = [for (final m in c2) resumo(m, origemMateriais)];
    final cmp = marcarForaDaC3(compararC1C2(r1, r2), Natureza.material);
    // M2 recontado na C3: 4.
    final comC3 = [
      for (final l in cmp)
        l.emAnalise
            ? LinhaComparativo.deMapa({
                ...l.toMap(),
                'c3': resultadoC3('material', quantidade: 4).toMap(),
              })
            : l
    ];
    final abas = montarRelatorio(
      numero: '002',
      tipo: Natureza.material,
      geradoEm: DateTime(2026, 10, 9, 17, 0),
      lancsC1: c1,
      lancsC2: c2,
      resumoC1: r1,
      resumoC2: r2,
      comparativo: comC3,
    );

    test('abas na ordem do modelo', () {
      expect(abas.map((a) => a.nome).toList(), [
        'C1 Lançamentos', 'C1 Consolidado', 'C2 Lançamentos',
        'C2 Consolidado', 'C3', 'Final',
      ]);
    });
    test('Lançamentos: título, fonte, linha em branco e cabeçalho na 4ª linha',
        () {
      final a = abas.first;
      expect(a.linhaCabecalho, 3);
      expect(a.linhas[0].first, contains('Relatório de Lançamentos LEGO'));
      expect(a.linhas[1].first, startsWith('Fonte: Firestore'));
      expect(a.linhas[2], isEmpty);
      expect(a.cabecalho, cabecalhoLancamentos);
      final l = a.dados.first;
      expect(l[1], '14:56:39'); // hora
      expect(l[2], 'GAIOLA_ALMOXARIFADO');
      expect(l[12], 'Luiz Henrique');
    });
    test('Consolidado de materiais: Código, Descrição, Quantidade, Prateleira',
        () {
      final a = abas[1];
      expect(a.cabecalho, ['Código', 'Descrição', 'Quantidade', 'Prateleira']);
      expect(a.dados, [
        ['M1', 'DESC M1', 20, '2G2'],
        ['M2', 'DESC M2', 5, '2G2'],
      ]);
    });
    test('C3: só a divergência, com C1, C2 e C3', () {
      final a = abas.firstWhere((x) => x.nome == 'C3');
      expect(a.dados.length, 1);
      final l = a.dados.single;
      expect(l[1], 'M2');
      expect(l[7], 5);
      expect(l[8], 4);
      expect(l[9], 4);
      expect(l[10], 'recontado');
    });
    test('Final: fechadas + resolvidas na C3, com a origem', () {
      final a = abas.last;
      expect(a.cabecalho.last, 'Origem');
      expect(a.dados, [
        ['M1', 'DESC M1', 20, '2G2', 'C1 = C2'],
        ['M2', 'DESC M2', 4, '2G2', 'C3'],
      ]);
    });
  });

  group('Gases (gera Gases e Cilindros)', () {
    final c1 = [bruto('G1', cheio: 8, vazio: 5, lote: 'L1', volume: 10)];
    final c2 = [bruto('G1', cheio: 7, vazio: 6, lote: 'L1', volume: 10)];
    final r1 = [for (final m in c1) resumo(m, origemGases)];
    final r2 = [for (final m in c2) resumo(m, origemGases)];
    final cmp = marcarForaDaC3(compararC1C2(r1, r2), Natureza.gas);
    final abas = montarRelatorio(
      numero: '003',
      tipo: Natureza.gas,
      geradoEm: DateTime(2026, 10, 9),
      lancsC1: c1,
      lancsC2: c2,
      resumoC1: r1,
      resumoC2: r2,
      comparativo: cmp,
    );

    test('abas por consolidado', () {
      expect(abas.map((a) => a.nome).toList(), [
        'C1 Lançamentos', 'C1 Consolidado Cilindros', 'C1 Consolidado Gases',
        'C2 Lançamentos', 'C2 Consolidado Cilindros', 'C2 Consolidado Gases',
        'C3', 'Final Cilindros', 'Final Gases',
      ]);
    });
    test('Consolidado de gases: lote, cheios e volume contado', () {
      final a = abas.firstWhere((x) => x.nome == 'C1 Consolidado Gases');
      expect(a.cabecalho, [
        'Código', 'Descrição', 'Lote', 'Cilindros cheios', 'Volume contado',
        'Localização',
      ]);
      expect(a.dados.single, ['G1', 'DESC G1', 'L1', 8, 80, 'GAIOLA_ALMOXARIFADO']);
    });
    test('Consolidado de cilindros: cheios e vazios', () {
      final a = abas.firstWhere((x) => x.nome == 'C1 Consolidado Cilindros');
      expect(a.cabecalho,
          ['Código', 'Descrição', 'Cheios', 'Vazios', 'Localização']);
      expect(a.dados.single, ['G1', 'DESC G1', 8, 5, 'GAIOLA_ALMOXARIFADO']);
    });
    test('8+5 × 7+6: cilindro fecha no Final; gás vai para a C3', () {
      final fc = abas.firstWhere((x) => x.nome == 'Final Cilindros');
      expect(fc.dados.single.last, 'C1 = C2');
      final fg = abas.firstWhere((x) => x.nome == 'Final Gases');
      expect(fg.dados, isEmpty); // gás pendente na C3: ainda não é final
      final c3 = abas.firstWhere((x) => x.nome == 'C3');
      expect(c3.dados.single[0], 'Gases');
      expect(c3.dados.single[10], 'pendente na C3');
    });
    test('divergência informativa aparece na C3 marcada e não vai ao Final',
        () {
      final c2b = [bruto('G1', cheio: 8, vazio: 4, lote: 'L1', volume: 10)];
      final r2b = [for (final m in c2b) resumo(m, origemGases)];
      final cmpb = marcarForaDaC3(compararC1C2(r1, r2b), Natureza.gas);
      final abasb = montarRelatorio(
        numero: '003',
        tipo: Natureza.gas,
        geradoEm: DateTime(2026, 10, 9),
        lancsC1: c1,
        lancsC2: c2b,
        resumoC1: r1,
        resumoC2: r2b,
        comparativo: cmpb,
      );
      final c3 = abasb.firstWhere((x) => x.nome == 'C3');
      expect(c3.dados.single[10], 'informativo (fora da C3)');
      expect(abasb.firstWhere((x) => x.nome == 'Final Cilindros').dados,
          isEmpty);
      expect(abasb.firstWhere((x) => x.nome == 'Final Gases').dados.single.last,
          'C1 = C2');
    });
  });
}
