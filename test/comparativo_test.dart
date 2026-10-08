// test/comparativo_test.dart
// Entrega 1: comparativo C1 × C2 (funções puras).
// Rodar com: flutter test test/comparativo_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lego/services/comparativo.dart';

LancResumo tag(String t, {String cod = 'OX10', double cheio = 1, double vazio = 0}) =>
    LancResumo(tag: t, codigo: cod, quantidade: 1, cheio: cheio, vazio: vazio);

LancResumo mat(String cod, double qtd, {String? lote, double cheio = 0, double vazio = 0}) =>
    LancResumo(codigo: cod, lote: lote, quantidade: qtd, cheio: cheio, vazio: vazio);

LinhaComparativo linha(List<LinhaComparativo> ls, String chave) =>
    ls.firstWhere((l) => l.chave == chave);

void main() {
  group('LancResumo.deMapa', () {
    test('com tag → chave TAG', () {
      final l = LancResumo.deMapa({'tag': ' 000123456 ', 'codigo': 'OX10'})!;
      expect(l.chave, 'TAG:000123456');
      expect(l.tipo, TipoChave.tag);
    });
    test('tag vazia → chave Material + Lote', () {
      final l = LancResumo.deMapa(
          {'tag': '', 'codigo': 'AR20', 'lote': 'L1', 'quantidade': 3})!;
      expect(l.chave, 'MAT:AR20|L1');
      expect(l.quantidade, 3);
    });
    test('sem lote → lote vazio na chave', () {
      expect(LancResumo.deMapa({'codigo': 'AR20'})!.chave, 'MAT:AR20|');
    });
    test('sem tag e sem código → ignorado', () {
      expect(LancResumo.deMapa({'quantidade': 5}), isNull);
    });
    test('quantidade como texto é lida', () {
      expect(LancResumo.deMapa({'codigo': 'X', 'quantidade': '2.5'})!.quantidade,
          2.5);
    });
  });

  group('compararC1C2: TAG', () {
    test('mesma tag nas duas → encerrada', () {
      final r = compararC1C2([tag('1')], [tag('1')]);
      expect(r.single.resultado, ResultadoLinha.encerrada);
    });
    test('tag só em C1 → em análise (soC1)', () {
      final r = compararC1C2([tag('1')], []);
      expect(r.single.motivo, MotivoAnalise.soC1);
    });
    test('tag só em C2 → em análise (soC2)', () {
      final r = compararC1C2([], [tag('2')]);
      expect(r.single.motivo, MotivoAnalise.soC2);
    });
    test('mesma tag cheio × vazio → divergente', () {
      final r = compararC1C2([tag('1')], [tag('1', cheio: 0, vazio: 1)]);
      expect(r.single.motivo, MotivoAnalise.divergente);
    });
    test('tag lida duas vezes na mesma rodada conta como um cilindro', () {
      final r = compararC1C2([tag('1'), tag('1')], [tag('1')]);
      expect(r.single.resultado, ResultadoLinha.encerrada);
      expect(r.single.c1!.ocorrencias, 2);
    });
  });

  group('compararC1C2: Material + Lote', () {
    test('soma de vários lançamentos igual nas duas → encerrada', () {
      final r = compararC1C2(
          [mat('AR20', 3, lote: 'L1'), mat('AR20', 2, lote: 'L1')],
          [mat('AR20', 5, lote: 'L1')]);
      expect(r.single.resultado, ResultadoLinha.encerrada);
      expect(r.single.c1!.quantidade, 5);
    });
    test('quantidades diferentes → divergente', () {
      final r = compararC1C2([mat('AR20', 5)], [mat('AR20', 4)]);
      expect(r.single.motivo, MotivoAnalise.divergente);
    });
    test('mesmo material, lotes diferentes → duas linhas', () {
      final r = compararC1C2([mat('AR20', 1, lote: 'A')], [mat('AR20', 1, lote: 'B')]);
      expect(r.length, 2);
      expect(linha(r, 'MAT:AR20|A').motivo, MotivoAnalise.soC1);
      expect(linha(r, 'MAT:AR20|B').motivo, MotivoAnalise.soC2);
    });
    test('diferença abaixo de 0,0001 → encerrada', () {
      final r = compararC1C2([mat('X', 1.00001)], [mat('X', 1.0)]);
      expect(r.single.resultado, ResultadoLinha.encerrada);
    });
  });

  group('compararC1C2: mistura e ordem', () {
    test('em análise vêm antes das encerradas', () {
      final r = compararC1C2(
          [tag('1', cod: 'A'), mat('B', 1)], [tag('1', cod: 'A'), mat('B', 2)]);
      expect(r.first.emAnalise, isTrue);
      expect(r.last.emAnalise, isFalse);
    });
    test('C1 e C2 vazias → nenhuma linha', () {
      expect(compararC1C2([], []), isEmpty);
    });
  });

  group('ResumoComparativo', () {
    test('conta por resultado e motivo', () {
      final r = ResumoComparativo.de(compararC1C2(
        [tag('1'), tag('2'), mat('X', 1)],
        [tag('1'), tag('3'), mat('X', 2)],
      ));
      expect(r.total, 4);
      expect(r.encerradas, 1);
      expect(r.emAnalise, 3);
      expect(r.soC1, 1);
      expect(r.soC2, 1);
      expect(r.divergentes, 1);
    });
  });

  group('persistência', () {
    test('toMap → deMapa preserva a linha', () {
      final orig = compararC1C2([mat('AR/20', 2, lote: 'L1')], []).single;
      final volta = LinhaComparativo.deMapa(orig.toMap());
      expect(volta.chave, orig.chave);
      expect(volta.motivo, MotivoAnalise.soC1);
      expect(volta.c1!.quantidade, 2);
      expect(volta.c2, isNull);
    });
    test('id do documento não contém barra', () {
      expect(idDocumento('MAT:AR/20|L/1').contains('/'), isFalse);
    });
  });

  group('C3 e resultado final (Entrega 2)', () {
    LinhaComparativo comC3(LinhaComparativo l, TotaisRodada? c3) =>
        LinhaComparativo.deMapa({...l.toMap(), 'c3': c3?.toMap(), 'c3_quem': 'Ana'});

    test('encerrada: final = C1 (consenso)', () {
      final l = compararC1C2([mat('X', 3)], [mat('X', 3)]).single;
      expect(l.valorFinal!.quantidade, 3);
      expect(l.origemFinal, 'C1 = C2');
    });
    test('em análise sem C3: final pendente', () {
      final l = compararC1C2([mat('X', 3)], [mat('X', 4)]).single;
      expect(l.valorFinal, isNull);
      expect(l.origemFinal, 'pendente na C3');
    });
    test('em análise com C3: final = C3', () {
      final base = compararC1C2([mat('X', 3)], [mat('X', 4)]).single;
      final l = comC3(base, const TotaisRodada(quantidade: 4, ocorrencias: 1));
      expect(l.valorFinal!.quantidade, 4);
      expect(l.origemFinal, 'C3');
      expect(l.c3Quem, 'Ana');
      expect(l.contadaNaC3, isTrue);
    });
    test('tag não encontrada na C3 → final zero', () {
      final base = compararC1C2([tag('9')], []).single;
      final l = comC3(base, const TotaisRodada(ocorrencias: 1));
      expect(l.valorFinal!.quantidade, 0);
    });
    test('ResumoC3 conta contadas e pendentes', () {
      final ls = compararC1C2([mat('A', 1), mat('B', 1), mat('C', 1)],
          [mat('A', 2), mat('B', 2), mat('C', 1)]);
      final a = ls.firstWhere((l) => l.codigo == 'A');
      final atual = [
        for (final l in ls)
          l.codigo == 'A' ? comC3(a, const TotaisRodada(quantidade: 2)) : l
      ];
      final r = ResumoC3.de(atual);
      expect(r.total, 2);
      expect(r.contadas, 1);
      expect(r.pendentes, 1);
    });
    test('CSV: cabeçalho, separador ; e decimal com vírgula', () {
      final csv = resultadoCsv(compararC1C2([mat('X', 1.5)], [mat('X', 1.5)]));
      final linhas = csv.trim().split('\n');
      expect(linhas.first.startsWith('tipo;tag;codigo;lote'), isTrue);
      expect(linhas[1].contains('1,5'), isTrue);
      expect(linhas[1].contains(';C1 = C2;resolvida;'), isTrue);
    });
  });

  group('A1 / A3 / não encontrado (Entrega 3)', () {
    test('A3: mesma TAG cheio e vazio na C1 → conflito, vai para a C3', () {
      final r = compararC1C2(
          [tag('7'), tag('7', cheio: 0, vazio: 1)], [tag('7')]);
      expect(r.single.motivo, MotivoAnalise.conflito);
      expect(r.single.c1!.conflito, isTrue);
    });
    test('A3: duplicata idêntica não é conflito', () {
      final r = compararC1C2([tag('7'), tag('7')], [tag('7')]);
      expect(r.single.resultado, ResultadoLinha.encerrada);
    });
    test('A3: conflito em material (sem TAG) não existe: soma normal', () {
      final r = compararC1C2(
          [mat('X', 1, cheio: 1), mat('X', 1, vazio: 1)],
          [mat('X', 2, cheio: 1, vazio: 1)]);
      expect(r.single.resultado, ResultadoLinha.encerrada);
    });
    test('A1: divergente sem C3 é pendente; com C3 é resolvida', () {
      final base = compararC1C2([mat('X', 1)], [mat('X', 2)]).single;
      expect(base.pendenteAtual, isTrue);
      expect(base.resolvida, isFalse);
      final com = LinhaComparativo.deMapa(
          {...base.toMap(), 'c3': const TotaisRodada(quantidade: 2).toMap()});
      expect(com.emAnalise, isTrue); // divergência original preservada
      expect(com.pendenteAtual, isFalse);
      expect(com.resolvida, isTrue);
    });
    test('não encontrado na C3: final zero e origem explícita', () {
      final base = compararC1C2([tag('1')], []).single;
      final l = LinhaComparativo.deMapa({
        ...base.toMap(),
        'c3': const TotaisRodada(ocorrencias: 1, naoEncontrado: true).toMap()
      });
      expect(l.valorFinal!.quantidade, 0);
      expect(l.origemFinal, 'C3: não encontrado');
      expect(l.c1!.quantidade, 1); // evidência da C1 preservada
    });
    test('conflitos aparecem no resumo', () {
      final r = ResumoComparativo.de(
          compararC1C2([tag('7'), tag('7', cheio: 0, vazio: 1)], []));
      expect(r.conflitos, 1);
    });
  });

  group('B63: mesma TAG com códigos diferentes', () {
    test('C1 código A × C2 código B → conflito (C3)', () {
      final r = compararC1C2([tag('5', cod: 'A')], [tag('5', cod: 'B')]);
      expect(r.single.motivo, MotivoAnalise.conflito);
    });
    test('na mesma rodada, dois códigos para a mesma TAG → conflito', () {
      final r = compararC1C2(
          [tag('5', cod: 'A'), tag('5', cod: 'B')], [tag('5', cod: 'A')]);
      expect(r.single.motivo, MotivoAnalise.conflito);
      expect(r.single.c1!.conflito, isTrue);
    });
    test('mesmo código nas duas → segue a regra normal (consenso)', () {
      final r = compararC1C2([tag('5', cod: 'A')], [tag('5', cod: 'A')]);
      expect(r.single.resultado, ResultadoLinha.encerrada);
    });
    test('códigos persistem no toMap/deMapa', () {
      final l = compararC1C2([tag('5', cod: 'A')], []).single;
      expect(LinhaComparativo.deMapa(l.toMap()).c1!.codigos, {'A'});
    });
  });
}
