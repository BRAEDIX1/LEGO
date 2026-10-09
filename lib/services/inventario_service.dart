// lib/services/inventario_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lego/config/fluxo2_config.dart';
import 'package:lego/models/inventario.dart';
import 'package:lego/models/participante.dart';
import 'package:lego/services/audit_event_service.dart';

// =====================================================================
// EXCEÇÕES E RESULTADOS DO FLUXO 2
// =====================================================================

/// Operação legada chamada para um inventário do fluxo 2 (ou o inverso).
class OperacaoNaoPermitidaException implements Exception {
  final String operacao;
  final String inventarioId;
  final String motivo;
  OperacaoNaoPermitidaException(this.operacao, this.inventarioId, this.motivo);
  @override
  String toString() => '$operacao não permitida para o inventário $inventarioId: $motivo';
}

/// Existe uma Contagem Completa do fluxo legado ainda ativa: o fluxo 2 não
/// pode abrir outra (regra §7: no máximo um Inventário Completo ativo).
class InventarioLegadoAtivoException implements Exception {
  final String inventarioId;
  final String codigo;
  InventarioLegadoAtivoException(this.inventarioId, this.codigo);
  @override
  String toString() =>
      'Já existe uma Contagem Completa ativa no fluxo antigo ($codigo). '
      'Finalize ou cancele esse inventário antes de abrir um novo.';
}

/// O inventário não cumpre as condições de encerramento (§7, §9.1).
class EncerramentoBloqueadoException implements Exception {
  final List<String> pendencias;
  EncerramentoBloqueadoException(this.pendencias);
  @override
  String toString() => 'Inventário não pode ser encerrado:\n- ${pendencias.join('\n- ')}';
}

/// D4: o usuário já tem outra rodada base neste inventário.
class RodadaBaseConflitoException implements Exception {
  final String rodadaBaseAtual;
  final String rodadaPedida;
  RodadaBaseConflitoException(this.rodadaBaseAtual, this.rodadaPedida);
  @override
  String toString() =>
      'Você já participa da ${Rodadas.rotulo(rodadaBaseAtual)} neste inventário '
      'e não pode entrar na ${Rodadas.rotulo(rodadaPedida)}.';
}

/// Compatibilidade (aceite do plano §5): finalizar exige ao menos 1
/// lançamento sincronizado do usuário na rodada.
class SemLancamentosSincronizadosException implements Exception {
  @override
  String toString() =>
      'Você precisa ter pelo menos 1 lançamento sincronizado antes de finalizar.';
}

/// Resultado de [InventarioService.entrarNaRodada].
class ResultadoEntradaRodada {
  final String statusIndividual;
  final String? statusRodada;
  final bool primeiraEntrada;
  const ResultadoEntradaRodada({
    required this.statusIndividual,
    required this.statusRodada,
    required this.primeiraEntrada,
  });
}

/// Resultado de [InventarioService.criarOuEntrarInventarioCompleto].
class ResultadoInventarioCompleto {
  final String id;
  final int numero;
  final String codigo;

  /// true = este chamado criou o inventário; false = entrou no que já estava ativo.
  final bool criado;
  /// L4: tipo do inventário ('material' | 'cilindro' | 'gas'); null = antigo.
  final String? naturezaContagem;

  const ResultadoInventarioCompleto({
    required this.id,
    required this.numero,
    required this.codigo,
    required this.criado,
    this.naturezaContagem,
  });

  String get numeroFormatado => numero.toString().padLeft(3, '0');
}

