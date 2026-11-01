// test/widget_test.dart
//
// Teste de interface do coletor: painel "Pendências de envio" (Pacote 1).
//
// Substitui o teste do modelo inicial do Flutter, que procurava o texto
// "Firebase inicializado com sucesso! 🚀". Esse texto não existe no app, e o
// MyApp completo depende do Firebase, do PackageInfo e da verificação de
// atualização, que não rodam num teste de unidade.
//
// O cenário reproduz o aparelho do incidente: tudo só no Hive, sem nenhuma
// conexão. São um lançamento sincronizado, um pendente, um aguardando reenvio
// depois de falha de rede e um recusado pelo servidor (rodada encerrada).
//
// O painel precisa mostrar cada pendência com os dados que identificam o
// registro, nas contagens certas e com a ação certa para cada uma. O
// recusado pode ir à Recuperação, mas nunca é reenviado. Nenhuma ação é
// acionada aqui, porque o reenvio usa o Firebase.

import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lego/data/local/lanc_local.dart';
import 'package:lego/data/local/registro_sync.dart';
import 'package:lego/services/sincronizacao/falha_sync.dart';
import 'package:lego/ui/mobile/screens/pendencias_sync_screen.dart';

const _uid = 'widget_test_uid';

LancLocal _lanc(String id, LancStatus status, DateTime em,
        {required String codigo, required String lote, double cheio = 0}) =>
    LancLocal(
      idLocal: id,
      uid: _uid,
      codigo: codigo,
      descricao: 'Oxigenio 10M3',
      unidade: 'CIL',
      quantidade: 0,
      prateleira: '',
      cheio: cheio,
      vazio: 0,
      lote: lote,
      createdAtLocal: em,
      status: status,
      localizacaoId: 'AREA_A',
      localizacaoNome: 'Área A',
      // Contagem Simples: inventarioId vazio.
    );

