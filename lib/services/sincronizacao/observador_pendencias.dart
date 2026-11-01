// lib/services/sincronizacao/observador_pendencias.dart
//
// Pacote 1: fonte de dados do painel "Pendências de envio".
// Reage a QUALQUER mudança no aparelho:
//   - caixa dos lançamentos (status, exclusão pendente);
//   - caixa `sync_meta_<uid>` (tentativa, motivo, próxima hora, Recuperação),
//     mesmo quando o lançamento em si não muda (rev1);
//   - lista antiga `delete_pending` (SharedPreferences), que não tem escuta
//     própria: aviso explícito de quem grava + conferência a cada
//     [intervaloConferenciaExclusoes] (rev2).
// Só dados locais: funciona sem internet.

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:lego/data/local/registro_sync.dart';
import 'package:lego/data/repositories/lancamentos_repository.dart';
import 'package:lego/services/sincronizacao/pendencias_sync.dart';

/// Chave do mecanismo antigo de exclusão remota pendente
/// (LancamentosRepository.delete, caminho legado).
const String kChaveExclusoesLegadas = 'delete_pending';

/// Conferência periódica da lista antiga (rede de segurança para gravações
/// que não avisaram).
Duration intervaloConferenciaExclusoes = const Duration(seconds: 5);

final StreamController<void> _exclusoesMudaram =
    StreamController<void>.broadcast();

/// Quem altera `delete_pending` chama isto (repositório e motor).
void avisarMudancaExclusoesLegadas() {
  if (!_exclusoesMudaram.isClosed) _exclusoesMudaram.add(null);
}

Future<List<String>> lerExclusoesLegadas() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(kChaveExclusoesLegadas) ?? const [];
  } catch (_) {
    return const [];
  }
}

/// Retrato atual das pendências do usuário.
/// [escoposExtras]: escopos verificados mesmo sem lançamento (ex.: a sessão
/// ativa do Completo).
Future<QuadroPendencias> lerQuadroPendencias(
    String uid, LancamentosRepository repo, RegistroSync reg,
    {Set<String> escoposExtras = const {}}) async {
  final todos = await repo.listarTodos();
  final estados = await reg.todos();
  final exclusoes =
      montarExclusoesLegadas(uid, await lerExclusoesLegadas(), estados);
  return QuadroPendencias(
    montarPendencias(todos, estados),
    exclusoes,
    {
      for (final l in todos) escopoDe(l),
      ...escoposExtras,
      for (final x in exclusoes)
        if (x.escopo != kEscopoNaoClassificado) x.escopo,
    },
  );
}

/// Emite o retrato ATUAL assim que alguém escuta (rev3: sem depender de
/// nenhuma mudança) e um novo a cada mudança (lançamentos, estado de
/// sincronização ou lista antiga de exclusões). Erro de leitura sai como
/// erro do stream; a escuta continua e a próxima mudança tenta de novo.
/// [leitor]: só para testes (substitui a leitura do aparelho).
Stream<QuadroPendencias> observarPendencias(
    String uid, LancamentosRepository repo, RegistroSync reg,
    {Future<QuadroPendencias> Function()? leitor}) {
  final ler = leitor ?? () => lerQuadroPendencias(uid, repo, reg);
  StreamSubscription<void>? a;
  StreamSubscription<void>? b;
  StreamSubscription<void>? d;
  Timer? conferencia;
  var assinaturaExclusoes = '';
  late final StreamController<QuadroPendencias> c;
  var emLeitura = false;
  var deNovo = false;

  Future<void> emitir() async {
    // Coalesce rajadas de mudanças numa leitura por vez.
    if (emLeitura) {
      deNovo = true;
      return;
    }
    emLeitura = true;
    try {
      do {
        deNovo = false;
        try {
          final q = await ler();
          assinaturaExclusoes = (await lerExclusoesLegadas()).join('|');
          if (!c.isClosed) c.add(q);
        } catch (e, st) {
          if (!c.isClosed) c.addError(e, st);
        }
      } while (deNovo && !c.isClosed);
    } finally {
      emLeitura = false;
    }
  }

  Future<void> conferirExclusoes() async {
    final atual = (await lerExclusoesLegadas()).join('|');
    if (atual != assinaturaExclusoes) await emitir();
  }

  c = StreamController<QuadroPendencias>(
    onListen: () {
      // Retrato inicial já, independente de qualquer mudança.
      emitir();
      void erro(Object e, StackTrace st) {
        if (!c.isClosed) c.addError(e, st);
      }
      a = repo.mudancas().listen((_) => emitir(), onError: erro);
      b = reg.mudancas().listen((_) => emitir(), onError: erro);
      d = _exclusoesMudaram.stream.listen((_) => emitir());
      conferencia = Timer.periodic(
          intervaloConferenciaExclusoes, (_) => conferirExclusoes());
    },
    onCancel: () async {
      conferencia?.cancel();
      await a?.cancel();
      await b?.cancel();
      await d?.cancel();
    },
  );
  return c.stream;
}
