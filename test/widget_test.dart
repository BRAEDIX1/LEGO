import 'package:flutter_test/flutter_test.dart';
import 'package:lego/main.dart'; // nome do pacote = name do pubspec.yaml (lego)

void main() {
  testWidgets('app renderiza a HomePage', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('Firebase inicializado com sucesso! 🚀'), findsOneWidget);
  });
}