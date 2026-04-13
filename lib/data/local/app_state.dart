// lib/data/local/app_state.dart
import 'package:hive/hive.dart';

part 'app_state.g.dart';

@HiveType(typeId: 2)
class AppState extends HiveObject {
  // armazenados como ISO-8601 (String) para simplicidade
  @HiveField(0)
  String? lastSyncMateriais;

  @HiveField(1)
  String? lastSyncBarras;

  @HiveField(2)
  String? lastSyncGases;

  @HiveField(3)
  DateTime? lastLogin;

  @HiveField(4)
  String? lastSyncProdutos;

  // controle de seed/versão
  @HiveField(5)
  int seedVersion;

  // cursores (se usar sharding/paginação)
  @HiveField(6)
  String? cursorBarrasShard;

  @HiveField(7)
  String? cursorProdutosShard;

  // flag de handover
  @HiveField(8)
  bool handover;

  @HiveField(9)
  int? contagemAtual;

  // ─── Versões das coleções fixas (sincronização automática) ───────────────
  // Comparadas com sistema/versoes no Firestore a cada login.
  // Se a versão remota for maior, o app baixa a coleção atualizada.

  @HiveField(10)
  int? versaoBarras;

  @HiveField(11)
  int? versaoProdutos;

  AppState({
    this.lastSyncMateriais,
    this.lastSyncBarras,
    this.lastSyncGases,
    this.lastLogin,
    this.lastSyncProdutos,
    this.seedVersion = 0,
    this.cursorBarrasShard,
    this.cursorProdutosShard,
    this.handover = false,
    this.contagemAtual,
    this.versaoBarras,
    this.versaoProdutos,
  });
}
