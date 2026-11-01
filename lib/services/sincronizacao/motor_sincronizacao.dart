// lib/services/sincronizacao/motor_sincronizacao.dart
//
// Pacote 1 (fila offline): motor de envio dos lançamentos Hive → Firestore.
//
// Regras:
// - Idempotente: o documento remoto é sempre `lancamentos/{uid}_{idLocal}`
//   (set com merge). Reenviar nunca duplica.
// - Uma execução por usuário de cada vez (trava). A automática não espera
//   (se já tem uma rodando, sai); a manual espera a vez.
// - Cada operação remota tem limite de tempo. Tempo esgotado = "rede": o
//   registro continua pendente e a rodada para (sem prender a fila).
// - Falha de rede/passageira: continua `pending`, com tentativa e próxima
//   hora registradas; o motor tenta de novo sozinho.
// - Recusa DEFINITIVA (ex.: rodada encerrada): `error`, motivo registrado,
//   NUNCA apagado do aparelho e NUNCA mais enviado à coleção oficial pelo
//   aparelho — nem pelo reenvio manual, nem se a rodada for reaberta
//   (rev1). O único caminho é a Recuperação (`lancamentos_recuperacao`,
//   fora do resultado), por onde o analista decide.
// - Erro antigo sem motivo registrado (de antes deste controle): se o texto
//   guardado for de recusa de permissão, vira recusa definitiva (sem
//   reenvio); senão volta para a fila uma vez.
// - Exclusão pendente (tombstone, B21) continua tombstone em qualquer falha:
//   o registro nunca "ressuscita".
// - Exclusões ANTIGAS pendentes (SharedPreferences `delete_pending`, que
//   nada processava antes): o motor conclui as do usuário logado, com as
//   mesmas regras de falha (rev1).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lego/data/local/lanc_local.dart';
import 'package:lego/data/local/registro_sync.dart';
import 'package:lego/data/repositories/lancamentos_repository.dart';
import 'package:lego/models/sessao_contagem.dart' show kDeletePending;
import 'package:lego/services/sincronizacao/falha_sync.dart';
import 'package:lego/services/sincronizacao/observador_pendencias.dart'
    show kChaveExclusoesLegadas, avisarMudancaExclusoesLegadas;
import 'package:lego/services/sincronizacao/pendencias_sync.dart'
    show ExclusaoLegada;

/// Operações remotas (o Firestore em produção; um falso nos testes).
abstract class RemotoLancamentos {
  Future<void> gravar(String docId, Map<String, dynamic> dados);
  Future<void> apagar(String docId);
  /// Documento oficial atual (null se não existe). Só para anexar à
  /// Recuperação de uma exclusão antiga recusada.
  Future<Map<String, dynamic>?> lerOficial(String docId);
  Future<bool> recuperacaoExiste(String docId);
  Future<void> gravarRecuperacao(String docId, Map<String, dynamic> dados);
}

class FirestoreRemotoLancamentos implements RemotoLancamentos {
  final FirebaseFirestore _fs;
  FirestoreRemotoLancamentos([FirebaseFirestore? fs])
      : _fs = fs ?? FirebaseFirestore.instance;

  @override
  Future<void> gravar(String docId, Map<String, dynamic> dados) => _fs
      .collection('lancamentos')
      .doc(docId)
      .set(dados, SetOptions(merge: true));

  @override
  Future<void> apagar(String docId) =>
      _fs.collection('lancamentos').doc(docId).delete();

  @override
  Future<Map<String, dynamic>?> lerOficial(String docId) async => (await _fs
          .collection('lancamentos')
          .doc(docId)
          .get(const GetOptions(source: Source.server)))
      .data();

  /// Leitura no SERVIDOR: sem conexão lança erro (o motor tenta depois).
  @override
  Future<bool> recuperacaoExiste(String docId) async => (await _fs
          .collection('lancamentos_recuperacao')
          .doc(docId)
          .get(const GetOptions(source: Source.server)))
      .exists;

  @override
  Future<void> gravarRecuperacao(String docId, Map<String, dynamic> dados) =>
      _fs.collection('lancamentos_recuperacao').doc(docId).set({
        ...dados,
        'recebido_em': FieldValue.serverTimestamp(),
      });
}

