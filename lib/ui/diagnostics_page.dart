
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:lego/services/hive_diagnostics.dart';
import 'package:lego/data/local/lanc_local.dart';

/// Página de diagnóstico visual do Hive.
/// Use temporariamente para conferir se o aparelho está com dados locais.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  late Future _future;

  @override
  void initState() {
    super.initState();
    _future = HiveDiagnostics.captureForCurrentUser(sample: 10);
  }

  void _refresh() {
    setState(() {
      _future = HiveDiagnostics.captureForCurrentUser(sample: 10);
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'SEM_UID';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico do Hive'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))
        ],
      ),
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Erro: ${snap.error}'));
          }
          final data = snap.data as HiveSnapshot;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              HiveDiagnostics.bannerForCurrentUser(),
              const SizedBox(height: 12),
              _tile('Usuário', uid),
              _tile('Produtos (Hive)', '${data.produtosCount} • amostra: ${data.produtoKeys}'),
              _tile('Barras (Hive)',   '${data.barrasCount} • amostra: ${data.barraKeys}'),
              _tile('Lançamentos (Hive)', '${data.lancCount} • P:${data.pendentes} S:${data.sincronizados} E:${data.erros}'),
              const SizedBox(height: 12),
              const Text('Amostra de lançamentos locais:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...data.lancSample.map(_lancTile),
              const SizedBox(height: 40),
              const Text('Se Produtos e Barras = 0, o Hive está vazio. Verifique:', style: TextStyle(fontSize: 12)),
              const Text('- assets/firestore_dump.json contém materiais + gases + barras', style: TextStyle(fontSize: 12)),
              const Text('- pubspec.yaml inclui assets/firestore_dump.json', style: TextStyle(fontSize: 12)),
              const Text('- OfflineBootstrap.run(user) foi chamado após o login', style: TextStyle(fontSize: 12)),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(String title, String subtitle) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      tileColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _lancTile(LancLocal e) {
    final status = e.status.toString().split('.').last;
    final dt = e.createdAtLocal.toLocal().toString().substring(0, 19);
    return Card(
      child: ListTile(
        leading: Icon(
          status == 'pending' ? Icons.hourglass_top :
          status == 'synced'  ? Icons.check_circle   :
                                Icons.error,
        ),
        title: Text('${e.codigo} — ${e.descricao}'),
        subtitle: Text('${e.quantidade} ${e.unidade}  •  ${e.prateleira}  •  $dt'),
        trailing: Text(status.toUpperCase()),
        dense: true,
      ),
    );
  }
}
