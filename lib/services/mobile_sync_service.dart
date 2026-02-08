// lib/services/mobile_sync_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lego/models/inventario.dart';

/// Modo de operação do mobile
enum ModoOperacao {
  autonomo,    // Sem vínculo com inventário (comportamento atual)
  controlado,  // Vinculado a inventário ativo do Firestore
}

/// Status da participação no inventário
enum StatusParticipacao {
  naoSolicitado,
  aguardandoAprovacao,
  aprovado,
  rejeitado,
}

/// Resultado da solicitação de participação
class ResultadoSolicitacao {
  final bool sucesso;
  final String mensagem;
  final StatusParticipacao status;

  ResultadoSolicitacao({
    required this.sucesso,
    required this.mensagem,
    required this.status,
  });
}

/// Informações do modo controlado
class InfoModoControlado {
  final Inventario inventario;
  final String contagemAtiva;
  final StatusParticipacao statusParticipacao;
  final int meusLancamentos;
  final bool podeContar;

  InfoModoControlado({
    required this.inventario,
    required this.contagemAtiva,
    required this.statusParticipacao,
    required this.meusLancamentos,
    required this.podeContar,
  });
}

/// Serviço de sincronização mobile com inventário ativo
class MobileSyncService {
  static final MobileSyncService _instance = MobileSyncService._internal();
  factory MobileSyncService() => _instance;
  MobileSyncService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Chaves de SharedPreferences
  static const String _keyModoOperacao = 'modo_operacao';
  static const String _keyInventarioId = 'inventario_vinculado_id';

  // Stream controllers
  final _modoController = StreamController<ModoOperacao>.broadcast();
  final _inventarioController = StreamController<InfoModoControlado?>.broadcast();

  Stream<ModoOperacao> get modoStream => _modoController.stream;
  Stream<InfoModoControlado?> get inventarioStream => _inventarioController.stream;

  // Cache local
  ModoOperacao? _modoAtual;
  String? _inventarioVinculadoId;
  StreamSubscription? _inventarioSubscription;
  StreamSubscription? _participanteSubscription;

  // ==================== INICIALIZAÇÃO ====================

  /// Inicializa o serviço e restaura estado salvo
  Future<void> inicializar() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Restaura modo
    final modoSalvo = prefs.getString(_keyModoOperacao);
    _modoAtual = modoSalvo == 'controlado' 
        ? ModoOperacao.controlado 
        : ModoOperacao.autonomo;
    
    // Restaura inventário vinculado
    _inventarioVinculadoId = prefs.getString(_keyInventarioId);

    // Se está em modo controlado, inicia monitoramento
    if (_modoAtual == ModoOperacao.controlado && _inventarioVinculadoId != null) {
      await _iniciarMonitoramento(_inventarioVinculadoId!);
    }

