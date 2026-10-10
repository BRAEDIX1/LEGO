// test/analista_test.dart — item 8: quem é analista (app_config.analistas).
import 'package:flutter_test/flutter_test.dart';
import 'package:lego/services/analista.dart';

void main() {
  const lista = ['d6gz41@linde.com'];
  test('e-mail na lista → analista', () {
    expect(ehAnalista(lista, 'd6gz41@linde.com'), isTrue);
  });
  test('maiúsculas e espaços não importam', () {
    expect(ehAnalista([' D6GZ41@Linde.com '], 'd6gz41@LINDE.com '), isTrue);
  });
  test('e-mail fora da lista → não', () {
    expect(ehAnalista(lista, 'operador@linde.com'), isFalse);
  });
  test('lista ausente, vazia ou de outro tipo → ninguém (falha fechada)', () {
    expect(ehAnalista(null, 'd6gz41@linde.com'), isFalse);
    expect(ehAnalista(<String>[], 'd6gz41@linde.com'), isFalse);
    expect(ehAnalista('d6gz41@linde.com', 'd6gz41@linde.com'), isFalse);
  });
  test('sem e-mail → não', () {
    expect(ehAnalista(lista, null), isFalse);
    expect(ehAnalista(lista, ''), isFalse);
  });
}
