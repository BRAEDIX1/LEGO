import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

// modelos/boxes
import 'package:lego/data/local/app_state.dart';
import 'package:lego/data/local/barra_local.dart';
import 'package:lego/data/local/produto_local.dart';
import 'package:lego/data/local/hive_boxes.dart';

/// Serviço de sincronização das coleções fixas (barras e produtos)
class FixedCollectionsSync {
  final _fs = FirebaseFirestore.instance;

  Box<AppState> get _appStateBox => Hive.box<AppState>(HiveBoxes.appStateBox);
  Box<ProdutoLocal> get _prodBox =>
      Hive.box<ProdutoLocal>(HiveBoxes.produtosBox);
  Box<BarraLocal> get _barBox => Hive.box<BarraLocal>(HiveBoxes.barrasBox);

  /// Garante que exista um registro AppState simples
  AppState _ensureAppState() {
    var st = _appStateBox.get('state');
    if (st == null) {
      st = AppState();
      _appStateBox.put('state', st);
    }
    return st;
  }

  /// Salva o AppState (imutabilidade manual para não depender de copyWith)
  void _saveAppState({
    String? lastSyncBarrasIso,
    String? lastSyncProdutosIso,
    int? seedVersion,
    String? cursorBarrasShard,
    String? cursorProdutosShard,
    bool? handover,
  }) {
    final st = _ensureAppState();
    if (lastSyncBarrasIso != null) st.lastSyncBarras = lastSyncBarrasIso;
    if (lastSyncProdutosIso != null) st.lastSyncProdutos = lastSyncProdutosIso;
    if (seedVersion != null) st.seedVersion = seedVersion;
    if (cursorBarrasShard != null) st.cursorBarrasShard = cursorBarrasShard;
    if (cursorProdutosShard != null) st.cursorProdutosShard = cursorProdutosShard;
    if (handover != null) st.handover = handover;
    _appStateBox.put('state', st);
  }

  /// Full sync simples com paginação por documentId
  Future<void> fullSync() async {
    _ensureAppState();
    log('[FULL] iniciando...');

    // ---- produtos (materiais)
    int prodCount = 0;
    {
      Query<Map<String, dynamic>> q =
      _fs.collection('materiais').orderBy(FieldPath.documentId);
      String? lastId;
      for (;;) {
        var qq = q.limit(500);
        if (lastId != null) {
          qq = qq.startAfter([lastId]);
        }
        final snap = await qq.get();
        if (snap.docs.isEmpty) break;

        for (final d in snap.docs) {
          final data = d.data();
          _prodBox.put(
            d.id,
            ProdutoLocal(
              codigo: d.id,
              descricao: (data['descricao'] ?? '').toString(),
              unidade: (data['unidade'] ?? '').toString(),
              origem: 'materiais',
              updatedAt: (data['updatedAt'] is Timestamp)
                  ? (data['updatedAt'] as Timestamp).toDate()
                  : DateTime.tryParse((data['updatedAt'] ?? '').toString()),
            ),
          );
          prodCount++;
        }
        lastId = snap.docs.last.id;
      }
    }

    // ---- barras
    int barCount = 0;
    {
      Query<Map<String, dynamic>> q =
      _fs.collection('barras').orderBy(FieldPath.documentId);
      String? lastId;
      for (;;) {
        var qq = q.limit(500);
        if (lastId != null) {
          qq = qq.startAfter([lastId]);
        }
        final snap = await qq.get();
        if (snap.docs.isEmpty) break;

        for (final d in snap.docs) {
          final data = d.data();
          _barBox.put(
            d.id,
            BarraLocal(
              codigo: (data['codigo'] ?? '').toString(),
              lote: (data['lote'] ?? '').toString(),
              tag: (data['tag'] ?? '').toString(),
              updatedAt: (data['updatedAt'] is Timestamp)
                  ? (data['updatedAt'] as Timestamp).toDate()
                  : DateTime.tryParse((data['updatedAt'] ?? '').toString()),
            ),
          );
          barCount++;
        }
        lastId = snap.docs.last.id;
      }
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();
    _saveAppState(
      lastSyncBarrasIso: nowIso,
      lastSyncProdutosIso: nowIso,
    );

    log('[FULL] concluído; barras=$barCount produtos=$prodCount');
  }

  /// Chamado pelo ConnectivityService quando a rede volta
  Future<void> ensureIncrementalInBackground() async {
    // Para evitar divergências com AppState antigo, aqui simplificamos:
    // ao recuperar a rede, roda um fullSync leve (pode aprimorar depois).
    try {
      await fullSync();
    } catch (e, st) {
      log('[SYNC-INCR] erro: $e', stackTrace: st);
    }
  }
}