enum ResultadoEnvio {
  enviado,
  excluido,
  rede,
  transitorio,
  definitivo,
  /// rev1: recusado em definitivo antes; o aparelho não reenvia à coleção
  /// oficial (só Recuperação).
  rejeitadoNaoReenviado,
  recuperacaoEnviada,
  jaSincronizado,
  naoEncontrado,
  naoTentado,
}

extension ResultadoEnvioRotulo on ResultadoEnvio {
  String get rotulo => switch (this) {
        ResultadoEnvio.enviado => 'Enviado',
        ResultadoEnvio.excluido => 'Exclusão enviada',
        ResultadoEnvio.rede => 'Sem conexão',
        ResultadoEnvio.transitorio => 'Falha passageira',
        ResultadoEnvio.definitivo => 'Rejeitado pelo servidor',
        ResultadoEnvio.rejeitadoNaoReenviado =>
          'Rejeitado: não reenviado (só Recuperação)',
        ResultadoEnvio.recuperacaoEnviada => 'Cópia na Recuperação',
        ResultadoEnvio.jaSincronizado => 'Já estava sincronizado',
        ResultadoEnvio.naoEncontrado => 'Não está mais no aparelho',
        ResultadoEnvio.naoTentado => 'Não tentado (conexão interrompida)',
      };

  bool get sucesso =>
      this == ResultadoEnvio.enviado ||
      this == ResultadoEnvio.excluido ||
      this == ResultadoEnvio.jaSincronizado ||
      this == ResultadoEnvio.recuperacaoEnviada;
}

class ResultadoItem {
  /// Id local do lançamento, ou `del:<docId>` para exclusão antiga.
  final String idLocal;
  final ResultadoEnvio resultado;
  final String? codigo;
  final String? mensagem;
  const ResultadoItem(this.idLocal, this.resultado,
      {this.codigo, this.mensagem});

  @override
  String toString() => '$idLocal: ${resultado.name}'
      '${codigo == null ? '' : ' ($codigo)'}';
}

/// Texto de erro antigo (gravado antes do Pacote 1) que indica recusa de
/// permissão — não pode voltar sozinho para a coleção oficial.
bool erroAntigoEhRecusa(String? texto) {
  final t = (texto ?? '').toLowerCase();
  return t.contains('permission-denied') ||
      t.contains('permission_denied') ||
      t.contains('missing or insufficient permissions');
}

class MotorSincronizacao {
  final String uid;
  final LancamentosRepository repo;
  final RegistroSync registro;
  final RemotoLancamentos remoto;
  final DateTime Function() agora;
  final Duration limiteOperacao;

  MotorSincronizacao({
    required this.uid,
    LancamentosRepository? repo,
    RegistroSync? registro,
    RemotoLancamentos? remoto,
    DateTime Function()? agora,
    this.limiteOperacao = const Duration(seconds: 20),
  })  : repo = repo ?? LancamentosRepository(uid: uid),
        registro = registro ?? RegistroSync(uid),
        remoto = remoto ?? FirestoreRemotoLancamentos(),
        agora = agora ?? DateTime.now;

  // ------------------------------------------------------------------
  // Trava por usuário
  // ------------------------------------------------------------------
  static final Map<String, Future<void>> _emCurso = {};

  static bool emExecucao(String uid) => _emCurso.containsKey(uid);

  Future<T> _exclusivo<T>(Future<T> Function() f,
      {required bool esperar}) async {
    while (_emCurso.containsKey(uid)) {
      if (!esperar) throw const _Ocupado();
      await _emCurso[uid];
    }
    final c = Completer<void>();
    _emCurso[uid] = c.future;
    try {
      return await f();
    } finally {
      _emCurso.remove(uid);
      c.complete();
    }
  }

  // ------------------------------------------------------------------
  // API
  // ------------------------------------------------------------------

  /// Envio automático. [ignorarEspera] = acabou de voltar a conexão: tenta já
  /// os que esperavam por rede. Devolve null se outra execução estava em
  /// curso (nada foi feito).
  Future<List<ResultadoItem>?> executarAutomatico(
      {bool ignorarEspera = false}) async {
    try {
      return await _exclusivo(() => _executar(ignorarEspera: ignorarEspera),
          esperar: false);
    } on _Ocupado {
      return null;
    }
  }