void main() {
  late Directory dir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('lego_widget_test');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(41)) Hive.registerAdapter(LancStatusAdapter());
    if (!Hive.isAdapterRegistered(42)) Hive.registerAdapter(LancLocalAdapter());
    if (!Hive.isAdapterRegistered(43)) Hive.registerAdapter(TipoRegistroAdapter());

    // As caixas são abertas e gravadas aqui, fora do relógio simulado do
    // testWidgets. Na tela, a leitura é só em memória.
    final box = await Hive.openBox<LancLocal>('lancamentos_$_uid');
    await box.putAll({
      'S1': _lanc('S1', LancStatus.synced, DateTime(2026, 10, 30, 14, 0),
          codigo: 'SYNC-000', lote: 'L-000', cheio: 1),
      'P1': _lanc('P1', LancStatus.pending, DateTime(2026, 10, 30, 14, 5),
          codigo: 'GAS-001', lote: 'L-100', cheio: 3),
      'A1': _lanc('A1', LancStatus.pending, DateTime(2026, 10, 30, 14, 6),
          codigo: 'GAS-002', lote: 'L-200', cheio: 2),
      'R1': _lanc('R1', LancStatus.error, DateTime(2026, 10, 30, 14, 7),
          codigo: 'GAS-003', lote: 'L-300', cheio: 4),
    });
    await Hive.openBox('sync_meta_$_uid');
    final reg = RegistroSync(_uid);
    await reg.gravar(
        'A1',
        EstadoSync(
          tentativas: 2,
          ultimaTentativa: DateTime(2026, 10, 30, 14, 10),
          proximaTentativa: DateTime(2026, 10, 30, 14, 12),
          tipo: TipoFalhaSync.rede,
          codigo: 'unavailable',
          mensagem: 'sem conexão',
        ));
    await reg.gravar(
        'R1',
        EstadoSync(
          tentativas: 1,
          ultimaTentativa: DateTime(2026, 10, 30, 15, 0),
          tipo: TipoFalhaSync.definitivo,
          codigo: 'permission-denied',
          mensagem: 'rodada encerrada',
        ));
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets(
      'painel "Pendências de envio" identifica cada lançamento não '
      'sincronizado, sem conexão', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Ao abrir, o painel tenta publicar o informe ao Desktop sem esperar o
    // resultado. Sem Firebase iniciado, essa chamada falha fora da tela. O
    // erro é capturado aqui e conferido abaixo: só essa falha é aceita.
    final errosForaDaTela = <Object>[];
    await runZonedGuarded(
      () => tester.pumpWidget(
          const MaterialApp(home: PendenciasSyncScreen(uid: _uid))),
      (e, _) => errosForaDaTela.add(e),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    // Abriu sem conexão e saiu do "carregando".
    expect(find.text('Pendências de envio'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Falha ao ler'), findsNothing);

    // Contadores: 1 pendente, 1 aguardando reenvio, 0 erro, 1 rejeitado.
    expect(find.text('Pendentes: 1'), findsOneWidget);
    expect(find.text('Aguardando reenvio: 1'), findsOneWidget);
    expect(find.text('Erro: 0'), findsOneWidget);
    expect(find.text('Rejeitados: 1'), findsOneWidget);

    // O sincronizado não aparece.
    expect(find.text('SYNC-000 · Oxigenio 10M3'), findsNothing);
    expect(find.text('Id local: S1'), findsNothing);

    // Cada pendência mostra produto, lote, quantidade, área, data, hora,
    // escopo e id local.
    expect(find.text('GAS-001 · Oxigenio 10M3'), findsOneWidget);
    expect(find.text('Lote L-100 · 3 cheio(s)'), findsOneWidget);
    expect(find.text('Área A · 30/10/2026 14:05:00'), findsOneWidget);
    expect(find.text('Id local: P1'), findsOneWidget);
    expect(find.text('Pendente'), findsOneWidget);
    expect(find.text('Contagem Simples'), findsNWidgets(3));

    // Falha de rede: motivo, tentativas e próxima tentativa.
    expect(find.text('GAS-002 · Oxigenio 10M3'), findsOneWidget);
    expect(find.text('Aguardando reenvio'), findsOneWidget);
    expect(find.text('Motivo: unavailable — sem conexão'), findsOneWidget);
    expect(
        find.text('2 tentativa(s) · última às 14:10:00 · próxima às 14:12:00'),
        findsOneWidget);
    expect(find.text('Id local: A1'), findsOneWidget);

    // Recusa definitiva: identificada e com o motivo.
    expect(find.text('GAS-003 · Oxigenio 10M3'), findsOneWidget);
    expect(find.text('Rejeitado pelo servidor'), findsOneWidget);
    expect(find.text('Motivo: permission-denied — rodada encerrada'),
        findsOneWidget);
    expect(find.text('Id local: R1'), findsOneWidget);

    // Ações: reenvio só para os 2 não recusados. O recusado só tem
    // "Enviar à Recuperação".
    expect(find.byTooltip('Reenviar este'), findsNWidgets(2));
    expect(find.byTooltip('Enviar à Recuperação'), findsOneWidget);
    expect(find.text('Reenviar todos (2)'), findsOneWidget);
    expect(find.text('Enviar rejeitados à Recuperação (1)'), findsOneWidget);

    // Filtro "Só com problema": some o pendente comum e ficam os outros.
    await tester.tap(find.text('Só com problema'));
    await tester.pump();
    expect(find.text('Id local: P1'), findsNothing);
    expect(find.text('Id local: A1'), findsOneWidget);
    expect(find.text('Id local: R1'), findsOneWidget);
    expect(find.text('Pendentes: 1'), findsOneWidget); // contagem não muda

    // A única falha aceita fora da tela é o informe sem Firebase.
    expect(errosForaDaTela, hasLength(1), reason: '$errosForaDaTela');
    expect(errosForaDaTela.single, isA<FirebaseException>());

    // Fecha a tela: cancela as escutas e o timer de conferência.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
