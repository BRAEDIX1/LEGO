// integration_test/encerramento_recusa_firestore_test.dart
//
// Pacote 1 rev3 — cenário COMPLETO de encerramento com o Firestore real do
// LEGO TESTE, num inventário de TESTE criado e apagado pelo próprio teste.
// Não usa nem altera inventários existentes, nem a trava/contador
// (`sistema/contadores`).
//
// Precisa:
//   - as regras do Pacote 1 publicadas NO lego-teste (rev4: OBRIGATÓRIO — o
//     teste exige a cópia na Recuperação no servidor e o pulso de hora;
//     `permission-denied` reprova);
//   - uma conta do lego-teste que seja ANALISTA (sistema/app_config) — o
//     teste encerra a rodada e depois apaga o inventário de teste.
//
//   flutter test integration_test/encerramento_recusa_firestore_test.dart -d windows ^
//     --dart-define=LEGO_TESTE_EMAIL=<email> --dart-define=LEGO_TESTE_SENHA=<senha>
//
// Roteiro:
//   1. cria inventarios/IT_PACOTE1_<hora> (fluxo 2, C1 em andamento, o
//      próprio usuário na rodada) e o participante;
//   2. lançamento A enviado normalmente;
//   3. lançamento B: sem rede, o motor desiste por tempo esgotado (a escrita
//      fica na fila do SDK); a rede volta e B chega ao servidor;
//   4. o aparelho publica o informe (entrega confirmada pelo servidor); o
//      encerramento NORMAL pelo serviço do Desktop (MonitorService) é
//      recusado por pendência conhecida; o encerramento EXCEPCIONAL, com
//      motivo, encerra e grava a auditoria (forcado, motivo, pendências);
//   5. o motor tenta B de novo: a regravação é recusada, mas o servidor tem
//      B igual → sincronizado, sem Recuperação;
//   6. lançamento C feito depois do encerramento: recusa definitiva, fica no
//      aparelho, vai à Recuperação (se as regras estiverem publicadas) e o
//      reenvio manual NÃO o grava na coleção oficial;
//   7. limpeza: apaga o inventário de teste (depois disso as regras deixam
//      apagar os lançamentos dele) e os lançamentos/participante.
//      A cópia em `lancamentos_recuperacao` não pode ser apagada (regra) e
//      fica identificada pelo inventarioId IT_PACOTE1_...

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lego/data/local/lanc_local.dart';
import 'package:lego/data/local/registro_sync.dart';
import 'package:lego/data/repositories/lancamentos_repository.dart';
import 'package:lego/firebase_options_teste.dart';
import 'package:lego/services/monitor_service.dart';
import 'package:lego/services/acompanhamento_sync_service.dart'
    show MotivoPendenciaEncerramento;
import 'package:lego/services/sincronizacao/motor_sincronizacao.dart';
import 'package:lego/services/sincronizacao/status_sync_aparelho.dart';