  /// Reenvio manual de falhas de envio (painel do coletor). [ids] null:
  /// todas as pendências deste usuário (inclusive exclusões antigas, como
  /// `del:<docId>`). Registros recusados em definitivo NÃO são reenviados à
  /// coleção oficial: voltam como [ResultadoEnvio.rejeitadoNaoReenviado].
  /// Espera a vez se houver envio em curso.
  Future<List<ResultadoItem>> reenviar([Iterable<String>? ids]) =>
      _exclusivo(() => _reenviar(ids?.toList()), esperar: true);

  /// Recuperação administrativa (manual): garante a cópia dos recusados em
  /// definitivo na Recuperação. Não toca a coleção oficial. [ids] null:
  /// todos os recusados deste usuário.
  Future<List<ResultadoItem>> recuperar([Iterable<String>? ids]) =>
      _exclusivo(() => _recuperar(ids?.toSet()), esperar: true);

  // ------------------------------------------------------------------
  // Execução automática
  // ------------------------------------------------------------------

  Future<List<ResultadoItem>> _executar({required bool ignorarEspera}) async {
    final todos = await repo.listarTodos();
    var estados = await registro.todos();
    final t = agora();

    // Erro antigo sem motivo registrado.
    for (final l in todos) {
      if (l.status != LancStatus.error ||
          l.errorCode == kDeletePending ||
          estados[l.idLocal]?.tipo != null) {
        continue;
      }
      if (erroAntigoEhRecusa(l.errorCode)) {
        // Recusa de permissão anterior ao Pacote 1: definitivo, sem reenvio.
        final e = (estados[l.idLocal] ?? const EstadoSync()).comFalha(
            FalhaSync(TipoFalhaSync.definitivo, 'permission-denied',
                'Recusa registrada antes do Pacote 1: ${l.errorCode}'),
            t);
        await registro.gravar(l.idLocal, e);
        await registro.registrar(EventoSync(
            idLocal: l.idLocal,
            em: t,
            acao: 'envio',
            resultado: 'definitivo',
            codigo: 'permission-denied',
            mensagem: 'Erro antigo de permissão: não reenviado'));
      } else {
        await repo.definirStatus(l.idLocal, LancStatus.pending);
        await registro.registrar(EventoSync(
            idLocal: l.idLocal,
            em: t,
            acao: 'envio',
            resultado: 'reenfileirado',
            mensagem: 'Erro antigo sem motivo registrado: '
                '${l.errorCode ?? ''}'));
      }
    }
    estados = await registro.todos();

    bool elegivel(EstadoSync? e) {
      if (e == null) return true;
      if (e.definitivo || e.esgotado) return false;
      final prox = e.proximaTentativa;
      if (prox == null || !prox.isAfter(t)) return true;
      return ignorarEspera && e.tipo == TipoFalhaSync.rede;
    }

    final fila = (await repo.listarTodos())
        .where((l) =>
            l.status == LancStatus.pending && elegivel(estados[l.idLocal]))
        .toList()
      ..sort((a, b) => a.createdAtLocal.compareTo(b.createdAtLocal));

    final out = await _enviarLista(fila, manual: false);
    final semRede = out.any((r) =>
        r.resultado == ResultadoEnvio.naoTentado ||
        (r.resultado == ResultadoEnvio.rede && r.codigo == 'timeout'));
    if (!semRede) {
      estados = await registro.todos();
      final legadas = [
        for (final d in await _lerExclusoesLegadas())
          if (elegivel(estados[ExclusaoLegada.chaveDe(d)])) d,
      ];
      out.addAll(await _excluirLegadas(legadas, manual: false));
    }
    await _enviarRecuperacoesPendentes(await registro.todos());
    return out;
  }

  // ------------------------------------------------------------------
  // Reenvio manual
  // ------------------------------------------------------------------

