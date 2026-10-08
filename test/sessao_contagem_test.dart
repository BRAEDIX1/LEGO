// test/sessao_contagem_test.dart
// Rodar com: flutter test test/sessao_contagem_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lego/models/inventario.dart';
import 'package:lego/models/participante.dart';
import 'package:lego/models/sessao_contagem.dart';

SessaoContagem _completa({
  String uid = 'userA',
  String? statusRodada = StatusRodada.emAndamento,
  String? statusIndividual = StatusParticipante.emAndamento,
  bool ativo = true,
}) =>
    SessaoContagem.completa(
      usuarioUid: uid,
      inventarioId: 'inv001',
      numero: 1,
      codigo: 'CMP_001_02102026',
      rodada: Rodadas.c1,
      statusRodada: statusRodada,
      statusIndividual: statusIndividual,
      inventarioAtivo: ativo,
    );

void main() {
  group('T18: podeLancar', () {
    test('Simples sempre pode e grava com IDs vazios (D1)', () {
      final s = SessaoContagem.simples('userA');
      expect(s.podeLancar, isTrue);
      expect(s.idsGravacao, ('', ''));
    });

    test('Completa em andamento pode e grava com IDs da sessão', () {
      final s = _completa();
      expect(s.podeLancar, isTrue);
      expect(s.idsGravacao, ('inv001', Rodadas.c1));
    });

    test('participação finalizada não pode (cenário 18)', () {
      final s = _completa(statusIndividual: StatusParticipante.finalizado);
      expect(s.podeLancar, isFalse);
      expect(s.motivoBloqueio, contains('finalizada'));
    });

    test('rodada encerrada pelo analista não pode', () {
      final s = _completa(statusRodada: StatusRodada.encerrada);
      expect(s.podeLancar, isFalse);
      expect(s.motivoBloqueio, contains('encerrada'));
    });

    test('inventário inativo não pode', () {
      expect(_completa(ativo: false).podeLancar, isFalse);
    });

    test('status individual desconhecido não pode', () {
      expect(_completa(statusIndividual: null).podeLancar, isFalse);
    });
  });

  group('B16: sessão pertence ao usuário', () {
    test('mesmo usuário', () {
      expect(_completa(uid: 'userA').pertenceA('userA'), isTrue);
    });
    test('outro usuário (cenário 1)', () {
      expect(_completa(uid: 'userA').pertenceA('userB'), isFalse);
    });
    test('sem usuário', () {
      expect(_completa().pertenceA(null), isFalse);
      expect(_completa().pertenceA(''), isFalse);
    });
  });

  group('T17: persistência local (cenário 2)', () {
    test('Completa: ida e volta preserva tudo', () {
      final s = _completa(statusIndividual: StatusParticipante.finalizado);
      final r = SessaoContagem.fromJson(s.toJson())!;
      expect(r.usuarioUid, 'userA');
      expect(r.isCompleta, isTrue);
      expect(r.inventarioId, 'inv001');
      expect(r.rodada, Rodadas.c1);
      expect(r.numero, 1);
      expect(r.statusIndividual, StatusParticipante.finalizado);
      expect(r.podeLancar, isFalse);
    });

    test('Simples: ida e volta', () {
      final r = SessaoContagem.fromJson(SessaoContagem.simples('u').toJson())!;
      expect(r.isSimples, isTrue);
      expect(r.usuarioUid, 'u');
    });

    test('schema desconhecido, JSON corrompido ou vazio → null', () {
      final m = _completa().toMap()..['schema_versao'] = 99;
      expect(SessaoContagem.fromMap(m), isNull);
      expect(SessaoContagem.fromJson('{quebrado'), isNull);
      expect(SessaoContagem.fromJson(null), isNull);
    });

    test('Completa sem inventário ou com rodada inválida → null', () {
      final semInv = _completa().toMap()..['inventario_id'] = '';
      final rodadaRuim = _completa().toMap()..['rodada'] = 'contagem_9';
      expect(SessaoContagem.fromMap(semInv), isNull);
      expect(SessaoContagem.fromMap(rodadaRuim), isNull);
    });
  });

  group('B23: escopo da lista', () {
    bool contem(String? inv, String? cont, [String? erro]) =>
        SessaoContagem.escopoContem(
          lancInventarioId: inv,
          lancContagemId: cont,
          lancErrorCode: erro,
          inventarioId: 'inv001',
          contagemId: Rodadas.c1,
        );

    test('mesmo inventário e rodada aparece (cenário 15)', () {
      expect(contem('inv001', Rodadas.c1), isTrue);
    });
    test('C2 ou inventário anterior não aparece (cenário 16)', () {
      expect(contem('inv001', Rodadas.c2), isFalse);
      expect(contem('inv000', Rodadas.c1), isFalse);
      expect(contem('', ''), isFalse); // Contagem Simples
    });
    test('tombstone não aparece (B21)', () {
      expect(contem('inv001', Rodadas.c1, kDeletePending), isFalse);
    });
  });

  group('B38: escopo da lista na Simples', () {
    bool simplesContem(String? inv, String? cont, [String? erro]) =>
        SessaoContagem.escopoContem(
          lancInventarioId: inv,
          lancContagemId: cont,
          lancErrorCode: erro,
          inventarioId: '',
          contagemId: '',
        );

    test('só registros sem inventário/rodada; Completa e tombstone não aparecem', () {
      expect(simplesContem('', ''), isTrue);
      expect(simplesContem(null, null), isTrue); // registros antigos
      expect(simplesContem('inv001', Rodadas.c1), isFalse);
      expect(simplesContem('', '', kDeletePending), isFalse);
    });
  });

  group('§10: cabeçalho', () {
    test('Completa', () {
      expect(_completa().rotuloCabecalho, 'Inventário 001 | C1 | Em andamento');
      expect(
        _completa(statusIndividual: StatusParticipante.finalizado).rotuloCabecalho,
        'Inventário 001 | C1 | Finalizado',
      );
    });
    test('Simples', () {
      expect(SessaoContagem.simples('u').rotuloCabecalho, 'Contagem Simples');
    });
  });
}