const _email = String.fromEnvironment('LEGO_TESTE_EMAIL');
const _senha = String.fromEnvironment('LEGO_TESTE_SENHA');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FirebaseFirestore fs;
  late String uid;

  setUpAll(() async {
    await Firebase.initializeApp(options: TesteFirebaseOptions.currentPlatform);
    expect(Firebase.app().options.projectId, 'lego-teste'); // trava
    if (_email.isEmpty || _senha.isEmpty) {
      fail('Informe --dart-define=LEGO_TESTE_EMAIL e LEGO_TESTE_SENHA');
    }
    uid = (await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: _email, password: _senha))
        .user!
        .uid;
    fs = FirebaseFirestore.instance;
    final dir = await Directory.systemTemp.createTemp('lego_it_enc');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(41)) Hive.registerAdapter(LancStatusAdapter());
    if (!Hive.isAdapterRegistered(42)) Hive.registerAdapter(LancLocalAdapter());
    if (!Hive.isAdapterRegistered(43)) Hive.registerAdapter(TipoRegistroAdapter());
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('recusa depois do encerramento, num inventário de teste',
      (tester) async {
    final t = DateTime.now().millisecondsSinceEpoch;
    final invId = 'IT_PACOTE1_$t';
    final invRef = fs.collection('inventarios').doc(invId);
    final partRef = invRef.collection('participantes').doc(uid);
    final col = fs.collection('lancamentos');
    final box = await Hive.openBox<LancLocal>('lancamentos_$uid');

    LancLocal lanc(String id, double cheio) => LancLocal(
          idLocal: id,
          uid: uid,
          codigo: 'IT-TESTE',
          descricao: 'Teste integrado Pacote 1 (apagar)',
          unidade: 'CIL',
          quantidade: 0,
          prateleira: '',
          cheio: cheio,
          vazio: 0,
          lote: 'IT',
          createdAtLocal: DateTime.now(),
          status: LancStatus.pending,
          inventarioId: invId,
          contagemId: 'contagem_1',
          localizacaoId: 'TESTE',
          localizacaoNome: 'TESTE',
        );

    final motor = MotorSincronizacao(
      uid: uid,
      repo: LancamentosRepository(uid: uid),
      registro: RegistroSync(uid),
      remoto: FirestoreRemotoLancamentos(fs),
      limiteOperacao: const Duration(seconds: 3),
    );
    final idA = 'ITA_$t', idB = 'ITB_$t', idC = 'ITC_$t';

    try {
      // 1. Inventário e participante de TESTE.
      await invRef.set({
        'fluxo_versao': 2,
        'status': 'em_andamento',
        'teste_integrado': true,
        'numero': 0,
        'contagens': {
          'contagem_1': {
            'status': 'em_andamento',
            'usuarios': [uid],
          },
        },
      });
      await partRef.set({
        'rodada_base': 'contagem_1',
        'status_c1': 'em_andamento',
      });

      // 2. A enviado normalmente.
      await box.put(idA, lanc(idA, 1));
      final rA = await motor.executarAutomatico();
      expect(rA!.single.resultado, ResultadoEnvio.enviado);

      // 3. B: tempo esgotado sem rede; a escrita do SDK chega depois.
      await box.put(idB, lanc(idB, 2));
      await fs.disableNetwork();
      final rB1 = await motor.executarAutomatico();
      expect(rB1!.single.codigo, 'timeout');
      await fs.enableNetwork();
      await fs.waitForPendingWrites().timeout(const Duration(seconds: 60));
      expect(
          (await col.doc('${uid}_$idB')
                  .get(const GetOptions(source: Source.server)))
              .exists,
          isTrue,
          reason: 'timeout da Future não cancelou a escrita do SDK');
      expect(box.get(idB)!.status, LancStatus.pending);

      // 4. Informe do aparelho (B ainda pendente no aparelho) e encerramento
      //    pelo serviço real do Desktop.
      expect(await StatusSyncAparelho.publicar(uid, forcar: true),
          ResultadoPublicacao.confirmado);
      final monitor = MonitorService();
      try {
        await monitor.encerrarRodada(invId, 'contagem_1');
        fail('encerramento normal deveria ser recusado (pendência conhecida)');
      } on PendentesLocaisException catch (e) {
        expect(
            e.detalhes.any((d) =>
                d.uid == uid &&
                d.motivo == MotivoPendenciaEncerramento.pendenciaInformada),
            isTrue,
            reason: e.quem.join(' | '));
      }
      const motivo = 'Teste integrado Pacote 1 - encerramento excepcional';
      await monitor.encerrarRodada(invId, 'contagem_1',
          forcar: true, motivo: motivo);
      final inv = await invRef.get(const GetOptions(source: Source.server));
      expect(inv.data()!['contagens']['contagem_1']['status'], 'encerrada');
      final eventos = await invRef
          .collection('eventos')
          .where('tipo', isEqualTo: 'rodada_encerrada')
          .get(const GetOptions(source: Source.server));
      expect(eventos.docs, hasLength(1));
      final dados = eventos.docs.single.data()['dados'] as Map;
      expect(dados['forcado'], isTrue);
      expect(dados['motivo'], motivo);
      expect((dados['pendencias'] as List), isNotEmpty);

      // 5. Regravação de B é recusada, mas o servidor já tem B igual.
      final rB2 = await motor.executarAutomatico(ignorarEspera: true);
      expect(rB2!.single.resultado, ResultadoEnvio.jaSincronizado);
      expect(box.get(idB)!.status, LancStatus.synced);

      // 6. C depois do encerramento: recusa definitiva.
      await box.put(idC, lanc(idC, 3));
      final rC = await motor.executarAutomatico();
      expect(rC!.single.resultado, ResultadoEnvio.definitivo);
      expect(box.get(idC)!.status, LancStatus.error);
      final eC = await RegistroSync(uid).de(idC);
      expect(eC!.definitivo, isTrue);
      // rev4: a cópia TEM de existir no servidor (regras publicadas no
      // lego-teste). permission-denied reprova.
      expect(eC.recuperacaoEnviadaEm, isNotNull,
          reason: 'Recuperação não enviada: ${eC.recuperacaoErro}');
      final rec = await fs
          .collection('lancamentos_recuperacao')
          .doc('${uid}_$idC')
          .get(const GetOptions(source: Source.server));
      expect(rec.exists, isTrue);
      expect(rec.data()!['inventarioId'], invId);
      expect(rec.data()!['operacao'], 'inclusao');
      expect(rec.data()!['motivo_codigo'], 'permission-denied');
      // Reenvio manual não grava na coleção oficial.
      final m = await motor.reenviar([idC]);
      expect(m.single.resultado, ResultadoEnvio.rejeitadoNaoReenviado);
      expect(
          (await col.doc('${uid}_$idC')
                  .get(const GetOptions(source: Source.server)))
              .exists,
          isFalse);
    } finally {
      // 7. Limpeza (inventário primeiro: sem ele, as regras deixam apagar
      //    os lançamentos dele). Ficam no lego-teste, por regra (não
      //    apagáveis pelo app): a cópia em lancamentos_recuperacao e os
      //    eventos de auditoria do inventário de teste — ver
      //    PACOTE1_LEIAME.md, "Limpeza dos registros dos testes".
      try {
        await fs.enableNetwork();
      } catch (_) {}
      for (final f in [
        () => invRef.delete(),
        () => col.doc('${uid}_$idA').delete(),
        () => col.doc('${uid}_$idB').delete(),
        () => partRef.delete(),
      ]) {
        try {
          await f();
        } catch (_) {}
      }
      await box.deleteAll([idA, idB, idC]);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