  Future<List<ResultadoItem>> _reenviar(List<String>? ids) async {
    final todos = {for (final l in await repo.listarTodos()) l.idLocal: l};
    final estados = await registro.todos();
    final legadas = (await _lerExclusoesLegadas()).toSet();
    final pedidos = ids ??
        [
          for (final l in todos.values)
            if (l.status != LancStatus.synced) l.idLocal,
          for (final d in legadas) ExclusaoLegada.chaveDe(d),
        ];
    final out = <ResultadoItem>[];
    final fila = <LancLocal>[];
    final legadasPedidas = <String>[];
    for (final id in pedidos) {
      if (id.startsWith('del:')) {
        final docId = id.substring(4);
        if (!legadas.contains(docId)) {
          out.add(ResultadoItem(id, ResultadoEnvio.jaSincronizado));
        } else if (estados[id]?.definitivo == true) {
          out.add(ResultadoItem(id, ResultadoEnvio.rejeitadoNaoReenviado,
              codigo: estados[id]?.codigo));
        } else {
          legadasPedidas.add(docId);
        }
        continue;
      }
      final l = todos[id];
      if (l == null) {
        out.add(ResultadoItem(id, ResultadoEnvio.naoEncontrado));
        continue;
      }
      if (l.status == LancStatus.synced) {
        out.add(ResultadoItem(id, ResultadoEnvio.jaSincronizado));
        continue;
      }
      final e = estados[id];
      // rev1: recusa definitiva NÃO volta à coleção oficial pelo aparelho,
      // mesmo que a rodada tenha sido reaberta. Caminho: Recuperação.
      if (e != null && e.definitivo) {
        out.add(ResultadoItem(id, ResultadoEnvio.rejeitadoNaoReenviado,
            codigo: e.codigo, mensagem: e.mensagem));
        continue;
      }
      if (l.status == LancStatus.error) {
        if (e == null && erroAntigoEhRecusa(l.errorCode)) {
          // Erro antigo de permissão: trata como definitivo, sem reenvio.
          await registro.gravar(
              id,
              const EstadoSync().comFalha(
                  FalhaSync(TipoFalhaSync.definitivo, 'permission-denied',
                      'Recusa registrada antes do Pacote 1: ${l.errorCode}'),
                  agora()));
          out.add(ResultadoItem(id, ResultadoEnvio.rejeitadoNaoReenviado,
              codigo: 'permission-denied'));
          continue;
        }
        await repo.definirStatus(id, LancStatus.pending);
      }
      if (e != null) await registro.gravar(id, e.liberadoParaReenvio());
      fila.add((await repo.obter(id)) ?? l);
    }
    fila.sort((a, b) => a.createdAtLocal.compareTo(b.createdAtLocal));
    out.addAll(await _enviarLista(fila, manual: true));
    out.addAll(await _excluirLegadas(legadasPedidas, manual: true));
    await _enviarRecuperacoesPendentes(await registro.todos(), manual: true);
    return out;
  }

  // ------------------------------------------------------------------
  // Envio de lançamentos (Hive)
  // ------------------------------------------------------------------

  Future<List<ResultadoItem>> _enviarLista(List<LancLocal> fila,
      {required bool manual}) async {
    final out = <ResultadoItem>[];
    var semRede = false;
    for (final l in fila) {
      if (semRede) {
        out.add(ResultadoItem(l.idLocal, ResultadoEnvio.naoTentado));
        continue;
      }
      final r = await _enviarUm(l, manual: manual);
      out.add(r);
      // Tempo esgotado: provavelmente sem conexão. Não prende a fila com N
      // esperas seguidas; o resto fica para a próxima execução.
      if (r.resultado == ResultadoEnvio.rede && r.codigo == 'timeout') {
        semRede = true;
      }
    }
    return out;
  }

