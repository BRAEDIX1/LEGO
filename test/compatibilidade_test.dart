// test/compatibilidade_test.dart
// Rodar com: flutter test test/compatibilidade_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lego/services/compatibilidade.dart';

DecisaoCompat _mobile({
  String? instalada = '1.5.0',
  Object? minima = '1.5.0',
  int? build = 20,
  int? preparado = 20,
}) =>
    avaliarCompatibilidade(
      versaoInstalada: instalada,
      versaoMinima: minima,
      exigirPreparacao: true,
      buildInstalado: build,
      buildPreparado: preparado,
    );

void main() {
  group('T32: leitura de versão', () {
    test('formatos aceitos', () {
      expect(lerVersao('1.2.3'), [1, 2, 3]);
      expect(lerVersao('v1.2.3'), [1, 2, 3]);
      expect(lerVersao('1.2'), [1, 2, 0]);
      expect(lerVersao(' 2 '), [2, 0, 0]);
    });
    test('formatos recusados', () {
      expect(lerVersao(null), isNull);
      expect(lerVersao(''), isNull);
      expect(lerVersao('1.2.3.4'), isNull);
      expect(lerVersao('1.a.3'), isNull);
      expect(lerVersao('1..3'), isNull);
      expect(lerVersao('1.2.3+5'), isNull);
      expect(lerVersao(123), isNull);
    });
  });

  group('T32: versão', () {
    test('igual ao mínimo e preparação correta → liberado', () {
      expect(_mobile().resultado, ResultadoCompat.liberado);
    });
    test('acima do mínimo e preparação correta → liberado', () {
      expect(_mobile(instalada: '1.6.0').resultado, ResultadoCompat.liberado);
      expect(_mobile(instalada: 'v2.0').resultado, ResultadoCompat.liberado);
    });
    test('abaixo do mínimo → bloqueado', () {
      final d = _mobile(instalada: '1.4.9');
      expect(d.resultado, ResultadoCompat.versaoAbaixoDoMinimo);
      expect(d.mensagem, contains('1.5.0'));
    });
    test('mínimo ausente, vazio ou malformado → configuração inválida', () {
      expect(_mobile(minima: null).resultado, ResultadoCompat.configuracaoInvalida);
      expect(_mobile(minima: '').resultado, ResultadoCompat.configuracaoInvalida);
      expect(_mobile(minima: 'abc').resultado, ResultadoCompat.configuracaoInvalida);
      expect(_mobile(minima: 15).resultado, ResultadoCompat.configuracaoInvalida);
    });
    test('versão instalada malformada → bloqueado', () {
      expect(_mobile(instalada: 'x.y').resultado,
          ResultadoCompat.versaoInstaladaInvalida);
      expect(_mobile(instalada: null).resultado,
          ResultadoCompat.versaoInstaladaInvalida);
    });
  });

  group('T32: preparação da build (igualdade exata)', () {
    test('preparado igual → liberado', () {
      expect(_mobile(build: 21, preparado: 21).liberado, isTrue);
    });
    test('preparado menor → incompleta', () {
      expect(_mobile(build: 21, preparado: 20).resultado,
          ResultadoCompat.preparacaoIncompleta);
    });
    test('preparado maior (downgrade) → incompleta, pede instalar', () {
      final d = _mobile(build: 20, preparado: 21);
      expect(d.resultado, ResultadoCompat.preparacaoIncompleta);
      expect(d.mensagem, contains('Instale a versão atual'));
    });
    test('preparado ou build ausente → incompleta', () {
      expect(_mobile(preparado: null).resultado,
          ResultadoCompat.preparacaoIncompleta);
      expect(_mobile(build: null).resultado,
          ResultadoCompat.preparacaoIncompleta);
    });
    test('versão ok + preparação errada → incompleta', () {
      expect(_mobile(instalada: '1.6.0', build: 22, preparado: 21).resultado,
          ResultadoCompat.preparacaoIncompleta);
    });
    test('desktop não exige preparação', () {
      final d = avaliarCompatibilidade(
        versaoInstalada: '1.5.0',
        versaoMinima: '1.5.0',
        exigirPreparacao: false,
      );
      expect(d.liberado, isTrue);
    });
  });

  group('Tela de atualização: comparação tolerante (inalterada)', () {
    test('mesmo comportamento da antiga _isNewer', () {
      expect(versaoMaisNova('1.0.1', '1.0.0'), isTrue);
      expect(versaoMaisNova('1.0.0', '1.0.0'), isFalse);
      expect(versaoMaisNova('1.0', '1.0.1'), isFalse);
      expect(versaoMaisNova('2.x.0', '1.9.9'), isTrue);
    });
  });

  group('B39/B41/B42: gravação legada', () {
    DecisaoGravacaoLegada decidir({
      bool detectado = true,
      ResultadoCompat? compat,
      bool autonomo = false,
    }) =>
        decidirGravacaoLegada(
          inventarioAtivoDetectado: detectado,
          compat: compat,
          autonomoExplicito: autonomo,
        );

    test('sem inventário ativo → sem vínculo (como hoje)', () {
      expect(decidir(detectado: false), DecisaoGravacaoLegada.semVinculo);
    });
    test('compatível → vincula', () {
      expect(decidir(compat: ResultadoCompat.liberado),
          DecisaoGravacaoLegada.vincular);
    });
    test('Controlado incompatível sem escolha → gravação negada', () {
      for (final r in ResultadoCompat.values.where((r) => r != ResultadoCompat.liberado)) {
        expect(decidir(compat: r), DecisaoGravacaoLegada.negar, reason: r.name);
      }
    });
    test('incompatível NÃO produz IDs vazios automaticamente', () {
      expect(decidir(compat: ResultadoCompat.versaoAbaixoDoMinimo),
          isNot(DecisaoGravacaoLegada.semVinculo));
      expect(decidir(compat: null), DecisaoGravacaoLegada.negar);
    });
    test('após escolha explícita de Autônomo → sem vínculo permitido', () {
      expect(decidir(compat: ResultadoCompat.versaoAbaixoDoMinimo, autonomo: true),
          DecisaoGravacaoLegada.semVinculo);
    });
    test('abaixo do mínimo → Completa bloqueada (mesma guarda)', () {
      final d = _mobile(instalada: '1.4.0');
      expect(podeVincularCentral(d.resultado), isFalse);
    });
    test('Simples não depende da guarda (só vínculo central é avaliado)', () {
      // Sem inventário central detectado, a gravação legada segue sem vínculo
      // mesmo com a versão abaixo do mínimo.
      expect(
          decidirGravacaoLegada(
            inventarioAtivoDetectado: false,
            compat: ResultadoCompat.versaoAbaixoDoMinimo,
            autonomoExplicito: false,
          ),
          DecisaoGravacaoLegada.semVinculo);
    });
    test('guarda central: só liberado vincula', () {
      expect(podeVincularCentral(ResultadoCompat.liberado), isTrue);
      expect(podeVincularCentral(ResultadoCompat.versaoAbaixoDoMinimo), isFalse);
      expect(podeVincularCentral(null), isFalse);
    });
  });

  group('B45/B46: vínculo Controlado salvo bloqueado (L4)', () {
    test('L4 bloqueado + L1 sem inventário → gravação negada', () {
      expect(
          decidirGravacaoLegada(
            inventarioAtivoDetectado: false,
            compat: null,
            autonomoExplicito: false,
            vinculoControladoBloqueado: true,
          ),
          DecisaoGravacaoLegada.negar);
    });
    test('L4 bloqueado + Autônomo explícito → sem vínculo permitido', () {
      expect(
          decidirGravacaoLegada(
            inventarioAtivoDetectado: false,
            compat: null,
            autonomoExplicito: true,
            vinculoControladoBloqueado: true,
          ),
          DecisaoGravacaoLegada.semVinculo);
    });
    test('L4 bloqueado → registro vinculado não altera; sem vínculo altera', () {
      expect(
          podeAlterarLancamentoLegado(
              lancInventarioId: 'inv9',
              compat: ResultadoCompat.liberado,
              vinculoControladoBloqueado: true),
          isFalse);
      expect(
          podeAlterarLancamentoLegado(
              lancInventarioId: '', compat: null, vinculoControladoBloqueado: true),
          isTrue);
    });
  });

  group('B48: dono do vínculo Controlado salvo', () {
    test('A salva X; B entra → não restaura (outro usuário, bloqueado)', () {
      final d = avaliarDonoVinculo('A', 'B');
      expect(d, DonoVinculo.outroUsuario);
      expect(motivoDonoVinculo(d), contains('outro usuário'));
    });
    test('B escolhe X de novo (L3 grava dono B); B reabre → L4 normal', () {
      // Depois da escolha consciente, o dono salvo passa a ser B
      expect(avaliarDonoVinculo('B', 'B'), DonoVinculo.mesmoUsuario);
      expect(motivoDonoVinculo(DonoVinculo.mesmoUsuario), isNull);
    });
    test('vínculo antigo sem dono não é assumido pelo usuário atual', () {
      expect(avaliarDonoVinculo(null, 'A'), DonoVinculo.semDono);
      expect(avaliarDonoVinculo('', 'A'), DonoVinculo.semDono);
      expect(motivoDonoVinculo(DonoVinculo.semDono), contains('sem dono'));
    });
    test('ninguém logado → não restaura', () {
      expect(avaliarDonoVinculo('A', null), DonoVinculo.semUsuario);
    });
  });

  group('B49: vinculação Controlado (L3) iniciada por A', () {
    test('A inicia, B entra antes do fim → operação abortada para B', () {
      // A guarda de setModoControlado, _solicitarParticipacao e do monitor
      // é a mesma: só vale para o UID que iniciou.
      expect(resultadoDoMesmoUsuario('A', 'B'), isFalse);
      expect(resultadoDoMesmoUsuario('A', 'A'), isTrue);
    });
  });

  group('B52/B53: operação vigente (usuário + geração do vínculo)', () {
    bool vig(String? ui, String? ua, int gi, int ga) => operacaoVigente(
        uidInicio: ui, uidAtual: ua, geracaoInicio: gi, geracaoAtual: ga);

    test('mesmo usuário e mesma geração → vale', () {
      expect(vig('A', 'A', 3, 3), isTrue);
    });
    test('B52: Autônomo manual de A; B entra no meio → no-op', () {
      expect(vig('A', 'B', 3, 3), isFalse);
    });
    test('B53: callback de X (geração 3) depois de A escolher Y (geração 4) → no-op', () {
      expect(vig('A', 'A', 3, 4), isFalse);
    });
    test('sem usuário de origem → nunca vale', () {
      expect(vig(null, null, 1, 1), isFalse);
    });
  });

  group('B47: resultado assíncrono por usuário', () {
    test('mesmo usuário vale; troca ou ausência descarta', () {
      expect(resultadoDoMesmoUsuario('A', 'A'), isTrue);
      expect(resultadoDoMesmoUsuario('A', 'B'), isFalse);
      expect(resultadoDoMesmoUsuario('A', null), isFalse);
      expect(resultadoDoMesmoUsuario(null, null), isFalse);
      expect(resultadoDoMesmoUsuario('', ''), isFalse);
    });
  });

  group('B41: editar/excluir lançamento legado', () {
    test('sem vínculo sempre pode', () {
      expect(
          podeAlterarLancamentoLegado(
              lancInventarioId: '', compat: ResultadoCompat.versaoAbaixoDoMinimo),
          isTrue);
      expect(
          podeAlterarLancamentoLegado(
              lancInventarioId: 'local_autonomo',
              compat: ResultadoCompat.versaoAbaixoDoMinimo),
          isTrue);
    });
    test('vinculado e incompatível não pode', () {
      expect(
          podeAlterarLancamentoLegado(
              lancInventarioId: 'inv9', compat: ResultadoCompat.politicaIndisponivel),
          isFalse);
    });
    test('vinculado e compatível ou ainda não avaliado pode', () {
      expect(
          podeAlterarLancamentoLegado(
              lancInventarioId: 'inv9', compat: ResultadoCompat.liberado),
          isTrue);
      expect(podeAlterarLancamentoLegado(lancInventarioId: 'inv9', compat: null),
          isTrue);
    });
  });

  group('B40/B43: filtro de fluxo', () {
    test('fluxo_versao ausente ou 1 → legado; 2 → fluxo 2', () {
      expect(ehFluxo2({}), isFalse);
      expect(ehFluxo2(null), isFalse);
      expect(ehFluxo2({'fluxo_versao': 1}), isFalse);
      expect(ehFluxo2({'fluxo_versao': 2}), isTrue);
      expect(ehFluxo2({'fluxo_versao': 'x'}), isFalse);
    });
    test('fluxo 2 mais novo + legado mais antigo → devolve o legado', () {
      final candidatos = <Map<String, dynamic>>[
        {'id': 'novo_f2', 'fluxo_versao': 2},
        {'id': 'antigo_legado'},
      ];
      final r = escolherLegadoAtivo<Map<String, dynamic>>(candidatos, lerFluxoVersao);
      expect(r?['id'], 'antigo_legado');
    });
    test('só fluxo 2 → nenhum', () {
      final r = escolherLegadoAtivo<Map<String, dynamic>>(
          [{'fluxo_versao': 2}], lerFluxoVersao);
      expect(r, isNull);
    });
    test('fluxo_versao = 1 explícito → aceito', () {
      final r = escolherLegadoAtivo<Map<String, dynamic>>(
          [{'id': 'a', 'fluxo_versao': 1}], lerFluxoVersao);
      expect(r?['id'], 'a');
    });
  });
}
