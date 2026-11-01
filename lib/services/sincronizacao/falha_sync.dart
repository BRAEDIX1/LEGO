// lib/services/sincronizacao/falha_sync.dart
//
// Pacote 1 (fila offline): classificação das falhas de envio de lançamentos.
// Função PURA (testável sem Firebase inicializado).
//
//   rede        → sem conexão / tempo esgotado / sessão a renovar: o aparelho
//                 tenta de novo sozinho, sem limite de tentativas.
//   transitorio → servidor recusou por motivo passageiro (cota, conflito,
//                 erro interno): tenta sozinho até [maxTentativasTransitorio];
//                 depois só por reenvio manual.
//   definitivo  → o servidor RECUSOU pela regra (ex.: rodada encerrada) ou
//                 pelo conteúdo: não adianta insistir sozinho. O registro
//                 fica no aparelho, visível, e vai para a Recuperação.

import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;

enum TipoFalhaSync { rede, transitorio, definitivo }

class FalhaSync {
  final TipoFalhaSync tipo;
  /// Código curto e estável (ex.: `unavailable`, `permission-denied`,
  /// `timeout`, `sem-conexao`, `desconhecido`).
  final String codigo;
  final String mensagem;
  const FalhaSync(this.tipo, this.codigo, this.mensagem);

  @override
  String toString() => '${tipo.name}/$codigo: $mensagem';
}

/// Códigos do Firestore que significam "o servidor não aceita este registro
/// assim" — repetir sem mudar nada dá o mesmo resultado.
const _definitivos = {
  'permission-denied',
  'invalid-argument',
  'failed-precondition',
  'out-of-range',
  'not-found',
  'already-exists',
  'data-loss',
  'unimplemented',
};

/// Falta de rede ou de sessão: volta sozinho quando a conexão/login voltam.
const _rede = {
  'unavailable',
  'deadline-exceeded',
  'unauthenticated',
  'network-request-failed',
};

const int maxTentativasTransitorio = 8;

FalhaSync classificarFalha(Object erro) {
  if (erro is TimeoutException) {
    return const FalhaSync(
        TipoFalhaSync.rede, 'timeout', 'Servidor não respondeu a tempo');
  }
  if (erro is SocketException || erro is HttpException) {
    return FalhaSync(TipoFalhaSync.rede, 'sem-conexao', '$erro');
  }
  if (erro is FirebaseException) {
    final c = erro.code;
    final msg = erro.message ?? c;
    if (_definitivos.contains(c)) {
      return FalhaSync(TipoFalhaSync.definitivo, c, msg);
    }
    if (_rede.contains(c)) return FalhaSync(TipoFalhaSync.rede, c, msg);
    // resource-exhausted (cota), aborted, internal, cancelled, unknown...
    return FalhaSync(TipoFalhaSync.transitorio, c, msg);
  }
  return FalhaSync(TipoFalhaSync.transitorio, 'desconhecido', '$erro');
}

/// Espera antes da próxima tentativa automática, pela quantidade de
/// tentativas já feitas (1 = primeira falha).
/// Rede: 30 s, 1, 2, 5 e no máximo 10 min. Transitório: 1, 2, 5, 10, 15, 30
/// e 60 min.
Duration esperaAntesDeReenviar(TipoFalhaSync tipo, int tentativas) {
  const rede = [30, 60, 120, 300, 600];
  const trans = [60, 120, 300, 600, 900, 1800, 3600];
  final tabela = tipo == TipoFalhaSync.rede ? rede : trans;
  final i = (tentativas - 1).clamp(0, tabela.length - 1);
  return Duration(seconds: tabela[i]);
}
