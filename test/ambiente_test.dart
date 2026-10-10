// test/ambiente_test.dart
// Lote 3C: ambiente, portões da inicialização (B55) e trava da T49.
// Rodar com: flutter test test/ambiente_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lego/config/ambiente.dart';
import 'package:lego/config/fluxo2_config.dart';

const _murilo = 'murilo-21h52m';
const _teste = 'lego-teste';
const _pkgProd = 'com.example.lego';
const _pkgTeste = 'com.example.lego.teste';
const _appProd = '1:1082826789172:android:ec3446a0b183cd75369561';
const _appTeste = '1:155608278634:android:0aacb8e34d3f1f48e5cc13';

void main() {
  group('resolverAmbiente (fonte única: appFlavor)', () {
    test('null → produção (desktop / sem sabor)', () {
      expect(resolverAmbiente(null), Ambiente.producao);
    });
    test("'prod' → produção", () {
      expect(resolverAmbiente('prod'), Ambiente.producao);
    });
    test("'homolog' → teste", () {
      expect(resolverAmbiente('homolog'), Ambiente.teste);
    });
    test("'teste' → inválido (o sabor Android não pode começar com test, B59)", () {
      expect(resolverAmbiente('teste'), isNull);
    });
    test("'' → inválido", () {
      expect(resolverAmbiente(''), isNull);
    });
    test("'Teste' (maiúscula) → inválido", () {
      expect(resolverAmbiente('Teste'), isNull);
    });
    test("'outro' → inválido", () {
      expect(resolverAmbiente('outro'), isNull);
    });
  });

  group('projetoEsperado / pacoteEsperado', () {
    test('produção', () {
      expect(projetoEsperado(Ambiente.producao), _murilo);
      expect(pacoteEsperado(Ambiente.producao), _pkgProd);
    });
    test('teste', () {
      expect(projetoEsperado(Ambiente.teste), _teste);
      expect(pacoteEsperado(Ambiente.teste), _pkgTeste);
    });
  });

  group('portaoPreFirebase (portões 1 e 2)', () {
    test('ambiente inválido → bloqueado, sem projeto esperado', () {
      final r = portaoPreFirebase(ambiente: null, packageName: _pkgProd);
      expect(r.liberado, isFalse);
      expect(r.motivo, MotivoBloqueioInicial.ambienteInvalido);
    });
    test('produção + pacote de produção → liberado', () {
      expect(
          portaoPreFirebase(ambiente: Ambiente.producao, packageName: _pkgProd)
              .liberado,
          isTrue);
    });
    test('teste + pacote de teste → liberado', () {
      expect(
          portaoPreFirebase(ambiente: Ambiente.teste, packageName: _pkgTeste)
              .liberado,
          isTrue);
    });
    test('pacote .teste que se acha produção → bloqueado', () {
      final r =
          portaoPreFirebase(ambiente: Ambiente.producao, packageName: _pkgTeste);
      expect(r.motivo, MotivoBloqueioInicial.pacoteDivergente);
    });
    test('ambiente teste com pacote de produção → bloqueado', () {
      final r =
          portaoPreFirebase(ambiente: Ambiente.teste, packageName: _pkgProd);
      expect(r.motivo, MotivoBloqueioInicial.pacoteDivergente);
    });
    test('pacote desconhecido → bloqueado', () {
      final r =
          portaoPreFirebase(ambiente: Ambiente.producao, packageName: null);
      expect(r.motivo, MotivoBloqueioInicial.pacoteDivergente);
    });
  });

  group('appIdEsperado (B56: fonte independente)', () {
    test('produção = app Android do murilo', () {
      expect(appIdEsperado(Ambiente.producao), _appProd);
    });
    test('teste = app Android do lego-teste (S2)', () {
      expect(appIdEsperado(Ambiente.teste), _appTeste);
    });
    test('os dois ambientes têm appIds diferentes', () {
      expect(appIdEsperado(Ambiente.teste),
          isNot(appIdEsperado(Ambiente.producao)));
    });
  });

  group('portaoOpcoes (antes do Firebase, B56/B57)', () {
    ResultadoPortao opcoesProd({
      String projectId = _murilo,
      String appId = _appProd,
      String apiKey = 'AIza',
      String messagingSenderId = '1082826789172',
      String? storageBucket = 'murilo-21h52m.firebasestorage.app',
    }) =>
        portaoOpcoes(
          ambiente: Ambiente.producao,
          projectId: projectId,
          appId: appId,
          apiKey: apiKey,
          messagingSenderId: messagingSenderId,
          storageBucket: storageBucket,
        );

    test('produção com as opções certas → liberado', () {
      expect(opcoesProd().liberado, isTrue);
    });
    test('B57: storageBucket ausente (null) + resto válido → liberado', () {
      expect(opcoesProd(storageBucket: null).liberado, isTrue);
    });
    test('B57: storageBucket vazio + resto válido → liberado', () {
      expect(opcoesProd(storageBucket: '').liberado, isTrue);
    });
    test('storageBucket com PREENCHER esquecido → bloqueado', () {
      expect(opcoesProd(storageBucket: valorNaoPreenchido).motivo,
          MotivoBloqueioInicial.configuracaoIncompleta);
    });
    test('apiKey vazia → bloqueado', () {
      expect(opcoesProd(apiKey: '').motivo,
          MotivoBloqueioInicial.configuracaoIncompleta);
    });
    test('messagingSenderId PREENCHER → bloqueado', () {
      expect(opcoesProd(messagingSenderId: valorNaoPreenchido).motivo,
          MotivoBloqueioInicial.configuracaoIncompleta);
    });
    test('B56: opções de produção apontando para lego-teste → bloqueado antes do Firebase', () {
      expect(opcoesProd(projectId: _teste).motivo,
          MotivoBloqueioInicial.projetoDivergente);
    });
    test('B56: appId das opções diferente do esperado → bloqueado antes do Firebase', () {
      expect(opcoesProd(appId: '1:1082826789172:android:outro').motivo,
          MotivoBloqueioInicial.appIdDivergente);
    });
    ResultadoPortao opcoesTeste({
      String projectId = _teste,
      String appId = _appTeste,
      String apiKey = 'AIzaSyA_teste',
      String messagingSenderId = '155608278634',
      String? storageBucket = 'lego-teste.firebasestorage.app',
    }) =>
        portaoOpcoes(
          ambiente: Ambiente.teste,
          projectId: projectId,
          appId: appId,
          apiKey: apiKey,
          messagingSenderId: messagingSenderId,
          storageBucket: storageBucket,
        );

    test('B58: opções corretas do lego-teste → liberado', () {
      expect(opcoesTeste().liberado, isTrue);
    });
    test('B58: murilo no ambiente teste → projetoDivergente', () {
      expect(opcoesTeste(projectId: _murilo).motivo,
          MotivoBloqueioInicial.projetoDivergente);
    });
    test('B58: appId errado no ambiente teste → appIdDivergente', () {
      expect(opcoesTeste(appId: '1:155608278634:android:outro').motivo,
          MotivoBloqueioInicial.appIdDivergente);
    });
    test('teste com o appId da produção → appIdDivergente', () {
      expect(opcoesTeste(appId: _appProd).motivo,
          MotivoBloqueioInicial.appIdDivergente);
    });
  });

  group('portaoPosFirebase (portão 3, depois do Firebase)', () {
    test('produção + murilo + appId esperado → liberado', () {
      expect(
          portaoPosFirebase(
                  ambiente: Ambiente.producao,
                  projectId: _murilo,
                  appId: _appProd)
              .liberado,
          isTrue);
    });
    test('B58: teste + lego-teste + appId do teste → liberado', () {
      expect(
          portaoPosFirebase(
                  ambiente: Ambiente.teste,
                  projectId: _teste,
                  appId: _appTeste)
              .liberado,
          isTrue);
    });
    test('teste + murilo → bloqueado', () {
      final r = portaoPosFirebase(
          ambiente: Ambiente.teste, projectId: _murilo, appId: _appProd);
      expect(r.motivo, MotivoBloqueioInicial.projetoDivergente);
    });
    test('produção + lego-teste → bloqueado', () {
      final r = portaoPosFirebase(
          ambiente: Ambiente.producao, projectId: _teste, appId: _appProd);
      expect(r.motivo, MotivoBloqueioInicial.projetoDivergente);
    });
    test('B56: app nativo com appId diferente do esperado → bloqueado', () {
      final r = portaoPosFirebase(
          ambiente: Ambiente.producao,
          projectId: _murilo,
          appId: '1:1082826789172:android:outro');
      expect(r.motivo, MotivoBloqueioInicial.appIdDivergente);
    });
  });

  group('fluxo2Habilitado (T49)', () {
    test('ambiente inválido → sempre desligado', () {
      expect(
          fluxo2Habilitado(ambiente: null, flag: true, flagProducao: true),
          isFalse);
    });
    test('teste + LEGO_FLUXO2 → ligado', () {
      expect(
          fluxo2Habilitado(
              ambiente: Ambiente.teste, flag: true, flagProducao: false),
          isTrue);
    });
    test('teste sem LEGO_FLUXO2 → desligado', () {
      expect(
          fluxo2Habilitado(
              ambiente: Ambiente.teste, flag: false, flagProducao: true),
          isFalse);
    });
    test('produção + só LEGO_FLUXO2 → DESLIGADO (o caso do 001)', () {
      expect(
          fluxo2Habilitado(
              ambiente: Ambiente.producao, flag: true, flagProducao: false),
          isFalse);
    });
    test('produção + as duas chaves → ligado', () {
      expect(
          fluxo2Habilitado(
              ambiente: Ambiente.producao, flag: true, flagProducao: true),
          isTrue);
    });
    test('produção + só LEGO_FLUXO2_PRODUCAO → desligado', () {
      expect(
          fluxo2Habilitado(
              ambiente: Ambiente.producao, flag: false, flagProducao: true),
          isFalse);
    });
  });

  group('D16: portões do desktop (ambiente fixado pelo ponto de entrada)', () {
    const appWinProd = '1:1082826789172:web:26bada18bdf591ca369561';
    const appWinTeste = '1:155608278634:web:6ebbd7c38e1e0a7ae5cc13';

    ResultadoPortao opcoesDesk(
      Ambiente amb, {
      required String projectId,
      required String appId,
      String apiKey = 'AIza',
      String? storageBucket,
    }) =>
        portaoOpcoes(
          ambiente: amb,
          projectId: projectId,
          appId: appId,
          apiKey: apiKey,
          messagingSenderId: '1',
          storageBucket: storageBucket,
          appIdExigido: appIdEsperadoDesktop(amb),
        );

    test('appIds desktop: produção = app Windows do murilo; teste = app Web do lego-teste', () {
      expect(appIdEsperadoDesktop(Ambiente.producao), appWinProd);
      expect(appIdEsperadoDesktop(Ambiente.teste), appWinTeste);
    });
    test('produção + murilo + appId Windows certo → liberado', () {
      expect(opcoesDesk(Ambiente.producao, projectId: _murilo, appId: appWinProd)
          .liberado, isTrue);
    });
    test('produção + appId Android → appIdDivergente', () {
      expect(opcoesDesk(Ambiente.producao, projectId: _murilo, appId: _appProd)
          .motivo, MotivoBloqueioInicial.appIdDivergente);
    });
    test('teste + lego-teste + appId real do desktop teste → liberado', () {
      expect(opcoesDesk(Ambiente.teste, projectId: _teste, appId: appWinTeste)
          .liberado, isTrue);
    });
    test('teste + murilo → projetoDivergente', () {
      expect(opcoesDesk(Ambiente.teste, projectId: _murilo, appId: appWinTeste)
          .motivo, MotivoBloqueioInicial.projetoDivergente);
    });
    test('teste + appId errado (Android do teste ou Windows da prod) → appIdDivergente', () {
      expect(opcoesDesk(Ambiente.teste, projectId: _teste, appId: _appTeste)
          .motivo, MotivoBloqueioInicial.appIdDivergente);
      expect(opcoesDesk(Ambiente.teste, projectId: _teste, appId: appWinProd)
          .motivo, MotivoBloqueioInicial.appIdDivergente);
    });
    test('opção com PREENCHER esquecido → configuração incompleta', () {
      expect(
          opcoesDesk(Ambiente.teste,
                  projectId: _teste,
                  appId: appWinTeste,
                  apiKey: valorNaoPreenchido)
              .motivo,
          MotivoBloqueioInicial.configuracaoIncompleta);
    });
    test('pós-Firebase: teste iniciado no lego-teste com o appId real → liberado', () {
      expect(
          portaoPosFirebase(
                  ambiente: Ambiente.teste,
                  projectId: _teste,
                  appId: appWinTeste,
                  appIdExigido: appIdEsperadoDesktop(Ambiente.teste))
              .liberado,
          isTrue);
    });
    test('pós-Firebase: teste iniciado no murilo → bloqueado', () {
      expect(
          portaoPosFirebase(
                  ambiente: Ambiente.teste,
                  projectId: _murilo,
                  appId: appWinProd,
                  appIdExigido: appIdEsperadoDesktop(Ambiente.teste))
              .motivo,
          MotivoBloqueioInicial.projetoDivergente);
    });
    test('pós-Firebase: produção certa → liberado', () {
      expect(
          portaoPosFirebase(
                  ambiente: Ambiente.producao,
                  projectId: _murilo,
                  appId: appWinProd,
                  appIdExigido: appIdEsperadoDesktop(Ambiente.producao))
              .liberado,
          isTrue);
    });
  });
}
