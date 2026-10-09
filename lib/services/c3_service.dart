// lib/services/c3_service.dart
//
// Entrega 3 (teste acelerado): C3 distribuída e offline.
//
// Servidor (precisa de internet): chamar participantes, confirmar "estou
// pronto", iniciar (congela participantes + distribui), baixar tarefas,
// sincronizar resultados, redistribuir pendentes, encerrar.
// Aparelho (sem internet): concluir as tarefas baixadas (SharedPreferences).
//
// Onde fica cada coisa:
// - inventarios/{id}.contagens.contagem_3: status, c3_versao, participantes
//   (congelados no início), total_tarefas.
// - inventarios/{id}/c3_participantes/{uid}: confirmação "estou pronto" e
//   progresso informado pelo aparelho.
// - inventarios/{id}/comparativo/{linha}: a tarefa (responsável, versão,
//   status) e o resultado `c3`.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/services/audit_event_service.dart';
import 'package:lego/services/c3.dart';
import 'package:lego/services/comparativo.dart';
import 'package:lego/services/inventario_service.dart'
    show OperacaoNaoPermitidaException;

/// Participante que confirmou "estou pronto" para a C3.
class ProntoC3 {
  final String uid;
  final String nome;
  final int concluidasLocais;
  final int sincronizadas;
  final DateTime? atualizadoEm;
  /// Item 6: o operador tocou em "Finalizar minha C3" (tudo sincronizado).
  final bool finalizado;
  const ProntoC3({
    required this.uid,
    required this.nome,
    this.concluidasLocais = 0,
    this.sincronizadas = 0,
    this.atualizadoEm,
    this.finalizado = false,
  });

  static ProntoC3 deDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    final ts = m['atualizado_em'];
    return ProntoC3(
      uid: d.id,
      nome: (m['nome'] ?? d.id).toString(),
      concluidasLocais: (m['concluidas_locais'] as num?)?.toInt() ?? 0,
      sincronizadas: (m['sincronizadas'] as num?)?.toInt() ?? 0,
      atualizadoEm: ts is Timestamp ? ts.toDate() : null,
      finalizado: m['finalizado'] == true,
    );
  }
}

/// Resultado de uma rodada de sincronização no aparelho.
class ResultadoSync {
  final int enviadas;
  final int recusadas;
  final int falhas; // sem rede ou erro: continuam pendentes
  const ResultadoSync(this.enviadas, this.recusadas, this.falhas);
}

class C3Service {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _inv(String id) =>
      _fs.collection('inventarios').doc(id);
  CollectionReference<Map<String, dynamic>> _linhas(String id) =>
      _inv(id).collection('comparativo');
  CollectionReference<Map<String, dynamic>> _prontos(String id) =>
      _inv(id).collection('c3_participantes');

  static const _c3 = Rodadas.c3;

