// test/c3_distribuicao_test.dart
// Item 2 (03/11) — C3-D: divisão da C3 por local, com peso de esforço.
// Rodar com: flutter test test/c3_distribuicao_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lego/services/c3.dart';
import 'package:lego/services/comparativo.dart';

ItemDistribuicaoC3 it(String id, String local, String produto, double e) =>
    ItemDistribuicaoC3(id: id, local: local, produto: produto, esforco: e);

/// Responsável de cada linha.
Map<String, String> donoDe(Map<String, List<String>> d) => {
      for (final e in d.entries)
        for (final id in e.value) id: e.key,
    };

double carga(Map<String, List<String>> d, String u,
        List<ItemDistribuicaoC3> itens) =>
    d[u]!.fold(0.0,
        (s, id) => s + itens.firstWhere((x) => x.id == id).esforco);

/// Invariantes que valem para QUALQUER distribuição.
void conferirInvariantes(
    List<ItemDistribuicaoC3> itens, List<String> uids,
    Map<String, List<String>> d) {
  // Todo uid aparece.
  expect(d.keys.toSet(), uids.toSet());
  // Toda linha exatamente uma vez.
  final todos = d.values.expand((x) => x).toList();
  expect(todos.length, itens.length);
  expect(todos.toSet(), itens.map((x) => x.id).toSet());
  // (local, produto) → exatamente 1 responsável.
  final dono = donoDe(d);
  final porPar = <String, Set<String>>{};
  for (final x in itens) {
    porPar.putIfAbsent('${x.local}|${x.produto}', () => {}).add(dono[x.id]!);
  }
  for (final e in porPar.entries) {
    expect(e.value.length, 1, reason: 'par ${e.key} com ${e.value}');
  }
}

