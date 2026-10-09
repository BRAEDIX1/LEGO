// test/comparativo_test.dart
// Comparativo C1 × C2 (funções puras) — L3: três consolidados.
//   MATERIAL → quantidade (código + lote + local + prateleira)
//   GÁS      → só cheios  (código + lote + local)
//   CILINDRO → cheios + vazios (produto/descrição do gás + local)
// Os testes usam a regra de PRODUÇÃO (sem classificador injetado).
// Rodar com: flutter test test/comparativo_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lego/models/sessao_contagem.dart';
import 'package:lego/services/c3.dart';
import 'package:lego/services/comparativo.dart';

LancResumo gas(String cod,
        {double cheio = 0,
        double vazio = 0,
        String lote = 'L1',
        String local = 'A',
        String desc = 'OXIGENIO CIL 10M3'}) =>
    LancResumo(
        codigo: cod,
        lote: lote,
        descricao: desc,
        cheio: cheio,
        vazio: vazio,
        quantidade: cheio + vazio,
        localId: local,
        localNome: 'Área $local',
        origem: origemGases);

LancResumo mat(String cod, double qtd,
        {String? lote, String local = 'A', String prat = 'P1'}) =>
    LancResumo(
        codigo: cod,
        lote: lote,
        quantidade: qtd,
        localId: local,
        localNome: 'Área $local',
        prateleira: prat,
        origem: origemMateriais);

List<LinhaComparativo> cmp(List<LancResumo> a, List<LancResumo> b) =>
    compararC1C2(a, b);

LinhaComparativo de(List<LinhaComparativo> ls, Natureza n) =>
    ls.singleWhere((l) => l.natureza == n);

