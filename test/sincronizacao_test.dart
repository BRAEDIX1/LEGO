// test/sincronizacao_test.dart
//
// Pacote 1 (fila offline): motor de sincronização, classificação de falhas,
// painel de pendências e reprodução do incidente do inventário oficial:
// lançamento local → falha de rede → erro → reconexão → reenvio →
// encerramento excepcional → recuperação posterior.
//
// Rodar com: flutter test test/sincronizacao_test.dart

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lego/data/local/lanc_local.dart';
import 'package:lego/data/local/registro_sync.dart';
import 'package:lego/data/repositories/lancamentos_repository.dart';
import 'package:lego/models/sessao_contagem.dart' show kDeletePending;
import 'package:lego/services/sincronizacao/falha_sync.dart';
import 'package:lego/services/acompanhamento_sync_service.dart';
import 'package:lego/services/sincronizacao/motor_sincronizacao.dart';
import 'package:lego/services/sincronizacao/observador_pendencias.dart';
import 'package:lego/services/sincronizacao/pendencias_sync.dart';
import 'package:lego/services/sincronizacao/status_sync_aparelho.dart';

FirebaseException fe(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code, message: code);

/// Firestore falso: grava num mapa; cada chamada pode falhar conforme
/// [falhaGravar] / [falhaRecuperacao].
class RemotoFalso implements RemotoLancamentos {
  final Map<String, Map<String, dynamic>> docs = {};
  final Map<String, Map<String, dynamic>> recuperacao = {};
  final List<String> apagados = [];
  int chamadasGravar = 0;
  int chamadasRecuperacao = 0;
  Object? Function(String docId)? falhaGravar;
  Object? Function(String docId)? falhaApagar;
  Object? Function(String docId)? falhaRecuperacao;
  /// Gravação que nunca responde (simula Firestore sem conexão).
  bool travarGravar = false;
  /// rev2: o SDK enfileira a escrita (ela CHEGA ao servidor), mas a Future
  /// não responde a tempo — o tempo esgotado não cancela a escrita.
  bool enfileirarETravar = false;

  @override
  Future<void> gravar(String docId, Map<String, dynamic> dados) async {
    chamadasGravar++;
    if (travarGravar) return Completer<void>().future;
    if (enfileirarETravar) {
      docs[docId] = {...?docs[docId], ...dados};
      return Completer<void>().future;
    }
    final f = falhaGravar?.call(docId);
    if (f != null) throw f;
    docs[docId] = {...?docs[docId], ...dados};
  }

  @override
  Future<void> apagar(String docId) async {
    final f = falhaApagar?.call(docId);
    if (f != null) throw f;
    apagados.add(docId);
    docs.remove(docId);
  }

  @override
  Future<Map<String, dynamic>?> lerOficial(String docId) async => docs[docId];

  @override
  Future<bool> recuperacaoExiste(String docId) async {
    final f = falhaRecuperacao?.call(docId);
    if (f != null) throw f;
    return recuperacao.containsKey(docId);
  }

  @override
  Future<void> gravarRecuperacao(String docId, Map<String, dynamic> dados) async {
    chamadasRecuperacao++;
    final f = falhaRecuperacao?.call(docId);
    if (f != null) throw f;
    recuperacao[docId] = dados;
  }
}

/// rev3: canal falso do informe (pulso + gravação).
class CanalFalso implements CanalStatusSync {
  bool falhar = false;
  DateTime hora = DateTime(2026, 10, 11, 12, 0);
  Future<void> Function()? aoPulsar;
  final List<Map<String, dynamic>> gravados = [];

  @override
  Future<DateTime> horaServidor(String uid) async {
    if (falhar) throw TimeoutException('sem conexão');
    await aoPulsar?.call();
    return hora;
  }

  /// rev4: false = gravação sem resposta do servidor no prazo.
  bool confirmar = true;

  @override
  Future<EntregaInforme> gravar(String uid, Map<String, dynamic> dados) async {
    gravados.add(dados);
    return confirmar ? EntregaInforme.confirmada : EntregaInforme.semConfirmacao;
  }
}

late Directory _dir;
var _seq = 0;

class Cenario {
  final String uid;
  final RemotoFalso remoto = RemotoFalso();
  DateTime relogio = DateTime(2026, 10, 11, 9, 0);
  late final LancamentosRepository repo = LancamentosRepository(uid: uid);
  late final RegistroSync registro = RegistroSync(uid);
  late final MotorSincronizacao motor = MotorSincronizacao(
    uid: uid,
    repo: repo,
    registro: registro,
    remoto: remoto,
    agora: () => relogio,
    limiteOperacao: const Duration(milliseconds: 200),
  );

  Cenario() : uid = 'u${++_seq}';

  Future<LancLocal> lancar({
    String id = 'L1',
    String inventarioId = 'INV7',
    String contagemId = 'contagem_1',
    String codigo = '40000197',
    String lote = '2628300262',
    double cheio = 3,
    LancStatus status = LancStatus.pending,
    String? errorCode,
    DateTime? em,
  }) async {
    final l = LancLocal(
      idLocal: id,
      uid: uid,
      codigo: codigo,
      descricao: 'Oxigenio Medicinal Cil T 10M3',
      unidade: 'CIL',
      quantidade: 0,
      prateleira: '',
      cheio: cheio,
      vazio: 0,
      lote: lote,
      createdAtLocal: em ?? relogio,
      status: status,
      errorCode: errorCode,
      inventarioId: inventarioId,
      contagemId: contagemId,
      localizacaoId: 'BUFFER_OXIGENIO',
      localizacaoNome: 'BUFFER_OXIGENIO',
      nomeCompleto: 'Operador Teste',
    );
    final box = await Hive.openBox<LancLocal>('lancamentos_$uid');
    await box.put(id, l);
    return l;
  }