void main() {
  group('C3-D — distribuirPorLocal', () {
    test('piloto 007 (simplificado): cada local com um único responsável',
        () {
      // 7 operadores, 14 locais leves (3 lotes cada, esforço 2..8).
      final itens = <ItemDistribuicaoC3>[];
      for (var l = 0; l < 14; l++) {
        for (var lote = 0; lote < 3; lote++) {
          itens.add(it('L${l}_$lote', 'LOC:A$l', 'GC:P${l % 4}',
              (2 + (l + lote) % 7).toDouble()));
        }
      }
      final uids = ['u1', 'u2', 'u3', 'u4', 'u5', 'u6', 'u7'];
      final d = distribuirPorLocal(itens, uids);
      conferirInvariantes(itens, uids, d);
      // Nenhum local foi dividido (todos menores que a parte justa).
      final dono = donoDe(d);
      final porLocal = <String, Set<String>>{};
      for (final x in itens) {
        porLocal.putIfAbsent(x.local, () => {}).add(dono[x.id]!);
      }
      expect(porLocal.values.every((s) => s.length == 1), isTrue);
      // Todos trabalham.
      expect(d.values.every((v) => v.isNotEmpty), isTrue);
    });

    test('local pesado é dividido por produto, entre pessoas diferentes',
        () {
      // Local GRANDE: 4 produtos de 25 = 100. Outros 2 locais de 10.
      // Total 120, 3 pessoas → parte justa 40; limite de divisão 60.
      // k = min(ceil(100/60)=2, 4 produtos, 3 pessoas) = 2.
      final itens = [
        for (var p = 0; p < 4; p++) it('G$p', 'LOC:GRANDE', 'GC:P$p', 25),
        it('X', 'LOC:X', 'GC:Q', 10),
        it('Y', 'LOC:Y', 'GC:R', 10),
      ];
      final uids = ['a', 'b', 'c'];
      final d = distribuirPorLocal(itens, uids);
      conferirInvariantes(itens, uids, d);
      final dono = donoDe(d);
      final donosGrande = {for (var p = 0; p < 4; p++) dono['G$p']};
      expect(donosGrande.length, 2); // k = 2 pessoas distintas
    });

    test('local só um pouco acima da média NÃO é dividido (51 × média 50)',
        () {
      // Total 100, 2 pessoas → parte justa 50. Local A = 51 (3 produtos).
      final itens = [
        it('a1', 'LOC:A', 'GC:1', 17),
        it('a2', 'LOC:A', 'GC:2', 17),
        it('a3', 'LOC:A', 'GC:3', 17),
        it('b1', 'LOC:B', 'GC:4', 49),
      ];
      final d = distribuirPorLocal(itens, ['x', 'y']);
      conferirInvariantes(itens, ['x', 'y'], d);
      final dono = donoDe(d);
      expect({dono['a1'], dono['a2'], dono['a3']}.length, 1);
      expect(dono['b1'], isNot(dono['a1']));
    });

    test('local com o dobro da média é dividido em 2 pessoas', () {
      // Total 120, 3 pessoas → parte justa 40; limite 60. Local A = 80.
      final itens = [
        for (var p = 0; p < 4; p++) it('a$p', 'LOC:A', 'GC:$p', 20),
        it('b', 'LOC:B', 'GC:9', 20),
        it('c', 'LOC:C', 'GC:8', 20),
      ];
      final d = distribuirPorLocal(itens, ['x', 'y', 'z']);
      conferirInvariantes(itens, ['x', 'y', 'z'], d);
      final dono = donoDe(d);
      expect({for (var p = 0; p < 4; p++) dono['a$p']}.length, 2);
    });

    test('produto gigante não é dividido (desequilíbrio aceito)', () {
      final itens = [
        it('G', 'LOC:A', 'GC:P', 100), // um só produto, maior que tudo
        it('X', 'LOC:B', 'GC:Q', 5),
        it('Y', 'LOC:C', 'GC:R', 5),
      ];
      final d = distribuirPorLocal(itens, ['a', 'b']);
      conferirInvariantes(itens, ['a', 'b'], d);
      final dono = donoDe(d);
      // Os dois locais leves vão para quem não pegou o gigante.
      expect(dono['X'], isNot(dono['G']));
      expect(dono['Y'], isNot(dono['G']));
    });

    test('limite de carga: máx ≤ parte justa + maior unidade entregue', () {
      final itens = <ItemDistribuicaoC3>[];
      var n = 0;
      for (var l = 0; l < 23; l++) {
        final produtos = 1 + l % 4;
        for (var p = 0; p < produtos; p++) {
          itens.add(it('i${n++}', 'LOC:$l', 'GC:$p', (1 + (l * 7 + p) % 13)
              .toDouble()));
        }
      }
      final uids = ['a', 'b', 'c', 'd', 'e'];
      final d = distribuirPorLocal(itens, uids);
      conferirInvariantes(itens, uids, d);
      final total = itens.fold(0.0, (s, x) => s + x.esforco);
      final parte = total / uids.length;
      double maiorLocal = 0;
      final porLocal = <String, double>{};
      for (final x in itens) {
        porLocal[x.local] = (porLocal[x.local] ?? 0) + x.esforco;
      }
      for (final v in porLocal.values) {
        if (v > maiorLocal) maiorLocal = v;
      }
      for (final u in uids) {
        expect(carga(d, u, itens), lessThanOrEqualTo(parte + maiorLocal),
            reason: u);
      }
    });

    test('determinística: mesma entrada, mesma saída (sem sorteio)', () {
      final itens = [
        for (var i = 0; i < 30; i++)
          it('i$i', 'LOC:${i % 6}', 'GC:${i % 4}', (1 + i % 5).toDouble()),
      ];
      final a = distribuirPorLocal(itens, ['c', 'a', 'b']);
      final b = distribuirPorLocal(itens.reversed.toList(), ['b', 'c', 'a']);
      expect(a, b);
    });

    test('lista de cada pessoa em ordem local → produto → linha', () {
      final itens = [
        it('3', 'LOC:B', 'GC:Z', 1),
        it('1', 'LOC:A', 'GC:Y', 1),
        it('2', 'LOC:A', 'GC:X', 1),
      ];
      final d = distribuirPorLocal(itens, ['u']);
      expect(d['u'], ['2', '1', '3']);
    });

    test('mais pessoas que locais: todos aparecem, alguns com zero', () {
      final itens = [it('1', 'LOC:A', 'GC:P', 3), it('2', 'LOC:B', 'GC:P', 3)];
      final d = distribuirPorLocal(itens, ['a', 'b', 'c', 'd']);
      conferirInvariantes(itens, ['a', 'b', 'c', 'd'], d);
      expect(d.values.where((v) => v.isEmpty).length, 2);
    });

    test('redistribuição (só pendentes) não repete nem perde linha', () {
      final itens = [
        for (var i = 0; i < 12; i++)
          it('i$i', 'LOC:${i % 4}', 'GC:${i % 3}', 2),
      ];
      // Linhas i0..i3 já sincronizadas ficam fora; o resto é redistribuído.
      final pendentes = itens.skip(4).toList();
      final d = distribuirPorLocal(pendentes, ['a', 'b']);
      conferirInvariantes(pendentes, ['a', 'b'], d);
    });

    test('sem participantes: erro', () {
      expect(() => distribuirPorLocal([it('1', 'L', 'P', 1)], const []),
          throwsArgumentError);
    });
  });

  group('C3-D — itemDistribuicaoDe (linha do comparativo)', () {
    TotaisRodada q(double v) => TotaisRodada(quantidade: v, cheio: v);
    LinhaComparativo l({
      Natureza nat = Natureza.gas,
      String cod = 'P1',
      String? lote = 'L1',
      String? localId = 'ENCH_OXI',
      String prateleira = '',
      double? c1 = 6,
      double? c2 = 5,
    }) =>
        LinhaComparativo(
          chave: '$nat|$cod|$lote|$localId|$prateleira',
          natureza: nat,
          codigo: cod,
          lote: lote,
          localId: localId,
          localNome: 'Nome visível qualquer',
          prateleira: prateleira,
          c1: c1 == null ? null : q(c1),
          c2: c2 == null ? null : q(c2),
          resultado: ResultadoLinha.emAnalise,
        );

    test('Gás: local = localizacaoId (não o nome); esforço = max(C1, C2)',
        () {
      final x = itemDistribuicaoDe(l());
      expect(x.local, 'LOC:ENCH_OXI');
      expect(x.produto, 'GC:P1');
      expect(x.esforco, 6);
    });
    test('Gás e Cilindro do mesmo código no mesmo local: mesmo produto', () {
      final g = itemDistribuicaoDe(l());
      final c = itemDistribuicaoDe(l(nat: Natureza.cilindro, lote: null));
      expect(c.local, g.local);
      expect(c.produto, g.produto);
    });
    test('Material: local = ÁREA; a prateleira é o pacote dentro dela', () {
      final x = itemDistribuicaoDe(
          l(nat: Natureza.material, prateleira: ' a-12 ', localId: 'deposito'));
      expect(x.local, 'LOC:DEPOSITO');
      expect(x.produto, 'PRAT:A-12');
    });
    test('Material sem área: a prateleira vira o local', () {
      final ml = LinhaComparativo(
        chave: 'M|x',
        natureza: Natureza.material,
        codigo: 'P1',
        prateleira: '2A3',
        c1: q(1),
        c2: q(2),
        resultado: ResultadoLinha.emAnalise,
      );
      expect(itemDistribuicaoDe(ml).local, 'PRAT:2A3');
    });
    test('piloto 009: 2 áreas de material, 2 pessoas → uma área para cada',
        () {
      LinhaComparativo m(String area, String prat, String cod, double v) =>
          LinhaComparativo(
            chave: 'MAT:$cod|$prat',
            natureza: Natureza.material,
            codigo: cod,
            localId: area,
            localNome: area,
            prateleira: prat,
            c1: q(v),
            c2: q(v + 1),
            resultado: ResultadoLinha.emAnalise,
          );
      final linhas = [
        m('DEPOSITO', '2A3', '50000869', 5),
        m('DEPOSITO', '5T4', '50000987', 2),
        m('DEPOSITO', '7Y7', '10000109', 6),
        m('DEPOSITO', '3E3', '50000874', 6),
        m('DESCARTAVEIS', '4F5', '30014292', 4),
        m('DESCARTAVEIS', '4G6', '30014294', 4),
        m('DESCARTAVEIS', '8K7', '30014291', 4),
      ];
      final itens = linhas.map(itemDistribuicaoDe).toList();
      final d = distribuirPorLocal(itens, ['a', 'b']);
      final dono = donoDe(d);
      final porArea = <String, Set<String>>{};
      for (final x in itens) {
        porArea.putIfAbsent(x.local, () => {}).add(dono[x.id]!);
      }
      expect(porArea['LOC:DEPOSITO']!.length, 1);
      expect(porArea['LOC:DESCARTAVEIS']!.length, 1);
      expect(porArea['LOC:DEPOSITO'], isNot(porArea['LOC:DESCARTAVEIS']));
    });
    test('só na C1 (C2 vazia) ou zero: esforço mínimo 1', () {
      expect(itemDistribuicaoDe(l(c1: 4, c2: null)).esforco, 4);
      expect(itemDistribuicaoDe(l(c1: 0, c2: 0)).esforco, 1);
    });
    test('sem localizacaoId: usa o nome do local como reserva', () {
      expect(itemDistribuicaoDe(l(localId: null)).local,
          'LOC:NOME VISÍVEL QUALQUER');
    });
  });

  test('aparelho: tarefas em ordem local → produto → lote', () {
    TarefaC3Local t(String id, String local, String cod, String lote) =>
        TarefaC3Local(
            docId: id,
            chave: id,
            tipo: 'gas',
            codigo: cod,
            lote: lote,
            localNome: local,
            versao: 1);
    final ts = [
      t('1', 'Enchimento', 'P2', 'L1'),
      t('2', 'Armazém', 'P9', 'L2'),
      t('3', 'Enchimento', 'P1', 'L2'),
      t('4', 'Armazém', 'P9', 'L1'),
      t('5', 'Enchimento', 'P1', 'L1'),
    ]..sort(ordemDeExecucaoC3);
    expect(ts.map((x) => x.docId), ['4', '2', '5', '3', '1']);
  });

  test('aparelho: material em ordem área → prateleira → produto', () {
    TarefaC3Local t(String id, String area, String prat, String cod) =>
        TarefaC3Local(
            docId: id,
            chave: id,
            tipo: 'material',
            codigo: cod,
            localNome: area,
            prateleira: prat,
            versao: 1);
    final ts = [
      t('1', 'DESCARTÁVEIS', '8K7', 'C'),
      t('2', 'DEPÓSITO', '7Y7', 'A'),
      t('3', 'DEPÓSITO', '3E3', 'B'),
      t('4', 'DESCARTÁVEIS', '4F5', 'D'),
    ]..sort(ordemDeExecucaoC3);
    expect(ts.map((x) => x.docId), ['3', '2', '4', '1']);
  });
}