void main() {
  group('Obrigatórios da orientação', () {
    test('1. material usa quantidade e não cheio/vazio', () {
      final l = de(
          cmp([mat('M1', 5)], [mat('M1', 5)]), Natureza.material);
      expect(l.resultado, ResultadoLinha.encerrada);
      expect(l.c1!.quantidade, 5);
      expect(l.c1!.cheio, 0);
      expect(l.c1!.vazio, 0);
      final d = de(cmp([mat('M1', 5)], [mat('M1', 4)]), Natureza.material);
      expect(d.motivo, MotivoAnalise.divergente);
    });

    test('2. material preserva prateleira e local', () {
      final r = cmp([mat('M1', 5, prat: 'P1'), mat('M1', 2, prat: 'P2')],
          [mat('M1', 5, prat: 'P1'), mat('M1', 3, prat: 'P2')]);
      expect(r.length, 2);
      final p2 = r.singleWhere((l) => l.prateleira == 'P2');
      expect(p2.motivo, MotivoAnalise.divergente);
      expect(p2.localNome, 'Área A');
      expect(r.singleWhere((l) => l.prateleira == 'P1').resultado,
          ResultadoLinha.encerrada);
    });

    test('3. 8+5 × 7+6: cilindro = consenso 13 × 13', () {
      final r = cmp([gas('G1', cheio: 8, vazio: 5)],
          [gas('G1', cheio: 7, vazio: 6)]);
      final cil = de(r, Natureza.cilindro);
      expect(cil.c1!.quantidade, 13);
      expect(cil.c2!.quantidade, 13);
      expect(cil.resultado, ResultadoLinha.encerrada);
    });

    test('4. mesmo caso: gás = divergência 8 × 7', () {
      final r = cmp([gas('G1', cheio: 8, vazio: 5)],
          [gas('G1', cheio: 7, vazio: 6)]);
      final g = de(r, Natureza.gas);
      expect(g.c1!.quantidade, 8);
      expect(g.c2!.quantidade, 7);
      expect(g.motivo, MotivoAnalise.divergente);
    });

    test('5. vazio não entra no consolidado de gás', () {
      final r = cmp([gas('G1', cheio: 3, vazio: 10)],
          [gas('G1', cheio: 3, vazio: 0)]);
      final g = de(r, Natureza.gas);
      expect(g.c1!.quantidade, 3);
      expect(g.resultado, ResultadoLinha.encerrada);
      // ...mas o físico diverge (13 × 3).
      expect(de(r, Natureza.cilindro).motivo, MotivoAnalise.divergente);
    });

    test('6. cheio e vazio entram juntos no consolidado de cilindros', () {
      final r = cmp([gas('G1', cheio: 2, vazio: 4)], [gas('G1', vazio: 6)]);
      final cil = de(r, Natureza.cilindro);
      expect(cil.c1!.quantidade, 6);
      expect(cil.c2!.quantidade, 6);
      expect(cil.resultado, ResultadoLinha.encerrada);
      expect(cil.c1!.cheio, 2);
      expect(cil.c1!.vazio, 4);
    });

    test('7. cilindro do mesmo produto em vários lançamentos consolida', () {
      final r = cmp([gas('OXI', cheio: 5), gas('OXI', vazio: 5)],
          [gas('OXI', cheio: 2, vazio: 8)]);
      final cil = r.where((l) => l.natureza == Natureza.cilindro).toList();
      expect(cil.length, 1);
      expect(cil.single.c1!.quantidade, 10);
      expect(cil.single.resultado, ResultadoLinha.encerrada);
      expect(cil.single.descricao, 'OXIGENIO CIL 10M3'); // a do gás
    });

    test('8. produtos de gás diferentes ficam em cilindros diferentes '
        '(decisão: descrição do gás, sem família física comum)', () {
      final r = cmp([
        gas('OXI', cheio: 5, desc: 'OXIGENIO CIL 10M3'),
        gas('ARG', cheio: 5, desc: 'ARGONIO CIL 10M3'),
      ], [
        gas('OXI', cheio: 5, desc: 'OXIGENIO CIL 10M3'),
        gas('ARG', cheio: 5, desc: 'ARGONIO CIL 10M3'),
      ]);
      final cil = r.where((l) => l.natureza == Natureza.cilindro).toList();
      expect(cil.length, 2);
      expect(cil.map((l) => l.codigo).toSet(), {'OXI', 'ARG'});
    });

    test('9. nenhuma correspondência é inventada entre produtos', () {
      expect(tipoCilindroDaDescricao('OXIGENIO CIL 10M3'), isNull);
      final cil = de(cmp([gas('X1', cheio: 2, desc: 'GAS ESPECIAL')], []),
          Natureza.cilindro);
      expect(cil.cilindroPorProduto, isTrue);
      expect(cil.codigo, 'X1');
      expect(cil.identificacao, 'X1');
      expect(cil.descricao, 'GAS ESPECIAL');
    });

    test('10. C3 material: só quantidade', () {
      expect(campoC3Para('material'), CampoC3.quantidade);
      final t = resultadoC3('material', quantidade: 4);
      expect(t.quantidade, 4);
      expect(t.cheio, 0);
      expect(t.vazio, 0);
    });

    test('11. C3 cilindro: cheio + vazio digitados, métrica = soma', () {
      expect(campoC3Para('cilindro'), CampoC3.cheioVazio);
      final t = resultadoC3('cilindro', cheio: 8, vazio: 5);
      expect(t.quantidade, 13);
      expect(t.cheio, 8);
      expect(t.vazio, 5);
    });

    test('12. C3 gás: cheio + vazio digitados, métrica = só cheios', () {
      expect(campoC3Para('gas'), CampoC3.cheioVazio);
      final t = resultadoC3('gas', cheio: 7, vazio: 3, volumeUnitario: 10);
      expect(t.quantidade, 7);
      expect(t.cheio, 7);
      expect(t.vazio, 3);
      expect(t.volume, 70);
    });

    test('C3 0 e 0 = não encontrado (só a C3 aceita)', () {
      expect(resultadoC3('gas').naoEncontrado, isTrue);
      expect(resultadoC3('cilindro').naoEncontrado, isTrue);
      expect(resultadoC3('material').naoEncontrado, isTrue);
      expect(resultadoC3('gas', vazio: 1).naoEncontrado, isFalse);
    });
  });

  group('Chaves do Djalma (09/10)', () {
    test('material = código + prateleira: locais/lotes diferentes somam', () {
      final r = cmp([
        mat('M1', 2, prat: 'P1', local: 'A', lote: 'X'),
        mat('M1', 3, prat: 'P1', local: 'B', lote: 'Y'),
      ], [
        mat('M1', 5, prat: 'P1', local: 'A'),
      ]);
      final m = de(r, Natureza.material);
      expect(m.chave, 'MAT:M1|P1');
      expect(m.c1!.quantidade, 5);
      expect(m.resultado, ResultadoLinha.encerrada);
      expect(m.lote, isNull);
    });
    test('gás = código + lote + localização; guarda volume contado', () {
      LancResumo g(double cheio, double? vol) => LancResumo(
          codigo: 'G1', lote: 'L1', cheio: cheio, localId: 'A',
          localNome: 'Área A', origem: origemGases, volume: vol);
      final r = cmp([g(3, 10), g(2, 10)], [g(5, 10)]);
      final linha = de(r, Natureza.gas);
      expect(linha.chave, 'GAS:G1|L1|A');
      expect(linha.c1!.quantidade, 5);
      expect(linha.c1!.volume, 50);
      expect(linha.volumeUnitario, 10);
      expect(LinhaComparativo.deMapa(linha.toMap()).volumeUnitario, 10);
    });
    test('gás sem volume no cadastro: volume vazio', () {
      final r = cmp([gas('G1', cheio: 2)], []);
      expect(de(r, Natureza.gas).c1!.volume, isNull);
    });
    test('cilindro = código + localização (sem lote)', () {
      final r = cmp([gas('G1', cheio: 1, lote: 'A'), gas('G1', vazio: 1, lote: 'B')],
          [gas('G1', cheio: 2, lote: 'A')]);
      final c = de(r, Natureza.cilindro);
      expect(c.chave, 'CIL:G1|A');
      expect(c.lote, isNull);
      expect(c.resultado, ResultadoLinha.encerrada);
    });
  });

  group('Um lançamento de gás alimenta gás e cilindro', () {
    test('gera duas linhas; material gera uma', () {
      expect(cmp([gas('G1', cheio: 1)], []).length, 2);
      expect(cmp([mat('M1', 1)], []).length, 1);
    });
    test('gás por lote: lotes diferentes, linhas diferentes', () {
      final r = cmp([gas('G1', cheio: 2, lote: 'A')],
          [gas('G1', cheio: 2, lote: 'B')]);
      final g = r.where((l) => l.natureza == Natureza.gas).toList();
      expect(g.length, 2);
      // O cilindro físico não tem lote: 2 × 2 no mesmo local.
      expect(de(r, Natureza.cilindro).resultado, ResultadoLinha.encerrada);
    });
    test('localização separa todos os consolidados', () {
      final r = cmp([gas('G1', cheio: 2, local: 'A')],
          [gas('G1', cheio: 2, local: 'B')]);
      expect(r.length, 4);
      expect(r.every((l) => l.emAnalise), isTrue);
    });
  });

  group('Classificação material × gás', () {
    test('origem do cadastro manda', () {
      const l = LancResumo(codigo: 'X', quantidade: 3, origem: origemGases);
      expect(l.ehGas, isTrue);
    });
    test('sem cadastro: cheio/vazio = gás; só quantidade = material', () {
      expect(const LancResumo(codigo: 'X', cheio: 1).ehGas, isTrue);
      expect(const LancResumo(codigo: 'X', quantidade: 1).ehGas, isFalse);
    });
    test('deMapa lê local, prateleira e descrição', () {
      final l = LancResumo.deMapa({
        'codigo': 'M1',
        'prateleira': 'p3',
        'localizacaoId': 'ENCH',
        'localizacaoNome': 'Enchimento',
        'descricao': 'ABC',
      })!;
      expect(l.prateleira, 'P3');
      expect(l.localNome, 'Enchimento');
      expect(l.descricao, 'ABC');
    });
    test('comOrigem completa a descrição pelo cadastro', () {
      const l = LancResumo(codigo: 'G', cheio: 1);
      final c = l.comOrigem(origemGases, descricaoCadastro: 'OXIGENIO CIL 10M3');
      expect(c.descricao, 'OXIGENIO CIL 10M3');
      expect(c.origem, origemGases);
    });
  });

  group('Escolha da C3 (um consolidado)', () {
    test('linha fora da C3: sem valor final, não conta como pendente', () {
      final base = de(cmp([mat('M1', 1)], [mat('M1', 2)]), Natureza.material);
      final fora = LinhaComparativo.deMapa({...base.toMap(), 'c3_fora': true});
      expect(fora.naC3, isFalse);
      expect(fora.pendenteAtual, isFalse);
      expect(fora.semC3, isTrue);
      expect(fora.valorFinal, isNull);
      expect(fora.origemFinal, 'sem C3 (não selecionado)');
      expect(ResumoC3.de([fora]).total, 0);
    });
    test('resumo conta divergências por natureza', () {
      final r = ResumoComparativo.de(cmp(
          [gas('G1', cheio: 8, vazio: 5), mat('M1', 1)],
          [gas('G1', cheio: 7, vazio: 6), mat('M1', 2)]));
      expect(r.divergenciasPor[Natureza.gas], 1);
      expect(r.divergenciasPor[Natureza.cilindro], 0);
      expect(r.divergenciasPor[Natureza.material], 1);
    });
  });

  group('B69: fechamento auditável por consolidado', () {
    List<LinhaComparativo> cenario() {
      // gás diverge (8×7), material diverge (1×2), cilindro consenso (13×13)
      final r = cmp([gas('G1', cheio: 8, vazio: 5), mat('M1', 1)],
          [gas('G1', cheio: 7, vazio: 6), mat('M1', 2)]);
      // Analista escolheu GASES: material fica fora; gás recontado.
      return [
        for (final l in r)
          LinhaComparativo.deMapa({
            ...l.toMap(),
            if (l.emAnalise) 'c3_fora': l.natureza != Natureza.gas,
            if (l.emAnalise && l.natureza == Natureza.gas)
              'c3': resultadoC3('gas', cheio: 8).toMap(),
          })
      ];
    }

    test('escolhido: recontado e resolvido', () {
      final g = resumoPorNatureza(cenario(), Natureza.gas)[Natureza.gas]!;
      expect(g.selecionada, isTrue);
      expect(g.divergencias, 1);
      expect(g.recontadas, 1);
      expect(g.resolvidas, 1);
      expect(g.texto, contains('1 recontada'));
    });
    test('não escolhido: "C3 não selecionada", nunca recontado', () {
      final m =
          resumoPorNatureza(cenario(), Natureza.gas)[Natureza.material]!;
      expect(m.selecionada, isFalse);
      expect(m.divergencias, 1);
      expect(m.recontadas, 0);
      expect(m.resolvidas, 0);
      expect(m.semC3, 1);
      expect(m.texto, endsWith('fora da C3 (informativo)'));
    });
    test('consolidado sem divergência aparece com zero', () {
      final c =
          resumoPorNatureza(cenario(), Natureza.gas)[Natureza.cilindro]!;
      expect(c.divergencias, 0);
      expect(c.texto, 'Cilindros: 0 divergência(s)');
    });
    test('CSV registra a C3 selecionada e "sem_c3"', () {
      final csv = resultadoCsv(cenario(), c3Selecionada: Natureza.gas);
      final ls = csv.trim().split('\n');
      expect(ls.first.endsWith(';c3_selecionada'), isTrue);
      expect(ls.skip(1).every((x) => x.endsWith(';gas')), isTrue);
      final mat = ls.firstWhere((x) => x.startsWith('material;'));
      expect(mat.contains(';sem C3 (não selecionado);sem_c3;'), isTrue);
    });
  });

  group('Persistência, C3 e planilha', () {
    test('toMap → deMapa preserva natureza, tipo, prateleira', () {
      final r = cmp([gas('G1', cheio: 1), mat('M1', 2, prat: 'P9')], []);
      for (final l in r) {
        final v = LinhaComparativo.deMapa(l.toMap());
        expect(v.natureza, l.natureza);
        expect(v.tipoCilindro, l.tipoCilindro);
        expect(v.prateleira, l.prateleira);
        expect(v.chave, l.chave);
      }
    });
    test('C3 soberana; não encontrado preserva evidência', () {
      final base = de(cmp([mat('M1', 2)], []), Natureza.material);
      final l = LinhaComparativo.deMapa({
        ...base.toMap(),
        'c3': const TotaisRodada(ocorrencias: 1, naoEncontrado: true).toMap()
      });
      expect(l.valorFinal!.quantidade, 0);
      expect(l.origemFinal, 'C3: não encontrado');
      expect(l.c1!.quantidade, 2);
    });
    test('consenso: final = C1', () {
      final l = de(cmp([mat('M1', 3)], [mat('M1', 3)]), Natureza.material);
      expect(l.valorFinal!.quantidade, 3);
      expect(l.origemFinal, 'C1 = C2');
    });
    test('id do documento não contém barra', () {
      expect(idDocumento('MAT:AR/20|L/1|X|P').contains('/'), isFalse);
    });
    test('CSV: natureza e local primeiro; decimal com vírgula', () {
      final csv = resultadoCsv(cmp([mat('M1', 1.5)], [mat('M1', 1.5)]));
      final ls = csv.trim().split('\n');
      expect(ls.first.startsWith('natureza;local;item;lote;prateleira'), isTrue);
      expect(ls[1].startsWith('material;Área A;M1;'), isTrue);
      expect(ls[1].contains('1,5'), isTrue);
      expect(ls[1].contains(';C1 = C2;resolvida;'), isTrue);
    });
  });

  group('L4: tipo do inventário', () {
    test('Materiais aceita só materiais', () {
      expect(SessaoContagem.origemPermitida('material', 'materiais'), isTrue);
      expect(SessaoContagem.origemPermitida('material', 'gases'), isFalse);
      expect(SessaoContagem.origemPermitida('material', null), isFalse);
    });
    test('Cilindros e Gases aceitam só gases', () {
      for (final n in ['cilindro', 'gas']) {
        expect(SessaoContagem.origemPermitida(n, 'gases'), isTrue);
        expect(SessaoContagem.origemPermitida(n, 'materiais'), isFalse);
      }
    });
    test('sem tipo (Simples ou inventário antigo) aceita tudo', () {
      expect(SessaoContagem.origemPermitida(null, 'gases'), isTrue);
      expect(SessaoContagem.origemPermitida(null, 'materiais'), isTrue);
    });
    test('o tipo sobrevive à sessão salva no aparelho', () {
      final s = SessaoContagem.completa(
        usuarioUid: 'u1',
        inventarioId: 'inv1',
        numero: 2,
        codigo: 'X_002',
        rodada: 'contagem_1',
        statusRodada: null,
        statusIndividual: null,
        natureza: 'gas',
      );
      final volta = SessaoContagem.fromJson(s.toJson())!;
      expect(volta.natureza, 'gas');
      expect(volta.aceitaOrigem('materiais'), isFalse);
      expect(volta.copyWith(statusIndividual: 'x').natureza, 'gas');
    });
    test('Natureza.name casa com o valor gravado no inventário', () {
      expect(NaturezaRotulo.deNome('material'), Natureza.material);
      expect(NaturezaRotulo.deNome('cilindro'), Natureza.cilindro);
      expect(NaturezaRotulo.deNome('gas'), Natureza.gas);
      expect(NaturezaRotulo.deNome(null), isNull);
    });
  });

  group('L5: Gases/Cilindros geram os dois; C3 segue o tipo', () {
    test('consolidados gerados por tipo', () {
      expect(consolidadosDoTipo(Natureza.material), {Natureza.material});
      expect(consolidadosDoTipo(Natureza.gas),
          {Natureza.gas, Natureza.cilindro});
      expect(consolidadosDoTipo(Natureza.cilindro),
          {Natureza.gas, Natureza.cilindro});
      expect(consolidadosDoTipo(null), Natureza.values.toSet());
    });
    test('inventário de Gases: 8+5 × 7+4 → só o gás vai para a C3', () {
      final r = cmp([gas('G1', cheio: 8, vazio: 5)],
          [gas('G1', cheio: 7, vazio: 4)]);
      expect(de(r, Natureza.cilindro).motivo, MotivoAnalise.divergente); // 13×11
      expect(de(r, Natureza.gas).motivo, MotivoAnalise.divergente); // 8×7
      expect(divergenciasParaC3(r, Natureza.gas), 1);
      expect(divergenciasParaC3(r, Natureza.cilindro), 1);
    });
    test('inventário de Gases com só o cilindro divergindo: C3 não necessária',
        () {
      final r = cmp([gas('G1', cheio: 8, vazio: 5)],
          [gas('G1', cheio: 8, vazio: 4)]);
      expect(divergenciasParaC3(r, Natureza.gas), 0);
      expect(divergenciasParaC3(r, Natureza.cilindro), 1);
    });
    test('B70: lançamento só de vazios não cria linha de gás com zero', () {
      final r = cmp([gas('G1', vazio: 1)], []);
      expect(r.where((l) => l.natureza == Natureza.gas), isEmpty);
      expect(de(r, Natureza.cilindro).c1!.quantidade, 1);
    });
    test('B72: cabeçalho mostra o tipo', () {
      final s = SessaoContagem.completa(
        usuarioUid: 'u1',
        inventarioId: 'inv1',
        numero: 2,
        codigo: 'X_002',
        rodada: 'contagem_1',
        statusRodada: null,
        statusIndividual: null,
        natureza: 'gas',
      );
      expect(s.rotuloCabecalho, startsWith('Inventário 002 | Gases | '));
    });
  });

  group('B73: informativas marcadas já na geração', () {
    test('Gases: gás consenso, cilindro divergente → C3 não necessária e '
        'cilindro "sem C3", nunca "pendente na C3"', () {
      final r = marcarForaDaC3(
          cmp([gas('G1', cheio: 8, vazio: 5)], [gas('G1', cheio: 8, vazio: 4)]),
          Natureza.gas);
      expect(divergenciasParaC3(r, Natureza.gas), 0); // C3 nao_necessaria
      final cil = de(r, Natureza.cilindro);
      expect(cil.emAnalise, isTrue);
      expect(cil.foraDaC3, isTrue);
      expect(cil.semC3, isTrue);
      expect(cil.pendenteAtual, isFalse);
      expect(cil.origemFinal, isNot('pendente na C3'));
      expect(ResumoC3.de(r).total, 0);
      // e sobrevive à gravação/leitura do Firestore:
      final volta = LinhaComparativo.deMapa(cil.toMap());
      expect(volta.foraDaC3, isTrue);
      expect(volta.semC3, isTrue);
    });
    test('Gases: gás e cilindro divergentes → antes de chamar a C3, gás '
        'pendente e cilindro informativo', () {
      final r = marcarForaDaC3(
          cmp([gas('G1', cheio: 8, vazio: 5)], [gas('G1', cheio: 7, vazio: 4)]),
          Natureza.gas);
      final g = de(r, Natureza.gas);
      final cil = de(r, Natureza.cilindro);
      expect(g.naC3, isTrue);
      expect(g.pendenteAtual, isTrue);
      expect(g.origemFinal, 'pendente na C3');
      expect(cil.naC3, isFalse);
      expect(cil.semC3, isTrue);
      expect(ResumoC3.de(r).total, 1);
      final csv = resultadoCsv(r, c3Selecionada: Natureza.gas);
      final linhaCil =
          csv.split('\n').firstWhere((x) => x.startsWith('cilindro;'));
      expect(linhaCil.contains(';sem_c3;'), isTrue);
    });
    test('sem tipo (inventário antigo): nada é marcado', () {
      final r = cmp([gas('G1', cheio: 8, vazio: 5)],
          [gas('G1', cheio: 7, vazio: 4)]);
      expect(marcarForaDaC3(r, null).any((l) => l.foraDaC3), isFalse);
    });
    test('consenso nunca é marcado', () {
      final r = marcarForaDaC3(
          cmp([mat('M1', 1)], [mat('M1', 1)]), Natureza.gas);
      expect(r.single.foraDaC3, isFalse);
    });
  });
}
