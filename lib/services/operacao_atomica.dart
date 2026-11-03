// lib/services/operacao_atomica.dart
//
// Item 7 (03/11) — no Windows (Desktop), a biblioteca nativa do Firestore
// derruba o app em transações sobre inventários (provado nos diagnósticos
// de 01/11 e, no Desktop de uso, ao encerrar/iniciar contagens). Por isso o
// app NÃO usa `runTransaction` no Windows:
//
//   Android/iOS: transação de verdade (como sempre);
//   Windows/macOS/Linux: as leituras do corpo vão ao SERVIDOR; as gravações
//   são acumuladas num WriteBatch e gravadas JUNTAS no fim (tudo ou nada).
//   Se o corpo recusar (exceção), nada é gravado e o erro volta para a tela.
//
// O que se perde no Desktop é só a releitura atômica (corrida entre dois
// analistas no mesmo segundo). As validações de estado continuam dentro do
// corpo, com dados lidos do servidor um instante antes da gravação.

import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';

/// O que o corpo de uma operação atômica pode fazer (o mesmo subconjunto
/// de [Transaction] que o app usa).
abstract class OperacaoAtomica {
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
      DocumentReference<Map<String, dynamic>> ref);
  void update(DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> dados);
  void set(DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> dados,
      [SetOptions? opcoes]);
}

/// true no computador (Desktop): usa leitura + lote em vez de transação.
/// Mutável só para testes.
bool usarLoteEmVezDeTransacao =
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Executa [corpo] como transação (celular) ou leitura + lote (Desktop).
Future<T> executarAtomico<T>(
  FirebaseFirestore fs,
  Future<T> Function(OperacaoAtomica op) corpo,
) async {
  if (!usarLoteEmVezDeTransacao) {
    return fs.runTransaction<T>((tx) => corpo(_NaTransacao(tx)));
  }
  final lote = _EmLote(fs);
  final resultado = await corpo(lote);
  await lote.gravar();
  return resultado;
}

class _NaTransacao implements OperacaoAtomica {
  final Transaction _tx;
  _NaTransacao(this._tx);

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
          DocumentReference<Map<String, dynamic>> ref) =>
      _tx.get(ref);

  @override
  void update(DocumentReference<Map<String, dynamic>> ref,
          Map<String, dynamic> dados) =>
      _tx.update(ref, dados);

  @override
  void set(DocumentReference<Map<String, dynamic>> ref,
          Map<String, dynamic> dados,
          [SetOptions? opcoes]) =>
      _tx.set(ref, dados, opcoes);
}

class _EmLote implements OperacaoAtomica {
  final WriteBatch _lote;
  var _gravacoes = 0;
  _EmLote(FirebaseFirestore fs) : _lote = fs.batch();

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
          DocumentReference<Map<String, dynamic>> ref) =>
      ref.get(const GetOptions(source: Source.server));

  @override
  void update(DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> dados) {
    _lote.update(ref, dados);
    _gravacoes++;
  }

  @override
  void set(DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> dados,
      [SetOptions? opcoes]) {
    _lote.set(ref, dados, opcoes);
    _gravacoes++;
  }

  Future<void> gravar() async {
    if (_gravacoes > 0) await _lote.commit();
  }
}
