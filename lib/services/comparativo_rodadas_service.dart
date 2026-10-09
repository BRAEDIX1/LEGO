// lib/services/comparativo_rodadas_service.dart
//
// Entrega 1 (teste em campo): encerrar C1/C2 e gerar o comparativo C1 × C2.
//
// - encerrarRodada: marca a rodada como encerrada (o celular já bloqueia
//   lançamento em rodada encerrada: SessaoContagem.podeLancar).
// - gerarComparativo: com C1 e C2 encerradas, lê os lançamentos das duas no
//   SERVIDOR, compara (comparativo.dart) e grava cada linha em
//   inventarios/{id}/comparativo/{linha}. Atualiza `reconciliacao` e deixa a
//   C3 como `pendente` (há linhas em análise) ou `nao_necessaria`.
//   Idempotente: comparativo concluído não roda de novo, a não ser com
//   `refazer: true` (só antes de a C3 começar).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:lego/data/repositories/produtos_repository.dart';
import 'package:lego/models/inventario.dart';
import 'package:lego/services/audit_event_service.dart';
import 'package:lego/services/comparativo.dart';
import 'package:lego/services/inventario_service.dart'
    show OperacaoNaoPermitidaException;

class ComparativoRodadasService {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _inventarios =>
      _fs.collection('inventarios');

  CollectionReference<Map<String, dynamic>> _linhas(String inventarioId) =>
      _inventarios.doc(inventarioId).collection('comparativo');