  Future<ResultadoItem> _enviarUm(LancLocal l, {required bool manual}) async {
    final docId = '${uid}_${l.idLocal}';
    final exclusao = l.errorCode == kDeletePending;
    final estado = await registro.de(l.idLocal) ?? const EstadoSync();
    final t0 = agora();
    try {
      if (exclusao) {
        await remoto.apagar(docId).timeout(limiteOperacao);
        await repo.hardDeleteLocal(l.idLocal);
        await registro.remover(l.idLocal);
      } else {
        await remoto.gravar(docId, l.toJson()).timeout(limiteOperacao);
        await repo.markSynced(l.idLocal, docId);
        await registro.gravar(l.idLocal, estado.comSucesso(t0));
      }
      await registro.registrar(EventoSync(
          idLocal: l.idLocal,
          em: t0,
          acao: exclusao ? 'exclusao' : 'envio',
          resultado: 'ok',
          manual: manual));
      return ResultadoItem(l.idLocal,
          exclusao ? ResultadoEnvio.excluido : ResultadoEnvio.enviado);
    } catch (erro) {
      final f = classificarFalha(erro);
      // rev2: o tempo esgotado da Future NÃO cancela a escrita que o SDK do
      // Firestore já enfileirou; ela pode ter chegado ao servidor antes do
      // encerramento. Se agora vem uma recusa, confere o documento oficial:
      // igual ao do aparelho = já estava lá (sincronizado, sem Recuperação);
      // exclusão cujo documento não existe mais = já excluído.
      if (f.tipo == TipoFalhaSync.definitivo) {
        if (!exclusao && await _confirmadoNoServidor(l, docId)) {
          await repo.markSynced(l.idLocal, docId);
          await registro.gravar(l.idLocal, estado.comSucesso(t0));
          await registro.registrar(EventoSync(
              idLocal: l.idLocal,
              em: t0,
              acao: 'envio',
              resultado: 'ok',
              manual: manual,
              codigo: f.codigo,
              mensagem: 'Recusa na regravação, mas o servidor já tinha o '
                  'registro igual (escrita anterior confirmada)'));
          return ResultadoItem(l.idLocal, ResultadoEnvio.jaSincronizado,
              codigo: f.codigo);
        }
        if (exclusao && await _exclusaoJaFeita(docId)) {
          await repo.hardDeleteLocal(l.idLocal);
          await registro.remover(l.idLocal);
          await registro.registrar(EventoSync(
              idLocal: l.idLocal,
              em: t0,
              acao: 'exclusao',
              resultado: 'ok',
              manual: manual,
              codigo: f.codigo,
              mensagem: 'Documento já não existia no servidor'));
          return ResultadoItem(l.idLocal, ResultadoEnvio.excluido,
              codigo: f.codigo);
        }
      }
      final novo = estado.comFalha(f, t0);
      await registro.gravar(l.idLocal, novo);
      // Definitivo ou esgotado: sai de `pending` (exceto tombstone, que
      // continua tombstone para nunca ser regravado).
      if (!exclusao && (novo.definitivo || novo.esgotado)) {
        await repo.markError(l.idLocal, '${f.codigo}: ${f.mensagem}');
      }
      await registro.registrar(EventoSync(
          idLocal: l.idLocal,
          em: t0,
          acao: exclusao ? 'exclusao' : 'envio',
          resultado: f.tipo.name,
          manual: manual,
          codigo: f.codigo,
          mensagem: f.mensagem));
      return ResultadoItem(l.idLocal, _resultadoDe(f),
          codigo: f.codigo, mensagem: f.mensagem);
    }
  }

  ResultadoEnvio _resultadoDe(FalhaSync f) => switch (f.tipo) {
        TipoFalhaSync.rede => ResultadoEnvio.rede,
        TipoFalhaSync.transitorio => ResultadoEnvio.transitorio,
        TipoFalhaSync.definitivo => ResultadoEnvio.definitivo,
      };

  /// Campos que identificam o conteúdo de um lançamento no servidor.
  static const _camposConteudo = [
    'uid', 'codigo', 'lote', 'tag', 'cheio', 'vazio', 'quantidade',
    'prateleira', 'localizacaoId', 'inventarioId', 'contagemId', 'createdAt',
  ];

