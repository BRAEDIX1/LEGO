// lib/services/hive_diagnostics.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import 'package:lego/data/local/hive_boxes.dart';
import 'package:lego/data/local/lanc_local.dart';
import 'package:lego/data/local/produto_local.dart';
import 'package:lego/data/local/barra_local.dart';

class HiveSnapshot {
  final String uid;
  final int lancCount;
  final int produtosCount;
  final int barrasCount;
  final List<dynamic> lancKeys;
  final List<dynamic> produtoKeys;
  final List<dynamic> barraKeys;
  final int pendentes;
  final int sincronizados;
  final int erros;
  final List<LancLocal> lancSample;
  final DateTime capturedAt;

  HiveSnapshot({
    required this.uid,
    required this.lancCount,
    required this.produtosCount,
    required this.barrasCount,
    required this.lancKeys,
    required this.produtoKeys,
    required this.barraKeys,
    required this.pendentes,
    required this.sincronizados,
    required this.erros,
    required this.lancSample,
    required this.capturedAt,
  });
}

class HiveDiagnostics {
  /// Captura um snapshot das boxes abertas para o usuário atual.
  /// [sample]: número de itens (0 = sem amostra).
  static Future<HiveSnapshot> captureForCurrentUser({int sample = 0}) async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'unknown';
    final lancBoxName = 'lancamentos_$uid';

    try { HiveBoxes.ensureAdapters(); } catch (_) {}

    Box<LancLocal>? lancBox;
    if (Hive.isBoxOpen(lancBoxName)) {
      lancBox = Hive.box<LancLocal>(lancBoxName);
    }

    Box<ProdutoLocal>? prodBox;
    if (Hive.isBoxOpen(HiveBoxes.produtosBox)) {
      prodBox = Hive.box<ProdutoLocal>(HiveBoxes.produtosBox);
    }

    Box<BarraLocal>? barBox;
    if (Hive.isBoxOpen(HiveBoxes.barrasBox)) {
      barBox = Hive.box<BarraLocal>(HiveBoxes.barrasBox);
    }

    // Contagens de status
    int pend = 0, sync = 0, err = 0;
    final sampleItems = <LancLocal>[];
    if (lancBox != null) {
      for (final v in lancBox.values) {
        if (v.status == LancStatus.pending) pend++;
        else if (v.status == LancStatus.synced) sync++;
        else if (v.status == LancStatus.error) err++;
      }
      if (sample > 0) {
        for (final v in lancBox.values.take(sample)) {
          sampleItems.add(v);
        }
      }
    }

    return HiveSnapshot(
      uid: uid,
      lancCount: lancBox?.length ?? 0,
      produtosCount: prodBox?.length ?? 0,
      barrasCount: barBox?.length ?? 0,
      lancKeys: lancBox?.keys.take(20).toList() ?? const [],
      produtoKeys: prodBox?.keys.take(20).toList() ?? const [],
      barraKeys: barBox?.keys.take(20).toList() ?? const [],
      pendentes: pend,
      sincronizados: sync,
      erros: err,
      lancSample: sampleItems,
      capturedAt: DateTime.now(),
    );
  }

  /// Banner informativo. Aceita 0 ou 1 argumento.
  static Widget bannerForCurrentUser([HiveSnapshot? snap]) {
    final s = snap;
    if (s == null) {
      return const Card(
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Sem snapshot (chame captureForCurrentUser primeiro).'),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'UID: ${s.uid}\n'
          'Lanc: ${s.lancCount} | Prod: ${s.produtosCount} | Barras: ${s.barrasCount}\n'
          'Pend: ${s.pendentes}  Sync: ${s.sincronizados}  Erros: ${s.erros}\n'
          'Lanc keys: ${s.lancKeys}\n'
          'Prod keys: ${s.produtoKeys}\n'
          'Bar keys: ${s.barraKeys}\n'
          'Amostra: ${s.lancSample.map((e)=>e.idLocal).toList()}\n'
          'At: ${s.capturedAt.toIso8601String()}',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ),
    );
  }
}