    _modoController.add(_modoAtual!);
    debugPrint('📱 MobileSyncService inicializado: modo=$_modoAtual, inv=$_inventarioVinculadoId');
  }

  /// Libera recursos
  void dispose() {
    _inventarioSubscription?.cancel();
    _participanteSubscription?.cancel();
    _modoController.close();
    _inventarioController.close();
  }

  // ==================== MODO DE OPERAÇÃO ====================

  /// Retorna modo atual
  ModoOperacao get modoAtual => _modoAtual ?? ModoOperacao.autonomo;

  /// Verifica se está em modo controlado
  bool get isControlado => _modoAtual == ModoOperacao.controlado;

  /// Verifica se está em modo autônomo
  bool get isAutonomo => _modoAtual == ModoOperacao.autonomo;

  /// Altera para modo autônomo
  Future<void> setModoAutonomo() async {
    await _cancelarMonitoramento();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyModoOperacao, 'autonomo');
    await prefs.remove(_keyInventarioId);

    _modoAtual = ModoOperacao.autonomo;
    _inventarioVinculadoId = null;

    _modoController.add(ModoOperacao.autonomo);
    _inventarioController.add(null);

    debugPrint('📱 Modo alterado para AUTÔNOMO');
  }

  /// Altera para modo controlado vinculando a um inventário
  Future<ResultadoSolicitacao> setModoControlado(String inventarioId) async {
    try {
      // Verifica se inventário existe e está ativo
      final invDoc = await _firestore.collection('inventarios').doc(inventarioId).get();
      if (!invDoc.exists) {
        return ResultadoSolicitacao(
          sucesso: false,
          mensagem: 'Inventário não encontrado',
          status: StatusParticipacao.naoSolicitado,
        );
      }

      final inventario = Inventario.fromFirestore(invDoc);
      
      // Verifica se está em andamento ou aguardando
      if (inventario.status != StatusInventario.emAndamento &&
          inventario.status != StatusInventario.aguardando) {
        return ResultadoSolicitacao(
          sucesso: false,
          mensagem: 'Inventário não está ativo (status: ${inventario.statusLabel})',
          status: StatusParticipacao.naoSolicitado,
        );
      }

      // Solicita participação
      final resultado = await _solicitarParticipacao(inventarioId);
      
      if (resultado.sucesso || resultado.status == StatusParticipacao.aprovado) {
        // Salva preferências
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyModoOperacao, 'controlado');
        await prefs.setString(_keyInventarioId, inventarioId);

        _modoAtual = ModoOperacao.controlado;
        _inventarioVinculadoId = inventarioId;

        // Inicia monitoramento
        await _iniciarMonitoramento(inventarioId);

        _modoController.add(ModoOperacao.controlado);
        
        debugPrint('📱 Modo alterado para CONTROLADO: $inventarioId');
      }

      return resultado;
    } catch (e) {
      debugPrint('❌ Erro ao vincular inventário: $e');
      return ResultadoSolicitacao(
        sucesso: false,
        mensagem: 'Erro: $e',
        status: StatusParticipacao.naoSolicitado,
      );
    }
  }

  // ==================== INVENTÁRIO ATIVO ====================

  /// Busca inventário ativo (em andamento ou aguardando)
  Future<Inventario?> buscarInventarioAtivo() async {
    try {
      // Busca primeiro por "em andamento"
      var query = await _firestore
          .collection('inventarios')
          .where('status', isEqualTo: 'emAndamento')
          .orderBy('data_inicio', descending: true)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        return Inventario.fromFirestore(query.docs.first);
      }

      // Se não encontrou, busca "aguardando"
      query = await _firestore
          .collection('inventarios')
          .where('status', isEqualTo: 'aguardando')
          .orderBy('data_inicio', descending: true)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        return Inventario.fromFirestore(query.docs.first);
      }

      return null;
    } catch (e) {
      debugPrint('❌ Erro ao buscar inventário ativo: $e');
      return null;
    }
  }

  /// Retorna o ID do inventário vinculado (se em modo controlado)
  String? get inventarioVinculadoId => _inventarioVinculadoId;

  /// Stream do inventário ativo
  Stream<Inventario?> streamInventarioAtivo() {
    return _firestore
        .collection('inventarios')
        .where('status', whereIn: ['emAndamento', 'aguardando', 'em_andamento'])
        .orderBy('data_inicio', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          return Inventario.fromFirestore(snapshot.docs.first);
        });
  }

  // ==================== PARTICIPAÇÃO ====================

  /// Solicita participação no inventário
  Future<ResultadoSolicitacao> _solicitarParticipacao(String inventarioId) async {
    final user = _auth.currentUser;
    if (user == null) {
      return ResultadoSolicitacao(
        sucesso: false,
        mensagem: 'Usuário não autenticado',
        status: StatusParticipacao.naoSolicitado,
      );
    }

    try {
      // Verifica se já é participante
      final participanteDoc = await _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('participantes')
          .doc(user.uid)
          .get();

      if (participanteDoc.exists) {
        final status = participanteDoc.data()?['status'] as String?;
        
        if (status == 'aprovado' || status == null) {
          return ResultadoSolicitacao(
            sucesso: true,
            mensagem: 'Você já é participante deste inventário',
            status: StatusParticipacao.aprovado,
          );
        } else if (status == 'solicitacao_pendente') {
          return ResultadoSolicitacao(
            sucesso: true,
            mensagem: 'Sua solicitação está aguardando aprovação',
            status: StatusParticipacao.aguardandoAprovacao,
          );
        } else if (status == 'rejeitado') {
          // Permite re-solicitar
        }
      }

      // Busca inventário para saber a contagem ativa
      final invDoc = await _firestore.collection('inventarios').doc(inventarioId).get();
      final inventario = Inventario.fromFirestore(invDoc);

      // Cria/atualiza solicitação
      await _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('participantes')
          .doc(user.uid)
          .set({
            'uid': user.uid,
            'displayName': user.displayName ?? 'Usuário ${user.uid.substring(0, 6)}',
            'email': user.email,
            'status': 'solicitacao_pendente',
            'contagem_solicitada': inventario.contagemAtiva,
            'solicitado_em': FieldValue.serverTimestamp(),
            'primeiro_acesso': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      return ResultadoSolicitacao(
        sucesso: true,
        mensagem: 'Solicitação enviada! Aguarde aprovação do analista.',
        status: StatusParticipacao.aguardandoAprovacao,
      );
    } catch (e) {
      debugPrint('❌ Erro ao solicitar participação: $e');
      return ResultadoSolicitacao(
        sucesso: false,
        mensagem: 'Erro ao solicitar: $e',
        status: StatusParticipacao.naoSolicitado,
      );
    }
  }

  /// Verifica status da participação
  Future<StatusParticipacao> verificarStatusParticipacao(String inventarioId) async {
    final user = _auth.currentUser;
    if (user == null) return StatusParticipacao.naoSolicitado;

    try {
      final doc = await _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('participantes')
          .doc(user.uid)
          .get();

      if (!doc.exists) return StatusParticipacao.naoSolicitado;

      final status = doc.data()?['status'] as String?;
      switch (status) {
        case 'solicitacao_pendente':
          return StatusParticipacao.aguardandoAprovacao;
        case 'aprovado':
        case null:
          return StatusParticipacao.aprovado;
        case 'rejeitado':
          return StatusParticipacao.rejeitado;
        default:
          return StatusParticipacao.aprovado;
      }
    } catch (e) {
      return StatusParticipacao.naoSolicitado;
    }
  }

  // ==================== MONITORAMENTO ====================

  Future<void> _iniciarMonitoramento(String inventarioId) async {
    await _cancelarMonitoramento();

    final user = _auth.currentUser;
    if (user == null) return;

    // Monitora inventário
    _inventarioSubscription = _firestore
        .collection('inventarios')
        .doc(inventarioId)
        .snapshots()
        .listen((snapshot) async {
          if (!snapshot.exists) {
            debugPrint('⚠️ Inventário foi removido');
            await setModoAutonomo();
            return;
          }

          final inventario = Inventario.fromFirestore(snapshot);
          
          // Se finalizou ou cancelou, volta para autônomo
          if (inventario.status == StatusInventario.finalizado ||
              inventario.status == StatusInventario.cancelado) {
            debugPrint('⚠️ Inventário ${inventario.status.name}, voltando para autônomo');
            await setModoAutonomo();
            return;
          }

          // Busca status de participação
          final statusPart = await verificarStatusParticipacao(inventarioId);
          
          // Conta lançamentos do usuário
          final meusLancs = await _contarMeusLancamentos(inventarioId, inventario.contagemAtiva);

          final info = InfoModoControlado(
            inventario: inventario,
            contagemAtiva: inventario.contagemAtiva,
            statusParticipacao: statusPart,
            meusLancamentos: meusLancs,
            podeContar: statusPart == StatusParticipacao.aprovado &&
                inventario.status == StatusInventario.emAndamento,
          );

          _inventarioController.add(info);
        });

    // Monitora participante para detectar aprovação/rejeição
    _participanteSubscription = _firestore
        .collection('inventarios')
        .doc(inventarioId)
        .collection('participantes')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists) {
            final status = snapshot.data()?['status'] as String?;
            debugPrint('📱 Status de participação atualizado: $status');
          }
        });

    // Atualiza último acesso
    _atualizarUltimoAcesso(inventarioId);
  }

  Future<void> _cancelarMonitoramento() async {
    await _inventarioSubscription?.cancel();
    await _participanteSubscription?.cancel();
    _inventarioSubscription = null;
    _participanteSubscription = null;
  }

  Future<int> _contarMeusLancamentos(String inventarioId, String contagemAtiva) async {
    final user = _auth.currentUser;
    if (user == null) return 0;

    try {
      final query = await _firestore
          .collection('lancamentos')
          .where('inventarioId', isEqualTo: inventarioId)
          .where('contagemId', isEqualTo: contagemAtiva)
          .where('uid', isEqualTo: user.uid)
          .count()
          .get();
      
      return query.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<void> _atualizarUltimoAcesso(String inventarioId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('participantes')
          .doc(user.uid)
          .update({
            'ultimo_acesso': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      // Ignora erro se documento não existe
    }
  }

  // ==================== HELPERS PARA LANÇAMENTOS ====================

  /// Retorna inventarioId e contagemId para usar nos lançamentos
  /// Se autônomo, retorna valores padrão
  (String inventarioId, String contagemId) getIdsParaLancamento(int contagemLocal) {
    if (isControlado && _inventarioVinculadoId != null) {
      // Modo controlado: usa inventário vinculado
      // A contagem ativa vem do inventário
      return (_inventarioVinculadoId!, 'contagem_$contagemLocal');
    } else {
      // Modo autônomo: usa valores locais
      return ('local_autonomo', 'contagem_$contagemLocal');
    }
  }

  /// Verifica se pode fazer lançamentos
  Future<bool> podeRegistrarLancamento() async {
    if (isAutonomo) return true;
    
    if (_inventarioVinculadoId == null) return false;

    final status = await verificarStatusParticipacao(_inventarioVinculadoId!);
    return status == StatusParticipacao.aprovado;
  }
}