  Future<LancLocal> lanc(String id) async => (await repo.obter(id))!;
  Future<EstadoSync?> estado(String id) => registro.de(id);
  Future<List<Pendencia>> pendencias() async =>
      montarPendencias(await repo.listarTodos(), await registro.todos());
}

void main() {
  setUpAll(() async {
    _dir = await Directory.systemTemp.createTemp('lego_sync_test');
    Hive.init(_dir.path);
    if (!Hive.isAdapterRegistered(41)) Hive.registerAdapter(LancStatusAdapter());
    if (!Hive.isAdapterRegistered(42)) Hive.registerAdapter(LancLocalAdapter());
    if (!Hive.isAdapterRegistered(43)) Hive.registerAdapter(TipoRegistroAdapter());
  });

  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      _dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('T-SYNC-001 — classificação das falhas', () {
    test('rede, passageira e definitiva', () {
      expect(classificarFalha(fe('unavailable')).tipo, TipoFalhaSync.rede);
      expect(classificarFalha(fe('deadline-exceeded')).tipo, TipoFalhaSync.rede);
      expect(classificarFalha(fe('unauthenticated')).tipo, TipoFalhaSync.rede);
      expect(classificarFalha(TimeoutException('x')).codigo, 'timeout');
      expect(classificarFalha(const SocketException('x')).tipo,
          TipoFalhaSync.rede);
      expect(classificarFalha(fe('resource-exhausted')).tipo,
          TipoFalhaSync.transitorio);
      expect(classificarFalha(fe('aborted')).tipo, TipoFalhaSync.transitorio);
      expect(classificarFalha(StateError('x')).codigo, 'desconhecido');
      expect(classificarFalha(fe('permission-denied')).tipo,
          TipoFalhaSync.definitivo);
      expect(classificarFalha(fe('invalid-argument')).tipo,
          TipoFalhaSync.definitivo);
    });
    test('espera entre tentativas', () {
      expect(esperaAntesDeReenviar(TipoFalhaSync.rede, 1).inSeconds, 30);
      expect(esperaAntesDeReenviar(TipoFalhaSync.rede, 5).inSeconds, 600);
      expect(esperaAntesDeReenviar(TipoFalhaSync.rede, 50).inSeconds, 600);
      expect(esperaAntesDeReenviar(TipoFalhaSync.transitorio, 1).inSeconds, 60);
      expect(
          esperaAntesDeReenviar(TipoFalhaSync.transitorio, 30).inSeconds, 3600);
    });
  });

  group('T-SYNC-002 — INCIDENTE do inventário oficial, ponta a ponta', () {
    test(
        'lançamento local → falha de rede → registro em erro → reconexão → '
        'reenvio → encerramento excepcional → recuperação posterior', () async {
      final c = Cenario();
      // 1. Lançamento local (C1 do inventário 007).
      await c.lancar(id: 'A');
      await c.lancar(
          id: 'B',
          codigo: '40000618',
          lote: '2619700298',
          em: c.relogio.add(const Duration(seconds: 1)));

      // 2. Falha de rede durante o envio.
      c.remoto.falhaGravar = (_) => fe('unavailable');
      var r = await c.motor.executarAutomatico();
      expect(r!.map((x) => x.resultado),
          everyElement(ResultadoEnvio.rede));
      expect((await c.lanc('A')).status, LancStatus.pending,
          reason: 'falha de rede não tira da fila');
      var e = await c.estado('A');
      expect(e!.tentativas, 1);
      expect(e.codigo, 'unavailable');
      expect(e.proximaTentativa, c.relogio.add(const Duration(seconds: 30)));

      // Identificação individual (painel, só Hive).
      var p = await c.pendencias();
      expect(p.map((x) => x.lanc.idLocal), ['A', 'B']);
      expect(p.first.situacao, SituacaoPendencia.aguardandoReenvio);
      expect(p.first.lanc.codigo, '40000197');
      expect(p.first.lanc.lote, '2628300262');
      expect(p.first.lanc.localizacaoNome, 'BUFFER_OXIGENIO');

      // 3. Antes da próxima hora, o automático não insiste.
      final antes = c.remoto.chamadasGravar;
      await c.motor.executarAutomatico();
      expect(c.remoto.chamadasGravar, antes);

      // 4. Registro em ERRO no esquema antigo (o caso do incidente): status
      //    error sem motivo registrado. Antes ele nunca mais era reenviado.
      await c.registro.remover('B');
      final box = await Hive.openBox<LancLocal>('lancamentos_${c.uid}');
      await box.put('B',
          (await c.lanc('B')).copyWith(status: LancStatus.error, errorCode: 'x'));
      expect((await c.pendencias()).last.situacao,
          SituacaoPendencia.erroSemMotivo);

      // 5. Reconexão: tenta já (ignora a espera) e devolve o erro antigo à fila.
      c.remoto.falhaGravar = null;
      r = await c.motor.executarAutomatico(ignorarEspera: true);
      expect(r!.map((x) => x.resultado),
          everyElement(ResultadoEnvio.enviado));
      expect((await c.lanc('A')).status, LancStatus.synced);
      expect((await c.lanc('B')).status, LancStatus.synced);
      // Sem duplicidade: um documento por lançamento, id determinístico.
      expect(c.remoto.docs.keys.toSet(), {'${c.uid}_A', '${c.uid}_B'});
      expect(await c.pendencias(), isEmpty);

      // 6. Novos lançamentos ficam no aparelho e o analista ENCERRA a rodada
      //    à força: o servidor passa a recusar (regra B82/B86).
      await c.lancar(id: 'C', em: c.relogio.add(const Duration(minutes: 1)));
      c.remoto.falhaGravar = (_) => fe('permission-denied');
      r = await c.motor.executarAutomatico();
      expect(r!.single.resultado, ResultadoEnvio.definitivo);
      final lc = await c.lanc('C');
      expect(lc.status, LancStatus.error);
      expect(lc.errorCode, startsWith('permission-denied'));
      e = await c.estado('C');
      expect(e!.definitivo, isTrue);
      expect((await c.pendencias()).single.situacao,
          SituacaoPendencia.rejeitado);
      // O registro local NÃO é apagado.
      expect(await c.repo.obter('C'), isNotNull);

      // 7. Recuperação: a cópia vai para lancamentos_recuperacao, uma vez.
      expect(c.remoto.recuperacao.keys, ['${c.uid}_C']);
      final copia = c.remoto.recuperacao['${c.uid}_C']!;
      expect(copia['idLocal'], 'C');
      expect(copia['inventarioId'], 'INV7');
      expect(copia['contagemId'], 'contagem_1');
      expect(copia['motivo_codigo'], 'permission-denied');
      expect((await c.estado('C'))!.recuperacaoEnviadaEm, isNotNull);

      // Automático não insiste na recusa definitiva nem duplica a cópia.
      final g = c.remoto.chamadasGravar;
      c.relogio = c.relogio.add(const Duration(hours: 2));
      await c.motor.executarAutomatico(ignorarEspera: true);
      expect(c.remoto.chamadasGravar, g);
      expect(c.remoto.chamadasRecuperacao, 1);

      // 8. Recuperação posterior. rev1: o reenvio manual NÃO devolve uma
      //    recusa definitiva à coleção oficial (nem tenta); o caminho é a
      //    Recuperação, que já tem a cópia (não duplica).
      final m = await c.motor.reenviar(['C']);
      expect(m.single.resultado, ResultadoEnvio.rejeitadoNaoReenviado);
      expect(m.single.codigo, 'permission-denied');
      expect(c.remoto.chamadasGravar, g, reason: 'nenhuma escrita oficial');
      expect(await c.repo.obter('C'), isNotNull);
      final rec = await c.motor.recuperar(['C']);
      expect(rec.single.resultado, ResultadoEnvio.recuperacaoEnviada);
      expect(c.remoto.recuperacao.length, 1);
      expect(c.remoto.chamadasRecuperacao, 1);

      // Histórico registra a tentativa com o motivo e a Recuperação.
      final h = await c.registro.historico(idLocal: 'C');
      expect(h.where((x) => x.resultado == 'definitivo').length, 1);
      expect(h.any((x) => x.acao == 'recuperacao' && x.resultado == 'ok'),
          isTrue);
      expect(h.first.codigo ?? h.first.acao, isNotEmpty);
    });
  });

  test('T-SYNC-003 — passageira esgota as automáticas; reenvio manual envia',
      () async {
    final c = Cenario();
    await c.lancar(id: 'A');
    c.remoto.falhaGravar = (_) => fe('resource-exhausted');
    for (var i = 0; i < maxTentativasTransitorio; i++) {
      await c.motor.executarAutomatico();
      c.relogio = c.relogio.add(const Duration(hours: 2));
    }
    expect((await c.estado('A'))!.esgotado, isTrue);
    expect((await c.lanc('A')).status, LancStatus.error);
    expect((await c.pendencias()).single.situacao,
        SituacaoPendencia.erroReenvioManual);

    final antes = c.remoto.chamadasGravar;
    await c.motor.executarAutomatico(ignorarEspera: true);
    expect(c.remoto.chamadasGravar, antes, reason: 'esgotado = só manual');

    c.remoto.falhaGravar = null;
    final r = await c.motor.reenviar();
    expect(r.single.resultado, ResultadoEnvio.enviado);
    expect((await c.lanc('A')).status, LancStatus.synced);
    expect(c.remoto.docs.length, 1);
  });

  test('T-SYNC-004 — tempo esgotado não prende a fila nem a trava', () async {
    final c = Cenario();
    await c.lancar(id: 'A');
    await c.lancar(id: 'B', em: c.relogio.add(const Duration(seconds: 1)));
    c.remoto.travarGravar = true;
    final r = await c.motor.executarAutomatico();
    expect(r!.first.resultado, ResultadoEnvio.rede);
    expect(r.first.codigo, 'timeout');
    expect(r.last.resultado, ResultadoEnvio.naoTentado);
    expect(MotorSincronizacao.emExecucao(c.uid), isFalse);
    expect((await c.estado('B')), isNull, reason: 'não tentado não conta');
    expect((await c.lanc('A')).status, LancStatus.pending);
  });

  test('T-SYNC-005 — exclusão recusada continua exclusão (não ressuscita)',
      () async {
    final c = Cenario();
    await c.lancar(id: 'A', errorCode: kDeletePending);
    c.remoto.docs['${c.uid}_A'] = {'codigo': 'x'}; // ainda existe no servidor
    c.remoto.falhaApagar = (_) => fe('permission-denied');
    final r = await c.motor.executarAutomatico();
    expect(r!.single.resultado, ResultadoEnvio.definitivo);
    final l = await c.lanc('A');
    expect(l.errorCode, kDeletePending);
    expect(l.status, LancStatus.pending);
    expect(c.remoto.chamadasGravar, 0);
    expect((await c.pendencias()).single.situacao,
        SituacaoPendencia.exclusaoRejeitada);
    // rev1: a exclusão recusada também vai à Recuperação, como EXCLUSÃO.
    expect(c.remoto.recuperacao['${c.uid}_A']!['operacao'], 'exclusao');
    // Reenvio manual não tenta apagar de novo na coleção oficial.
    final m = await c.motor.reenviar(['A']);
    expect(m.single.resultado, ResultadoEnvio.rejeitadoNaoReenviado);
    expect((await c.lanc('A')).errorCode, kDeletePending);
  });

  test('T-SYNC-006 — recuperação sem rede fica registrada e sai depois',
      () async {
    final c = Cenario();
    await c.lancar(id: 'A');
    c.remoto.falhaGravar = (_) => fe('permission-denied');
    c.remoto.falhaRecuperacao = (_) => fe('unavailable');
    await c.motor.executarAutomatico();
    final e = (await c.estado('A'))!;
    expect(e.recuperacaoEnviadaEm, isNull);
    expect(e.recuperacaoErro, startsWith('unavailable'));
    c.remoto.falhaRecuperacao = null;
    await c.motor.executarAutomatico();
    expect(c.remoto.recuperacao.keys, ['${c.uid}_A']);
    expect((await c.estado('A'))!.recuperacaoErro, isNull);
  });

  test('T-SYNC-007 — uma execução por vez; a manual espera a vez', () async {
    final c = Cenario();
    await c.lancar(id: 'A');
    c.remoto.falhaGravar = (_) => null;
    final f1 = c.motor.executarAutomatico();
    final f2 = c.motor.executarAutomatico();
    final f3 = c.motor.reenviar(['A']);
    expect(await f2, isNull, reason: 'automática concorrente sai');
    expect((await f1)!.single.resultado, ResultadoEnvio.enviado);
    expect((await f3).single.resultado, ResultadoEnvio.jaSincronizado);
    expect(c.remoto.docs.length, 1);
  });

  test('T-SYNC-008 — CSV e informe ao Desktop', () async {
    final c = Cenario();
    await c.lancar(id: 'A');
    await c.lancar(
        id: 'S',
        inventarioId: '',
        contagemId: '',
        codigo: '40000050',
        em: c.relogio.add(const Duration(seconds: 1)));
    c.remoto.falhaGravar = (id) => id.endsWith('_A') ? fe('permission-denied') : null;
    c.remoto.falhaRecuperacao = (_) => fe('unavailable');
    await c.lancar(id: 'P', em: c.relogio.add(const Duration(minutes: 5)));
    // P fica pendente (não enviado ainda): simula sem rede para ele.
    c.remoto.falhaGravar = (id) => id.endsWith('_A')
        ? fe('permission-denied')
        : id.endsWith('_P')
            ? fe('unavailable')
            : null;
    await c.motor.executarAutomatico();

    final p = await c.pendencias();
    expect(p.map((x) => x.lanc.idLocal), ['A', 'P']); // S foi enviado
    final csv = pendenciasCsv(p);
    expect(csv, startsWith('\uFEFFid_local;situacao;escopo'));
    expect(csv, contains('A;Rejeitado pelo servidor;INV7__contagem_1'));
    expect(csv, contains('permission-denied'));
    expect(csv, contains('BUFFER_OXIGENIO'));

    final info = StatusSyncAparelho.montar(
        uid: c.uid,
        quadro: QuadroPendencias(p),
        agora: c.relogio,
        nome: 'Operador Teste');
    expect(info['rejeitados'], 1);
    expect(info['aguardando_reenvio'], 1);
    expect(info['total'], 2);
    expect((info['escopos'] as Map).keys, ['INV7__contagem_1']);
    expect((info['itens'] as List).length, 2);
    expect(((info['itens'] as List).first as Map)['id_local'], 'A');
  });

  test('T-SYNC-009 — Contagem Simples: erro antigo volta sozinho para a fila',
      () async {
    final c = Cenario();
    await c.lancar(
        id: 'S',
        inventarioId: '',
        contagemId: '',
        status: LancStatus.error,
        errorCode: '[cloud_firestore/unavailable] x');
    final r = await c.motor.executarAutomatico();
    expect(r!.single.resultado, ResultadoEnvio.enviado);
    expect((await c.lanc('S')).status, LancStatus.synced);
    expect(c.remoto.docs['${c.uid}_S']!['inventarioId'], '');
  });

  group('T-SYNC-010 — rev1: recusa definitiva nunca volta sozinha à coleção '
      'oficial', () {
    test('reenvio manual depois da reabertura da rodada não grava', () async {
      final c = Cenario();
      await c.lancar(id: 'A');
      c.remoto.falhaGravar = (_) => fe('permission-denied'); // encerrada
      await c.motor.executarAutomatico();
      expect((await c.estado('A'))!.definitivo, isTrue);
      final g = c.remoto.chamadasGravar;

      // A rodada foi REABERTA: o servidor voltaria a aceitar.
      c.remoto.falhaGravar = null;
      final um = await c.motor.reenviar(['A']);
      final todos = await c.motor.reenviar();
      await c.motor.executarAutomatico(ignorarEspera: true);
      expect(um.single.resultado, ResultadoEnvio.rejeitadoNaoReenviado);
      expect(todos.single.resultado, ResultadoEnvio.rejeitadoNaoReenviado);
      expect(c.remoto.chamadasGravar, g);
      expect(c.remoto.docs.containsKey('${c.uid}_A'), isFalse);
      expect((await c.lanc('A')).status, LancStatus.error);
      expect(c.remoto.recuperacao.keys, ['${c.uid}_A']);
    });

    test('erro antigo de permissão (antes do Pacote 1) vira recusa, sem '
        'reenvio', () async {
      final c = Cenario();
      await c.lancar(
          id: 'A',
          status: LancStatus.error,
          errorCode: '[cloud_firestore/permission-denied] Missing or '
              'insufficient permissions.');
      final r = await c.motor.executarAutomatico();
      expect(r, isEmpty);
      expect(c.remoto.chamadasGravar, 0);
      expect((await c.estado('A'))!.definitivo, isTrue);
      expect((await c.pendencias()).single.situacao,
          SituacaoPendencia.rejeitado);
      expect(c.remoto.recuperacao.keys, ['${c.uid}_A']);
    });
  });

  group('T-SYNC-011 — rev1: encerramento considera os informes (sync_status)',
      () {
    final agora = DateTime(2026, 10, 11, 12, 0);
    StatusSyncInformado st(String uid, int pend, Duration idade,
            {Set<String>? verificados, int formato = 2, int semEscopo = 0}) =>
        StatusSyncInformado(
          uid: uid,
          escopos: {
            escopoInventario('INV7', 'contagem_1'):
                ContagemPendencias(pendentes: pend),
            if (semEscopo > 0)
              kEscopoNaoClassificado: ContagemPendencias(pendentes: semEscopo),
          },
          formato: formato,
          escoposVerificados:
              verificados ?? {escopoInventario('INV7', 'contagem_1')},
          // rev3: idade pela base (servidor); recebido logo depois.
          baseServidor: agora.subtract(idade),
          informadoEm: agora.subtract(idade).add(const Duration(seconds: 5)),
        );
    ({
      String uid,
      String nome,
      bool finalizou,
      int pendentesLocais,
      DateTime? pendentesInformadosEm,
    }) part(String uid,
            {bool finalizou = false, int pendentes = 0}) =>
        (
          uid: uid,
          nome: 'Nome $uid',
          finalizou: finalizou,
          pendentesLocais: pendentes,
          pendentesInformadosEm: null,
        );

    test('pendência só no informe do aparelho bloqueia', () {
      final r = avaliarPendenciasEncerramento(
        inventarioId: 'INV7',
        rodada: 'contagem_1',
        participantes: [part('a')],
        status: {'a': st('a', 3, const Duration(minutes: 2))},
        agora: agora,
      );
      expect(r.single.motivo, MotivoPendenciaEncerramento.pendenciaInformada);
      expect(r.single.quantidade, 3);
      expect(r.single.idade, const Duration(minutes: 2));
      expect(r.single.texto, contains('3 lançamento(s)'));
    });

    test('pendência conhecida nunca é ignorada (vale a maior)', () {
      final r = avaliarPendenciasEncerramento(
        inventarioId: 'INV7',
        rodada: 'contagem_1',
        participantes: [part('a', pendentes: 2)],
        status: {'a': st('a', 0, const Duration(minutes: 1))},
        agora: agora,
      );
      expect(r.single.quantidade, 2);
    });

    test('sem informe ou informe antigo = desconhecido (não é "zero")', () {
      final r = avaliarPendenciasEncerramento(
        inventarioId: 'INV7',
        rodada: 'contagem_1',
        participantes: [part('sem'), part('velho'), part('ok')],
        status: {
          'velho': st('velho', 0, const Duration(minutes: 40)),
          'ok': st('ok', 0, const Duration(minutes: 3)),
        },
        agora: agora,
      );
      expect({for (final p in r) p.uid: p.motivo}, {
        'sem': MotivoPendenciaEncerramento.semInforme,
        'velho': MotivoPendenciaEncerramento.informeAntigo,
      });
    });

    test('quem finalizou (provou zero) não bloqueia por falta de informe', () {
      final r = avaliarPendenciasEncerramento(
        inventarioId: 'INV7',
        rodada: 'contagem_1',
        participantes: [part('f', finalizou: true)],
        status: const {},
        agora: agora,
      );
      expect(r, isEmpty);
    });

    test('rev2: informe recente SEM este escopo não é zero confirmado', () {
      final r = avaliarPendenciasEncerramento(
        inventarioId: 'INV7',
        rodada: 'contagem_1',
        participantes: [part('outro'), part('antigo'), part('ok')],
        status: {
          // verificou só outra rodada
          'outro': st('outro', 0, const Duration(minutes: 1),
              verificados: {escopoInventario('INV7', 'contagem_2')}),
          // formato antigo (sem lista de escopos verificados)
          'antigo': st('antigo', 0, const Duration(minutes: 1), formato: 1),
          'ok': st('ok', 0, const Duration(minutes: 1)),
        },
        agora: agora,
      );
      expect({for (final p in r) p.uid: p.motivo}, {
        'outro': MotivoPendenciaEncerramento.escopoNaoConfirmado,
        'antigo': MotivoPendenciaEncerramento.escopoNaoConfirmado,
      });
    });

    test('rev2: exclusão antiga sem escopo aparece como NÃO CLASSIFICADA, '
        'mesmo para quem finalizou', () {
      final r = avaliarPendenciasEncerramento(
        inventarioId: 'INV7',
        rodada: 'contagem_1',
        participantes: [part('f', finalizou: true)],
        status: {
          'f': st('f', 0, const Duration(minutes: 1), semEscopo: 2),
        },
        agora: agora,
      );
      expect(r.single.motivo, MotivoPendenciaEncerramento.naoClassificada);
      expect(r.single.quantidade, 2);
      expect(r.single.texto, contains('NÃO CLASSIFICADA'));
    });

    test('pendência de OUTRO inventário/rodada não conta', () {
      final r = avaliarPendenciasEncerramento(
        inventarioId: 'INV7',
        rodada: 'contagem_2',
        participantes: [part('a', finalizou: true)],
        status: {'a': st('a', 5, const Duration(minutes: 1))},
        agora: agora,
      );
      expect(r, isEmpty);
    });
  });

  test('T-SYNC-012 — rev1: painel atualiza com falha registrada só no '
      'metadado', () async {
    final c = Cenario();
    await c.lancar(id: 'A');
    final fila = <QuadroPendencias>[];
    final sub = observarPendencias(c.uid, c.repo, c.registro).listen(fila.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fila.last.lancamentos.single.situacao, SituacaoPendencia.pendente);

    // Só o sync_meta muda (o lançamento continua igual no Hive).
    await c.registro.gravar(
        'A',
        const EstadoSync().comFalha(
            const FalhaSync(TipoFalhaSync.rede, 'unavailable', 'sem rede'),
            c.relogio));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final p = fila.last.lancamentos.single;
    expect(p.situacao, SituacaoPendencia.aguardandoReenvio);
    expect(p.estado!.codigo, 'unavailable');
    expect(p.estado!.tentativas, 1);
    expect(p.estado!.proximaTentativa, isNotNull);
  });

  group('T-SYNC-013 — rev1: exclusões antigas (SharedPreferences '
      'delete_pending)', () {
    test('são concluídas pelo motor; as de outro usuário ficam', () async {
      final c = Cenario();
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({
        kChaveExclusoesLegadas: ['${c.uid}_X', 'outroUid_Y'],
      });
      c.remoto.docs['${c.uid}_X'] = {'codigo': '1'};
      var q = await lerQuadroPendencias(c.uid, c.repo, c.registro);
      expect(q.exclusoesLegadas.single.docId, '${c.uid}_X');

      final r = await c.motor.executarAutomatico();
      expect(r!.single.resultado, ResultadoEnvio.excluido);
      expect(c.remoto.apagados, ['${c.uid}_X']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(kChaveExclusoesLegadas), ['outroUid_Y']);
      q = await lerQuadroPendencias(c.uid, c.repo, c.registro);
      expect(q.exclusoesLegadas, isEmpty);
    });

    test('sem rede: continua pendente e visível; depois conclui', () async {
      final c = Cenario();
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({
        kChaveExclusoesLegadas: ['${c.uid}_X'],
      });
      c.remoto.falhaApagar = (_) => fe('unavailable');
      await c.motor.executarAutomatico();
      var q = await lerQuadroPendencias(c.uid, c.repo, c.registro);
      expect(q.exclusoesLegadas.single.situacao,
          SituacaoPendencia.aguardandoReenvio);
      expect(q.contagem.aguardandoReenvio, 1);
      c.remoto.falhaApagar = null;
      final r = await c.motor.reenviar();
      expect(r.single.resultado, ResultadoEnvio.excluido);
      q = await lerQuadroPendencias(c.uid, c.repo, c.registro);
      expect(q.exclusoesLegadas, isEmpty);
    });

    test('recusada: fica na lista, vai à Recuperação e não é reenviada',
        () async {
      final c = Cenario();
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({
        kChaveExclusoesLegadas: ['${c.uid}_X'],
      });
      c.remoto.docs['${c.uid}_X'] = {
        'codigo': '40000197',
        'inventarioId': 'INV7',
        'contagemId': 'contagem_1',
      };
      c.remoto.falhaApagar = (_) => fe('permission-denied');
      await c.motor.executarAutomatico();
      final q = await lerQuadroPendencias(c.uid, c.repo, c.registro);
      expect(q.exclusoesLegadas.single.situacao,
          SituacaoPendencia.exclusaoRejeitada);
      final rec = c.remoto.recuperacao['${c.uid}_X']!;
      expect(rec['operacao'], 'exclusao');
      expect(rec['idLocal'], 'X');
      expect(rec['inventarioId'], 'INV7');
      expect((rec['registro_oficial'] as Map)['codigo'], '40000197');
      final m = await c.motor.reenviar(['del:${c.uid}_X']);
      expect(m.single.resultado, ResultadoEnvio.rejeitadoNaoReenviado);
      expect(c.remoto.apagados, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(kChaveExclusoesLegadas), ['${c.uid}_X']);
      expect(pendenciasCsv(const [], q.exclusoesLegadas),
          contains('${c.uid}_X'));
    });
  });

  group('T-SYNC-014 — rev2: escopo das exclusões antigas', () {
    test('identificado pelo documento oficial quando possível', () async {
      final c = Cenario();
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({
        kChaveExclusoesLegadas: ['${c.uid}_X'],
      });
      c.remoto.docs['${c.uid}_X'] = {
        'inventarioId': 'INV7',
        'contagemId': 'contagem_1',
      };
      c.remoto.falhaApagar = (_) => fe('unavailable');
      await c.motor.executarAutomatico();
      final q = await lerQuadroPendencias(c.uid, c.repo, c.registro);
      expect(q.exclusoesLegadas.single.escopo, 'INV7__contagem_1');
      expect(q.porEscopo.keys, contains('INV7__contagem_1'));
      expect(q.porEscopo.containsKey(kEscopoNaoClassificado), isFalse);
    });

    test('sem leitura possível: NÃO CLASSIFICADA (não presume a rodada)',
        () async {
      final c = Cenario();
      // Aparelho já enviou tudo da INV7 C1 (escopo verificado, zero).
      await c.lancar(id: 'A', status: LancStatus.synced);
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({
        kChaveExclusoesLegadas: ['${c.uid}_X'],
      });
      final q = await lerQuadroPendencias(c.uid, c.repo, c.registro);
      expect(q.exclusoesLegadas.single.escopo, kEscopoNaoClassificado);
      expect(q.porEscopo[kEscopoNaoClassificado]!.total, 1);
      final info = StatusSyncAparelho.montar(
          uid: c.uid, quadro: q, agora: c.relogio);
      expect(info['formato'], 2);
      expect(info['escopos_verificados'], contains('INV7__contagem_1'));
      expect(info['escopos_verificados'], contains(kEscopoNaoClassificado));
      // A pendência não classificada NÃO entra na contagem da rodada.
      expect(((info['escopos'] as Map)['INV7__contagem_1'] as Map)['total'],
          0);
    });
  });

  group('T-SYNC-015 — rev2: painel acompanha a lista antiga (SharedPreferences)',
      () {
    test('com aviso de quem grava', () async {
      final c = Cenario();
      final fila = <QuadroPendencias>[];
      final sub =
          observarPendencias(c.uid, c.repo, c.registro).listen(fila.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fila.last.exclusoesLegadas, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(kChaveExclusoesLegadas, ['${c.uid}_Z']);
      avisarMudancaExclusoesLegadas();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(fila.last.exclusoesLegadas.single.docId, '${c.uid}_Z');
    });

    test('sem aviso: a conferência periódica percebe', () async {
      final c = Cenario();
      final antes = intervaloConferenciaExclusoes;
      intervaloConferenciaExclusoes = const Duration(milliseconds: 50);
      addTearDown(() => intervaloConferenciaExclusoes = antes);
      final fila = <QuadroPendencias>[];
      final sub =
          observarPendencias(c.uid, c.repo, c.registro).listen(fila.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(kChaveExclusoesLegadas, ['${c.uid}_W']);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(fila.last.exclusoesLegadas.single.docId, '${c.uid}_W');
    });
  });

  group('T-SYNC-016 — rev2: escrita que excedeu o tempo mas chegou ao '
      'servidor', () {
    test('recusa na regravação + servidor com registro igual = sincronizado '
        '(sem Recuperação)', () async {
      final c = Cenario();
      await c.lancar(id: 'A');
      c.remoto.enfileirarETravar = true; // SDK enfileirou; Future não volta
      final r1 = await c.motor.executarAutomatico();
      expect(r1!.single.codigo, 'timeout');
      expect((await c.lanc('A')).status, LancStatus.pending);
      expect(c.remoto.docs.containsKey('${c.uid}_A'), isTrue,
          reason: 'a escrita enfileirada chegou ao servidor');

      // Rodada encerrada depois: regravar (update) é recusado.
      c.remoto.enfileirarETravar = false;
      c.remoto.falhaGravar = (_) => fe('permission-denied');
      final r2 = await c.motor.executarAutomatico(ignorarEspera: true);
      expect(r2!.single.resultado, ResultadoEnvio.jaSincronizado);
      expect((await c.lanc('A')).status, LancStatus.synced);
      expect(c.remoto.recuperacao, isEmpty);
      expect(c.remoto.docs.length, 1);
    });

    test('servidor com conteúdo DIFERENTE: continua recusa definitiva',
        () async {
      final c = Cenario();
      await c.lancar(id: 'A', cheio: 3);
      c.remoto.docs['${c.uid}_A'] = {
        ...(await c.lanc('A')).toJson(),
        'cheio': 2, // versão anterior no servidor
      };
      c.remoto.falhaGravar = (_) => fe('permission-denied');
      final r = await c.motor.executarAutomatico();
      expect(r!.single.resultado, ResultadoEnvio.definitivo);
      expect((await c.lanc('A')).status, LancStatus.error);
      expect(c.remoto.recuperacao.keys, ['${c.uid}_A']);
    });

    test('exclusão cujo documento já sumiu = exclusão concluída', () async {
      final c = Cenario();
      await c.lancar(id: 'A', errorCode: kDeletePending);
      c.remoto.falhaApagar = (_) => fe('permission-denied');
      final r = await c.motor.executarAutomatico();
      expect(r!.single.resultado, ResultadoEnvio.excluido);
      expect(await c.repo.obter('A'), isNull);
    });
  });

  group('T-SYNC-017 — rev3: painel emite o estado inicial sem nenhuma mudança',
      () {
    test('abre com pendências antigas, sem alteração posterior', () async {
      final c = Cenario();
      await c.lancar(id: 'A');
      await c.registro.gravar(
          'A',
          const EstadoSync().comFalha(
              const FalhaSync(TipoFalhaSync.rede, 'unavailable', 'x'),
              c.relogio));
      // Nenhuma escrita depois de começar a escutar.
      final primeiro = await observarPendencias(c.uid, c.repo, c.registro)
          .first
          .timeout(const Duration(seconds: 2));
      expect(primeiro.lancamentos.single.lanc.idLocal, 'A');
      expect(primeiro.lancamentos.single.situacao,
          SituacaoPendencia.aguardandoReenvio);
    });

    test('erro de leitura sai como erro e a escuta continua', () async {
      final c = Cenario();
      var chamadas = 0;
      final eventos = <Object>[];
      final sub = observarPendencias(c.uid, c.repo, c.registro, leitor: () async {
        chamadas++;
        if (chamadas == 1) throw StateError('falha de leitura');
        return const QuadroPendencias([]);
      }).listen(eventos.add, onError: (Object e) => eventos.add('ERRO:$e'));
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(eventos.first, startsWith('ERRO:'));
      await c.registro.gravar('X', const EstadoSync());
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(eventos.whereType<QuadroPendencias>(), isNotEmpty);
    });
  });

  group('T-SYNC-018 — rev3: atualidade do informe (relógio do servidor)', () {
    final agora = DateTime(2026, 10, 11, 12, 0); // hora do SERVIDOR
    final escopo = escopoInventario('INV7', 'contagem_1');
    ({
      String uid,
      String nome,
      bool finalizou,
      int pendentesLocais,
      DateTime? pendentesInformadosEm,
    }) part(String uid) => (
          uid: uid,
          nome: uid,
          finalizou: false,
          pendentesLocais: 0,
          pendentesInformadosEm: null,
        );
    StatusSyncInformado inf(
            {DateTime? base, DateTime? recebido, DateTime? aparelho}) =>
        StatusSyncInformado(
          uid: 'u',
          escopos: {escopo: const ContagemPendencias()},
          formato: 2,
          escoposVerificados: {escopo},
          baseServidor: base,
          informadoEm: recebido,
          aparelhoEm: aparelho,
        );
    MotivoPendenciaEncerramento? motivo(StatusSyncInformado s) {
      final r = avaliarPendenciasEncerramento(
        inventarioId: 'INV7',
        rodada: 'contagem_1',
        participantes: [part('u')],
        status: {'u': s},
        agora: agora,
      );
      return r.isEmpty ? null : r.single.motivo;
    }

    test('informe enfileirado offline que chega agora com dados de 40 min',
        () {
      expect(
          motivo(inf(
              base: agora.subtract(const Duration(minutes: 40)),
              recebido: agora.subtract(const Duration(seconds: 30)))),
          MotivoPendenciaEncerramento.informeAntigo);
    });

    test('reconexão: dados de 5 min entregues com 4,5 min de atraso', () {
      expect(
          motivo(inf(
              base: agora.subtract(const Duration(minutes: 5)),
              recebido: agora.subtract(const Duration(seconds: 30)))),
          MotivoPendenciaEncerramento.informeAtrasado);
    });

    test('relógio do aparelho errado não engana nem atrapalha', () {
      // aparelho adiantado em anos, mas a base (servidor) é recente
      expect(
          motivo(inf(
              base: agora.subtract(const Duration(minutes: 2)),
              recebido: agora.subtract(const Duration(minutes: 2))
                  .add(const Duration(seconds: 3)),
              aparelho: DateTime(2031, 1, 1))),
          isNull);
      // aparelho "recente", mas sem base confirmada
      expect(
          motivo(inf(
              recebido: agora.subtract(const Duration(seconds: 10)),
              aparelho: agora)),
          MotivoPendenciaEncerramento.informeAntigo);
    });

    test('publicar: offline NÃO grava; online grava com a base do servidor e '
        'conteúdo produzido depois dela', () async {
      final c = Cenario();
      await c.lancar(id: 'A');
      final semRede = CanalFalso()..falhar = true;
      expect(
          await StatusSyncAparelho.publicar(c.uid,
              forcar: true, canal: semRede),
          ResultadoPublicacao.semConexao);
      expect(semRede.gravados, isEmpty);

      final horaServidor = DateTime(2026, 10, 11, 12, 30);
      final online = CanalFalso()
        ..hora = horaServidor
        // Lançamento feito "durante" o pulso: precisa aparecer no informe.
        ..aoPulsar = () => c.lancar(
            id: 'B', em: c.relogio.add(const Duration(minutes: 1)));
      expect(
          await StatusSyncAparelho.publicar(c.uid,
              forcar: true, canal: online),
          ResultadoPublicacao.confirmado);
      final d = online.gravados.single;
      expect((d['base_servidor'] as Timestamp).toDate(), horaServidor);
      expect(d['formato'], 2);
      expect(d['total'], 2, reason: 'conteúdo lido depois da base');
    });

    test('rev4: gravação sem resposta do servidor não conta como entrega',
        () async {
      final c = Cenario();
      await c.lancar(id: 'A');
      final lento = CanalFalso()..confirmar = false;
      expect(await StatusSyncAparelho.publicar(c.uid, canal: lento),
          ResultadoPublicacao.semConfirmacao);
      // Sem entrega confirmada, a próxima execução informa de novo (não
      // fica "segurada" como se tivesse entregado).
      expect(await StatusSyncAparelho.publicar(c.uid, canal: lento),
          ResultadoPublicacao.semConfirmacao);
      expect(lento.gravados.length, 2);
      final ok = CanalFalso();
      expect(await StatusSyncAparelho.publicar(c.uid, canal: ok),
          ResultadoPublicacao.confirmado);
      expect(await StatusSyncAparelho.publicar(c.uid, canal: ok),
          ResultadoPublicacao.semMudanca);
    });
  });
}
