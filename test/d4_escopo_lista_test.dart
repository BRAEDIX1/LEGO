// test/d4_escopo_lista_test.dart
//
// D4 revisto (05/11/2026), teste 4: a mesma pessoa contou a C1 (já
// encerrada) e agora conta a C2 do MESMO inventário, no MESMO aparelho.
// Os lançamentos da C1 continuam no Hive (B28), mas a lista da tela da C2
// não pode mostrá-los: a contagem é às cegas.
//
// A lista do coletor (home_page.dart, _escopoLista + watchAllSorted) e o
// contador de pendentes da sessão (_observarPendentes) leem SÓ deste stream,
// com inventarioId + contagemId da sessão. O teste usa o repositório real
// sobre um Hive real em pasta temporária.
//
// Rodar com: flutter test test/d4_escopo_lista_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:lego/data/local/lanc_local.dart';
import 'package:lego/data/repositories/lancamentos_repository.dart';
import 'package:lego/models/inventario.dart' show Rodadas;

const _uid = 'd4_mesmo_operador';
const _inv = 'INV_D4';

LancLocal _lanc(String id, String rodada, String codigo, {int minuto = 0}) =>
    LancLocal(
      idLocal: id,
      uid: _uid,
      codigo: codigo,
      descricao: 'Item $codigo',
      unidade: 'UN',
      quantidade: 1,
      prateleira: '3E3',
      cheio: 0,
      vazio: 0,
      createdAtLocal: DateTime(2026, 11, 5, 9, minuto),
      status: LancStatus.synced,
      inventarioId: _inv,
      contagemId: rodada,
      localizacaoId: 'AREA_A',
      localizacaoNome: 'Área A',
    );

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('lego_d4_test');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(41)) Hive.registerAdapter(LancStatusAdapter());
    if (!Hive.isAdapterRegistered(42)) Hive.registerAdapter(LancLocalAdapter());
    if (!Hive.isAdapterRegistered(43)) Hive.registerAdapter(TipoRegistroAdapter());

    final box = await Hive.openBox<LancLocal>('lancamentos_$_uid');
    await box.putAll({
      // C1 (encerrada): sincronizados, continuam no aparelho.
      'C1a': _lanc('C1a', Rodadas.c1, 'MAT-100', minuto: 1),
      'C1b': _lanc('C1b', Rodadas.c1, 'MAT-200', minuto: 2),
      // C2 (em andamento): a mesma pessoa, depois do encerramento da C1.
      'C2a': _lanc('C2a', Rodadas.c2, 'MAT-100', minuto: 30),
      // Contagem Simples do mesmo operador: fora das duas.
      'S1': LancLocal(
        idLocal: 'S1',
        uid: _uid,
        codigo: 'MAT-900',
        descricao: 'Simples',
        unidade: 'UN',
        quantidade: 1,
        prateleira: '',
        cheio: 0,
        vazio: 0,
        createdAtLocal: DateTime(2026, 11, 5, 8),
        status: LancStatus.synced,
      ),
    });
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('sessão na C2: a lista mostra só a C2, nunca os lançamentos da C1',
      () async {
    final repo = LancamentosRepository(uid: _uid);
    final lista = await repo
        .watchAllSorted(inventarioId: _inv, contagemId: Rodadas.c2)
        .first;
    expect(lista.map((l) => l.idLocal), ['C2a']);
    expect(lista.every((l) => l.contagemId == Rodadas.c2), isTrue);
  });

  test('os lançamentos da C1 continuam no aparelho, no escopo da C1', () async {
    final repo = LancamentosRepository(uid: _uid);
    final c1 = await repo
        .watchAllSorted(inventarioId: _inv, contagemId: Rodadas.c1)
        .first;
    expect(c1.map((l) => l.idLocal).toSet(), {'C1a', 'C1b'});
  });

  test('um lançamento novo da C1 não entra na lista da C2', () async {
    final repo = LancamentosRepository(uid: _uid);
    final emitidas = <List<String>>[];
    final sub = repo
        .watchAllSorted(inventarioId: _inv, contagemId: Rodadas.c2)
        .listen((l) => emitidas.add([for (final x in l) x.idLocal]));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final box = Hive.box<LancLocal>('lancamentos_$_uid');
    await box.put('C1c', _lanc('C1c', Rodadas.c1, 'MAT-300', minuto: 3));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(emitidas, isNotEmpty);
    for (final e in emitidas) {
      expect(e, ['C2a']);
    }
  });
}