  String _uid() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw Exception('Usuário não autenticado');
    return u.uid;
  }

  // ---------------------------------------------------------------------
  // ENCERRAR RODADA (D8: com confirmação na tela)
  // ---------------------------------------------------------------------

  Future<void> encerrarRodada(
    String inventarioId,
    String rodada, {
    Map<String, dynamic>? dadosParticipantes,
  }) async {
    if (!Rodadas.isBase(rodada)) {
      throw OperacaoNaoPermitidaException(
          'Encerrar rodada', inventarioId, 'só C1 ou C2 ($rodada)');
    }
    final uid = _uid();
    final ref = _inventarios.doc(inventarioId);

    await _fs.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw OperacaoNaoPermitidaException(
            'Encerrar rodada', inventarioId, 'inventário não encontrado');
      }
      final inv = Inventario.fromFirestore(snap);
      if (!inv.isFluxoMaquinaEstados || !inv.isAtivo) {
        throw OperacaoNaoPermitidaException(
            'Encerrar rodada', inventarioId, 'inventário não está ativo');
      }
      if (inv.rodadaEncerrada(rodada)) {
        throw OperacaoNaoPermitidaException('Encerrar rodada', inventarioId,
            '${Rodadas.rotulo(rodada)} já está encerrada');
      }

      tx.update(ref, {
        'contagens.$rodada.status': StatusRodada.encerrada,
        'contagens.$rodada.finalizada_em': FieldValue.serverTimestamp(),
        'contagens.$rodada.encerrada_por': uid,
      });
      AuditEventService.registrarNaTransacao(
        tx,
        inventarioId: inventarioId,
        tipo: TipoEvento.rodadaEncerrada,
        uid: uid,
        rodada: rodada,
        dados: dadosParticipantes ?? const {},
      );
    });
    debugPrint('✅ ${Rodadas.rotulo(rodada)} encerrada ($inventarioId)');
  }

  // ---------------------------------------------------------------------
  // COMPARATIVO C1 × C2
  // ---------------------------------------------------------------------

  /// Lê os lançamentos de uma rodada no servidor.
  Future<List<LancResumo>> carregarRodada(
          String inventarioId, String rodada) async =>
      (await carregarRodadaCompleta(inventarioId, rodada)).$2;

  /// Documentos brutos da rodada (para a aba "Lançamentos" do relatório, com
  /// `createdAt` em DateTime local) e o resumo classificado (consolidados).
  Future<(List<Map<String, dynamic>>, List<LancResumo>)> carregarRodadaCompleta(
      String inventarioId, String rodada) async {
    final snap = await _fs
        .collection('lancamentos')
        .where('inventarioId', isEqualTo: inventarioId)
        .where('contagemId', isEqualTo: rodada)
        .get(const GetOptions(source: Source.server));
    final brutos = [
      for (final d in snap.docs)
        () {
          final m = <String, dynamic>{...d.data()};
          final ts = m['createdAt'];
          if (ts is Timestamp) m['createdAt'] = ts.toDate();
          return m;
        }(),
    ];
    final lancs =
        brutos.map(LancResumo.deMapa).whereType<LancResumo>().toList();
    return (brutos, await _classificar(lancs));
  }

  /// L3: natureza pelo cadastro (coleção do produto: `gases` ou
  /// `materiais`), descrição e volume unitário do cadastro quando o
  /// lançamento não tem. Sem cadastro no aparelho, fica a regra de reserva
  /// de [LancResumo.ehGas].
  Future<List<LancResumo>> _classificar(List<LancResumo> lancs) async {
    final repo = ProdutosRepository();
    final cache = <String, (String?, String?, double?)>{};
    final out = <LancResumo>[];
    for (final l in lancs) {
      if (l.codigo.isEmpty) {
        out.add(l);
        continue;
      }
      final info = cache[l.codigo] ??= await () async {
        try {
          final p = await repo.getByCodigoPreferGases(l.codigo);
          if (p == null) return (null, null, null);
          final Object? o = p.origem;
          final Object? d = p.descricao;
          final Object? v = p.volume;
          return (
            o?.toString(),
            d?.toString(),
            v is num ? v.toDouble() : null,
          );
        } catch (e) {
          debugPrint('⚠️ Comparativo: cadastro de ${l.codigo} indisponível: $e');
          return (null, null, null);
        }
      }();
      out.add(l.comOrigem(l.origem ?? info.$1,
          descricaoCadastro: info.$2, volumeCadastro: info.$3));
    }
    return out;
  }

  /// Gera (ou devolve) o comparativo. Devolve o resumo.
  Future<ResumoComparativo> gerarComparativo(
    String inventarioId, {
    bool refazer = false,
  }) async {
    final uid = _uid();
    final ref = _inventarios.doc(inventarioId);

    // L4: tipo do inventário (só o consolidado dele entra no comparativo).
    Natureza? naturezaInv;

    // 1) Reserva a execução (idempotência / dois analistas ao mesmo tempo).
    final jaPronto = await _fs.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw OperacaoNaoPermitidaException(
            'Comparativo', inventarioId, 'inventário não encontrado');
      }
      final inv = Inventario.fromFirestore(snap);
      if (!inv.isFluxoMaquinaEstados || !inv.isAtivo) {
        throw OperacaoNaoPermitidaException(
            'Comparativo', inventarioId, 'inventário não está ativo');
      }
      naturezaInv = NaturezaRotulo.deNome(inv.naturezaContagem);
      for (final r in Rodadas.base) {
        if (!inv.rodadaEncerrada(r)) {
          throw OperacaoNaoPermitidaException('Comparativo', inventarioId,
              'encerre a ${Rodadas.rotulo(r)} antes');
        }
      }
      final rec = inv.reconciliacao ?? const ReconciliacaoInfo();
      if (rec.status == StatusReconciliacao.executando) {
        throw OperacaoNaoPermitidaException('Comparativo', inventarioId,
            'já está sendo gerado por outro aparelho; aguarde e atualize');
      }
      if (rec.concluida && !refazer) return true;

      final c3 = inv.statusRodada(Rodadas.c3);
      if (refazer &&
          (c3 == StatusRodada.emAndamento || c3 == StatusRodada.encerrada)) {
        throw OperacaoNaoPermitidaException('Comparativo', inventarioId,
            'a C3 já começou; o comparativo não pode ser refeito');
      }

      tx.update(ref, {
        'reconciliacao.status': StatusReconciliacao.executando,
        'reconciliacao.executor_uid': uid,
        'reconciliacao.iniciada_em': FieldValue.serverTimestamp(),
      });
      AuditEventService.registrarNaTransacao(
        tx,
        inventarioId: inventarioId,
        tipo: TipoEvento.reconciliacaoIniciada,
        uid: uid,
        dados: {'refazer': refazer},
      );
      return false;
    });

    if (jaPronto) {
      return ResumoComparativo.de(await lerComparativo(inventarioId));
    }

    try {
      // 2) Lê e compara.
      final c1 = await carregarRodada(inventarioId, Rodadas.c1);
      final c2 = await carregarRodada(inventarioId, Rodadas.c2);
      // L5: Materiais → só Materiais; Gases/Cilindros → os dois.
      final gerados = consolidadosDoTipo(naturezaInv);
      // B73: informativas já gravadas com c3_fora = true.
      final linhas = marcarForaDaC3(
          compararC1C2(c1, c2)
              .where((l) => gerados.contains(l.natureza))
              .toList(),
          naturezaInv);
      final resumo = ResumoComparativo.de(linhas);
      // C3 só é necessária se houver divergência do consolidado do tipo.
      final paraC3 = divergenciasParaC3(linhas, naturezaInv);

      // 3) Apaga linhas antigas (refazer) e grava as novas, em lotes.
      final antigas = await _linhas(inventarioId)
          .get(const GetOptions(source: Source.server));
      final novos = {for (final l in linhas) l.docId};
      final ops = <void Function(WriteBatch)>[];
      for (final d in antigas.docs) {
        // Só apaga o que não será regravado (nada de duas escritas no mesmo
        // documento num lote).
        if (!novos.contains(d.id)) ops.add((b) => b.delete(d.reference));
      }
      for (final l in linhas) {
        ops.add((b) => b.set(_linhas(inventarioId).doc(l.docId), {
              ...l.toMap(),
              'gerado_em': FieldValue.serverTimestamp(),
            }));
      }
      const tamanho = 400;
      for (var i = 0; i < ops.length; i += tamanho) {
        final batch = _fs.batch();
        for (final op in ops.skip(i).take(tamanho)) {
          op(batch);
        }
        await batch.commit();
      }

      // 4) Fecha: resumo no inventário + estado da C3.
      final fim = _fs.batch();
      fim.update(ref, {
        'reconciliacao.status': StatusReconciliacao.concluida,
        'reconciliacao.concluida_em': FieldValue.serverTimestamp(),
        'reconciliacao.total_linhas': resumo.total,
        'reconciliacao.encerradas': resumo.encerradas,
        // L5: pendências = só as que vão para a C3. As do outro consolidado
        // (ex.: Cilindros num inventário de Gases) são informativas.
        'reconciliacao.em_analise': paraC3,
        'reconciliacao.divergencias_informativas': resumo.emAnalise - paraC3,
        'contagens.${Rodadas.c3}.status': paraC3 > 0
            ? StatusRodada.pendente
            : StatusRodada.naoNecessaria,
        'contagens.${Rodadas.c3}.total_tarefas': paraC3,
      });
      AuditEventService.registrarNoBatch(
        fim,
        inventarioId: inventarioId,
        tipo: TipoEvento.reconciliacaoConcluida,
        uid: uid,
        dados: {
          'total': resumo.total,
          'encerradas': resumo.encerradas,
          'em_analise': resumo.emAnalise,
          'lancamentos_c1': c1.length,
          'lancamentos_c2': c2.length,
        },
      );
      await fim.commit();
      debugPrint('✅ Comparativo $inventarioId: ${resumo.total} linhas, '
          '${resumo.emAnalise} em análise');
      return resumo;
    } catch (e) {
      // Libera a reserva para nova tentativa.
      try {
        await ref.update({
          'reconciliacao.status': StatusReconciliacao.naoExecutada,
        });
      } catch (_) {}
      rethrow;
    }
  }

  /// Linhas gravadas do comparativo (servidor), em análise primeiro.
  Future<List<LinhaComparativo>> lerComparativo(String inventarioId) async {
    final snap = await _linhas(inventarioId)
        .get(const GetOptions(source: Source.server));
    final linhas =
        snap.docs.map((d) => LinhaComparativo.deMapa(d.data())).toList();
    linhas.sort((x, y) {
      if (x.emAnalise != y.emAnalise) return x.emAnalise ? -1 : 1;
      final c = x.codigo.compareTo(y.codigo);
      return c != 0 ? c : x.chave.compareTo(y.chave);
    });
    return linhas;
  }
}
