import 'package:flutter/material.dart';

class HandoverPage extends StatelessWidget {
  const HandoverPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 64),
              const SizedBox(height: 16),
              const Text('Dispositivo aguardando o administrador.', style: TextStyle(fontSize: 18), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Existem lançamentos não enviados. Chame o administrador para concluir a sincronização.', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
            ],
          ),
        ),
      ),
    );
  }
}
