import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

import 'package:lego/data/local/app_state.dart';
import 'package:lego/data/local/barra_local.dart';
import 'package:lego/data/local/produto_local.dart';
import 'package:lego/data/local/hive_boxes.dart';

/// Comprimento padrão das tags (complementa com zeros à esquerda)
const int _kTagLength = 9;

String _normalizarTag(String tag) => tag.trim().padLeft(_kTagLength, '0');

/// Serviço de sincronização das coleções fixas (barras e produtos).
///
/// Escuta o documento [sistema/versoes] em tempo real.
/// Quando qualquer versão muda, sincroniza apenas a coleção afetada.
class FixedCollectionsSync {
  final _fs = FirebaseFirestore.instance;

  StreamSubscription<DocumentSnapshot>? _versaoListener;

  Box<AppState> get _appStateBox => Hive.box<AppState>(HiveBoxes.appStateBox);
  Box<ProdutoLocal> get _prodBox => Hive.box<ProdutoLocal>(HiveBoxes.produtosBox);
  Box<BarraLocal> get _barBox => Hive.box<BarraLocal>(HiveBoxes.barrasBox);

  // ─── AppState helpers ────────────────────────────────────────────────────

  AppState _ensureAppState() {
    var st = _appStateBox.get('state');
    if (st == null) {
      st = AppState();
      _appStateBox.put('state', st);
    }
    return st;
  }

  void _saveAppState({
    String? lastSyncBarrasIso,
    String? lastSyncProdutosIso,
    int? seedVersion,
    int? versaoBarras,
    int? versaoProdutos,
    String? cursorBarrasShard,
    String? cursorProdutosShard,
    bool? handover,
  }) {
    final st = _ensureAppState();
    if (lastSyncBarrasIso != null) st.lastSyncBarras = lastSyncBarrasIso;
    if (lastSyncProdutosIso != null) st.lastSyncProdutos = lastSyncProdutosIso;
    if (seedVersion != null) st.seedVersion = seedVersion;
    if (versaoBarras != null) st.versaoBarras = versaoBarras;
    if (versaoProdutos != null) st.versaoProdutos = versaoProdutos;
    if (cursorBarrasShard != null) st.cursorBarrasShard = cursorBarrasShard;
    if (cursorProdutosShard != null) st.cursorProdutosShard = cursorProdutosShard;
    if (handover != null) st.handover = handover;
    _appStateBox.put('state', st);
  }

  // ─── Listener de versão em tempo real ────────────────────────────────────

  /// Inicia o listener do documento [sistema/versoes].
  /// Deve ser chamado uma vez após o login do usuário.
  void iniciarListenerVersao() {
    _versaoListener?.cancel();

    _versaoListener = _fs
        .collection('sistema')
        .doc('versoes')
        .snapshots()
        .listen((snap) async {
      if (!snap.exists) return;

      final data = snap.data()!;
      final versaoBarrasRemota = (data['versaoBarras'] as num?)?.toInt() ?? 1;
      final versaoProdutosRemota = (data['versaoProdutos'] as num?)?.toInt() ?? 1;

      final st = _ensureAppState();
      final versaoBarrasLocal = st.versaoBarras ?? 0;
      final versaoProdutosLocal = st.versaoProdutos ?? 0;

      log('[VERSAO] Barras: local=$versaoBarrasLocal remota=$versaoBarrasRemota | '
          'Produtos: local=$versaoProdutosLocal remota=$versaoProdutosRemota');

      if (versaoBarrasRemota > versaoBarrasLocal) {
        log('[VERSAO] Nova versão de barras detectada. Sincronizando...');
        await _syncBarras();
        _saveAppState(versaoBarras: versaoBarrasRemota);
      }

      if (versaoProdutosRemota > versaoProdutosLocal) {
        log('[VERSAO] Nova versão de produtos detectada. Sincronizando...');
        await _syncProdutos();
        _saveAppState(versaoProdutos: versaoProdutosRemota);
      }
    }, onError: (e) {
      log('[VERSAO] Erro no listener: $e');
    });

    log('[VERSAO] Listener iniciado.');
  }

  /// Para o listener. Chamar no logout ou dispose do app.
  void pararListenerVersao() {
    _versaoListener?.cancel();
    _versaoListener = null;
    log('[VERSAO] Listener encerrado.');
  }

  // ─── Sync de barras ───────────────────────────────────────────────────────

  Future<void> _syncBarras() async {
    int count = 0;
    String? lastId;

    final q = _fs.collection('barras').orderBy(FieldPath.documentId);

    for (;;) {
      var qq = q.limit(500);
      if (lastId != null) qq = qq.startAfter([lastId]);

      final snap = await qq.get();
      if (snap.docs.isEmpty) break;

      for (final d in snap.docs) {
        final data = d.data();

        // ✅ Normaliza a tag para 9 dígitos com zeros à esquerda
        final tag = _normalizarTag(
          (data['tag']?.toString().isNotEmpty == true)
              ? data['tag'].toString()
              : d.id,
        );

        _barBox.put(
          tag,
          BarraLocal(
            codigo: (data['codigo'] ?? '').toString(),
            lote: (data['lote'] ?? '').toString(),
            tag: tag,
            updatedAt: (data['updatedAt'] is Timestamp)
                ? (data['updatedAt'] as Timestamp).toDate()
                : DateTime.tryParse((data['updatedAt'] ?? '').toString()),
          ),
        );
        count++;
      }
      lastId = snap.docs.last.id;
    }

    _saveAppState(lastSyncBarrasIso: DateTime.now().toUtc().toIso8601String());
    log('[SYNC] Barras sincronizadas: $count');
  }

  // ─── Sync de produtos ─────────────────────────────────────────────────────

  Future<void> _syncProdutos() async {
    int count = 0;
    String? lastId;

    final q = _fs.collection('materiais').orderBy(FieldPath.documentId);

    for (;;) {
      var qq = q.limit(500);
      if (lastId != null) qq = qq.startAfter([lastId]);

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
        count++;
      }
      lastId = snap.docs.last.id;
    }

    _saveAppState(lastSyncProdutosIso: DateTime.now().toUtc().toIso8601String());
    log('[SYNC] Produtos sincronizados: $count');
  }

  // ─── Full sync (mantido para compatibilidade / primeiro acesso) ───────────

  Future<void> fullSync() async {
    _ensureAppState();
    log('[FULL] iniciando...');
    await _syncProdutos();
    await _syncBarras();
    log('[FULL] concluído.');
  }

  /// Chamado pelo ConnectivityService quando a rede volta.
  Future<void> ensureIncrementalInBackground() async {
    try {
      await fullSync();
    } catch (e, st) {
      log('[SYNC-INCR] erro: $e', stackTrace: st);
    }
  }
}
