// test/c3_test.dart
// Entrega 3: distribuição justa, tarefas locais e decisão de sincronização.
// Rodar com: flutter test test/c3_test.dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lego/services/c3.dart';

List<int> tamanhos(Map<String, List<String>> d) =>
    d.values.map((v) => v.length).toList()..sort();

TarefaC3Local t(String id, {int v = 1, EstadoLocalC3 e = EstadoLocalC3.atribuida}) =>
    TarefaC3Local(
        docId: id, chave: id, tipo: 'material', codigo: id, versao: v, estado: e);

void main() {
  group('distribuirTarefas', () {
    List<String> n(int k) => [for (var i = 0; i < k; i++) 'L$i'];

    test('20 linhas / 3 usuários → 7, 7, 6', () {
      expect(tamanhos(distribuirTarefas(n(20), ['a', 'b', 'c'])), [6, 7, 7]);
    });
    test('47 / 4 → 12, 12, 12, 11', () {
      expect(tamanhos(distribuirTarefas(n(47), ['a', 'b', 'c', 'd'])),
          [11, 12, 12, 12]);
    });
    test('3 / 5 → 1, 1, 1, 0, 0 (todos aparecem)', () {
      final d = distribuirTarefas(n(3), ['a', 'b', 'c', 'd', 'e']);
      expect(d.length, 5);
      expect(tamanhos(d), [0, 0, 1, 1, 1]);
    });
    test('1 participante recebe tudo', () {
      expect(distribuirTarefas(n(9), ['a'])['a']!.length, 9);
    });
    test('nenhuma linha perdida nem repetida', () {
      final d = distribuirTarefas(n(50), ['a', 'b', 'c'], rng: Random(1));
      final todas = d.values.expand((x) => x).toList();
      expect(todas.length, 50);
      expect(todas.toSet().length, 50);
    });
    test('máx − mín ≤ 1 em vários tamanhos', () {
      for (var linhas = 0; linhas < 40; linhas++) {
        for (var us = 1; us < 7; us++) {
          final s = tamanhos(distribuirTarefas(
              n(linhas), [for (var i = 0; i < us; i++) 'u$i'],
              rng: Random(linhas * 7 + us)));
          expect(s.last - s.first <= 1, isTrue, reason: '$linhas/$us');
        }
      }
    });
    test('uid repetido conta uma vez', () {
      expect(distribuirTarefas(n(4), ['a', 'a', 'b']).length, 2);
    });
    test('sem participantes → erro', () {
      expect(() => distribuirTarefas(n(3), []), throwsArgumentError);
    });
  });

  group('mesclarTarefas', () {
    test('mesma versão mantém o trabalho local', () {
      final r = mesclarTarefas(
        doServidor: [t('A')],
        sincronizadasNoServidor: {},
        locais: [t('A', e: EstadoLocalC3.concluidaLocal)],
      );
      expect(r.single.estado, EstadoLocalC3.concluidaLocal);
    });
    test('versão nova reabre a tarefa', () {
      final r = mesclarTarefas(
        doServidor: [t('A', v: 2)],
        sincronizadasNoServidor: {},
        locais: [t('A', e: EstadoLocalC3.concluidaLocal)],
      );
      expect(r.single.estado, EstadoLocalC3.atribuida);
      expect(r.single.versao, 2);
    });
    test('sincronizada no servidor fica sincronizada', () {
      final r = mesclarTarefas(
          doServidor: [t('A')], sincronizadasNoServidor: {'A'}, locais: []);
      expect(r.single.estado, EstadoLocalC3.sincronizada);
    });
    test('concluída local que saiu da minha lista vira recusada', () {
      final r = mesclarTarefas(
        doServidor: [],
        sincronizadasNoServidor: {},
        locais: [t('A', e: EstadoLocalC3.concluidaLocal)],
      );
      expect(r.single.estado, EstadoLocalC3.recusada);
    });
    test('não concluída que saiu da lista some', () {
      final r = mesclarTarefas(
          doServidor: [], sincronizadasNoServidor: {}, locais: [t('A')]);
      expect(r, isEmpty);
    });
    test('json ida e volta', () {
      final x = t('A', v: 3, e: EstadoLocalC3.concluidaLocal)
          .copyWith(resultado: {'quantidade': 2.0});
      final y = TarefaC3Local.fromJson(x.toJson());
      expect(y.versao, 3);
      expect(y.estado, EstadoLocalC3.concluidaLocal);
      expect(y.resultado!['quantidade'], 2.0);
    });
  });

  group('decidirSync (B62)', () {
    (DecisaoSync, String?) d({
      String? st = 'em_andamento',
      String? resp = 'u1',
      int? vl = 1,
      String? sl = StatusTarefaC3.atribuida,
      String uid = 'u1',
      int vt = 1,
    }) =>
        decidirSync(
            statusC3Inventario: st,
            responsavelLinha: resp,
            versaoLinha: vl,
            statusLinha: sl,
            uid: uid,
            versaoTarefa: vt);

    test('tudo certo → aceita', () => expect(d().$1, DecisaoSync.aceitar));
    test('distribuindo → aguarda (não recusa)',
        () => expect(d(st: 'distribuindo').$1, DecisaoSync.aguardar));
    test('redistribuindo → aguarda (não recusa)',
        () => expect(d(st: 'redistribuindo', vl: 2).$1, DecisaoSync.aguardar));
    test('C3 encerrada → recusa',
        () => expect(d(st: 'encerrada').$1, DecisaoSync.recusar));
    test('já sincronizada → recusa',
        () => expect(d(sl: StatusTarefaC3.sincronizada).$1, DecisaoSync.recusar));
    test('outro responsável → recusa',
        () => expect(d(resp: 'u2').$1, DecisaoSync.recusar));
    test('versão antiga (redistribuída) → recusa com motivo', () {
      final r = d(vl: 2, vt: 1);
      expect(r.$1, DecisaoSync.recusar);
      expect(r.$2, contains('versão'));
    });
  });

  group('Item 4: tarefas C3 não ficam eternizadas no aparelho', () {
    test('mesmo inventário com a C3 aberta → mantém', () {
      for (final st in [
        'aguardando_participantes',
        'distribuindo',
        'em_andamento',
        'redistribuindo'
      ]) {
        expect(
            tarefasLocaisAindaValidas(
                inventarioLocal: 'A', inventarioAtivoId: 'A', statusC3Ativo: st),
            isTrue);
      }
    });
    test('C3 encerrada ou não necessária → descarta', () {
      for (final st in ['encerrada', 'nao_necessaria', 'pendente', null]) {
        expect(
            tarefasLocaisAindaValidas(
                inventarioLocal: 'A', inventarioAtivoId: 'A', statusC3Ativo: st),
            isFalse);
      }
    });
    test('outro inventário ativo ou nenhum → descarta', () {
      expect(
          tarefasLocaisAindaValidas(
              inventarioLocal: 'A',
              inventarioAtivoId: 'B',
              statusC3Ativo: 'em_andamento'),
          isFalse);
      expect(
          tarefasLocaisAindaValidas(
              inventarioLocal: 'A',
              inventarioAtivoId: null,
              statusC3Ativo: null),
          isFalse);
    });
  });

  group('B77: participante com zero tarefas', () {
    test('3 tarefas / 5 participantes → 2 com zero, e podem finalizar', () {
      final uids = ['a', 'b', 'c', 'd', 'e'];
      final d = distribuirTarefas(['t1', 't2', 't3'], uids);
      final zero = [for (final u in uids) if ((d[u] ?? const []).isEmpty) u];
      expect(zero.length, 2);
      for (final u in zero) {
        expect(
            podeFinalizarSemTarefas(
                statusC3: 'em_andamento',
                participantes: uids,
                uid: u,
                atribuidasNoServidor: 0),
            isTrue);
      }
    });
    test('não finaliza "sem tarefas" se o servidor tem item meu', () {
      expect(
          podeFinalizarSemTarefas(
              statusC3: 'em_andamento',
              participantes: ['a'],
              uid: 'a',
              atribuidasNoServidor: 1),
          isFalse);
    });
    test('não finaliza fora da C3 em andamento ou sem participar', () {
      expect(
          podeFinalizarSemTarefas(
              statusC3: 'distribuindo',
              participantes: ['a'],
              uid: 'a',
              atribuidasNoServidor: 0),
          isFalse);
      expect(
          podeFinalizarSemTarefas(
              statusC3: 'em_andamento',
              participantes: ['b'],
              uid: 'a',
              atribuidasNoServidor: 0),
          isFalse);
    });
    test('lista local vazia nunca habilita o "Finalizar" normal', () {
      expect(todasSincronizadas(const []), isFalse);
    });
  });
}