  static bool mesmoConteudo(
      Map<String, dynamic> oficial, Map<String, dynamic> local) {
    for (final k in _camposConteudo) {
      final a = oficial[k];
      final b = local[k];
      if (a is num && b is num) {
        if (a.toDouble() != b.toDouble()) return false;
      } else if ((a ?? '') != (b ?? '')) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _confirmadoNoServidor(LancLocal l, String docId) async {
    try {
      final oficial = await remoto.lerOficial(docId).timeout(limiteOperacao);
      return oficial != null && mesmoConteudo(oficial, l.toJson());
    } catch (_) {
      return false;
    }
  }

  Future<bool> _exclusaoJaFeita(String docId) async {
    try {
      return (await remoto.lerOficial(docId).timeout(limiteOperacao)) == null;
    } catch (_) {
      return false;
    }
  }

  /// Escopo de um documento oficial (`simples` ou `<inv>__<rodada>`).
  static String escopoDoOficial(Map<String, dynamic> d) {
    final inv = '${d['inventarioId'] ?? ''}';
    return inv.isEmpty ? 'simples' : '${inv}__${d['contagemId'] ?? ''}';
  }

  // ------------------------------------------------------------------
  // Exclusões antigas (SharedPreferences `delete_pending`)
  // ------------------------------------------------------------------

  /// Só as do usuário logado (as regras só deixam apagar o próprio).
  Future<List<String>> _lerExclusoesLegadas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return [
        for (final d in prefs.getStringList(kChaveExclusoesLegadas) ??
            const <String>[])
          if (d.startsWith('${uid}_')) d,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _removerExclusaoLegada(String docId) async {
    final prefs = await SharedPreferences.getInstance();
    final l = List<String>.of(
        prefs.getStringList(kChaveExclusoesLegadas) ?? const <String>[])
      ..removeWhere((d) => d == docId);
    await prefs.setStringList(kChaveExclusoesLegadas, l);
    avisarMudancaExclusoesLegadas();
  }

  Future<List<ResultadoItem>> _excluirLegadas(List<String> docIds,
      {required bool manual}) async {
    final out = <ResultadoItem>[];
    for (final docId in docIds) {
      final chave = ExclusaoLegada.chaveDe(docId);
      var estado = await registro.de(chave) ?? const EstadoSync();
      final t0 = agora();
      // rev2: identifica o escopo pelo documento oficial (se ainda não
      // sabe). Sem leitura possível, continua "não classificado" — nunca
      // presume a rodada atual.
      if (estado.escopo == null) {
        try {
          final oficial =
              await remoto.lerOficial(docId).timeout(limiteOperacao);
          if (oficial != null) {
            estado = estado.comEscopo(escopoDoOficial(oficial));
            await registro.gravar(chave, estado);
          }
        } catch (_) {/* fica não classificado */}
      }
      try {
        await remoto.apagar(docId).timeout(limiteOperacao);
        await _removerExclusaoLegada(docId);
        await registro.remover(chave);
        await registro.registrar(EventoSync(
            idLocal: chave,
            em: t0,
            acao: 'exclusao',
            resultado: 'ok',
            manual: manual,
            mensagem: 'Exclusão antiga concluída'));
        out.add(ResultadoItem(chave, ResultadoEnvio.excluido));
      } catch (erro) {
        final f = classificarFalha(erro);
        // rev2: as regras recusam apagar documento que já não existe; se o
        // oficial sumiu, a exclusão está feita.
        if (f.tipo == TipoFalhaSync.definitivo && await _exclusaoJaFeita(docId)) {
          await _removerExclusaoLegada(docId);
          await registro.remover(chave);
          await registro.registrar(EventoSync(
              idLocal: chave,
              em: t0,
              acao: 'exclusao',
              resultado: 'ok',
              manual: manual,
              codigo: f.codigo,
              mensagem: 'Documento já não existia no servidor'));
          out.add(ResultadoItem(chave, ResultadoEnvio.excluido,
              codigo: f.codigo));
          continue;
        }
        await registro.gravar(chave, estado.comFalha(f, t0));
        await registro.registrar(EventoSync(
            idLocal: chave,
            em: t0,
            acao: 'exclusao',
            resultado: f.tipo.name,
            manual: manual,
            codigo: f.codigo,
            mensagem: f.mensagem));
        out.add(ResultadoItem(chave, _resultadoDe(f),
            codigo: f.codigo, mensagem: f.mensagem));
        if (f.tipo == TipoFalhaSync.rede) break;
      }
    }
    return out;
  }

  // ------------------------------------------------------------------
  // Recuperação (recusa definitiva)
  // ------------------------------------------------------------------

  /// Cada recusa definitiva vai para `lancamentos_recuperacao/{uid}_{idLocal}`
  /// uma vez (confere no servidor antes): inclusão recusada, exclusão
  /// recusada (tombstone) ou exclusão antiga recusada. O analista vê; o
  /// inventário encerrado não muda.
  Future<List<ResultadoItem>> _enviarRecuperacoesPendentes(
      Map<String, EstadoSync> estados,
      {bool manual = false,
      Set<String>? apenas}) async {
    final out = <ResultadoItem>[];
    final candidatos = estados.entries
        .where((e) =>
            e.value.definitivo &&
            e.value.recuperacaoEnviadaEm == null &&
            (apenas == null || apenas.contains(e.key)))
        .toList();
    for (final c in candidatos) {
      final legada = c.key.startsWith('del:');
      final docId = legada ? c.key.substring(4) : '${uid}_${c.key}';
      LancLocal? l;
      if (!legada) {
        l = await repo.obter(c.key);
        if (l == null) continue;
      }
      final t0 = agora();
      try {
        final existe =
            await remoto.recuperacaoExiste(docId).timeout(limiteOperacao);
        if (!existe) {
          final Map<String, dynamic> dados;
          if (legada) {
            Map<String, dynamic>? oficial;
            try {
              oficial = await remoto.lerOficial(docId).timeout(limiteOperacao);
            } catch (_) {
              oficial = null; // anexo opcional
            }
            dados = dadosRecuperacaoExclusaoAntiga(docId, c.value, oficial);
          } else {
            dados = dadosRecuperacao(l!, c.value);
          }
          await remoto
              .gravarRecuperacao(docId, dados)
              .timeout(limiteOperacao);
        }
        await registro.gravar(c.key, c.value.comRecuperacao(enviadaEm: t0));
        await registro.registrar(EventoSync(
            idLocal: c.key,
            em: t0,
            acao: 'recuperacao',
            resultado: 'ok',
            manual: manual,
            mensagem: existe ? 'já estava na Recuperação' : null));
        out.add(ResultadoItem(c.key, ResultadoEnvio.recuperacaoEnviada));
      } catch (erro) {
        final f = classificarFalha(erro);
        await registro.gravar(
            c.key, c.value.comRecuperacao(erro: '${f.codigo}: ${f.mensagem}'));
        await registro.registrar(EventoSync(
            idLocal: c.key,
            em: t0,
            acao: 'recuperacao',
            resultado: f.tipo.name,
            manual: manual,
            codigo: f.codigo,
            mensagem: f.mensagem));
        out.add(ResultadoItem(c.key, _resultadoDe(f),
            codigo: f.codigo, mensagem: f.mensagem));
        // Sem rede: não insiste nos outros agora.
        if (f.tipo == TipoFalhaSync.rede) break;
      }
    }
    return out;
  }

  Future<List<ResultadoItem>> _recuperar(Set<String>? ids) async {
    final estados = await registro.todos();
    final out = <ResultadoItem>[];
    if (ids != null) {
      for (final id in ids) {
        final e = estados[id];
        if (e == null || !e.definitivo) {
          out.add(ResultadoItem(id, ResultadoEnvio.naoTentado,
              mensagem: 'Não é uma recusa definitiva'));
        } else if (e.recuperacaoEnviadaEm != null) {
          out.add(ResultadoItem(id, ResultadoEnvio.recuperacaoEnviada,
              mensagem: 'já estava na Recuperação'));
        }
      }
    }
    out.addAll(await _enviarRecuperacoesPendentes(estados,
        manual: true, apenas: ids));
    return out;
  }

  /// Conteúdo da cópia de recuperação de um lançamento do aparelho: o
  /// lançamento como seria enviado, mais a identificação local, a operação
  /// recusada e o motivo. O `createdAt` é o do aparelho (hora do lançamento).
  Map<String, dynamic> dadosRecuperacao(LancLocal l, EstadoSync e) => {
        ...l.toJson(),
        'idLocal': l.idLocal,
        'operacao': l.errorCode == kDeletePending ? 'exclusao' : 'inclusao',
        'motivo_codigo': e.codigo,
        'motivo_mensagem': e.mensagem,
        'rejeitado_em': e.ultimaTentativa == null
            ? null
            : Timestamp.fromDate(e.ultimaTentativa!),
        'tentativas': e.tentativas,
        'situacao': 'aguardando_analise',
      };

  /// Exclusão antiga recusada: só existe o id do documento oficial; anexa o
  /// conteúdo atual dele, se foi possível ler.
  Map<String, dynamic> dadosRecuperacaoExclusaoAntiga(
          String docId, EstadoSync e, Map<String, dynamic>? oficial) =>
      {
        'uid': uid,
        'idLocal': docId.substring(uid.length + 1),
        'operacao': 'exclusao',
        'doc_oficial': docId,
        'inventarioId': oficial?['inventarioId'] ?? '',
        'contagemId': oficial?['contagemId'] ?? '',
        if (oficial != null) 'registro_oficial': oficial,
        'motivo_codigo': e.codigo,
        'motivo_mensagem': e.mensagem,
        'rejeitado_em': e.ultimaTentativa == null
            ? null
            : Timestamp.fromDate(e.ultimaTentativa!),
        'tentativas': e.tentativas,
        'situacao': 'aguardando_analise',
      };
}

class _Ocupado implements Exception {
  const _Ocupado();
}
