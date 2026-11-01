// integration_test/sync_timeout_firestore_test.dart
//
// Pacote 1 rev2 — teste INTEGRADO com o Firestore real do LEGO TESTE
// (projeto lego-teste). Verifica que o tempo esgotado da Future NÃO cancela
// uma escrita já enfileirada pelo SDK, e que o motor trata isso sem
// duplicar nem marcar recusa indevida.
//
// Roda no Windows (desktop), com uma conta de teste do lego-teste:
//   flutter test integration_test/sync_timeout_firestore_test.dart -d windows ^
//     --dart-define=LEGO_TESTE_EMAIL=<email> --dart-define=LEGO_TESTE_SENHA=<senha>
//
// Segurança: aborta se o projeto não for `lego-teste`. Grava UM lançamento
// de Contagem Simples (inventarioId vazio) com id local `IT_<hora>` e o
// apaga no fim. Não toca inventários.

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
import 'package:lego/services/sincronizacao/motor_sincronizacao.dart';

const _email = String.fromEnvironment('LEGO_TESTE_EMAIL');
const _senha = String.fromEnvironment('LEGO_TESTE_SENHA');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FirebaseFirestore fs;
  late String uid;

  setUpAll(() async {
    await Firebase.initializeApp(options: TesteFirebaseOptions.currentPlatform);
    // Trava: nunca roda fora do projeto de teste.
    expect(Firebase.app().options.projectId, 'lego-teste');
    if (_email.isEmpty || _senha.isEmpty) {
      fail('Informe --dart-define=LEGO_TESTE_EMAIL e LEGO_TESTE_SENHA');
    }
    final cred = await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: _email, password: _senha);
    uid = cred.user!.uid;
    fs = FirebaseFirestore.instance;
    final dir = await Directory.systemTemp.createTemp('lego_it_sync');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(41)) Hive.registerAdapter(LancStatusAdapter());
    if (!Hive.isAdapterRegistered(42)) Hive.registerAdapter(LancLocalAdapter());
    if (!Hive.isAdapterRegistered(43)) Hive.registerAdapter(TipoRegistroAdapter());
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'escrita que excede o tempo continua enfileirada no SDK e chega ao '
      'servidor; o motor reconcilia sem duplicar', (tester) async {
    final idLocal = 'IT_${DateTime.now().millisecondsSinceEpoch}';
    final docId = '${uid}_$idLocal';
    final col = fs.collection('lancamentos');

    final box = await Hive.openBox<LancLocal>('lancamentos_$uid');
    await box.put(
      idLocal,
      LancLocal(
        idLocal: idLocal,
        uid: uid,
        codigo: 'IT-TESTE',
        descricao: 'Teste integrado Pacote 1 (apagar)',
        unidade: 'UN',
        quantidade: 1,
        prateleira: '',
        cheio: 0,
        vazio: 0,
        createdAtLocal: DateTime.now(),
        status: LancStatus.pending,
        inventarioId: '',
        contagemId: '',
        localizacaoId: 'TESTE',
        localizacaoNome: 'TESTE',
      ),
    );

    final motor = MotorSincronizacao(
      uid: uid,
      repo: LancamentosRepository(uid: uid),
      registro: RegistroSync(uid),
      remoto: FirestoreRemotoLancamentos(fs),
      limiteOperacao: const Duration(seconds: 2),
    );

    try {
      // 1. Sem rede: a Future do set não volta; o motor desiste em 2 s.
      await fs.disableNetwork();
      final r1 = await motor.executarAutomatico();
      expect(r1!.single.resultado, ResultadoEnvio.rede);
      expect(r1.single.codigo, 'timeout');
      expect(box.get(idLocal)!.status, LancStatus.pending);

      // 2. Volta a rede: o SDK envia a escrita que ficou enfileirada, mesmo
      //    com a Future abandonada pelo timeout.
      await fs.enableNetwork();
      await fs.waitForPendingWrites().timeout(const Duration(seconds: 60));
      final snap =
          await col.doc(docId).get(const GetOptions(source: Source.server));
      expect(snap.exists, isTrue,
          reason: 'o timeout da Future NÃO cancelou a escrita do SDK');

      // 3. O motor regrava (idempotente) e marca sincronizado: um documento.
      final r2 = await motor.executarAutomatico(ignorarEspera: true);
      expect(r2!.single.resultado.sucesso, isTrue);
      expect(box.get(idLocal)!.status, LancStatus.synced);
      final mesmos = await col
          .where('uid', isEqualTo: uid)
          .where('codigo', isEqualTo: 'IT-TESTE')
          .get(const GetOptions(source: Source.server));
      expect(mesmos.docs.where((d) => d.id == docId).length, 1);
    } finally {
      try {
        await fs.enableNetwork();
        await col.doc(docId).delete();
      } catch (_) {}
      await box.delete(idLocal);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