  User _user() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw Exception('Usuário não autenticado');
    return u;
  }

  static String nomeDe(User u) {
    final n = u.displayName?.trim();
    return (n != null && n.isNotEmpty) ? n : (u.email ?? u.uid);
  }

  // =====================================================================
  // ANALISTA
  // =====================================================================

  /// Comparativo pronto com linhas em análise → C3 "aguardando participantes".
  /// L3: o analista escolhe UMA natureza (gás, cilindro ou material). Só as
  /// divergências dela viram tarefas; as demais ficam `c3_fora` (sem C3).
  Future<void> chamarParticipantes(
      String inventarioId, Natureza natureza) async {
    final uid = _user().uid;
    // 0) Só com a C3 pendente (não mexe nas linhas de uma C3 já aberta).
    final invAtual = Inventario.fromFirestore(await _inv(inventarioId)
        .get(const GetOptions(source: Source.server)));
    final atual = invAtual.statusRodada(_c3);
    if (atual != StatusRodada.pendente) {
      throw OperacaoNaoPermitidaException('Chamar participantes', inventarioId,
          'a C3 não está pendente (${StatusRodada.rotulo(atual)})');
    }
    // B75: inventário com tipo → a C3 só pode ser desse tipo.
    final tipoInv = NaturezaRotulo.deNome(invAtual.naturezaContagem);
    if (tipoInv != null && tipoInv != natureza) {
      throw OperacaoNaoPermitidaException('Chamar participantes', inventarioId,
          'o inventário é de ${tipoInv.rotulo}; a C3 não pode ser de '
          '${natureza.rotulo}');
    }
    // 1) Marca as linhas (idempotente: pode repetir se falhar no meio).
    final linhas = (await _linhas(inventarioId)
            .get(const GetOptions(source: Source.server)))
        .docs
        .map((d) => LinhaComparativo.deMapa(d.data()))
        .where((l) => l.emAnalise)
        .toList();
    if (!linhas.any((l) => l.natureza == natureza)) {
      throw OperacaoNaoPermitidaException('Chamar participantes', inventarioId,
          'não há divergências de ${natureza.rotulo}');
    }
    final ops = [
      for (final l in linhas)
        (WriteBatch b) => b.update(_linhas(inventarioId).doc(l.docId),
            {'c3_fora': l.natureza != natureza}),
    ];
    for (var i = 0; i < ops.length; i += 400) {
      final b = _fs.batch();
      for (final op in ops.skip(i).take(400)) {
        op(b);
      }
      await b.commit();
    }
    // 2) Abre a C3 com a natureza escolhida.
    await _fs.runTransaction<void>((tx) async {
      final snap = await tx.get(_inv(inventarioId));
      final inv = Inventario.fromFirestore(snap);
      if (inv.statusRodada(_c3) != StatusRodada.pendente) {
        throw OperacaoNaoPermitidaException('Chamar participantes', inventarioId,
            'a C3 não está pendente (${StatusRodada.rotulo(inv.statusRodada(_c3))})');
      }
      tx.update(_inv(inventarioId), {
        'contagens.$_c3.status': StatusRodada.aguardandoParticipantes,
        'contagens.$_c3.natureza': natureza.name,
        'contagens.$_c3.total_tarefas':
            linhas.where((l) => l.natureza == natureza).length,
      });
      AuditEventService.registrarNaTransacao(tx,
          inventarioId: inventarioId,
          tipo: TipoEvento.c3Liberada,
          uid: uid,
          rodada: _c3,
          dados: {'natureza': natureza.name});
    });
  }

  Stream<List<ProntoC3>> streamProntos(String inventarioId) =>
      _prontos(inventarioId).snapshots().map(
          (s) => s.docs.map(ProntoC3.deDoc).toList()
            ..sort((a, b) => a.nome.compareTo(b.nome)));

  Stream<List<LinhaComparativo>> streamLinhas(String inventarioId) =>
      _linhas(inventarioId).snapshots().map((s) =>
          s.docs.map((d) => LinhaComparativo.deMapa(d.data())).toList());

  Future<List<ProntoC3>> _prontosServidor(String inventarioId) async =>
      (await _prontos(inventarioId)
              .get(const GetOptions(source: Source.server)))
          .docs
          .map(ProntoC3.deDoc)
          .toList();

  /// "Iniciar C3" (B62): 1) trava em `distribuindo` e congela os
  /// participantes; 2) grava TODAS as tarefas; 3) só então `em_andamento`.
  /// Enquanto `distribuindo`, ninguém baixa tarefas.
  Future<Map<String, int>> iniciarC3(String inventarioId) async {
    final uid = _user().uid;
    final prontos = await _prontosServidor(inventarioId);
    if (prontos.isEmpty) {
      throw OperacaoNaoPermitidaException(
          'Iniciar C3', inventarioId, 'nenhum participante confirmou');
    }
    final uids = prontos.map((p) => p.uid).toList();
    await _fs.runTransaction<void>((tx) async {
      final snap = await tx.get(_inv(inventarioId));
      final inv = Inventario.fromFirestore(snap);
      if (inv.statusRodada(_c3) != StatusRodada.aguardandoParticipantes) {
        throw OperacaoNaoPermitidaException('Iniciar C3', inventarioId,
            'a C3 não está aguardando participantes');
      }
      tx.update(_inv(inventarioId), {
        'contagens.$_c3.status': StatusRodada.distribuindo,
        'contagens.$_c3.c3_versao': 1,
        'contagens.$_c3.usuarios': uids,
      });
      AuditEventService.registrarNaTransacao(tx,
          inventarioId: inventarioId,
          tipo: TipoEvento.c3Distribuida,
          uid: uid,
          rodada: _c3,
          dados: {'participantes': uids.length, 'versao': 1});
    });
    return _concluirDistribuicao(inventarioId, prontos);
  }

  /// Redistribui SÓ as tarefas não sincronizadas (B62): 1) trava em
  /// `redistribuindo` (versão += 1, participantes = prontos de agora);
  /// 2) RELÊ as tarefas depois da trava; 3) reatribui; 4) `em_andamento`.
  /// Com a trava, nenhuma sincronização entra no meio: ela espera.
  Future<Map<String, int>> redistribuirPendentes(String inventarioId) async {
    final uid = _user().uid;
    // B79: quem já finalizou a própria C3 não recebe tarefas novas.
    final prontos = (await _prontosServidor(inventarioId))
        .where((p) => !p.finalizado)
        .toList();
    if (prontos.isEmpty) {
      throw OperacaoNaoPermitidaException(
          'Redistribuir', inventarioId, 'nenhum participante confirmado');
    }
    await _fs.runTransaction<void>((tx) async {
      final snap = await tx.get(_inv(inventarioId));
      final inv = Inventario.fromFirestore(snap);
      if (inv.statusRodada(_c3) != StatusRodada.emAndamento) {
        throw OperacaoNaoPermitidaException(
            'Redistribuir', inventarioId, 'a C3 não está em andamento');
      }
      final v = _versao(snap) + 1;
      tx.update(_inv(inventarioId), {
        'contagens.$_c3.status': StatusRodada.redistribuindo,
        'contagens.$_c3.c3_versao': v,
        'contagens.$_c3.usuarios': prontos.map((p) => p.uid).toList(),
      });
      AuditEventService.registrarNaTransacao(tx,
          inventarioId: inventarioId,
          tipo: TipoEvento.c3Redistribuida,
          uid: uid,
          rodada: _c3,
          dados: {'versao': v, 'participantes': prontos.length});
    });
    return _concluirDistribuicao(inventarioId, prontos);
  }

  /// Retoma uma distribuição interrompida (app fechou, rede caiu): o
  /// inventário ficou em `distribuindo`/`redistribuindo`.
  Future<Map<String, int>> retomarDistribuicao(String inventarioId) async =>
      _concluirDistribuicao(inventarioId, await _prontosServidor(inventarioId));

  static int _versao(DocumentSnapshot<Map<String, dynamic>> snap) {
    final v = ((snap.data()?['contagens'] as Map?)?[_c3] as Map?)?['c3_versao'];
    return (v as num?)?.toInt() ?? 1;
  }

  Future<Map<String, int>> _concluirDistribuicao(
      String inventarioId, List<ProntoC3> prontos) async {
    final invSnap =
        await _inv(inventarioId).get(const GetOptions(source: Source.server));
    final inv = Inventario.fromFirestore(invSnap);
    final st = inv.statusRodada(_c3);
    if (st != StatusRodada.distribuindo && st != StatusRodada.redistribuindo) {
      throw OperacaoNaoPermitidaException('Distribuir', inventarioId,
          'a C3 não está distribuindo (${StatusRodada.rotulo(st)})');
    }
    final versao = _versao(invSnap);
    final congelados = inv.contagens[_c3]?.usuarios ?? const <String>[];
    final nomePorUid = {for (final p in prontos) p.uid: p.nome};
    final nomes = {for (final u in congelados) u: nomePorUid[u] ?? u};
    if (nomes.isEmpty) {
      throw OperacaoNaoPermitidaException(
          'Distribuir', inventarioId, 'nenhum participante congelado');
    }

    // Relê DEPOIS da trava: o que já sincronizou não muda de dono.
    final todas = (await _linhas(inventarioId)
            .get(const GetOptions(source: Source.server)))
        .docs
        .map((d) => LinhaComparativo.deMapa(d.data()))
        .where((l) => l.naC3) // L3: só a natureza escolhida
        .toList();
    final pendentes = todas
        .where((l) => l.c3Status != StatusTarefaC3.sincronizada)
        .map((l) => l.docId)
        .toList();

    final dist = distribuirTarefas(pendentes, nomes.keys.toList());
    final ops = <void Function(WriteBatch)>[];
    dist.forEach((resp, ids) {
      for (final id in ids) {
        ops.add((b) => b.update(_linhas(inventarioId).doc(id), {
              'c3_responsavel_uid': resp,
              'c3_responsavel_nome': nomes[resp],
              'c3_versao': versao,
              'c3_status': StatusTarefaC3.atribuida,
              'c3_atribuida_em': FieldValue.serverTimestamp(),
            }));
      }
    });
    for (var i = 0; i < ops.length; i += 400) {
      final b = _fs.batch();
      for (final op in ops.skip(i).take(400)) {
        op(b);
      }
      await b.commit();
    }

    // Libera: só agora os aparelhos baixam / sincronizam.
    await _fs.runTransaction<void>((tx) async {
      final s = await tx.get(_inv(inventarioId));
      final atual = Inventario.fromFirestore(s).statusRodada(_c3);
      if (atual != st) {
        throw OperacaoNaoPermitidaException(
            'Distribuir', inventarioId, 'estado mudou durante a distribuição');
      }
      tx.update(_inv(inventarioId), {
        'contagens.$_c3.status': StatusRodada.emAndamento,
        'contagens.$_c3.total_tarefas': todas.length,
        if (st == StatusRodada.distribuindo)
          'contagens.$_c3.iniciada_em': FieldValue.serverTimestamp(),
      });
    });
    return {for (final e in dist.entries) nomes[e.key]!: e.value.length};
  }

  /// Encerra a C3 só com 100% das tarefas sincronizadas (autoridade = servidor).
  Future<void> encerrarC3(String inventarioId) async {
    final uid = _user().uid;
    final todasLinhas = (await _linhas(inventarioId)
            .get(const GetOptions(source: Source.server)))
        .docs
        .map((d) => LinhaComparativo.deMapa(d.data()))
        .toList();
    final linhas = todasLinhas.where((l) => l.naC3).toList(); // L3
    final faltam =
        linhas.where((l) => l.c3Status != StatusTarefaC3.sincronizada).length;
    if (faltam > 0) {
      throw OperacaoNaoPermitidaException('Encerrar C3', inventarioId,
          '$faltam tarefa(s) ainda não sincronizada(s)');
    }
    await _fs.runTransaction<void>((tx) async {
      final snap = await tx.get(_inv(inventarioId));
      final inv = Inventario.fromFirestore(snap);
      if (inv.statusRodada(_c3) != StatusRodada.emAndamento) {
        throw OperacaoNaoPermitidaException(
            'Encerrar C3', inventarioId, 'a C3 não está em andamento');
      }
      // B69: a C3 resolve SÓ o consolidado escolhido. Os outros ficam
      // registrados como "C3 não selecionada" — nunca como recontados.
      final escolhida =
          NaturezaRotulo.deNome(inv.contagens[_c3]?.natureza);
      final resumo = resumoPorNatureza(todasLinhas, escolhida);
      final semC3 = todasLinhas.where((l) => l.semC3).length;
      tx.update(_inv(inventarioId), {
        'contagens.$_c3.status': StatusRodada.encerrada,
        'contagens.$_c3.finalizada_em': FieldValue.serverTimestamp(),
        'contagens.$_c3.encerrada_por': uid,
        // Pendências da C3 escolhida: zero. O inventário segue o fluxo
        // (decisão operacional); o que ficou fora está registrado abaixo.
        'reconciliacao.em_analise': 0,
        'reconciliacao.c3_natureza': escolhida?.name,
        'reconciliacao.sem_c3': semC3,
        'reconciliacao.por_natureza': {
          for (final e in resumo.entries) e.key.name: e.value.toMap(),
        },
      });
      AuditEventService.registrarNaTransacao(tx,
          inventarioId: inventarioId,
          tipo: TipoEvento.c3Encerrada,
          uid: uid,
          rodada: _c3,
          dados: {
            'tarefas': linhas.length,
            'natureza': escolhida?.name,
            'sem_c3': semC3,
          });
    });
  }

  // =====================================================================
  // OPERADOR
  // =====================================================================

  /// "Estou pronto para a C3".
  Future<void> marcarPronto(String inventarioId) async {
    final u = _user();
    await _prontos(inventarioId).doc(u.uid).set({
      'uid': u.uid,
      'nome': nomeDe(u),
      'pronto_em': FieldValue.serverTimestamp(),
      'atualizado_em': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> estouPronto(String inventarioId) async =>
      (await meuStatusC3(inventarioId)).$1;

  /// (pronto, finalizado) do usuário logado na C3 deste inventário.
  Future<(bool, bool)> meuStatusC3(String inventarioId) async {
    final u = _user();
    final d = await _prontos(inventarioId).doc(u.uid).get();
    return (d.exists, d.data()?['finalizado'] == true);
  }

  // ---- armazenamento local (offline) ----
  //
  // B61: toda leitura-modificação-gravação da lista local passa por uma fila
  // única ([_exclusivo]); a sincronização é "single-flight" e aplica cada
  // resultado sobre a lista MAIS RECENTE, tarefa por tarefa. Nada regrava
  // uma fotografia antiga.

  static Future<void> _fila = Future<void>.value();
  static Future<ResultadoSync>? _syncEmCurso;

  static Future<T> _exclusivo<T>(Future<T> Function() f) {
    final c = Completer<T>();
    _fila = _fila.then((_) async {
      try {
        c.complete(await f());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  static String _chaveLocal(String uid) => 'c3_tarefas_$uid';

  Future<(String?, String?, List<TarefaC3Local>)> _lerLocalSemFila() async {
    final u = _user();
    final prefs = await SharedPreferences.getInstance();
    final txt = prefs.getString(_chaveLocal(u.uid));
    if (txt == null) return (null, null, const <TarefaC3Local>[]);
    try {
      final j = jsonDecode(txt) as Map<String, dynamic>;
      final lista = (j['tarefas'] as List)
          .map((e) =>
              TarefaC3Local.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return (j['inventarioId'] as String?, j['numero'] as String?, lista);
    } catch (e) {
      debugPrint('⚠️ C3 local ilegível: $e');
      return (null, null, const <TarefaC3Local>[]);
    }
  }

  Future<void> _salvarLocalSemFila(
      String inventarioId, String numero, List<TarefaC3Local> t) async {
    final u = _user();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _chaveLocal(u.uid),
        jsonEncode({
          'inventarioId': inventarioId,
          'numero': numero,
          'tarefas': t.map((x) => x.toJson()).toList(),
        }));
  }

  /// Tarefas guardadas no aparelho: (inventarioId, numero, tarefas).
  Future<(String?, String?, List<TarefaC3Local>)> lerLocal() =>
      _exclusivo(_lerLocalSemFila);

  Future<void> limparLocal() => _exclusivo(() async {
        final u = _user();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_chaveLocal(u.uid));
      });

  /// Item 4 (Djalma, 09/10): a C3 não fica "eternizada" no login. Tarefas
  /// guardadas no aparelho são descartadas quando o inventário delas não é
  /// mais o ativo, ou quando a C3 dele já não está aberta. Chamar SÓ depois de
  /// uma leitura bem-sucedida do servidor (offline não se decide nada).
  /// Devolve true se descartou.
  Future<bool> descartarLocalObsoleto({
    required String? inventarioAtivoId,
    required String? statusC3Ativo,
  }) =>
      _exclusivo(() async {
        final (inv, _, _) = await _lerLocalSemFila();
        if (inv == null) return false;
        if (tarefasLocaisAindaValidas(
            inventarioLocal: inv,
            inventarioAtivoId: inventarioAtivoId,
            statusC3Ativo: statusC3Ativo)) {
          return false;
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_chaveLocal(_user().uid));
        return true;
      });

  /// Aplica [f] a UMA tarefa da lista mais recente (dentro da fila).
  Future<List<TarefaC3Local>> _atualizarTarefa(
      String docId, TarefaC3Local Function(TarefaC3Local) f) {
    return _exclusivo(() async {
      final (inv, numero, lista) = await _lerLocalSemFila();
      if (inv == null) return lista;
      final nova = [for (final t in lista) t.docId == docId ? f(t) : t];
      await _salvarLocalSemFila(inv, numero ?? '', nova);
      return nova;
    });
  }

  /// Baixa do servidor as tarefas atribuídas a mim e mescla com o aparelho.
  /// Só com a C3 em andamento (B62: nada de baixar durante a distribuição).
  Future<List<TarefaC3Local>> baixarMinhasTarefas(
      String inventarioId, String numero) async {
    final u = _user();
    final invSnap =
        await _inv(inventarioId).get(const GetOptions(source: Source.server));
    final st = Inventario.fromFirestore(invSnap).statusRodada(_c3);
    if (st != StatusRodada.emAndamento) {
      throw OperacaoNaoPermitidaException('Baixar tarefas', inventarioId,
          st == StatusRodada.distribuindo || st == StatusRodada.redistribuindo
              ? 'distribuição em andamento; tente em instantes'
              : 'a C3 não está em andamento (${StatusRodada.rotulo(st)})');
    }
    // B76: quem já finalizou a própria C3 não baixa de novo.
    if ((await meuStatusC3(inventarioId)).$2) {
      throw OperacaoNaoPermitidaException('Baixar tarefas', inventarioId,
          'você já finalizou a sua C3');
    }
    final snap = await _linhas(inventarioId)
        .where('c3_responsavel_uid', isEqualTo: u.uid)
        .get(const GetOptions(source: Source.server));
    final doServidor = <TarefaC3Local>[];
    final sincronizadas = <String>{};
    for (final d in snap.docs) {
      final l = LinhaComparativo.deMapa(d.data());
      if (l.c3Status == StatusTarefaC3.sincronizada) sincronizadas.add(d.id);
      doServidor.add(TarefaC3Local(
        docId: d.id,
        chave: l.chave,
        // L3: o tipo da tarefa é a natureza (material | cilindro | gas).
        tipo: l.natureza.name,
        codigo: l.natureza == Natureza.cilindro ? l.identificacao : l.codigo,
        lote: l.lote,
        descricao: l.descricao,
        localId: l.localId,
        localNome: l.localNome,
        prateleira: l.prateleira,
        volumeUnitario: l.volumeUnitario,
        versao: l.c3Versao ?? 1,
      ));
    }
    return _exclusivo(() async {
      final (invLocal, _, locais) = await _lerLocalSemFila();
      final mescladas = mesclarTarefas(
        doServidor: doServidor,
        sincronizadasNoServidor: sincronizadas,
        locais: invLocal == inventarioId ? locais : const [],
      )..sort((a, b) => a.codigo.compareTo(b.codigo));
      await _salvarLocalSemFila(inventarioId, numero, mescladas);
      return mescladas;
    });
  }

  /// Conclui uma tarefa NO APARELHO (funciona sem internet).
  Future<List<TarefaC3Local>> concluirLocal(
          TarefaC3Local tarefa, TotaisRodada valores) =>
      _atualizarTarefa(
        tarefa.docId,
        (t) => t.copyWith(
            estado: EstadoLocalC3.concluidaLocal,
            resultado: valores.toMap(),
            concluidaEm: DateTime.now().toIso8601String()),
      );

  /// Envia as tarefas concluídas no aparelho. Single-flight (B61): se já
  /// houver uma sincronização em curso, devolve a mesma.
  Future<ResultadoSync> sincronizar() {
    final emCurso = _syncEmCurso;
    if (emCurso != null) return emCurso;
    final f = _sincronizarUmaVez().whenComplete(() => _syncEmCurso = null);
    _syncEmCurso = f;
    return f;
  }

  Future<ResultadoSync> _sincronizarUmaVez() async {
    final u = _user();
    final (invId, _, retrato) = await lerLocal();
    if (invId == null) return const ResultadoSync(0, 0, 0);

    var env = 0, rec = 0, fal = 0;
    // O retrato só escolhe O QUE enviar; cada resposta é aplicada sobre a
    // lista mais recente e só se a tarefa ainda for a mesma conclusão.
    final aEnviar =
        retrato.where((t) => t.estado == EstadoLocalC3.concluidaLocal).toList();
    for (final t in aEnviar) {
      (DecisaoSync, String?) decisao;
      try {
        decisao = await _fs.runTransaction<(DecisaoSync, String?)>((tx) async {
          final invSnap = await tx.get(_inv(invId));
          final linhaRef = _linhas(invId).doc(t.docId);
          final linhaSnap = await tx.get(linhaRef);
          final status = ((invSnap.data()?['contagens'] as Map?)?[_c3]
              as Map?)?['status'] as String?;
          final m = linhaSnap.data() ?? const <String, dynamic>{};
          final d = decidirSync(
            statusC3Inventario: status,
            responsavelLinha: m['c3_responsavel_uid'] as String?,
            versaoLinha: (m['c3_versao'] as num?)?.toInt(),
            statusLinha: m['c3_status'] as String?,
            uid: u.uid,
            versaoTarefa: t.versao,
          );
          if (d.$1 != DecisaoSync.aceitar) return d;
          tx.update(linhaRef, {
            'c3': t.resultado,
            'c3_quem': nomeDe(u),
            'c3_uid': u.uid,
            'c3_status': StatusTarefaC3.sincronizada,
            'c3_concluida_no_aparelho_em': t.concluidaEm,
            'c3_em': FieldValue.serverTimestamp(),
          });
          return d;
        }).timeout(const Duration(seconds: 15));
      } catch (e) {
        // Sem rede: para aqui; o resto fica para a próxima tentativa.
        fal = aEnviar.length - env - rec;
        break;
      }

      bool mesmaConclusao(TarefaC3Local x) =>
          x.versao == t.versao &&
          x.concluidaEm == t.concluidaEm &&
          x.estado == EstadoLocalC3.concluidaLocal;

      switch (decisao.$1) {
        case DecisaoSync.aceitar:
          env++;
          await _atualizarTarefa(t.docId, (x) => mesmaConclusao(x)
              ? x.copyWith(estado: EstadoLocalC3.sincronizada)
              : x);
        case DecisaoSync.recusar:
          rec++;
          await _atualizarTarefa(t.docId, (x) => mesmaConclusao(x)
              ? x.copyWith(
                  estado: EstadoLocalC3.recusada, motivoRecusa: decisao.$2)
              : x);
        case DecisaoSync.aguardar:
          fal++; // fica concluída no aparelho; reenviar depois
      }
    }
    final (_, _, atual) = await lerLocal();
    await informarProgresso(invId, atual);
    return ResultadoSync(env, rec, fal);
  }

  /// Informa ao monitor quantas tarefas este aparelho já concluiu
  /// (melhor esforço; sem rede não faz nada).
  /// Item 6: "Finalizar minha C3". Só com 100% das tarefas do aparelho
  /// sincronizadas (o botão já fica desabilitado antes disso; aqui é a
  /// garantia). Marca o participante como finalizado no servidor e só então
  /// limpa o aparelho (item 4).
  Future<void> finalizarMinhaC3() async {
    final u = _user();
    final (invId, _, lista) = await lerLocal();
    if (invId == null) return;
    if (!todasSincronizadas(lista)) {
      throw OperacaoNaoPermitidaException('Finalizar C3', invId,
          'ainda há tarefa(s) não sincronizada(s)');
    }
    await _prontos(invId).doc(u.uid).set({
      'finalizado': true,
      'finalizado_em': FieldValue.serverTimestamp(),
      'sincronizadas':
          lista.where((t) => t.estado == EstadoLocalC3.sincronizada).length,
      'atualizado_em': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).timeout(const Duration(seconds: 15));
    await limparLocal();
  }

  /// B77: participante congelado na C3 que recebeu ZERO tarefas. Só finaliza
  /// se o servidor confirmar: C3 em andamento, eu entre os participantes e
  /// nenhuma linha atribuída a mim (não confunde com "ainda não baixei").
  Future<void> finalizarSemTarefas(String inventarioId) async {
    final u = _user();
    final inv = Inventario.fromFirestore(
        await _inv(inventarioId).get(const GetOptions(source: Source.server)));
    final atribuidas = (await _linhas(inventarioId)
            .where('c3_responsavel_uid', isEqualTo: u.uid)
            .get(const GetOptions(source: Source.server)))
        .docs
        .length;
    if (!podeFinalizarSemTarefas(
      statusC3: inv.statusRodada(_c3),
      participantes: inv.contagens[_c3]?.usuarios ?? const [],
      uid: u.uid,
      atribuidasNoServidor: atribuidas,
    )) {
      throw OperacaoNaoPermitidaException('Finalizar C3', inventarioId,
          atribuidas > 0
              ? 'há $atribuidas item(ns) atribuídos a você'
              : 'a C3 não está em andamento ou você não participa dela');
    }
    await _prontos(inventarioId).doc(u.uid).set({
      'finalizado': true,
      'finalizado_em': FieldValue.serverTimestamp(),
      'sem_tarefas': true,
      'atualizado_em': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await limparLocal();
  }

  Future<void> informarProgresso(
      String inventarioId, List<TarefaC3Local> lista) async {
    try {
      final u = _user();
      await _prontos(inventarioId).doc(u.uid).set({
        'concluidas_locais': lista
            .where((t) =>
                t.estado == EstadoLocalC3.concluidaLocal ||
                t.estado == EstadoLocalC3.sincronizada)
            .length,
        'sincronizadas':
            lista.where((t) => t.estado == EstadoLocalC3.sincronizada).length,
        'atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}
