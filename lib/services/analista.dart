// lib/services/analista.dart
//
// Item 8: quem é analista. Fonte única: `sistema/app_config.analistas`
// (lista de e-mails). A MESMA lista é lida pelas regras do Firestore, então
// tela e servidor nunca discordam. Lista ausente ou vazia = ninguém é
// analista (falha fechada).

/// Regra pura (testável): o e-mail está na lista? Sem diferença de
/// maiúsculas nem espaços.
bool ehAnalista(Object? lista, String? email) {
  if (lista is! List || email == null) return false;
  final e = email.trim().toLowerCase();
  if (e.isEmpty) return false;
  return lista.any((x) => x is String && x.trim().toLowerCase() == e);
}
