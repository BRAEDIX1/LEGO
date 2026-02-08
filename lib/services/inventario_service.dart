// lib/services/inventario_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lego/models/inventario.dart';

/// Serviço para gerenciamento de inventários e contagens
/// Responsável pelo CRUD e controle de estado dos inventários
class InventarioService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== CRIAÇÃO ====================

  /// Cria um novo inventário completo (novo método - wizard desktop)
  Future<String> criarInventarioCompleto({
    required TipoContagem tipoContagem,
    required String tipoMaterial,
    String? deposito,
    String? descricao,
    int totalItensEstoque = 0,
    double valorTotalEstoque = 0.0,
    String? criadoPor,
  }) async {
    try {
      // 1. Gerar número sequencial
      final numero = await _gerarProximoNumero();

      // 2. Gerar data no formato DDMMAAAA
      final agora = DateTime.now();
      final data = '${agora.day.toString().padLeft(2, '0')}'
          '${agora.month.toString().padLeft(2, '0')}'
          '${agora.year}';

      // 3. Montar código do inventário
      final prefixo = deposito?.isNotEmpty == true ? deposito : tipoMaterial.substring(0, 3).toUpperCase();
      final codigoInventario = '${prefixo}_${numero}_$data';

      // 4. Criar documento
      final docRef = await _firestore.collection('inventarios').add({
        'codigo': codigoInventario,
        'numero': int.parse(numero),
        'data_inicio': FieldValue.serverTimestamp(),
        'data_fim': null,
        'contagem_ativa': 'contagem_1',
        'status': StatusInventario.aguardando.name,
        'versao_estoque': null,

        // Novos campos
        'tipo_contagem': tipoContagem.name,
        'tipo_material': tipoMaterial,
        'deposito': deposito,
        'descricao': descricao,
        'total_itens_estoque': totalItensEstoque,
        'valor_total_estoque': valorTotalEstoque,
        'criado_por': criadoPor,
        'criado_em': FieldValue.serverTimestamp(),

        // Inicializa contagens
        'contagens': {
          'contagem_1': {
            'iniciada_em': null,
            'finalizada_em': null,
            'usuarios': [],
            'total_lancamentos': 0,
          },
        },
      });

      debugPrint('✅ Inventário criado: $codigoInventario (ID: ${docRef.id})');
      return docRef.id;

    } catch (e) {
      debugPrint('❌ Erro ao criar inventário: $e');
      rethrow;
    }
  }

  /// Cria um novo inventário (método legado - mantido por compatibilidade)
  Future<String> criarInventario() async {
    try {
      // 1. Gerar número sequencial
      final numero = await _gerarProximoNumero();

      // 2. Gerar data no formato DDMMAAAA
      final agora = DateTime.now();
      final data = '${agora.day.toString().padLeft(2, '0')}'
          '${agora.month.toString().padLeft(2, '0')}'
          '${agora.year}';

      // 3. Montar código do inventário
      final codigoInventario = '${numero}_$data';

      // 4. Criar documento
      final docRef = await _firestore.collection('inventarios').add({
        'codigo': codigoInventario,
        'numero': int.parse(numero),
        'data_inicio': FieldValue.serverTimestamp(),
        'data_fim': null,
        'contagem_ativa': 'contagem_1',
        'status': 'em_andamento',
        'versao_estoque': null,
        'contagens': {
          'contagem_1': {
            'iniciada_em': FieldValue.serverTimestamp(),
            'finalizada_em': null,
            'usuarios': [],
            'total_lancamentos': 0,
          },
        },
      });

      debugPrint('✅ Inventário criado: $codigoInventario (ID: ${docRef.id})');
      return docRef.id;

    } catch (e) {
      debugPrint('❌ Erro ao criar inventário: $e');
      rethrow;
    }
  }

  /// Gera próximo número sequencial para o inventário (formato: 001, 002, 003...)
  Future<String> _gerarProximoNumero() async {
    try {
      final contadorRef = _firestore
          .collection('sistema')
          .doc('contadores');

      final snapshot = await contadorRef.get();

      int proximoNumero = 1;

      if (snapshot.exists) {
        final dados = snapshot.data() as Map<String, dynamic>?;
        proximoNumero = (dados?['ultimo_inventario'] ?? 0) + 1;
      }

      // Atualiza contador (sem transação)
      await contadorRef.set({
        'ultimo_inventario': proximoNumero,
        'atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Retorna com padding de 3 dígitos
      return proximoNumero.toString().padLeft(3, '0');
    } catch (e) {
      debugPrint('❌ Erro ao gerar número: $e');
      // Fallback: usa timestamp se falhar
      return DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    }
  }

  // ==================== CONSULTAS ====================

  /// Busca o inventário ativo (em andamento)
  Future<Inventario?> buscarInventarioAtivo() async {
    try {
      // Busca por status em_andamento OU aguardando
      final snapshot = await _firestore
          .collection('inventarios')
          .where('status', whereIn: ['em_andamento', 'emAndamento', 'aguardando'])
          .orderBy('data_inicio', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('ℹ️ Nenhum inventário ativo encontrado');
        return null;
      }

      return Inventario.fromFirestore(snapshot.docs.first);
    } catch (e) {
      debugPrint('❌ Erro ao buscar inventário ativo: $e');
      return null;
    }
  }

  /// Busca um inventário específico por ID
  Future<Inventario?> buscarInventarioPorId(String id) async {
    try {
      final doc = await _firestore.collection('inventarios').doc(id).get();

      if (!doc.exists) {
        debugPrint('⚠️ Inventário $id não encontrado');
        return null;
      }

      return Inventario.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ Erro ao buscar inventário: $e');
      return null;
    }
  }

  /// Lista todos os inventários (ativos e finalizados)
  Future<List<Inventario>> listarInventarios({
    int limite = 20,
    String? status,
    String? tipoMaterial,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('inventarios')
          .orderBy('data_inicio', descending: true)
          .limit(limite);

      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }

      if (tipoMaterial != null) {
        query = query.where('tipo_material', isEqualTo: tipoMaterial);
      }

      final snapshot = await query.get();

      return snapshot.docs
          .map((doc) => Inventario.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ Erro ao listar inventários: $e');
      return [];
    }
  }

  /// Stream de inventários (atualização em tempo real)
  Stream<List<Inventario>> streamInventarios({String? status}) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('inventarios')
        .orderBy('data_inicio', descending: true);

    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Inventario.fromFirestore(doc))
          .toList();
    });
  }

  /// Stream de um inventário específico
  Stream<Inventario?> streamInventario(String inventarioId) {
    return _firestore
        .collection('inventarios')
        .doc(inventarioId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return Inventario.fromFirestore(doc);
    });
  }

  // ==================== CONTROLE DE ESTADO ====================

  /// Inicia o inventário (muda de aguardando para em_andamento)
  Future<void> iniciarInventario(String inventarioId) async {
    try {
      await _firestore.collection('inventarios').doc(inventarioId).update({
        'status': StatusInventario.emAndamento.name,
        'contagens.contagem_1.iniciada_em': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Inventário $inventarioId iniciado');
    } catch (e) {
      debugPrint('❌ Erro ao iniciar inventário: $e');
      rethrow;
    }
  }

  /// Inicia uma nova contagem no inventário
  Future<void> iniciarContagem(String inventarioId, String contagemId) async {
    try {
      final now = DateTime.now();

      await _firestore.collection('inventarios').doc(inventarioId).update({
        'contagem_ativa': contagemId,
        'contagens.$contagemId': {
          'iniciada_em': Timestamp.fromDate(now),
          'finalizada_em': null,
          'usuarios': [],
          'total_lancamentos': 0,
          'itens_marcados': null,
        },
      });

      debugPrint('✅ Contagem $contagemId iniciada no inventário $inventarioId');
    } catch (e) {
      debugPrint('❌ Erro ao iniciar contagem: $e');
      rethrow;
    }
  }

  /// Finaliza uma contagem
  Future<void> finalizarContagem(String inventarioId, String contagemId) async {
    try {
      final now = DateTime.now();

      // Conta total de lançamentos desta contagem
      final lancamentos = await _firestore
          .collection('lancamentos')
          .where('inventarioId', isEqualTo: inventarioId)
          .where('contagemId', isEqualTo: contagemId)
          .get();

      await _firestore.collection('inventarios').doc(inventarioId).update({
        'contagens.$contagemId.finalizada_em': Timestamp.fromDate(now),
        'contagens.$contagemId.total_lancamentos': lancamentos.size,
      });

      debugPrint('✅ Contagem $contagemId finalizada com ${lancamentos.size} lançamentos');
    } catch (e) {
      debugPrint('❌ Erro ao finalizar contagem: $e');
      rethrow;
    }
  }

  /// Finaliza o inventário completo
  Future<void> finalizarInventario(String inventarioId) async {
    try {
      final now = DateTime.now();

      await _firestore.collection('inventarios').doc(inventarioId).update({
        'status': StatusInventario.finalizado.name,
        'data_fim': Timestamp.fromDate(now),
      });

      debugPrint('✅ Inventário $inventarioId finalizado');
    } catch (e) {
      debugPrint('❌ Erro ao finalizar inventário: $e');
      rethrow;
    }
  }

  /// Avança para a próxima contagem (C1→C2 ou C2→C3)
  Future<bool> avancarParaProximaContagem(String inventarioId) async {
    try {
      final inventario = await buscarInventarioPorId(inventarioId);
      if (inventario == null) {
        debugPrint('❌ Inventário não encontrado');
        return false;
      }

      final proximaContagem = inventario.proximaContagem();
      if (proximaContagem == null) {
        debugPrint('⚠️ Não há próxima contagem disponível');
        return false;
      }

      // Finaliza contagem atual
      await finalizarContagem(inventarioId, inventario.contagemAtiva);

      // Inicia próxima contagem
      await iniciarContagem(inventarioId, proximaContagem);

      debugPrint('✅ Avançou de ${inventario.contagemAtiva} para $proximaContagem');
      return true;
    } catch (e) {
      debugPrint('❌ Erro ao avançar contagem: $e');
      return false;
    }
  }

  /// Cancela um inventário
  Future<void> cancelarInventario(String inventarioId, {String? motivo}) async {
    try {
      await _firestore.collection('inventarios').doc(inventarioId).update({
        'status': StatusInventario.cancelado.name,
        'data_fim': FieldValue.serverTimestamp(),
        'motivo_cancelamento': motivo,
      });

      debugPrint('✅ Inventário $inventarioId cancelado');
    } catch (e) {
      debugPrint('❌ Erro ao cancelar inventário: $e');
      rethrow;
    }
  }

  /// Marca itens para serem recontados na Contagem 3
  Future<void> marcarItensParaC3(
      String inventarioId,
      List<String> codigos,
      ) async {
    try {
      await _firestore.collection('inventarios').doc(inventarioId).update({
        'contagens.contagem_3.itens_marcados': codigos,
      });

      debugPrint('✅ ${codigos.length} itens marcados para C3');
    } catch (e) {
      debugPrint('❌ Erro ao marcar itens para C3: $e');
      rethrow;
    }
  }

  // ==================== PARTICIPANTES ====================

  /// Stream de participantes de um inventário
  Stream<List<Map<String, dynamic>>> streamParticipantes(String inventarioId) {
    return _firestore
        .collection('inventarios')
        .doc(inventarioId)
        .collection('participantes')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['uid'] = doc.id;
        return data;
      }).toList();
    });
  }

  /// Inicializa participante no inventário (chamado via botão no mobile)
  Future<void> iniciarParticipante(String inventarioId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');

      final participanteRef = _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('participantes')
          .doc(user.uid);

      final doc = await participanteRef.get();

      if (!doc.exists) {
        // Criar novo participante
        await participanteRef.set({
          'uid': user.uid,
          'displayName': user.displayName ?? user.email ?? 'Sem nome',
          'email': user.email,
          'contagem_atual': 'contagem_1',
          'status_c1': 'em_andamento',
          'status_c2': 'bloqueada',
          'status_c3': 'bloqueada',
          'liberado_para_c2': false,
          'liberado_para_c3': false,
          'primeiro_acesso': FieldValue.serverTimestamp(),
          'ultimo_acesso': FieldValue.serverTimestamp(),
          'iniciou_c1_em': FieldValue.serverTimestamp(),
          'finalizou_c1_em': null,
          'iniciou_c2_em': null,
          'finalizou_c2_em': null,
          'iniciou_c3_em': null,
          'finalizou_c3_em': null,
          'total_lancamentos_c1': 0,
          'total_lancamentos_c2': 0,
          'total_lancamentos_c3': 0,
        });
        debugPrint('✅ Participante iniciado: ${user.email}');
      } else {
        // Atualizar último acesso
        await participanteRef.update({
          'ultimo_acesso': FieldValue.serverTimestamp(),
        });
        debugPrint('✅ Participante já existe, atualizado último acesso');
      }
    } catch (e) {
      debugPrint('❌ Erro ao iniciar participante: $e');
      rethrow;
    }
  }

  /// Finaliza contagem atual do participante
  Future<void> finalizarContagemParticipante(String inventarioId, String contagemId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');

      // Contar lançamentos do usuário nesta contagem
      final lancamentosSnapshot = await _firestore
          .collection('lancamentos')
          .where('inventarioId', isEqualTo: inventarioId)
          .where('contagemId', isEqualTo: contagemId)
          .where('uid', isEqualTo: user.uid)
          .get();

      final totalLancamentos = lancamentosSnapshot.size;

      // Atualizar participante
      final participanteRef = _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('participantes')
          .doc(user.uid);

      final contagemNum = contagemId.replaceAll('contagem_', 'c');

      final updates = <String, dynamic>{
        'finalizou_${contagemId}_em': FieldValue.serverTimestamp(),
        'status_$contagemNum': 'finalizada',
        'total_lancamentos_$contagemNum': totalLancamentos,
        'ultimo_acesso': FieldValue.serverTimestamp(),
      };

      await participanteRef.update(updates);

      debugPrint('✅ Contagem $contagemId finalizada: $totalLancamentos lançamentos');
    } catch (e) {
      debugPrint('❌ Erro ao finalizar contagem: $e');
      rethrow;
    }
  }

  /// Libera próxima contagem para um participante (chamado do desktop)
  Future<void> liberarProximaContagem(
      String inventarioId,
      String uid,
      String proximaContagem,
      ) async {
    try {
      final participanteRef = _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('participantes')
          .doc(uid);

      final contagemNum = proximaContagem.replaceAll('contagem_', 'c');

      final updates = <String, dynamic>{
        'contagem_atual': proximaContagem,
        'status_$contagemNum': 'em_andamento',
        'iniciou_${proximaContagem}_em': FieldValue.serverTimestamp(),
      };

      if (proximaContagem == 'contagem_2') {
        updates['liberado_para_c2'] = true;
      } else if (proximaContagem == 'contagem_3') {
        updates['liberado_para_c3'] = true;
      }

      await participanteRef.update(updates);

      debugPrint('✅ Participante $uid liberado para $proximaContagem');
    } catch (e) {
      debugPrint('❌ Erro ao liberar contagem: $e');
      rethrow;
    }
  }

  /// Participante solicita participar de uma contagem específica
  Future<void> solicitarParticipacao(
      String inventarioId,
      String contagemEscolhida,
      ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');

      final participanteRef = _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('participantes')
          .doc(user.uid);

      await participanteRef.set({
        'uid': user.uid,
        'displayName': user.displayName ?? user.email ?? 'Sem nome',
        'email': user.email,
        'status': 'solicitacao_pendente',
        'contagem_solicitada': contagemEscolhida,
        'solicitado_em': FieldValue.serverTimestamp(),
        'primeiro_acesso': FieldValue.serverTimestamp(),
        'ultimo_acesso': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Solicitação enviada: $contagemEscolhida');
    } catch (e) {
      debugPrint('❌ Erro ao solicitar: $e');
      rethrow;
    }
  }

  /// Analista aprova participação
  Future<void> aprovarParticipacao(
      String inventarioId,
      String uid,
      String contagemSolicitada,
      ) async {
    try {
      final participanteRef = _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('participantes')
          .doc(uid);

      final contagemNum = contagemSolicitada.replaceAll('contagem_', 'c');

      final dados = <String, dynamic>{
        'status': 'aprovado',
        'contagem_atual': contagemSolicitada,
        'aprovado_em': FieldValue.serverTimestamp(),
        'aprovado_por': FirebaseAuth.instance.currentUser?.uid,
        'iniciou_${contagemSolicitada}_em': FieldValue.serverTimestamp(),
      };

      // Configurar status das contagens
      if (contagemSolicitada == 'contagem_1') {
        dados['status_c1'] = 'em_andamento';
        dados['status_c2'] = 'bloqueada';
        dados['status_c3'] = 'bloqueada';
        dados['liberado_para_c2'] = false;
        dados['liberado_para_c3'] = false;
      } else if (contagemSolicitada == 'contagem_2') {
        dados['status_c1'] = 'nao_participou';
        dados['status_c2'] = 'em_andamento';
        dados['status_c3'] = 'bloqueada';
        dados['liberado_para_c2'] = true;
        dados['liberado_para_c3'] = false;
      } else if (contagemSolicitada == 'contagem_3') {
        dados['status_c1'] = 'nao_participou';
        dados['status_c2'] = 'nao_participou';
        dados['status_c3'] = 'em_andamento';
        dados['liberado_para_c2'] = false;
        dados['liberado_para_c3'] = true;
      }

      dados['total_lancamentos_c1'] = 0;
      dados['total_lancamentos_c2'] = 0;
      dados['total_lancamentos_c3'] = 0;

      await participanteRef.update(dados);

      debugPrint('✅ Participação aprovada: $uid → $contagemSolicitada');
    } catch (e) {
      debugPrint('❌ Erro ao aprovar: $e');
      rethrow;
    }
  }

  /// Analista rejeita participação
  Future<void> rejeitarParticipacao(
      String inventarioId,
      String uid,
      ) async {
    try {
      await _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('participantes')
          .doc(uid)
          .update({
        'status': 'rejeitado',
        'rejeitado_em': FieldValue.serverTimestamp(),
        'rejeitado_por': FirebaseAuth.instance.currentUser?.uid,
      });

      debugPrint('✅ Participação rejeitada: $uid');
    } catch (e) {
      debugPrint('❌ Erro ao rejeitar: $e');
      rethrow;
    }
  }

  // ==================== ESTATÍSTICAS ====================

  /// Obtém estatísticas do inventário
  Future<Map<String, dynamic>> getEstatisticasInventario(String inventarioId) async {
    try {
      // Total de lançamentos por contagem
      final c1 = await _firestore
          .collection('lancamentos')
          .where('inventarioId', isEqualTo: inventarioId)
          .where('contagemId', isEqualTo: 'contagem_1')
          .count()
          .get();

      final c2 = await _firestore
          .collection('lancamentos')
          .where('inventarioId', isEqualTo: inventarioId)
          .where('contagemId', isEqualTo: 'contagem_2')
          .count()
          .get();

      final c3 = await _firestore
          .collection('lancamentos')
          .where('inventarioId', isEqualTo: inventarioId)
          .where('contagemId', isEqualTo: 'contagem_3')
          .count()
          .get();

      // Participantes
      final participantes = await _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .collection('participantes')
          .get();

      return {
        'lancamentos_c1': c1.count,
        'lancamentos_c2': c2.count,
        'lancamentos_c3': c3.count,
        'total_lancamentos': (c1.count ?? 0) + (c2.count ?? 0) + (c3.count ?? 0),
        'total_participantes': participantes.size,
      };
    } catch (e) {
      debugPrint('❌ Erro ao obter estatísticas: $e');
      return {'erro': e.toString()};
    }
  }
}