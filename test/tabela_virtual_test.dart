// test/tabela_virtual_test.dart
// Item 6 (03/11): a tabela do relatório desenha só as linhas visíveis.
// Rodar com: flutter test test/tabela_virtual_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lego/services/relatorio_inventario.dart' show AbaRelatorio;
import 'package:lego/ui/analista/tabela_virtual.dart';

AbaRelatorio abaGrande(int linhas, {int colunas = 18}) => AbaRelatorio(
      'C1 Lançamentos',
      [
        ['Título'],
        [for (var c = 0; c < colunas; c++) 'Coluna $c'],
        for (var r = 0; r < linhas; r++)
          [for (var c = 0; c < colunas; c++) 'L$r C$c'],
      ],
      linhaCabecalho: 1,
    );

Widget emTela(AbaRelatorio a) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          height: 700,
          child: TabelaVirtual(aba: a, formatar: (v) => '${v ?? ''}'),
        ),
      ),
    );

void main() {
  testWidgets('3.250 linhas × 18 colunas: só as linhas visíveis são montadas',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(emTela(abaGrande(3250)));
    await tester.pump();

    expect(find.text('Coluna 0'), findsOneWidget); // cabeçalho
    expect(find.text('L0 C0'), findsOneWidget); // primeira linha
    expect(find.text('L3249 C0'), findsNothing); // última: não montada
    // Com 700 px e 30 px por linha, cabem ~22 linhas (+ cache do ListView).
    final montadas = find.textContaining(RegExp(r'^L\d+ C0$')).evaluate().length;
    expect(montadas, lessThan(60));

    // Rolar até o fim monta a última linha.
    await tester.drag(find.text('L0 C0'), const Offset(0, -200000));
    await tester.pumpAndSettle();
    expect(find.text('L3249 C0'), findsOneWidget);
  });

  test('larguras: pelo texto mais longo, com mínimo e máximo', () {
    final w = TabelaVirtual.largurasPara(
      ['A', 'Descrição'],
      [
        ['x', 'curta'],
        ['y', 'uma descrição bem mais longa que as outras'],
        ['z', 'x' * 500],
      ],
      (v) => '${v ?? ''}',
    );
    expect(w[0], 56); // mínimo
    expect(w[1], 420); // máximo
  });
}
