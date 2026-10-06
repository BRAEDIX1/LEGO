// test/fluxo2_modelos_test.dart
// Rodar com: flutter test test/fluxo2_modelos_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lego/models/inventario.dart';
import 'package:lego/models/participante.dart';

Inventario _inv({
  int fluxo = FluxoVersao.maquinaEstados,
  StatusInventario status = StatusInventario.emAndamento,
  Map<String, ContagemInfo> contagens = const {},
  ReconciliacaoInfo? rec,
}) {
  return Inventario(
    id: 'x',
    codigo: 'CMP_001_02102026',
    numero: 1,
    dataInicio: DateTime(2026, 10, 2),
    contagemAtiva: Rodadas.c1,
    status: status,
    contagens: contagens,
    fluxoVersao: fluxo,
    reconciliacao: rec,
  );
}

ContagemInfo _rodada(String status) => ContagemInfo(status: status);

void main() {
  group('Rodadas', () {
    test('sufixo e rótulo', () {
      expect(Rodadas.sufixo(Rodadas.c2), 'c2');
      expect(Rodadas.rotulo(Rodadas.c3), 'C3');
      expect(Rodadas.isBase(Rodadas.c3), isFalse);
    });
  });

  group('ContagemInfo.statusEfetivo (compatibilidade com legado)', () {
    test('sem status e sem datas = disponível', () {
      expect(ContagemInfo.fromMap({}).statusEfetivo, StatusRodada.disponivel);
    });
    test('legado com início e sem fim = em andamento', () {
      final c = ContagemInfo(iniciadaEm: DateTime(2026));
      expect(c.statusEfetivo, StatusRodada.emAndamento);
      expect(c.emAndamento, isTrue);
    });
    test('legado com fim = encerrada', () {
      final c = ContagemInfo(iniciadaEm: DateTime(2026), finalizadaEm: DateTime(2026));
      expect(c.statusEfetivo, StatusRodada.encerrada);
      expect(c.finalizada, isTrue);
    });
    test('campo status do fluxo 2 tem prioridade', () {
      final c = ContagemInfo(iniciadaEm: DateTime(2026), status: StatusRodada.encerrada);
      expect(c.statusEfetivo, StatusRodada.encerrada);
    });
  });

  group('Inventario.pendenciasParaEncerrar (§7)', () {
    test('recém-criado tem pendências', () {
      final inv = _inv(contagens: {
        Rodadas.c1: _rodada(StatusRodada.disponivel),
        Rodadas.c2: _rodada(StatusRodada.disponivel),
      }, rec: const ReconciliacaoInfo());
      expect(inv.aptoAEncerrar, isFalse);
      expect(inv.pendenciasParaEncerrar().length, greaterThanOrEqualTo(3));
    });

    test('C1/C2 encerradas, reconciliação concluída, C3 não necessária = apto', () {
      final inv = _inv(contagens: {
        Rodadas.c1: _rodada(StatusRodada.encerrada),
        Rodadas.c2: _rodada(StatusRodada.encerrada),
        Rodadas.c3: _rodada(StatusRodada.naoNecessaria),
      }, rec: const ReconciliacaoInfo(status: StatusReconciliacao.concluida));
      expect(inv.pendenciasParaEncerrar(), isEmpty);
    });

    test('linha em análise bloqueia', () {
      final inv = _inv(contagens: {
        Rodadas.c1: _rodada(StatusRodada.encerrada),
        Rodadas.c2: _rodada(StatusRodada.encerrada),
        Rodadas.c3: _rodada(StatusRodada.encerrada),
      }, rec: const ReconciliacaoInfo(status: StatusReconciliacao.concluida, emAnalise: 2));
      expect(inv.aptoAEncerrar, isFalse);
    });

    test('C3 pendente bloqueia', () {
      final inv = _inv(contagens: {
        Rodadas.c1: _rodada(StatusRodada.encerrada),
        Rodadas.c2: _rodada(StatusRodada.encerrada),
        Rodadas.c3: _rodada(StatusRodada.pendente),
      }, rec: const ReconciliacaoInfo(status: StatusReconciliacao.concluida));
      expect(inv.aptoAEncerrar, isFalse);
    });

    test('inventário legado nunca usa o encerramento do fluxo 2', () {
      expect(_inv(fluxo: FluxoVersao.legado).aptoAEncerrar, isFalse);
    });
  });

  group('Inventario (fluxo 2)', () {
    test('numeroFormatado e isAtivo', () {
      final inv = _inv();
      expect(inv.numeroFormatado, '001');
      expect(inv.isAtivo, isTrue);
      expect(_inv(status: StatusInventario.cancelado).isAtivo, isFalse);
    });

    test('proximaContagem não se aplica ao fluxo 2', () {
      // ignore: deprecated_member_use_from_same_package
      expect(_inv().proximaContagem(), isNull);
    });

    test('toFirestore preserva fluxo_versao e reconciliação', () {
      final m = _inv(rec: const ReconciliacaoInfo()).toFirestore();
      expect(m['fluxo_versao'], FluxoVersao.maquinaEstados);
      expect((m['reconciliacao'] as Map)['status'], StatusReconciliacao.naoExecutada);
    });
  });

  group('Participante', () {
    const p = Participante(
      uid: 'u1',
      displayName: 'Teste',
      statusC1: StatusParticipante.emAndamento,
      statusC2: StatusParticipante.finalizadaLegado,
      status: 'aprovado',
      contagemSolicitada: Rodadas.c1,
      rodadaBase: Rodadas.c1,
    );

    test('regras por rodada', () {
      expect(p.podeLancarEm(Rodadas.c1), isTrue);
      expect(p.podeLancarEm(Rodadas.c2), isFalse);
      expect(p.estaFinalizadoEm(Rodadas.c2), isTrue); // grafia legada
    });

    test('B6: toFirestore e copyWith não perdem status e contagem_solicitada', () {
      final m = p.toFirestore();
      expect(m['status'], 'aprovado');
      expect(m['contagem_solicitada'], Rodadas.c1);
      final c = p.copyWith(displayName: 'Outro');
      expect(c.status, 'aprovado');
      expect(c.contagemSolicitada, Rodadas.c1);
      expect(c.rodadaBase, Rodadas.c1);
    });

    test('B5: grava timestamps com o nome que o modelo lê', () {
      final m = p.copyWith(iniciouC1Em: DateTime(2026)).toFirestore();
      expect(m.containsKey('iniciou_c1_em'), isTrue);
      expect(m['iniciou_c1_em'], isNotNull);
    });
  });
}