/// Serviço para gerenciamento de inventários e contagens
/// Responsável pelo CRUD e controle de estado dos inventários
class InventarioService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Documento que guarda os contadores e a trava de exclusividade.
  DocumentReference<Map<String, dynamic>> get _contadoresRef =>
      _firestore.collection('sistema').doc('contadores');

  CollectionReference<Map<String, dynamic>> get _inventarios =>
      _firestore.collection('inventarios');

  // Campos de sistema/contadores
  static const String _campoUltimoInventario = 'ultimo_inventario';
  static const String _campoUltimoCompleto = 'ultimo_inventario_completo';
  static const String _campoTravaCompleto = 'inventario_completo_ativo_id';

  /// Números acima disto vieram do fallback antigo por timestamp (B1) e são
  /// ignorados ao inicializar a sequência da Contagem Completa.
  static const int _numeroMaximoValido = 9999;

  // ==================== CRIAÇÃO ====================

  /// Cria um novo inventário pelo wizard desktop.
  ///
  /// Com o fluxo 2 habilitado ([Fluxo2Config.habilitado]) e
  /// `tipoContagem == completa`, passa pela mesma transação do mobile (D6):
  /// se já houver Inventário Completo ativo, devolve o ID dele em vez de criar.
  /// Contagem Simples e fluxo 2 desligado seguem o caminho antigo.
  Future<String> criarInventarioCompleto({
    required TipoContagem tipoContagem,
    required String tipoMaterial,
    String? deposito,
    String? descricao,
    int totalItensEstoque = 0,
    double valorTotalEstoque = 0.0,
    String? criadoPor,
  }) async {
    if (Fluxo2Config.habilitado && tipoContagem == TipoContagem.completa) {
      final resultado = await criarOuEntrarInventarioCompleto(
        origem: 'desktop',
        tipoMaterial: tipoMaterial,
        deposito: deposito,
        descricao: descricao,
        totalItensEstoque: totalItensEstoque,
        valorTotalEstoque: valorTotalEstoque,
      );
      if (!resultado.criado) {
        debugPrint('ℹ️ Wizard entrou no Inventário Completo já ativo: '
            '${resultado.codigo} (ID: ${resultado.id})');
      }
      return resultado.id;
    }

    try {
      // 1. Gerar número sequencial
      final numero = await _gerarProximoNumero();

      // 2. Gerar data no formato DDMMAAAA
      final data = _dataDDMMAAAA(DateTime.now());

      // 3. Montar código do inventário
      final prefixo = _prefixoCodigo(deposito: deposito, tipoMaterial: tipoMaterial);
      final codigoInventario = '${prefixo}_${numero}_$data';

      // 4. Criar documento
      final docRef = await _inventarios.add({
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
  @Deprecated('Grava status "em_andamento" sem tipo_contagem. '
      'Use criarInventarioCompleto ou criarOuEntrarInventarioCompleto.')
  Future<String> criarInventario() async {
    try {
      // 1. Gerar número sequencial
      final numero = await _gerarProximoNumero();

      // 2. Gerar data no formato DDMMAAAA
      final data = _dataDDMMAAAA(DateTime.now());

      // 3. Montar código do inventário
      final codigoInventario = '${numero}_$data';

      // 4. Criar documento
      final docRef = await _inventarios.add({
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

  /// Gera próximo número sequencial do fluxo legado/Simples (001, 002, 003...).
  ///
  /// B1: agora em transação, e sem o fallback por timestamp — se falhar, a
  /// criação falha (antes gerava um número de 6 dígitos sem aviso).
  Future<String> _gerarProximoNumero() async {
    final proximoNumero = await _firestore.runTransaction<int>((tx) async {
      final snapshot = await tx.get(_contadoresRef);
      final atual = snapshot.data()?[_campoUltimoInventario];
      final proximo = (atual is num ? atual.toInt() : 0) + 1;

      tx.set(_contadoresRef, {
        _campoUltimoInventario: proximo,
        'atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return proximo;
    });

    // Retorna com padding de 3 dígitos
    return proximoNumero.toString().padLeft(3, '0');
  }

  // ==================== FLUXO 2: INVENTÁRIO COMPLETO ====================

  /// Cria o próximo Inventário Completo OU devolve o que já está ativo.
  ///
  /// Regras (Plano §7; decisões D2, D6, D7):
  /// - Existe no máximo um Inventário Completo ativo. A exclusividade é a
  ///   trava `inventario_completo_ativo_id` em `sistema/contadores`, lida e
  ///   gravada na MESMA transação que cria o inventário.
  /// - A numeração é própria (`ultimo_inventario_completo`). Na primeira vez,
  ///   começa depois do maior número de Contagem Completa já existente.
  /// - Quem chega com a trava ocupada recebe o inventário ativo; nenhum
  ///   número é consumido.
  /// - Trava apontando para inventário encerrado, cancelado ou apagado é
  ///   tratada como livre e o fato é registrado em evento.
  ///
  /// Exige conexão: transações do Firestore não rodam offline.
  Future<ResultadoInventarioCompleto> criarOuEntrarInventarioCompleto({
    required String origem, // 'mobile' | 'desktop'
    /// L4: 'material' | 'cilindro' | 'gas' — só usado se o inventário for
    /// CRIADO agora; quem entra num ativo herda o tipo dele.
    String? naturezaContagem,
    String? tipoMaterial,
    String? deposito,
    String? descricao,
    int totalItensEstoque = 0,
    double valorTotalEstoque = 0.0,
  }) async {
    // B14: a chave protege o próprio serviço, não só quem o chama.
    if (!Fluxo2Config.habilitado) {
      throw OperacaoNaoPermitidaException(
        'Criar/entrar Inventário Completo',
        '',
        'fluxo 2 desabilitado nesta build (LEGO_FLUXO2=false)',
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuário não autenticado');

    // 1. Barreira do fluxo legado (fora da transação: transação no cliente
    //    não executa consulta). O legado só é criado pelo desktop.
    await _verificarCompletoLegadoAtivo();

    // 2. Base da sequência, só usada se o contador ainda não existir.
    final baseSequencia = await _baseSequenciaCompleta();

    // ID gerado fora da transação: se ela repetir, usa o mesmo ID.
    final novoRef = _inventarios.doc();

    return _firestore.runTransaction<ResultadoInventarioCompleto>((tx) async {
      // ---------- LEITURAS ----------
      final contadores = await tx.get(_contadoresRef);
      final dados = contadores.data() ?? <String, dynamic>{};
      final ativoId = dados[_campoTravaCompleto] as String?;

      String? travaOrfa;
      if (ativoId != null) {
        final ativoSnap = await tx.get(_inventarios.doc(ativoId));
        if (ativoSnap.exists) {
          final ativo = Inventario.fromFirestore(ativoSnap);
          if (ativo.isAtivo) {
            // Trava ocupada por inventário válido: entra nele.
            return ResultadoInventarioCompleto(
              id: ativo.id,
              numero: ativo.numero,
              codigo: ativo.codigo,
              criado: false,
              naturezaContagem: ativo.naturezaContagem,
            );
          }
        }
        travaOrfa = ativoId; // aponta para encerrado/cancelado/apagado
      }

      // ---------- ESCRITAS ----------
      final ultimo = dados[_campoUltimoCompleto];
      final numero = (ultimo is num ? ultimo.toInt() : baseSequencia) + 1;
      final numeroTxt = numero.toString().padLeft(3, '0');
      final prefixo = _prefixoCodigo(deposito: deposito, tipoMaterial: tipoMaterial);
      final codigo = '${prefixo}_${numeroTxt}_${_dataDDMMAAAA(DateTime.now())}';

      tx.set(novoRef, {
        'codigo': codigo,
        'numero': numero,
        'data_inicio': FieldValue.serverTimestamp(),
        'data_fim': null,
        // Congelado no fluxo 2 (só o legado lê). Ver registro §3.
        'contagem_ativa': Rodadas.c1,
        'status': StatusInventario.emAndamento.name,
        'versao_estoque': null,
        'tipo_contagem': TipoContagem.completa.name,
        'fluxo_versao': FluxoVersao.maquinaEstados,
        'origem_criacao': origem,
        if (naturezaContagem != null) 'natureza_contagem': naturezaContagem,
        'tipo_material': tipoMaterial,
        'deposito': deposito,
        'descricao': descricao,
        'total_itens_estoque': totalItensEstoque,
        'valor_total_estoque': valorTotalEstoque,
        'criado_por': user.uid,
        'criado_em': FieldValue.serverTimestamp(),
        // C1 e C2 nascem disponíveis e independentes. C3 só nasce da
        // reconciliação (Fase 6), por isso não existe aqui.
        'contagens': {
          Rodadas.c1: _rodadaInicial(),
          Rodadas.c2: _rodadaInicial(),
        },
        'reconciliacao': const ReconciliacaoInfo().toMap(),
      });

      tx.set(_contadoresRef, {
        _campoUltimoCompleto: numero,
        _campoTravaCompleto: novoRef.id,
        'atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (travaOrfa != null) {
        AuditEventService.registrarNaTransacao(
          tx,
          inventarioId: travaOrfa,
          tipo: TipoEvento.travaOrfaLiberada,
          uid: user.uid,
          dados: {'substituida_por': novoRef.id},
        );
      }

      AuditEventService.registrarNaTransacao(
        tx,
        inventarioId: novoRef.id,
        tipo: TipoEvento.inventarioCriado,
        uid: user.uid,
        dados: {
          'numero': numero,
          'codigo': codigo,
          'origem': origem,
          if (naturezaContagem != null) 'natureza': naturezaContagem,
          if (travaOrfa != null) 'trava_orfa_anterior': travaOrfa,
        },
      );

      return ResultadoInventarioCompleto(
        id: novoRef.id,
        numero: numero,
        codigo: codigo,
        criado: true,
        naturezaContagem: naturezaContagem,
      );
    }).then((r) {
      debugPrint(r.criado
          ? '✅ Inventário Completo ${r.numeroFormatado} criado (${r.codigo}, ID: ${r.id})'
          : 'ℹ️ Entrou no Inventário Completo ativo ${r.numeroFormatado} (ID: ${r.id})');
      return r;
    });
  }

  /// Inventário Completo ativo do fluxo 2, lido pela trava (não por consulta).
  /// Null se não houver, ou se a trava apontar para inventário já fechado.
  /// [propagarErros] = true: falha de leitura (ex.: sem rede) vira exceção em
  /// vez de `null`, para a tela não confundir "offline" com "nenhum ativo".
  Future<Inventario?> buscarInventarioCompletoAtivo({bool propagarErros = false}) async {
    try {
      // B29: com propagarErros, só servidor. A fonte padrão devolveria o cache
      // offline e a tela confundiria "sem rede" com "nenhum ativo".
      final opcoes = propagarErros ? const GetOptions(source: Source.server) : null;
      final contadores = await _contadoresRef.get(opcoes);
      final ativoId = contadores.data()?[_campoTravaCompleto] as String?;
      if (ativoId == null) return null;

      final doc = await _inventarios.doc(ativoId).get(opcoes);
      if (!doc.exists) return null;

      final inv = Inventario.fromFirestore(doc);
      return inv.isAtivo ? inv : null;
    } catch (e) {
      debugPrint('❌ Erro ao buscar Inventário Completo ativo: $e');
      if (propagarErros) rethrow;
      return null;
    }
  }

  /// Encerra o Inventário Completo do fluxo 2 e libera a trava.
  /// Recusa se restar qualquer pendência ([Inventario.pendenciasParaEncerrar]).
  /// Até a Fase 6 (reconciliação) existir, sempre recusará — comportamento
  /// esperado.
  Future<void> encerrarInventarioCompleto(String inventarioId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuário não autenticado');

    final invRef = _inventarios.doc(inventarioId);

    await _firestore.runTransaction<void>((tx) async {
      // ---------- LEITURAS ----------
      final invSnap = await tx.get(invRef);
      if (!invSnap.exists) {
        throw OperacaoNaoPermitidaException(
            'Encerrar inventário', inventarioId, 'inventário não encontrado');
      }
      final inv = Inventario.fromFirestore(invSnap);
      if (!inv.isFluxoMaquinaEstados) {
        throw OperacaoNaoPermitidaException('Encerrar inventário', inventarioId,
            'inventário do fluxo legado; use finalizarInventario');
      }
      final pendencias = inv.pendenciasParaEncerrar();
      if (pendencias.isNotEmpty) throw EncerramentoBloqueadoException(pendencias);

      final contadores = await tx.get(_contadoresRef);

      // ---------- ESCRITAS ----------
      tx.update(invRef, {
        'status': StatusInventario.finalizado.name,
        'data_fim': FieldValue.serverTimestamp(),
        'encerrado_por': user.uid,
      });

      if (contadores.data()?[_campoTravaCompleto] == inventarioId) {
        tx.set(_contadoresRef, {
          _campoTravaCompleto: null,
          'atualizado_em': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      AuditEventService.registrarNaTransacao(
        tx,
        inventarioId: inventarioId,
        tipo: TipoEvento.inventarioEncerrado,
        uid: user.uid,
        dados: {'numero': inv.numero},
      );
    });

    debugPrint('✅ Inventário Completo $inventarioId encerrado; trava liberada');
  }

  // ==================== FLUXO 2: PARTICIPAÇÃO (FASE 3) ====================

  /// Entra (ou retoma) a participação do usuário em C1 ou C2 (D3, D4, T23).
  ///
  /// Em transação:
  /// - o inventário precisa ser do fluxo 2, estar ativo e a rodada não pode
  ///   estar encerrada;
  /// - `rodada_base` é gravada na primeira entrada e nunca muda (D4);
  /// - participação já finalizada NÃO é reaberta: a sessão volta em modo
  ///   consulta;
  /// - a primeira entrada na rodada a tira de `disponivel` para `em_andamento`.
  ///
  /// Exige conexão.
  Future<ResultadoEntradaRodada> entrarNaRodada(
      String inventarioId, String rodada) async {
    if (!Fluxo2Config.habilitado) {
      throw OperacaoNaoPermitidaException(
          'Entrar na rodada', inventarioId, 'fluxo 2 desabilitado nesta build');
    }
    if (!Rodadas.isBase(rodada)) {
      throw OperacaoNaoPermitidaException('Entrar na rodada', inventarioId,
          'só C1 ou C2 podem ser escolhidas; a C3 é atribuída (T23)');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuário não autenticado');

    final invRef = _inventarios.doc(inventarioId);
    final partRef = invRef.collection('participantes').doc(user.uid);
    final sufixo = Rodadas.sufixo(rodada);

    return _firestore.runTransaction<ResultadoEntradaRodada>((tx) async {
      // ---------- LEITURAS ----------
      final invSnap = await tx.get(invRef);
      if (!invSnap.exists) {
        throw OperacaoNaoPermitidaException(
            'Entrar na rodada', inventarioId, 'inventário não encontrado');
      }
      final inv = Inventario.fromFirestore(invSnap);
      if (!inv.isFluxoMaquinaEstados || !inv.isAtivo) {
        throw OperacaoNaoPermitidaException(
            'Entrar na rodada', inventarioId, 'inventário não está ativo no fluxo 2');
      }
      final statusRodada = inv.statusRodada(rodada);
      if (statusRodada == null) {
        throw OperacaoNaoPermitidaException(
            'Entrar na rodada', inventarioId, '${Rodadas.rotulo(rodada)} não existe');
      }
      if (statusRodada == StatusRodada.encerrada) {
        throw OperacaoNaoPermitidaException(
            'Entrar na rodada', inventarioId, '${Rodadas.rotulo(rodada)} já foi encerrada');
      }

      final partSnap = await tx.get(partRef);
      final dados = partSnap.data();
      final rodadaBase = dados?['rodada_base'] as String?;
      if (rodadaBase != null && rodadaBase != rodada) {
        throw RodadaBaseConflitoException(rodadaBase, rodada);
      }
      final statusAtual = dados?['status_$sufixo'] as String?;
      final primeira = statusAtual == null;

      // ---------- ESCRITAS ----------
      final agora = FieldValue.serverTimestamp();
      final participante = <String, dynamic>{
        'uid': user.uid,
        'displayName': user.displayName ?? user.email ?? 'Sem nome',
        'email': user.email,
        'ultimo_acesso': agora,
      };
      if (dados == null || dados['primeiro_acesso'] == null) {
        participante['primeiro_acesso'] = agora;
      }
      if (rodadaBase == null) participante['rodada_base'] = rodada;
      if (primeira) {
        participante['status_$sufixo'] = StatusParticipante.emAndamento;
        participante['iniciou_${sufixo}_em'] = agora;
        participante['total_lancamentos_$sufixo'] = 0;
      }
      tx.set(partRef, participante, SetOptions(merge: true));

      final inventario = <String, dynamic>{
        'contagens.$rodada.usuarios': FieldValue.arrayUnion([user.uid]),
      };
      if (statusRodada == StatusRodada.disponivel) {
        inventario['contagens.$rodada.status'] = StatusRodada.emAndamento;
        inventario['contagens.$rodada.iniciada_em'] = agora;
      }
      tx.update(invRef, inventario);

      if (primeira) {
        AuditEventService.registrarNaTransacao(
          tx,
          inventarioId: inventarioId,
          tipo: TipoEvento.participanteEntrou,
          uid: user.uid,
          rodada: rodada,
        );
      }

      return ResultadoEntradaRodada(
        statusIndividual: statusAtual ?? StatusParticipante.emAndamento,
        statusRodada: statusRodada == StatusRodada.disponivel
            ? StatusRodada.emAndamento
            : statusRodada,
        primeiraEntrada: primeira,
      );
    });
  }

  /// "Finalizar minha contagem": encerra SOMENTE a participação do usuário
  /// na rodada (§7). Não toca no status global da rodada.
  ///
  /// A checagem de "zero não sincronizados" é do coletor
  /// (MobileSyncService.finalizarMinhaParticipacao), que chama este método
  /// só depois de esvaziar a fila local (B17, B19).
  ///
  /// Devolve o total de lançamentos sincronizados do usuário na rodada.
  /// Exige conexão.
  Future<int> finalizarMinhaParticipacao(String inventarioId, String rodada) async {
    if (!Fluxo2Config.habilitado) {
      throw OperacaoNaoPermitidaException('Finalizar participação', inventarioId,
          'fluxo 2 desabilitado nesta build');
    }
    if (!Rodadas.isBase(rodada)) {
      throw OperacaoNaoPermitidaException('Finalizar participação', inventarioId,
          'só C1 ou C2 nesta fase');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuário não autenticado');

    // Contagem no servidor (fora da transação: agregação não roda em transação)
    final contagem = await _firestore
        .collection('lancamentos')
        .where('inventarioId', isEqualTo: inventarioId)
        .where('contagemId', isEqualTo: rodada)
        .where('uid', isEqualTo: user.uid)
        .count()
        .get();
    final total = contagem.count ?? 0;
    if (total == 0) throw SemLancamentosSincronizadosException();

    final invRef = _inventarios.doc(inventarioId);
    final partRef = invRef.collection('participantes').doc(user.uid);
    final sufixo = Rodadas.sufixo(rodada);

    await _firestore.runTransaction<void>((tx) async {
      // ---------- LEITURAS ----------
      final invSnap = await tx.get(invRef);
      if (!invSnap.exists) {
        throw OperacaoNaoPermitidaException(
            'Finalizar participação', inventarioId, 'inventário não encontrado');
      }
      // B27: o estado global é revalidado DENTRO da transação. Se o analista
      // cancelou/encerrou o inventário ou a rodada no meio do caminho, a
      // finalização individual é recusada e nenhum evento é gravado.
      final inv = Inventario.fromFirestore(invSnap);
      if (!inv.isFluxoMaquinaEstados) {
        throw OperacaoNaoPermitidaException(
            'Finalizar participação', inventarioId, 'inventário fora do fluxo 2');
      }
      if (!inv.isAtivo) {
        throw OperacaoNaoPermitidaException('Finalizar participação',
            inventarioId, 'o inventário não está mais ativo');
      }
      if (inv.statusRodada(rodada) != StatusRodada.emAndamento) {
        throw OperacaoNaoPermitidaException('Finalizar participação', inventarioId,
            'a ${Rodadas.rotulo(rodada)} não está em andamento');
      }
      final partSnap = await tx.get(partRef);
      final status = partSnap.data()?['status_$sufixo'] as String?;
      if (status != StatusParticipante.emAndamento) {
        throw OperacaoNaoPermitidaException('Finalizar participação',
            inventarioId, 'participação não está em andamento ($status)');
      }

      // ---------- ESCRITAS ----------
      final agora = FieldValue.serverTimestamp();
      tx.update(partRef, {
        'status_$sufixo': StatusParticipante.finalizado,
        'finalizado_por_$sufixo': FinalizadoPor.usuario,
        'finalizou_${sufixo}_em': agora,
        'total_lancamentos_$sufixo': total,
        'pendentes_locais': 0,
        'pendentes_informados_em': agora,
        'ultimo_acesso': agora,
      });

      AuditEventService.registrarNaTransacao(
        tx,
        inventarioId: inventarioId,
        tipo: TipoEvento.participanteFinalizou,
        uid: user.uid,
        rodada: rodada,
        dados: {'total_lancamentos': total, 'por': FinalizadoPor.usuario},
      );
    });

    debugPrint('✅ Participação ${Rodadas.rotulo(rodada)} finalizada ($total lançamentos)');
    return total;
  }

  /// Meu documento de participante no inventário (null se não existe).
  /// Usado pela tela de escolha para aplicar D4 antes da entrada.
  /// [somenteServidor] = true: lê só do servidor (B29); sem rede, lança.
  Future<Participante?> buscarMeuParticipante(String inventarioId,
      {bool somenteServidor = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final doc = await _inventarios
        .doc(inventarioId)
        .collection('participantes')
        .doc(user.uid)
        .get(somenteServidor ? const GetOptions(source: Source.server) : null);
    if (!doc.exists) return null;
    return Participante.fromFirestore(doc, null);
  }

  /// Informa ao monitor quantos lançamentos o coletor ainda não sincronizou
  /// (B17: pending + error + exclusões pendentes). Não aguarda o servidor:
  /// offline, a escrita fica na fila do Firestore.
  /// B30: usa `update()`: se o participante não existir mais, falha em
  /// silêncio e NUNCA recria um documento parcial.
  void informarPendentesLocais(String inventarioId, int naoSincronizados) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _inventarios
        .doc(inventarioId)
        .collection('participantes')
        .doc(user.uid)
        .update({
          'pendentes_locais': naoSincronizados,
          'pendentes_informados_em': FieldValue.serverTimestamp(),
        })
        .catchError((Object e) => debugPrint('ℹ️ Pendentes não informados: $e'));
  }

  /// Base da sequência da Contagem Completa (D2). Só faz a varredura quando
  /// `ultimo_inventario_completo` ainda não existe; depois disso, o valor
  /// lido dentro da transação é o que vale.
  Future<int> _baseSequenciaCompleta() async {
    final contadores = await _contadoresRef.get();
    final atual = contadores.data()?[_campoUltimoCompleto];
    if (atual is num) return atual.toInt();

    // Primeira vez: maior número de Contagem Completa válido já gravado.
    // Inventário sem tipo_contagem é lido como completa pelo modelo.
    final todos = await _inventarios.get();
    var maior = 0;
    for (final doc in todos.docs) {
      final inv = Inventario.fromFirestore(doc);
      if (!inv.isCompleta) continue;
      if (inv.numero <= 0 || inv.numero > _numeroMaximoValido) {
        debugPrint('⚠️ Número ignorado na base da sequência: ${inv.numero} (${inv.codigo})');
        continue;
      }
      if (inv.numero > maior) maior = inv.numero;
    }
    debugPrint('ℹ️ Sequência da Contagem Completa inicializada a partir de $maior');
    return maior;
  }

  /// Recusa abrir o fluxo 2 se houver Contagem Completa legada ativa.
  Future<void> _verificarCompletoLegadoAtivo() async {
    final snapshot = await _inventarios
        .where('status', whereIn: Inventario.valoresStatusAtivo)
        .get();

    for (final doc in snapshot.docs) {
      final inv = Inventario.fromFirestore(doc);
      if (!inv.isFluxoMaquinaEstados && inv.isCompleta) {
        throw InventarioLegadoAtivoException(inv.id, inv.codigo);
      }
    }
  }

  static Map<String, dynamic> _rodadaInicial() => {
        'status': StatusRodada.disponivel,
        'iniciada_em': null,
        'finalizada_em': null,
        'usuarios': <String>[],
        'total_lancamentos': 0,
      };

  static String _dataDDMMAAAA(DateTime agora) =>
      '${agora.day.toString().padLeft(2, '0')}'
      '${agora.month.toString().padLeft(2, '0')}'
      '${agora.year}';

  /// Depósito > 3 letras do tipo de material > 'CMP'.
  static String _prefixoCodigo({String? deposito, String? tipoMaterial}) {
    if (deposito != null && deposito.isNotEmpty) return deposito;
    if (tipoMaterial != null && tipoMaterial.isNotEmpty) {
      final fim = tipoMaterial.length < 3 ? tipoMaterial.length : 3;
      return tipoMaterial.substring(0, fim).toUpperCase();
    }
    return 'CMP';
  }

  /// Guarda das funções legadas: recusa inventário do fluxo 2.
  Future<void> _exigirFluxoLegado(String inventarioId, String operacao) async {
    final doc = await _inventarios.doc(inventarioId).get();
    if (!doc.exists) return; // o próprio método legado trata a ausência
    final versao = doc.data()?['fluxo_versao'];
    if (versao is num && versao.toInt() >= FluxoVersao.maquinaEstados) {
      throw OperacaoNaoPermitidaException(
          operacao, inventarioId, 'inventário do fluxo 2 (máquina de estados)');
    }
  }

  // ==================== CONSULTAS ====================

  /// Busca o inventário ativo (em andamento ou aguardando).
  ///
  /// Por padrão IGNORA inventários do fluxo 2: as telas legadas (home_page,
  /// dashboard) não podem vincular lançamentos a eles antes da Fase 3/4
  /// (parecer do revisor §8.3). Para o fluxo 2 use
  /// [buscarInventarioCompletoAtivo].
  Future<Inventario?> buscarInventarioAtivo({bool incluirFluxo2 = false}) async {
    try {
      // Busca por status em_andamento OU aguardando
      final snapshot = await _inventarios
          .where('status', whereIn: Inventario.valoresStatusAtivo)
          .orderBy('data_inicio', descending: true)
          .limit(10)
          .get();

      for (final doc in snapshot.docs) {
        final inv = Inventario.fromFirestore(doc);
        if (!incluirFluxo2 && inv.isFluxoMaquinaEstados) continue;
        return inv;
      }

      debugPrint('ℹ️ Nenhum inventário ativo encontrado');
      return null;
    } catch (e) {
      debugPrint('❌ Erro ao buscar inventário ativo: $e');
      return null;
    }
  }

  /// Busca um inventário específico por ID
  Future<Inventario?> buscarInventarioPorId(String id) async {
    try {
      final doc = await _inventarios.doc(id).get();

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
      Query<Map<String, dynamic>> query = _inventarios
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
    Query<Map<String, dynamic>> query = _inventarios
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
    return _inventarios
        .doc(inventarioId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return Inventario.fromFirestore(doc);
    });
  }

  // ==================== CONTROLE DE ESTADO (FLUXO 1) ====================

  /// Inicia o inventário (muda de aguardando para em_andamento).
  /// Fluxo 2: o inventário já nasce em andamento; a chamada não faz nada.
  Future<void> iniciarInventario(String inventarioId) async {
    try {
      final doc = await _inventarios.doc(inventarioId).get();
      final versao = doc.data()?['fluxo_versao'];
      if (versao is num && versao.toInt() >= FluxoVersao.maquinaEstados) {
        debugPrint('ℹ️ Inventário $inventarioId é do fluxo 2 e já nasce em andamento');
        return;
      }

      await _inventarios.doc(inventarioId).update({
        'status': StatusInventario.emAndamento.name,
        'contagens.contagem_1.iniciada_em': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Inventário $inventarioId iniciado');
    } catch (e) {
      debugPrint('❌ Erro ao iniciar inventário: $e');
      rethrow;
    }
  }

  /// Inicia uma nova contagem no inventário (fluxo 1)
  Future<void> iniciarContagem(String inventarioId, String contagemId) async {
    try {
      await _exigirFluxoLegado(inventarioId, 'iniciarContagem');
      final now = DateTime.now();

      await _inventarios.doc(inventarioId).update({
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

  /// Finaliza uma contagem (fluxo 1)
  Future<void> finalizarContagem(String inventarioId, String contagemId) async {
    try {
      await _exigirFluxoLegado(inventarioId, 'finalizarContagem');
      final now = DateTime.now();

      // Conta total de lançamentos desta contagem
      final lancamentos = await _firestore
          .collection('lancamentos')
          .where('inventarioId', isEqualTo: inventarioId)
          .where('contagemId', isEqualTo: contagemId)
          .get();

      await _inventarios.doc(inventarioId).update({
        'contagens.$contagemId.finalizada_em': Timestamp.fromDate(now),
        'contagens.$contagemId.total_lancamentos': lancamentos.size,
      });

      debugPrint('✅ Contagem $contagemId finalizada com ${lancamentos.size} lançamentos');
    } catch (e) {
      debugPrint('❌ Erro ao finalizar contagem: $e');
      rethrow;
    }
  }

  /// Finaliza o inventário completo (fluxo 1).
  /// Fluxo 2: use [encerrarInventarioCompleto], que valida e libera a trava.
  Future<void> finalizarInventario(String inventarioId) async {
    try {
      await _exigirFluxoLegado(inventarioId, 'finalizarInventario');
      final now = DateTime.now();

      await _inventarios.doc(inventarioId).update({
        'status': StatusInventario.finalizado.name,
        'data_fim': Timestamp.fromDate(now),
      });

      debugPrint('✅ Inventário $inventarioId finalizado');
    } catch (e) {
      debugPrint('❌ Erro ao finalizar inventário: $e');
      rethrow;
    }
  }

  /// Avança para a próxima contagem (C1→C2 ou C2→C3) — SOMENTE fluxo 1.
  @Deprecated('Fluxo 1 apenas. No fluxo 2 as rodadas são encerradas pelo '
      'analista e a C3 nasce da reconciliação.')
  Future<bool> avancarParaProximaContagem(String inventarioId) async {
    try {
      final inventario = await buscarInventarioPorId(inventarioId);
      if (inventario == null) {
        debugPrint('❌ Inventário não encontrado');
        return false;
      }

      if (inventario.isFluxoMaquinaEstados) {
        debugPrint('⚠️ Inventário do fluxo 2: "avançar contagem" não se aplica');
        return false;
      }

      // ignore: deprecated_member_use_from_same_package
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

  /// Cancela um inventário.
  ///
  /// Fluxo 2 (D7): motivo obrigatório; só inventário ativo; libera a trava
  /// na mesma transação; grava evento; o número não volta para a sequência;
  /// nada é apagado.
  /// O "somente analista" depende da tela (desktop): o app ainda não tem
  /// papel de usuário no modelo.
  Future<void> cancelarInventario(String inventarioId, {String? motivo}) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final invRef = _inventarios.doc(inventarioId);

      await _firestore.runTransaction<void>((tx) async {
        // ---------- LEITURAS ----------
        final invSnap = await tx.get(invRef);
        if (!invSnap.exists) {
          throw OperacaoNaoPermitidaException(
              'Cancelar inventário', inventarioId, 'inventário não encontrado');
        }
        final inv = Inventario.fromFirestore(invSnap);

        if (!inv.isFluxoMaquinaEstados) {
          // Fluxo 1: comportamento antigo
          tx.update(invRef, {
            'status': StatusInventario.cancelado.name,
            'data_fim': FieldValue.serverTimestamp(),
            'motivo_cancelamento': motivo,
          });
          return;
        }

        // B15: fluxo 2 exige usuário autenticado (cancelado_por e evento
        // nunca ficam sem autor). O fluxo legado mantém o comportamento antigo.
        if (uid == null) {
          throw OperacaoNaoPermitidaException(
              'Cancelar inventário', inventarioId, 'usuário não autenticado');
        }
        if (motivo == null || motivo.trim().isEmpty) {
          throw OperacaoNaoPermitidaException(
              'Cancelar inventário', inventarioId, 'motivo obrigatório');
        }
        if (!inv.isAtivo) {
          throw OperacaoNaoPermitidaException('Cancelar inventário', inventarioId,
              'inventário não está ativo (${inv.status.name})');
        }

        final contadores = await tx.get(_contadoresRef);

        // ---------- ESCRITAS ----------
        tx.update(invRef, {
          'status': StatusInventario.cancelado.name,
          'data_fim': FieldValue.serverTimestamp(),
          'motivo_cancelamento': motivo.trim(),
          'cancelado_por': uid,
        });

        if (contadores.data()?[_campoTravaCompleto] == inventarioId) {
          tx.set(_contadoresRef, {
            _campoTravaCompleto: null,
            'atualizado_em': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        AuditEventService.registrarNaTransacao(
          tx,
          inventarioId: inventarioId,
          tipo: TipoEvento.inventarioCancelado,
          uid: uid,
          dados: {'numero': inv.numero, 'motivo': motivo.trim()},
        );
      });

      debugPrint('✅ Inventário $inventarioId cancelado');
    } catch (e) {
      debugPrint('❌ Erro ao cancelar inventário: $e');
      rethrow;
    }
  }

  /// Marca itens para serem recontados na Contagem 3 — SOMENTE fluxo 1.
  @Deprecated('Fluxo 1 apenas. No fluxo 2 a C3 nasce da reconciliação.')
  Future<void> marcarItensParaC3(
      String inventarioId,
      List<String> codigos,
      ) async {
    try {
      await _exigirFluxoLegado(inventarioId, 'marcarItensParaC3');
      await _inventarios.doc(inventarioId).update({
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
    return _inventarios
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

  /// Inicializa participante no inventário (fluxo 1).
  @Deprecated('Sem chamador ativo (home_page._iniciarParticipacao não é usado). '
      'No fluxo 2 a entrada será entrarNaRodada (Fase 3).')
  Future<void> iniciarParticipante(String inventarioId) async {
    try {
      await _exigirFluxoLegado(inventarioId, 'iniciarParticipante');
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');

      final participanteRef = _inventarios
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

  /// Finaliza contagem atual do participante (fluxo 1).
  /// No fluxo 2 será finalizarMinhaParticipacao (Fase 3).
  Future<void> finalizarContagemParticipante(String inventarioId, String contagemId) async {
    try {
      await _exigirFluxoLegado(inventarioId, 'finalizarContagemParticipante');
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
      final participanteRef = _inventarios
          .doc(inventarioId)
          .collection('participantes')
          .doc(user.uid);

      final contagemNum = Rodadas.sufixo(contagemId);

      final updates = <String, dynamic>{
        // B5: antes gravava 'finalizou_contagem_1_em'; o modelo lê 'finalizou_c1_em'
        'finalizou_${contagemNum}_em': FieldValue.serverTimestamp(),
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

  /// Libera próxima contagem para um participante — SOMENTE fluxo 1.
  @Deprecated('Fluxo 1 apenas. No fluxo 2 a C3 é atribuída pelo '
      'c3_assignment_service (Fases 8/9).')
  Future<void> liberarProximaContagem(
      String inventarioId,
      String uid,
      String proximaContagem,
      ) async {
    try {
      await _exigirFluxoLegado(inventarioId, 'liberarProximaContagem');
      final participanteRef = _inventarios
          .doc(inventarioId)
          .collection('participantes')
          .doc(uid);

      final contagemNum = Rodadas.sufixo(proximaContagem);

      final updates = <String, dynamic>{
        'contagem_atual': proximaContagem,
        'status_$contagemNum': 'em_andamento',
        // B5: antes gravava 'iniciou_contagem_2_em'
        'iniciou_${contagemNum}_em': FieldValue.serverTimestamp(),
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

  /// Participante solicita participar de uma contagem específica (fluxo 1).
  /// Destino no fluxo 2 depende da decisão D3.
  Future<void> solicitarParticipacao(
      String inventarioId,
      String contagemEscolhida,
      ) async {
    try {
      await _exigirFluxoLegado(inventarioId, 'solicitarParticipacao');
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');

      final participanteRef = _inventarios
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

  /// Analista aprova participação (fluxo 1)
  Future<void> aprovarParticipacao(
      String inventarioId,
      String uid,
      String contagemSolicitada,
      ) async {
    try {
      await _exigirFluxoLegado(inventarioId, 'aprovarParticipacao');
      final participanteRef = _inventarios
          .doc(inventarioId)
          .collection('participantes')
          .doc(uid);

      final contagemNum = Rodadas.sufixo(contagemSolicitada);

      final dados = <String, dynamic>{
        'status': 'aprovado',
        'contagem_atual': contagemSolicitada,
        'aprovado_em': FieldValue.serverTimestamp(),
        'aprovado_por': FirebaseAuth.instance.currentUser?.uid,
        // B5: antes gravava 'iniciou_contagem_N_em'
        'iniciou_${contagemNum}_em': FieldValue.serverTimestamp(),
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

  /// Analista rejeita participação (fluxo 1)
  Future<void> rejeitarParticipacao(
      String inventarioId,
      String uid,
      ) async {
    try {
      await _exigirFluxoLegado(inventarioId, 'rejeitarParticipacao');
      await _inventarios
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
      final participantes = await _inventarios
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
