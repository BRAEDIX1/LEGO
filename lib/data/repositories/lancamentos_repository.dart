// lib/data/repositories/lancamentos_repository.dart
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lego/services/user_service.dart';
import 'package:lego/data/local/lanc_local.dart';
import 'package:path_provider/path_provider.dart';

class LancamentosRepository {
  static const int MAX_VISIBLE_RECORDS = 50;
  static const int INACTIVE_DAYS_THRESHOLD = 5;
  static const String CLEANUP_PASSWORD_KEY = 'cleanup_password';

  final String uid;
  LancamentosRepository({required this.uid});

  String get _boxName => 'lancamentos_$uid';

  Future<Box<LancLocal>> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<LancLocal>(_boxName);
    }
    return await Hive.openBox<LancLocal>(_boxName);
  }

  // ---------- Utils de conversão ----------
  double _toDouble(Object? v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is bool) return v ? 1.0 : 0.0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == 'sim' || s == 'yes') return 1.0;
      if (s == 'false' || s == 'nao' || s == 'não' || s == 'no') return 0.0;
      final parsed = double.tryParse(s);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  // 🔧 NOVO MÉTODO: Busca TODAS as boxes de lançamentos no dispositivo
  Future<List<String>> _getAllLancamentosBoxNames() async {
    final allBoxes = <String>{};  // Usando Set para evitar duplicatas

    // 🔍 MÉTODO 1: Buscar via filesystem (arquivos .hive)
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final files = Directory(appDir.path).listSync();

      for (final file in files) {
        if (file is File && file.path.endsWith('.hive')) {
          final fileName = file.path.split('/').last.replaceAll('.hive', '');
          if (fileName.startsWith('lancamentos_')) {
            allBoxes.add(fileName);
            debugPrint('[BOXES] Encontrada via filesystem: $fileName');
          }
        }
      }
    } catch (e) {
      debugPrint('[BOXES] Erro ao buscar via filesystem: $e');
    }

    // 🔍 MÉTODO 2: Garantir que pelo menos a box atual está na lista
    if (allBoxes.isEmpty) {
      allBoxes.add(_boxName);
      debugPrint('[BOXES] Nenhuma box encontrada, adicionando box atual: $_boxName');
    }

    final sortedList = allBoxes.toList()..sort();
    debugPrint('[BOXES] Total de boxes encontradas: ${sortedList.length}');
    return sortedList;
  }

  // ---------- Create (pendente local) ----------
  Future<LancLocal> addPending({
    required String uid,
    required String inventarioId,
    required String contagemId,
    required String codigo,
    required String descricao,
    required String unidade,
    String? tag,
    String? prateleira,
    dynamic quantidade,
    dynamic cheio,
    dynamic vazio,
    String? lote,
    double? volume,
    TipoRegistro? registro,
    String? localizacaoId,
    String? localizacaoNome,
  }) async {
    final box = await _openBox();
    final idLocal = const Uuid().v4();

    // 🔧 CORREÇÃO CRÍTICA: USAR UserService.buscarPerfil() em vez de SharedPreferences
    String nickname = 'temp_${uid.substring(0, 6)}';
    String nomeCompleto = 'Carregando...';

    try {
      debugPrint('🔍 Buscando perfil do usuário $uid...');
      final userService = UserService();
      final perfil = await userService.buscarPerfil(uid);
      
      if (perfil != null) {
        nickname = perfil.nickname;
        nomeCompleto = perfil.nomeCompleto;
        debugPrint('✅ Perfil carregado do cache: $nickname ($nomeCompleto)');
      } else {
        debugPrint('⚠️ Perfil não encontrado no cache, usando temporário');
        debugPrint('⚠️ Tentando atualizar em background...');
        _atualizarPerfilAsync(uid, idLocal);
      }
    } catch (e) {
      debugPrint('❌ ERRO ao buscar perfil: $e');
      debugPrint('⚠️ Tentando atualizar em background...');
      _atualizarPerfilAsync(uid, idLocal);
    }

    debugPrint('📝 Criando lançamento: nickname=$nickname, nomeCompleto=$nomeCompleto');

    final lanc = LancLocal(
      idLocal: idLocal,
      uid: uid,
      nickname: nickname,
      nomeCompleto: nomeCompleto,
      codigo: codigo,
      descricao: descricao,
      unidade: unidade,
      quantidade: _toDouble(quantidade),
      prateleira: prateleira ?? '',
      cheio: _toDouble(cheio),
      vazio: _toDouble(vazio),
      lote: lote,
      tag: tag,
      createdAtLocal: DateTime.now(),
      status: LancStatus.pending,
      registro: registro ?? TipoRegistro.automatico,
      volume: volume,
      inventarioId: inventarioId,
      contagemId: contagemId,
      localizacaoId:   localizacaoId,
      localizacaoNome: localizacaoNome,
    );

    await box.put(idLocal, lanc);
    debugPrint('💾 Lançamento salvo no Hive');
    
    return lanc;
  }

  /// Atualiza perfil do usuário em background sem bloquear
  void _atualizarPerfilAsync(String uid, String lancId) async {
    try {
      debugPrint('🔄 [BACKGROUND] Atualizando perfil para lançamento $lancId...');
      final userService = UserService();
      final profile = await userService.buscarPerfil(uid);

      if (profile != null) {
        debugPrint('✅ [BACKGROUND] Perfil encontrado: ${profile.nickname}');
        
        final box = await _openBox();
        final lanc = box.get(lancId);

        if (lanc != null) {
          final updated = lanc.copyWith(
            nickname: profile.nickname,
            nomeCompleto: profile.nomeCompleto,
          );

          await box.put(lancId, updated);
          debugPrint('✅ [BACKGROUND] Perfil atualizado no lançamento $lancId');
        } else {
          debugPrint('⚠️ [BACKGROUND] Lançamento $lancId não encontrado');
        }
      } else {
        debugPrint('⚠️ [BACKGROUND] Perfil não encontrado para UID $uid');
      }
    } catch (e) {
      debugPrint('❌ [BACKGROUND] Erro ao atualizar perfil: $e');
    }
  }

  // ---------- Read helpers ----------
  Future<List<LancLocal>> getPending() async {
    final box = await _openBox();
    return box.values.where((e) => e.status == LancStatus.pending).toList();
  }

  Future<int> countPending() async {
    final box = await _openBox();
    return box.values.where((e) => e.status == LancStatus.pending).length;
  }

  Future<int> countErrors() async {
    final box = await _openBox();
    return box.values.where((e) => e.status == LancStatus.error).length;
  }

  Future<int> countManual() async {
    final box = await _openBox();
    return box.values.where((e) => e.registro == TipoRegistro.manual).length;
  }

  LancLocal? _getByIdLocalSync(Box<LancLocal> box, String idLocal) {
    return box.get(idLocal);
  }

  // ---------- Stream all sorted ----------
  Stream<List<LancLocal>> watchAllSorted() async* {
    final box = await _openBox();
    List<LancLocal> _sorted() {
      final list = box.values.toList();
      list.sort((a, b) => b.createdAtLocal.compareTo(a.createdAtLocal));
      return list;
    }
    yield _sorted();
    yield* box.watch().map((_) => _sorted());
  }

  // ---------- Update ----------
  Future<void> updatePartial(
      String idLocal, {
        String? codigo,
        String? descricao,
        String? unidade,
        Object? quantidade,
        Object? cheio,
        Object? vazio,
        String? prateleira,
        String? tag,
        String? lote,
        LancStatus? status,
        TipoRegistro? registro,
        double? volume,
        String? inventarioId,
        String? contagemId,
        String? localizacaoId,
        String? localizacaoNome,
      }) async {
    final box = await _openBox();
    final current = _getByIdLocalSync(box, idLocal);
    if (current == null) return;

    final q = quantidade == null ? current.quantidade : _toDouble(quantidade, fallback: current.quantidade);
    final ch = cheio == null ? current.cheio : _toDouble(cheio, fallback: current.cheio);
    final vz = vazio == null ? current.vazio : _toDouble(vazio, fallback: current.vazio);

    final updated = current.copyWith(
      codigo: codigo ?? current.codigo,
      descricao: descricao ?? current.descricao,
      unidade: unidade ?? current.unidade,
      quantidade: q,
      cheio: ch,
      vazio: vz,
      prateleira: prateleira ?? current.prateleira,
      tag: tag ?? current.tag,
      lote: lote ?? current.lote,
      status: status ?? LancStatus.pending,
      registro: registro ?? current.registro,
      volume: volume ?? current.volume,
      inventarioId: inventarioId ?? current.inventarioId,
      contagemId: contagemId ?? current.contagemId,
      localizacaoId:   localizacaoId   ?? current.localizacaoId,
      localizacaoNome: localizacaoNome ?? current.localizacaoNome,
    );

    await box.put(idLocal, updated);

    final docId = '${uid}_$idLocal';
    try {
      await FirebaseFirestore.instance
          .collection('lancamentos')
          .doc(docId)
          .set(updated.toJson(), SetOptions(merge: true));
      await markSynced(idLocal, docId);
    } catch (e) {
      // fica pending para o SyncService cuidar depois
    }
  }

  // ---------- Delete ----------
  Future<void> delete(String idLocal) async {
    final box = await _openBox();
    final current = _getByIdLocalSync(box, idLocal);
    if (current == null) return;

    final docId = '${uid}_$idLocal';
    try {
      await FirebaseFirestore.instance
          .collection('lancamentos')
          .doc(docId)
          .delete();
      await box.delete(idLocal);
    } catch (e) {
      final flagged = current.copyWith(
        status: LancStatus.pending,
        errorCode: 'DELETE_PENDING',
      );
      await box.put(idLocal, flagged);
    }
  }

  // ---------- Helpers de estado ----------
  Future<void> markSynced(String idLocal, String remoteId) async {
    final box = await _openBox();
    final v = _getByIdLocalSync(box, idLocal);
    if (v == null) return;
    await box.put(
      idLocal,
      v.copyWith(status: LancStatus.synced, remoteId: remoteId, errorCode: null),
    );
  }

  Future<void> markError(String idLocal, String message) async {
    final box = await _openBox();
    final v = _getByIdLocalSync(box, idLocal);
    if (v == null) return;
    await box.put(
      idLocal,
      v.copyWith(status: LancStatus.error, errorCode: message),
    );
  }

  Future<void> hardDeleteLocal(String idLocal) async {
    final box = await _openBox();
    await box.delete(idLocal);
  }

  Future<bool> tagJaExiste(String tag) async {
    if (tag.isEmpty) return false;
    final box = await _openBox();
    return box.values.any((lanc) => lanc.tag == tag);
  }

  // ========== ESTATÍSTICAS DO DISPOSITIVO (TODOS OS USUÁRIOS) ==========
  // 🔧 CORRIGIDO: Busca estatísticas de TODAS as boxes do dispositivo
  Future<CleanupStats> getCleanupStats() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // 🔧 USAR MÉTODO QUE BUSCA TODAS AS BOXES
    final allBoxNames = await _getAllLancamentosBoxNames();

    debugPrint('═══════════════════════════════════════');
    debugPrint('📊 ESTATÍSTICAS DO DISPOSITIVO');
    debugPrint('Boxes encontradas: ${allBoxNames.length}');

    int totalDevice = 0;
    int syncedDevice = 0;
    int pendingDevice = 0;
    int errorsDevice = 0;

    final Map<String, UserStats> perUserMap = {};
    final Map<String, int> userIndexMap = {};
    int userCounter = 1;

    for (final boxName in allBoxNames) {
      try {
        final boxUid = boxName.replaceFirst('lancamentos_', '');

        Box<LancLocal> box;
        if (Hive.isBoxOpen(boxName)) {
          box = Hive.box<LancLocal>(boxName);
        } else {
          box = await Hive.openBox<LancLocal>(boxName);
        }

        final all = box.values.toList();
        final synced = all.where((t) => t.status == LancStatus.synced).length;
        final pending = all.where((t) => t.status == LancStatus.pending).length;
        final errors = all.where((t) => t.status == LancStatus.error).length;

        totalDevice += all.length;
        syncedDevice += synced;
        pendingDevice += pending;
        errorsDevice += errors;

        String displayName;
        if (boxUid == currentUid) {
          displayName = 'Você';
        } else {
          if (!userIndexMap.containsKey(boxUid)) {
            userIndexMap[boxUid] = userCounter++;
          }
          displayName = 'Usuário ${userIndexMap[boxUid]}';
        }

        perUserMap[boxUid] = UserStats(
          uid: boxUid,
          displayName: displayName,
          isCurrentUser: boxUid == currentUid,
          total: all.length,
          synced: synced,
          pending: pending,
          errors: errors,
        );

        debugPrint('  - $boxName: ${all.length} registros (✅$synced ⏳$pending ❌$errors)');

      } catch (e) {
        debugPrint('  ❌ Erro ao processar $boxName: $e');
      }
    }

    final perUserList = perUserMap.values.toList()
      ..sort((a, b) {
        if (a.isCurrentUser) return -1;
        if (b.isCurrentUser) return 1;
        return b.total.compareTo(a.total);
      });

    debugPrint('───────────────────────────────────────');
    debugPrint('TOTAL DISPOSITIVO: $totalDevice registros');
    debugPrint('  ✅ Sincronizados: $syncedDevice');
    debugPrint('  ⏳ Pendentes: $pendingDevice');
    debugPrint('  ❌ Erros: $errorsDevice');
    debugPrint('═══════════════════════════════════════');

    return CleanupStats(
      totalDevice: totalDevice,
      syncedDevice: syncedDevice,
      pendingDevice: pendingDevice,
      errorsDevice: errorsDevice,
      perUser: perUserList,
    );
  }

  // ========== LIMPEZA TOTAL DO DISPOSITIVO (TUDO!) ==========
  // 🔧 CORRIGIDO: Apaga TODOS os registros de TODAS as boxes
  Future<CleanupResult> manualCleanup({
    required bool includePending,
    String? password,
  }) async {
    if (password != '0179') {
      return CleanupResult(
        success: false,
        message: '❌ Senha incorreta',
        deletedCount: 0,
      );
    }

    debugPrint('═══════════════════════════════════════');
    debugPrint('🗑️  LIMPEZA MANUAL INICIADA');
    debugPrint('═══════════════════════════════════════');

    int totalDeleted = 0;

    // 🔧 USAR MÉTODO QUE BUSCA TODAS AS BOXES
    final allBoxNames = await _getAllLancamentosBoxNames();

    debugPrint('Boxes a serem limpas: ${allBoxNames.length}');

    for (final boxName in allBoxNames) {
      try {
        Box<LancLocal> box;

        if (Hive.isBoxOpen(boxName)) {
          box = Hive.box<LancLocal>(boxName);
        } else {
          box = await Hive.openBox<LancLocal>(boxName);
        }

        final count = box.length;
        
        // 🔧 APAGAR TUDO, SEM EXCEÇÕES
        await box.clear();
        
        totalDeleted += count;

        debugPrint('  ✅ $boxName: $count registros apagados');

      } catch (e) {
        debugPrint('  ❌ Erro ao limpar $boxName: $e');
      }
    }

    debugPrint('───────────────────────────────────────');
    debugPrint('TOTAL APAGADO: $totalDeleted registros');
    debugPrint('═══════════════════════════════════════');

    return CleanupResult(
      success: true,
      message: totalDeleted > 0
          ? '✅ $totalDeleted registro(s) de todos os usuários removido(s) com sucesso'
          : 'ℹ️ Nenhum registro para remover',
      deletedCount: totalDeleted,
    );
  }

  // ========== LIMPEZA AUTOMÁTICA (TODOS OS USUÁRIOS INATIVOS) ==========
  // 🔧 CORRIGIDO: Limpa TODAS as boxes com 5+ dias de inatividade
  Future<void> autoCleanupIfInactive() async {
    debugPrint('═══════════════════════════════════════');
    debugPrint('🧹 LIMPEZA AUTOMÁTICA INICIADA');
    debugPrint('═══════════════════════════════════════');

    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    // 🔧 BUSCAR TODAS AS BOXES
    final allBoxNames = await _getAllLancamentosBoxNames();

    debugPrint('Verificando ${allBoxNames.length} boxes...');

    int totalCleaned = 0;

    for (final boxName in allBoxNames) {
      try {
        final boxUid = boxName.replaceFirst('lancamentos_', '');

        // Verificar última atividade deste usuário
        final timestamp = prefs.getInt('last_activity_$boxUid');
        
        if (timestamp == null) {
          debugPrint('  ⏭️  $boxName: Sem registro de atividade, pulando');
          continue;
        }

        final lastActivity = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final daysDiff = now.difference(lastActivity).inDays;

        if (daysDiff >= INACTIVE_DAYS_THRESHOLD) {
          Box<LancLocal> box;
          
          if (Hive.isBoxOpen(boxName)) {
            box = Hive.box<LancLocal>(boxName);
          } else {
            box = await Hive.openBox<LancLocal>(boxName);
          }

          final allTransactions = box.values.toList()
            ..sort((a, b) => b.createdAtLocal.compareTo(a.createdAtLocal));

          if (allTransactions.length > MAX_VISIBLE_RECORDS) {
            final oldRecords = allTransactions.skip(MAX_VISIBLE_RECORDS);
            int removed = 0;

            for (var record in oldRecords) {
              if (record.status == LancStatus.synced) {
                await box.delete(record.idLocal);
                removed++;
              }
            }

            if (removed > 0) {
              totalCleaned += removed;
              debugPrint('  ✅ $boxName: $removed registros removidos ($daysDiff dias inativo)');
            } else {
              debugPrint('  ℹ️  $boxName: Sem registros sincronizados para remover');
            }
          } else {
            debugPrint('  ℹ️  $boxName: Apenas ${allTransactions.length} registros (< $MAX_VISIBLE_RECORDS)');
          }
        } else {
          debugPrint('  ⏭️  $boxName: Ativo há $daysDiff dias (< $INACTIVE_DAYS_THRESHOLD)');
        }

      } catch (e) {
        debugPrint('  ❌ Erro ao processar $boxName: $e');
      }
    }

    // Atualizar timestamp do usuário ATUAL
    await _updateLastActivityDate();

    debugPrint('───────────────────────────────────────');
    debugPrint('TOTAL LIMPO: $totalCleaned registros');
    debugPrint('═══════════════════════════════════════');
  }

  Future<DateTime> _getLastActivityDate() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt('last_activity_$uid') ??
        DateTime.now().millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  Future<void> _updateLastActivityDate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_activity_$uid', DateTime.now().millisecondsSinceEpoch);
  }

  Future<String> _getStoredPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(CLEANUP_PASSWORD_KEY) ?? '1234';
  }

  Future<void> setCleanupPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(CLEANUP_PASSWORD_KEY, password);
  }
}

// ========== CLASSES DE SUPORTE ==========

class UserStats {
  final String uid;
  final String displayName;
  final bool isCurrentUser;
  final int total;
  final int synced;
  final int pending;
  final int errors;

  UserStats({
    required this.uid,
    required this.displayName,
    required this.isCurrentUser,
    required this.total,
    required this.synced,
    required this.pending,
    required this.errors,
  });
}

class CleanupStats {
  final int totalDevice;
  final int syncedDevice;
  final int pendingDevice;
  final int errorsDevice;
  final List<UserStats> perUser;

  CleanupStats({
    required this.totalDevice,
    required this.syncedDevice,
    required this.pendingDevice,
    required this.errorsDevice,
    required this.perUser,
  });
}

class CleanupResult {
  final bool success;
  final String message;
  final int deletedCount;

  CleanupResult({
    required this.success,
    required this.message,
    required this.deletedCount,
  });
}
