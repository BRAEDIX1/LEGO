import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'package:lego/data/local/app_state.dart';
import 'package:lego/data/local/hive_boxes.dart';

class ContagemChoicePage extends StatelessWidget {
  const ContagemChoicePage({super.key});

  Future<void> _selecionarContagem(BuildContext context, int numero) async {
    // Reutiliza o box já aberto e tipado.
    final box = Hive.box<AppState>(HiveBoxes.appStateBox);

    // Garante que existe um AppState salvo sob a chave 'state'.
    final state = box.get('state') ?? AppState();
    state.contagemAtual = numero;
    await box.put('state', state);

    if (context.mounted) {
      // Volta pra Home depois de escolher a contagem.
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final itens = const [1, 2, 3, 4, 5];

    return Scaffold(
      appBar: AppBar(title: const Text('Selecione a contagem')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: itens.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final n = itens[index];
          return InkWell(
            onTap: () => _selecionarContagem(context, n),
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Row(
                children: [
                  CircleAvatar(child: Text('$n')),
                  const SizedBox(width: 12),
                  Text('Contagem $n',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
