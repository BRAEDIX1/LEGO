// lib/services/mobile_sync_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lego/config/fluxo2_config.dart';
import 'package:lego/data/repositories/lancamentos_repository.dart';
import 'package:lego/models/inventario.dart';
import 'package:lego/models/participante.dart' show StatusParticipante;
import 'package:lego/models/sessao_contagem.dart';
import 'package:lego/services/compatibilidade.dart';
import 'package:lego/services/compatibilidade_service.dart';
import 'package:lego/services/inventario_service.dart';
import 'package:lego/services/sync_service.dart';

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

/// Resposta de [MobileSyncService.iniciarMutacao] (B19, B24).
class AutorizacaoMutacao {
  final bool permitida;
  final String inventarioId;
  final String contagemId;
  final String? motivo;

  /// true quando a autorização incrementou o contador de mutações e exige
  /// [MobileSyncService.concluirMutacao].
  final bool contabilizada;

  const AutorizacaoMutacao._({
    required this.permitida,
    this.inventarioId = '',
    this.contagemId = '',
    this.motivo,
    this.contabilizada = false,
  });

  /// Fluxo legado (chave desligada): IDs vêm da tela, como hoje.
  factory AutorizacaoMutacao.legado(String inventarioId, String contagemId) =>
      AutorizacaoMutacao._(
        permitida: true,
        inventarioId: inventarioId,
        contagemId: contagemId,
      );

  factory AutorizacaoMutacao.negada(String motivo) =>
      AutorizacaoMutacao._(permitida: false, motivo: motivo);
}

/// Resultado de [MobileSyncService.finalizarMinhaParticipacao].
class ResultadoFinalizacao {
  final bool sucesso;
  final String mensagem;
  const ResultadoFinalizacao(this.sucesso, this.mensagem);
}

/// Serviço de sincronização mobile com inventário ativo.
///
/// Fluxo 2 (Lote 3A): é o DONO ÚNICO da sessão de contagem ([sessaoAtual]).
/// Toda gravação da tela passa por [iniciarMutacao]/[concluirMutacao].
class MobileSyncService {
  static final MobileSyncService _instance = MobileSyncService._internal();
  factory MobileSyncService() => _instance;
  MobileSyncService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Chaves de SharedPreferences
  static const String _keyModoOperacao = 'modo_operacao';
  static const String _keyInventarioId = 'inventario_vinculado_id';
  // B48 (3B): dono do vínculo Controlado salvo
  static const String _keyInventarioUid = 'inventario_vinculado_uid';

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

  // ---------- Fluxo 2: sessão ----------
  static const String _keySessao = 'sessao_contagem_v1';
  final _sessaoController = StreamController<SessaoContagem?>.broadcast();
  SessaoContagem? _sessao;
  StreamSubscription? _sessaoInvSub;
  StreamSubscription? _sessaoPartSub;
  bool _finalizacaoEmAndamento = false;
  int _mutacoesEmCurso = 0;

  /// Motivo do último fim de sessão por inventário encerrado/cancelado (T19).
  String? ultimoMotivoFimSessao;

  // ---------- Lote 3B: vínculo central no fluxo legado (B39, B41, B42) ----------
  // Estado ÚNICO no serviço (B42): a HomePage e a tela legada leem daqui.
  bool _inventarioLegadoDetectado = false;
  ResultadoCompat? _compatCentralLegado;
  String? _motivoBloqueioCentral;
  String? _codigoInventarioBloqueado;
  bool _autonomoExplicito = false;
  String? _vinculoControladoBloqueado;
  bool _validandoL4 = false;
  String? _donoVinculo; // B48: UID que salvou o vínculo Controlado

  /// B53: geração do vínculo legado. Toda transição (L3, L4, Autônomo,
  /// troca de usuário) cria uma geração nova; trabalho assíncrono de uma
  /// geração anterior vira no-op.
  int _geracaoVinculo = 0;
  int _novaGeracao() => ++_geracaoVinculo;

  /// Dono do estado acima. Troca de usuário (inclusive logout legado, que
  /// não passa por limparSessao) zera tudo: a escolha de um usuário nunca
  /// vale para outro (revisão 3B).
  String? _estado3BUid;

  void _garantirUsuario3B() {
    final uid = _auth.currentUser?.uid;
    if (uid == _estado3BUid) return;
    _estado3BUid = uid;
    _novaGeracao(); // B53: nada do usuário anterior continua valendo
    _inventarioLegadoDetectado = false;
    _compatCentralLegado = null;
    _motivoBloqueioCentral = null;
    _codigoInventarioBloqueado = null;
    _autonomoExplicito = false;
    _validandoL4 = false;
    // Vínculo Controlado salvo no aparelho: nunca parece restaurado depois de
    // uma troca de usuário. Dono diferente ou ausente = bloqueado (B48);
    // mesmo dono = precisa validar de novo (a inicialização roda a L4).
    if (_modoAtual == ModoOperacao.controlado && _inventarioVinculadoId != null) {
      _vinculoControladoBloqueado =
          motivoDonoVinculo(avaliarDonoVinculo(_donoVinculo, uid)) ??
              'Vínculo salvo: valide de novo ("Verificar de novo").';
    } else {
      _vinculoControladoBloqueado = null;
    }
  }

  /// O operador escolheu Autônomo de forma explícita nesta execução (B42).
  bool get autonomoExplicito {
    _garantirUsuario3B();
    return _autonomoExplicito;
  }

  /// Compatibilidade avaliada para o inventário legado ativo (L1).
  /// null com inventário detectado = ainda conferindo.
  ResultadoCompat? get compatCentralLegado {
    _garantirUsuario3B();
    return _compatCentralLegado;
  }

  /// Motivo do bloqueio do vínculo central legado (L1), ou null.
  String? get motivoBloqueioCentral {
    _garantirUsuario3B();
    return _inventarioLegadoDetectado && !podeVincularCentral(_compatCentralLegado)
        ? _motivoBloqueioCentral
        : null;
  }

  /// Código do inventário legado ativo que ficou bloqueado (L1).
  String? get codigoInventarioBloqueado =>
      motivoBloqueioCentral == null ? null : _codigoInventarioBloqueado;

  /// L4: vínculo Controlado salvo que não pôde ser restaurado (B41), ou null.
  String? get vinculoControladoBloqueado {
    _garantirUsuario3B();
    return _vinculoControladoBloqueado;
  }

  /// B45: motivo que impede gravação legada AGORA (L4 ou L1), ou null.
  /// Autônomo explícito libera as gravações sem vínculo.
  String? get motivoBloqueioLegado {
    _garantirUsuario3B();
    if (_autonomoExplicito) return null;
    return _vinculoControladoBloqueado ?? motivoBloqueioCentral;
  }

  /// B48: o bloqueio da L4 é por dono do vínculo (outro usuário ou sem dono)?
  /// Nesse caso a saída é escolher o inventário de novo (tela legada).
  bool get vinculoBloqueadoPorDono {
    _garantirUsuario3B();
    if (_vinculoControladoBloqueado == null) return false;
    return avaliarDonoVinculo(_donoVinculo, _auth.currentUser?.uid) !=
        DonoVinculo.mesmoUsuario;
  }

  /// Ainda conferindo (L1 sem resultado ou L4 validando): sem botões na faixa.
  bool get bloqueioLegadoConferindo {
    _garantirUsuario3B();
    if (_vinculoControladoBloqueado != null) return _validandoL4;
    return _inventarioLegadoDetectado && _compatCentralLegado == null;
  }

  // Idempotência de inicializar() por usuário (B18)
  String? _inicializadoParaUid;
  Future<void>? _inicializacao;

  /// Sessão atual (síncrono: a tela consulta antes de gravar, sem rede).
  SessaoContagem? get sessaoAtual => _sessao;

  /// Emite a cada mudança de sessão; `null` = sem sessão (T19).
  Stream<SessaoContagem?> get sessaoStream => _sessaoController.stream;

  bool get finalizacaoEmAndamento => _finalizacaoEmAndamento;

  /// Criar, editar ou excluir lançamento é permitido agora? (B24)
  /// B26: a sessão precisa pertencer ao usuário logado AGORA (B16 como
  /// invariante de execução, não só na restauração).
  bool get podeMutarAgora {
    final s = _sessao;
    return s != null &&
        s.pertenceA(_auth.currentUser?.uid) &&
        !_finalizacaoEmAndamento &&
        s.podeLancar;
  }

  final InventarioService _inventarioService = InventarioService();

  // ==================== INICIALIZAÇÃO ====================

  /// Inicializa o serviço e restaura estado salvo.
  /// Idempotente por usuário (B18): chamadas repetidas para o mesmo UID
  /// reaproveitam a mesma inicialização.
  Future<void> inicializar() {
    final uid = _auth.currentUser?.uid ?? '';
    if (_inicializacao != null && _inicializadoParaUid == uid) {
      return _inicializacao!;
    }
    _inicializadoParaUid = uid;
    return _inicializacao = _inicializarInterno().catchError((Object e) {
      // Permite nova tentativa numa próxima chamada
      _inicializacao = null;
      _inicializadoParaUid = null;
      throw e;
    });
  }

  Future<void> _inicializarInterno() async {
    final prefs = await SharedPreferences.getInstance();

    // 3B: o monitor legado de um usuário anterior não segue ativo para o
    // próximo (a L4 abaixo religa só para o dono validado).
    await _cancelarMonitoramento();

    // 3B: estado do vínculo central vale por usuário e por execução
    _estado3BUid = null;
    _garantirUsuario3B();
    _vinculoControladoBloqueado = null; // a L4 abaixo decide de novo

    if (Fluxo2Config.habilitado) {
      await _restaurarSessao(prefs);
    }

    
    // Restaura modo
    final modoSalvo = prefs.getString(_keyModoOperacao);
    _modoAtual = modoSalvo == 'controlado' 
        ? ModoOperacao.controlado 
        : ModoOperacao.autonomo;
    
    // Restaura inventário vinculado
    _inventarioVinculadoId = prefs.getString(_keyInventarioId);
    _donoVinculo = prefs.getString(_keyInventarioUid);

    // L4 (3B, B40, B41): o vínculo Controlado salvo só é restaurado depois de
    // validado (inventário legado + compatibilidade). Até lá, e se falhar,
    // fica BLOQUEADO; nunca vira Autônomo sozinho.
    // B48: só o DONO do vínculo segue para a L4. Outro usuário ou vínculo
    // sem dono (APK anterior) fica bloqueado até nova escolha consciente.
    if (_modoAtual == ModoOperacao.controlado && _inventarioVinculadoId != null) {
      final dono = avaliarDonoVinculo(_donoVinculo, _auth.currentUser?.uid);
      if (dono == DonoVinculo.mesmoUsuario) {
        _vinculoControladoBloqueado = 'Validando o vínculo com o inventário...';
        _validandoL4 = true;
        unawaited(_validarRestauracaoControlado(
            _inventarioVinculadoId!, _novaGeracao()));
      } else {
        _vinculoControladoBloqueado = motivoDonoVinculo(dono);
        _validandoL4 = false;
        debugPrint('🔒 Controlado NÃO restaurado (B48): ${dono.name}');
      }
    }

    _modoController.add(_modoAtual!);
    debugPrint('📱 MobileSyncService inicializado: modo=$_modoAtual, inv=$_inventarioVinculadoId');
  }

  /// Libera recursos
  void dispose() {
    _inventarioSubscription?.cancel();
    _participanteSubscription?.cancel();
    _sessaoInvSub?.cancel();
    _sessaoPartSub?.cancel();
    _modoController.close();
    _inventarioController.close();
    _sessaoController.close();
  }

  // ==================== FLUXO 2: SESSÃO ====================

  /// B16: restaura a sessão salva SOMENTE se pertencer ao usuário logado.
  Future<void> _restaurarSessao(SharedPreferences prefs) async {
    await _pararMonitoramentoSessao();
    final salva = SessaoContagem.fromJson(prefs.getString(_keySessao));
    final uid = _auth.currentUser?.uid;

    if (salva == null || !salva.pertenceA(uid)) {
      if (salva != null) {
        debugPrint('📱 Sessão salva de outro usuário descartada (B16)');
      }
      await prefs.remove(_keySessao);
      _sessao = null;
      _emitirSessao();
      return;
    }

    _sessao = salva;
    _emitirSessao();
    if (salva.isCompleta) _monitorarSessao(salva);
    debugPrint('📱 Sessão restaurada: ${salva.rotuloCabecalho}');
  }

  Future<void> _salvarSessao() async {
    final prefs = await SharedPreferences.getInstance();
    if (_sessao == null) {
      await prefs.remove(_keySessao);
    } else {
      await prefs.setString(_keySessao, _sessao!.toJson());
    }
  }

  void _emitirSessao() {
    if (!_sessaoController.isClosed) _sessaoController.add(_sessao);
  }

  /// Contagem Simples (D1): sem inventário, IDs vazios. Funciona offline.
  Future<void> escolherSimples() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Usuário não autenticado');
    await _pararMonitoramentoSessao();
    _sessao = SessaoContagem.simples(uid);
    await _salvarSessao();
    _emitirSessao();
  }

  /// Contagem Completa (T16): cria ou entra no inventário ativo e na rodada
  /// escolhida. Exige conexão. Se a segunda etapa falhar, uma nova tentativa
  /// recebe o mesmo inventário (R7).
  Future<SessaoContagem> entrarContagemCompleta(String rodada) async {
    if (!Fluxo2Config.habilitado) {
      throw OperacaoNaoPermitidaException(
          'Entrar na Contagem Completa', '', 'fluxo 2 desabilitado nesta build');
    }
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Usuário não autenticado');

    // T33a (3B): versão mínima + preparação da build, leitura OBRIGATÓRIA no
    // servidor. Lança FirebaseException ou CompatibilidadeException.
    await CompatibilidadeService().verificarNoServidor(PlataformaCompat.mobile);

    final inv = await _inventarioService.criarOuEntrarInventarioCompleto(
        origem: 'mobile');
    final entrada = await _inventarioService.entrarNaRodada(inv.id, rodada);

    await _pararMonitoramentoSessao();
    final sessao = SessaoContagem.completa(
      usuarioUid: uid,
      inventarioId: inv.id,
      numero: inv.numero,
      codigo: inv.codigo,
      rodada: rodada,
      statusRodada: entrada.statusRodada,
      statusIndividual: entrada.statusIndividual,
    );
    _sessao = sessao;
    ultimoMotivoFimSessao = null;
    await _salvarSessao();
    _emitirSessao();
    _monitorarSessao(sessao);
    return sessao;
  }

  /// Logout: a sessão não pode sobreviver à troca de usuário (B16).
  Future<void> limparSessao() async {
    await _pararMonitoramentoSessao();
    _sessao = null;
    _inicializacao = null;
    _inicializadoParaUid = null;
    await _salvarSessao();
    _emitirSessao();
  }

  void _monitorarSessao(SessaoContagem sessao) {
    final invId = sessao.inventarioId!;
    final rodada = sessao.rodada!;
    final uid = sessao.usuarioUid;
    final invRef = _firestore.collection('inventarios').doc(invId);

    // B31: includeMetadataChanges garante a notificação quando só a origem
    // muda (cache → servidor), que é o que confirma uma ausência (T30/B30).
    _sessaoInvSub = invRef
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      final atual = _sessao;
      if (atual == null || atual.inventarioId != invId) return;
      // B32 (endurecimento): ignora eventos se o usuário logado mudou
      if (_auth.currentUser?.uid != uid) return;

      // Offline sem cache: "não existe" não é informação confiável.
      if (!snap.exists) {
        if (!snap.metadata.isFromCache) {
          _encerrarSessao('O inventário não existe mais.');
        }
        return;
      }

      final inv = Inventario.fromFirestore(snap);
      if (!inv.isAtivo) {
        _encerrarSessao(
          inv.status == StatusInventario.cancelado
              ? 'O Inventário ${inv.numeroFormatado} foi cancelado.'
              : 'O Inventário ${inv.numeroFormatado} foi encerrado.',
        );
        return;
      }

      _atualizarSessao(atual.copyWith(
        statusRodada: inv.statusRodada(rodada),
        numero: inv.numero,
        codigo: inv.codigo,
        inventarioAtivo: true,
      ));
    }, onError: (Object e) => debugPrint('⚠️ Monitor do inventário: $e'));

    _sessaoPartSub = invRef
        .collection('participantes')
        .doc(uid)
        .snapshots(includeMetadataChanges: true) // B31
        .listen((snap) {
      final atual = _sessao;
      if (atual == null || atual.inventarioId != invId) return;
      if (_auth.currentUser?.uid != uid) return; // B32 (endurecimento)
      if (!snap.exists) {
        // B30: participante ausente confirmado pelo servidor não pode manter
        // a autorização antiga. Ausência só no cache offline é ignorada (T30).
        if (!snap.metadata.isFromCache) {
          _encerrarSessao(
              'Sua participação no Inventário ${atual.numeroFormatado} não existe mais.');
        }
        return;
      }
      final status = snap.data()?['status_${Rodadas.sufixo(rodada)}'] as String?;
      if (status != null && status != atual.statusIndividual) {
        _atualizarSessao(atual.copyWith(statusIndividual: status));
      }
    }, onError: (Object e) => debugPrint('⚠️ Monitor do participante: $e'));
  }

  void _atualizarSessao(SessaoContagem nova) {
    final antes = _sessao;
    _sessao = nova;
    final mudou = antes == null ||
        antes.statusRodada != nova.statusRodada ||
        antes.statusIndividual != nova.statusIndividual ||
        antes.inventarioAtivo != nova.inventarioAtivo ||
        antes.numero != nova.numero;
    if (mudou) {
      _salvarSessao();
      _emitirSessao();
    }
  }

  /// T19 / B30: inventário encerrado/cancelado/inexistente ou participante
  /// ausente → sessão limpa, stream emite null e a HomePage navega para a
  /// tela de escolha. Nunca vira Simples sozinha.
  Future<void> _encerrarSessao(String motivo) async {
    debugPrint('📱 Fim da sessão: $motivo');
    ultimoMotivoFimSessao = motivo;
    await _pararMonitoramentoSessao();
    _sessao = null;
    await _salvarSessao();
    _emitirSessao();
  }

  Future<void> _pararMonitoramentoSessao() async {
    await _sessaoInvSub?.cancel();
    await _sessaoPartSub?.cancel();
    _sessaoInvSub = null;
    _sessaoPartSub = null;
  }

  // ---------- Mutações (B19, B24) ----------

  /// Pede autorização para criar, editar ou excluir lançamento.
  /// Permitida: devolve os IDs da sessão (T18) e incrementa o contador.
  /// SEMPRE chamar [concluirMutacao] num `finally`.
  AutorizacaoMutacao iniciarMutacao() {
    final s = _sessao;
    if (s == null) {
      return AutorizacaoMutacao.negada(
          'Escolha o tipo de contagem antes de lançar.');
    }
    // B26: nunca combinar o UID atual com a sessão de outro usuário
    if (!s.pertenceA(_auth.currentUser?.uid)) {
      return AutorizacaoMutacao.negada(
          'A sessão de contagem é de outro usuário. Escolha o tipo de contagem novamente.');
    }
    if (_finalizacaoEmAndamento) {
      return AutorizacaoMutacao.negada(
          'Finalização em andamento. Aguarde.');
    }
    if (!s.podeLancar) {
      return AutorizacaoMutacao.negada(
          s.motivoBloqueio ?? 'Lançamento não permitido.');
    }
    _mutacoesEmCurso++;
    final (inventarioId, contagemId) = s.idsGravacao;
    return AutorizacaoMutacao._(
      permitida: true,
      inventarioId: inventarioId,
      contagemId: contagemId,
      contabilizada: true,
    );
  }

  void concluirMutacao(AutorizacaoMutacao autorizacao) {
    if (!autorizacao.contabilizada) return;
    if (_mutacoesEmCurso > 0) _mutacoesEmCurso--;
  }

  // ---------- Finalização (T20, B17, B19) ----------

  /// "Finalizar minha contagem".
  /// trava → espera mutações em curso → reenfileira `error` → sincroniza →
  /// zero não sincronizados → finaliza no Firestore → sessão `finalizado`.
  /// Falha em qualquer etapa antes do Firestore libera a trava e mantém
  /// `em_andamento`. Segundo toque durante a operação é ignorado.
  Future<ResultadoFinalizacao> finalizarMinhaParticipacao() async {
    if (_finalizacaoEmAndamento) {
      return const ResultadoFinalizacao(false, 'Finalização já em andamento.');
    }
    final s = _sessao;
    final uid = _auth.currentUser?.uid;
    if (s == null || !s.isCompleta || uid == null || !s.pertenceA(uid)) {
      return const ResultadoFinalizacao(false, 'Não há Contagem Completa ativa.');
    }
    if (s.statusIndividual != StatusParticipante.emAndamento) {
      return ResultadoFinalizacao(
          false, s.motivoBloqueio ?? 'Participação não está em andamento.');
    }

    final (inventarioId, contagemId) = s.idsGravacao;
    _finalizacaoEmAndamento = true;
    _emitirSessao(); // a tela desabilita os controles de mutação

    try {
      // 1. Espera mutações que passaram na checagem antes da trava
      final limite = DateTime.now().add(const Duration(seconds: 15));
      while (_mutacoesEmCurso > 0) {
        if (DateTime.now().isAfter(limite)) {
          return const ResultadoFinalizacao(false,
              'Há uma operação de lançamento em andamento. Tente novamente.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      // 2. Erros voltam para a fila e 3. sincroniza (com limite de espera:
      //    offline o Firestore só completa ao reconectar)
      final repo = LancamentosRepository(uid: uid);
      await repo.reenfileirarErros(
          inventarioId: inventarioId, contagemId: contagemId);
      try {
        await SyncService.runOnce(uid).timeout(const Duration(seconds: 25));
      } on TimeoutException {
        debugPrint('⚠️ Sincronização antes de finalizar excedeu o tempo');
      }

      // 4. Zero não sincronizados (pending + error + tombstones)
      final naoSincronizados = await repo.contarNaoSincronizados(
          inventarioId: inventarioId, contagemId: contagemId);
      _inventarioService.informarPendentesLocais(inventarioId, naoSincronizados);
      if (naoSincronizados > 0) {
        return ResultadoFinalizacao(false,
            '$naoSincronizados lançamento(s) ainda não chegaram ao servidor. '
            'Verifique a conexão e tente novamente.');
      }

      // 5. Finaliza no Firestore
      final total = await _inventarioService.finalizarMinhaParticipacao(
          inventarioId, contagemId);

      // 6. Sessão vira finalizado (nunca volta a em_andamento)
      final atual = _sessao;
      if (atual != null && atual.inventarioId == inventarioId) {
        _sessao = atual.copyWith(statusIndividual: StatusParticipante.finalizado);
        await _salvarSessao();
      }
      return ResultadoFinalizacao(
          true, 'Sua contagem foi finalizada ($total lançamentos).');
    } on SemLancamentosSincronizadosException catch (e) {
      return ResultadoFinalizacao(false, e.toString());
    } on OperacaoNaoPermitidaException catch (e) {
      // B27: inventário ou rodada fechados no meio do caminho
      return ResultadoFinalizacao(false, 'Não foi possível finalizar: ${e.motivo}.');
    } catch (e) {
      debugPrint('❌ Erro ao finalizar participação: $e');
      return ResultadoFinalizacao(false,
          'Não foi possível finalizar agora (é preciso conexão). Detalhe: $e');
    } finally {
      _finalizacaoEmAndamento = false;
      _emitirSessao();
    }
  }

  /// Atualiza no monitor quantos lançamentos da sessão ainda não chegaram ao
  /// servidor (B17). Silencioso; sem efeito fora da sessão Completa.
  Future<void> informarPendentesLocais() async {
    final s = _sessao;
    final uid = _auth.currentUser?.uid;
    // B32: nunca combinar a sessão de um usuário com o login de outro
    if (s == null || !s.isCompleta || uid == null || !s.pertenceA(uid)) return;
    final (inventarioId, contagemId) = s.idsGravacao;
    final n = await LancamentosRepository(uid: uid).contarNaoSincronizados(
        inventarioId: inventarioId, contagemId: contagemId);
    _inventarioService.informarPendentesLocais(inventarioId, n);
  }

  // ==================== MODO DE OPERAÇÃO ====================

  /// Retorna modo atual
  ModoOperacao get modoAtual => _modoAtual ?? ModoOperacao.autonomo;

  /// Verifica se está em modo controlado
  bool get isControlado => _modoAtual == ModoOperacao.controlado;

  /// Verifica se está em modo autônomo
  bool get isAutonomo => _modoAtual == ModoOperacao.autonomo;

  /// Altera para modo autônomo.
  /// [explicito]: escolha consciente do operador (B42). Só ela libera a
  /// gravação sem vínculo quando o vínculo central está bloqueado (B41).
  ///
  /// [uidEsperado] (B50): transições AUTOMÁTICAS (monitor, L4) informam o
  /// usuário em nome de quem agem. Se o usuário logado mudou, nada é
  /// alterado (nem preferências, nem estado) e devolve false.
  ///
  /// B52: sem [uidEsperado] (escolha manual), o usuário logado AGORA vira o
  /// dono da operação; uma troca no meio a torna no-op.
  /// B53: [geracaoEsperada] (transições automáticas) só age se o vínculo
  /// ainda é o mesmo que o monitor/L4 observava. A própria transição cria
  /// uma geração nova, invalidando trabalhos anteriores.
  Future<bool> setModoAutonomo({
    bool explicito = false,
    String? uidEsperado,
    int? geracaoEsperada,
  }) async {
    _garantirUsuario3B(); // antes de capturar a geração (troca já aplicada)
    final donoOperacao = uidEsperado ?? _auth.currentUser?.uid;
    if (donoOperacao == null || donoOperacao.isEmpty) return false;
    if (!resultadoDoMesmoUsuario(donoOperacao, _auth.currentUser?.uid)) {
      return false;
    }
    if (geracaoEsperada != null && geracaoEsperada != _geracaoVinculo) {
      debugPrint('🔒 Transição automática obsoleta ignorada (B53)');
      return false;
    }
    final g = _novaGeracao();
    bool valido() => operacaoVigente(
          uidInicio: donoOperacao,
          uidAtual: _auth.currentUser?.uid,
          geracaoInicio: g,
          geracaoAtual: _geracaoVinculo,
        );
    await _cancelarMonitoramento();
    final prefs = await SharedPreferences.getInstance();
    if (!valido()) return false;

    // Estado em memória primeiro (síncrono, sem troca possível no meio)
    _garantirUsuario3B();
    if (explicito) _autonomoExplicito = true;
    _vinculoControladoBloqueado = null;
    _validandoL4 = false;
    _donoVinculo = null;
    _modoAtual = ModoOperacao.autonomo;
    _inventarioVinculadoId = null;

    // B51: ordem das preferências. Dono e inventário saem antes do modo;
    // uma interrupção no meio deixa "controlado" sem dono = bloqueado (B48),
    // nunca um vínculo atribuído a outro usuário.
    await prefs.remove(_keyInventarioUid); // B48
    if (!valido()) return false;
    await prefs.remove(_keyInventarioId);
    if (!valido()) return false;
    await prefs.setString(_keyModoOperacao, 'autonomo');

    _modoController.add(ModoOperacao.autonomo);
    _inventarioController.add(null);

    debugPrint('📱 Modo alterado para AUTÔNOMO');
    return true;
  }

  /// Altera para modo controlado vinculando a um inventário (fluxo 1)
  @Deprecated('Fluxo 1. No fluxo 2 use entrarContagemCompleta(rodada).')
  Future<ResultadoSolicitacao> setModoControlado(String inventarioId) async {
    // B49 (3B): a operação inteira pertence a quem a iniciou. Se o usuário
    // mudar no meio, nada é vinculado, gravado ou monitorado para o novo.
    final uidInicio = _auth.currentUser?.uid;
    if (uidInicio == null || uidInicio.isEmpty) {
      return ResultadoSolicitacao(
        sucesso: false,
        mensagem: 'Usuário não autenticado',
        status: StatusParticipacao.naoSolicitado,
      );
    }
    final abortado = ResultadoSolicitacao(
      sucesso: false,
      mensagem: 'O usuário mudou durante a vinculação; nada foi vinculado.',
      status: StatusParticipacao.naoSolicitado,
    );
    // B53: até o commit, a vinculação só OBSERVA a geração vigente (uma
    // tentativa que falha não invalida o vínculo atual nem a L4). A geração
    // nova só é criada no commit, logo antes da primeira gravação.
    _garantirUsuario3B(); // antes de capturar a geração (troca já aplicada)
    var g = _geracaoVinculo;
    bool mesmoUsuario() => operacaoVigente(
          uidInicio: uidInicio,
          uidAtual: _auth.currentUser?.uid,
          geracaoInicio: g,
          geracaoAtual: _geracaoVinculo,
        );

    try {
      // Verifica se inventário existe e está ativo
      final invDoc = await _firestore.collection('inventarios').doc(inventarioId).get();
      if (!mesmoUsuario()) return abortado;
      if (!invDoc.exists) {
        return ResultadoSolicitacao(
          sucesso: false,
          mensagem: 'Inventário não encontrado',
          status: StatusParticipacao.naoSolicitado,
        );
      }

      // B40 (3B): o fluxo legado nunca se vincula a inventário do fluxo 2
      if (ehFluxo2(invDoc.data())) {
        return ResultadoSolicitacao(
          sucesso: false,
          mensagem: 'Este é um Inventário Completo do fluxo novo; '
              'o modo Controlado não pode ser usado nele.',
          status: StatusParticipacao.naoSolicitado,
        );
      }

      // T33b/L3 (3B): nova entrada no Controlado exige o servidor
      try {
        await CompatibilidadeService().verificarNoServidor(PlataformaCompat.mobile);
      } on CompatibilidadeException catch (e) {
        return ResultadoSolicitacao(
          sucesso: false,
          mensagem: e.mensagem,
          status: StatusParticipacao.naoSolicitado,
        );
      } on FirebaseException catch (e) {
        return ResultadoSolicitacao(
          sucesso: false,
          mensagem: e.code == 'unavailable'
              ? 'Servidor indisponível ou sem internet: não foi possível '
                  'conferir a compatibilidade deste aparelho.'
              : 'Erro ao conferir a compatibilidade (${e.code}): ${e.message}',
          status: StatusParticipacao.naoSolicitado,
        );
      }
      if (!mesmoUsuario()) return abortado; // B49: após a compatibilidade

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

      // Solicita participação (B49: só em nome de quem iniciou)
      if (!mesmoUsuario()) return abortado;
      final resultado =
          await _solicitarParticipacao(inventarioId, uidEsperado: uidInicio);
      if (!mesmoUsuario()) return abortado; // B49: após a participação

      if (resultado.sucesso || resultado.status == StatusParticipacao.aprovado) {
        // Salva preferências
        final prefs = await SharedPreferences.getInstance();
        if (!mesmoUsuario()) return abortado; // B49: antes de persistir
        // B51: sem desfazer depois de uma troca (desfazer tarde poderia
        // sobrescrever uma escolha nova de outro usuário). Ordem de escrita:
        //   1. modo = autonomo  (invalida qualquer vínculo anterior)
        //   2. dono             3. inventário
        //   4. modo = controlado (marcador final de "vínculo completo")
        // Interrompido em 1–3: o modo salvo é Autônomo e nada é restaurado
        // (nenhum vínculo misto, ex.: inventário de A com dono B).
        // B53: commit — a partir daqui esta vinculação é a geração vigente.
        g = _novaGeracao();
        await prefs.setString(_keyModoOperacao, 'autonomo');
        if (!mesmoUsuario()) return abortado;
        // B48/B49: o dono é o UID que INICIOU e passou pela L3 inteira
        await prefs.setString(_keyInventarioUid, uidInicio);
        if (!mesmoUsuario()) return abortado;
        await prefs.setString(_keyInventarioId, inventarioId);
        if (!mesmoUsuario()) return abortado;
        await prefs.setString(_keyModoOperacao, 'controlado');
        if (!mesmoUsuario()) return abortado;
        _donoVinculo = uidInicio;

        _modoAtual = ModoOperacao.controlado;
        _inventarioVinculadoId = inventarioId;
        _garantirUsuario3B();
        _autonomoExplicito = false;
        _vinculoControladoBloqueado = null;
        _validandoL4 = false;

        // Inicia monitoramento (B49: só para o UID que iniciou)
        if (!mesmoUsuario()) return abortado;
        await _iniciarMonitoramento(inventarioId,
            uidEsperado: uidInicio, geracao: g);
        if (!mesmoUsuario()) return abortado; // B50/B53: depois do monitor

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
  /// B40/B43 (3B): só inventários LEGADOS. Busca até 10 candidatos por
  /// status e escolhe em memória o mais recente que não é do fluxo 2
  /// (`fluxo_versao` ausente ou 1 = legado).
  Future<Inventario?> buscarInventarioAtivo() async {
    try {
      // Busca primeiro por "em andamento"
      var query = await _firestore
          .collection('inventarios')
          .where('status', isEqualTo: 'emAndamento')
          .orderBy('data_inicio', descending: true)
          .limit(10)
          .get();

      var legado = escolherLegadoAtivo<Inventario>(
        query.docs.map(Inventario.fromFirestore).toList(),
        (i) => i.fluxoVersao,
      );
      if (legado != null) return legado;

      // Se não encontrou, busca "aguardando"
      query = await _firestore
          .collection('inventarios')
          .where('status', isEqualTo: 'aguardando')
          .orderBy('data_inicio', descending: true)
          .limit(10)
          .get();

      legado = escolherLegadoAtivo<Inventario>(
        query.docs.map(Inventario.fromFirestore).toList(),
        (i) => i.fluxoVersao,
      );
      return legado;
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
  Future<ResultadoSolicitacao> _solicitarParticipacao(
    String inventarioId, {
    String? uidEsperado,
  }) async {
    final user = _auth.currentUser;
    // B49: recusa se o usuário atual não for o que iniciou a operação
    if (uidEsperado != null && user?.uid != uidEsperado) {
      return ResultadoSolicitacao(
        sucesso: false,
        mensagem: 'O usuário mudou durante a vinculação; nada foi solicitado.',
        status: StatusParticipacao.naoSolicitado,
      );
    }
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

      // B49: o usuário não pode ter mudado entre as leituras e a escrita
      if (_auth.currentUser?.uid != user.uid) {
        return ResultadoSolicitacao(
          sucesso: false,
          mensagem: 'O usuário mudou durante a vinculação; nada foi solicitado.',
          status: StatusParticipacao.naoSolicitado,
        );
      }

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
  Future<StatusParticipacao> verificarStatusParticipacao(
    String inventarioId, {
    String? uidEsperado,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return StatusParticipacao.naoSolicitado;
    // B50: nunca consultar dados de outro usuário em nome do esperado
    if (uidEsperado != null && user.uid != uidEsperado) {
      return StatusParticipacao.naoSolicitado;
    }

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

  Future<void> _iniciarMonitoramento(
    String inventarioId, {
    String? uidEsperado,
    required int geracao,
  }) async {
    await _cancelarMonitoramento();

    final user = _auth.currentUser;
    if (user == null) return;
    // B49: o monitor pertence a um único usuário. Iniciado por A, não vira
    // monitor de B: se o usuário mudar, ele se desliga sozinho.
    // B53: e a um único VÍNCULO (geração + inventário): se A trocar de X
    // para Y, o monitor de X não age nem emite mais.
    final dono = uidEsperado ?? user.uid;
    bool aindaDoDono() =>
        operacaoVigente(
          uidInicio: dono,
          uidAtual: _auth.currentUser?.uid,
          geracaoInicio: geracao,
          geracaoAtual: _geracaoVinculo,
        ) &&
        _modoAtual == ModoOperacao.controlado &&
        _inventarioVinculadoId == inventarioId;
    if (!aindaDoDono()) return;

    // Monitora inventário
    // B50: cada assinatura cancela só a SI MESMA (nunca a de outro usuário)
    // e todo trabalho assíncrono leva o dono até o fim.
    StreamSubscription? minhaInv;
    StreamSubscription? minhaPart;
    Future<void> desligarMinhas() async {
      await minhaInv?.cancel();
      await minhaPart?.cancel();
      if (identical(_inventarioSubscription, minhaInv)) _inventarioSubscription = null;
      if (identical(_participanteSubscription, minhaPart)) _participanteSubscription = null;
    }

    minhaInv = _inventarioSubscription = _firestore
        .collection('inventarios')
        .doc(inventarioId)
        .snapshots()
        .listen((snapshot) async {
          if (!aindaDoDono()) {
            debugPrint('🔒 Monitor legado de outro usuário desligado (B49/B50)');
            await desligarMinhas();
            return;
          }
          if (!snapshot.exists) {
            debugPrint('⚠️ Inventário foi removido');
            await setModoAutonomo(uidEsperado: dono, geracaoEsperada: geracao);
            return;
          }

          final inventario = Inventario.fromFirestore(snapshot);
          
          // Se finalizou ou cancelou, volta para autônomo
          if (inventario.status == StatusInventario.finalizado ||
              inventario.status == StatusInventario.cancelado) {
            debugPrint('⚠️ Inventário ${inventario.status.name}, voltando para autônomo');
            await setModoAutonomo(uidEsperado: dono, geracaoEsperada: geracao);
            return;
          }

          // Busca status de participação
          final statusPart =
              await verificarStatusParticipacao(inventarioId, uidEsperado: dono);
          if (!aindaDoDono()) return; // B50
          
          // Conta lançamentos do usuário
          final meusLancs = await _contarMeusLancamentos(
              inventarioId, inventario.contagemAtiva,
              uidEsperado: dono);
          if (!aindaDoDono()) return; // B50

          final info = InfoModoControlado(
            inventario: inventario,
            contagemAtiva: inventario.contagemAtiva,
            statusParticipacao: statusPart,
            meusLancamentos: meusLancs,
            podeContar: statusPart == StatusParticipacao.aprovado &&
                inventario.status == StatusInventario.emAndamento,
          );

          if (!aindaDoDono()) return; // B50: nunca emitir para outro usuário
          _inventarioController.add(info);
        });

    // Monitora participante para detectar aprovação/rejeição
    minhaPart = _participanteSubscription = _firestore
        .collection('inventarios')
        .doc(inventarioId)
        .collection('participantes')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
          if (!aindaDoDono()) return; // B49
          if (snapshot.exists) {
            final status = snapshot.data()?['status'] as String?;
            debugPrint('📱 Status de participação atualizado: $status');
          }
        });

    // Atualiza último acesso
    _atualizarUltimoAcesso(inventarioId, uidEsperado: dono);
  }

  Future<void> _cancelarMonitoramento() async {
    // B50: desliga exatamente as assinaturas vigentes AGORA; uma assinatura
    // nova criada durante o await não é afetada nem fica órfã.
    final inv = _inventarioSubscription;
    final part = _participanteSubscription;
    _inventarioSubscription = null;
    _participanteSubscription = null;
    await inv?.cancel();
    await part?.cancel();
  }

  Future<int> _contarMeusLancamentos(
    String inventarioId,
    String contagemAtiva, {
    String? uidEsperado,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return 0;
    if (uidEsperado != null && user.uid != uidEsperado) return 0; // B50

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

  Future<void> _atualizarUltimoAcesso(
    String inventarioId, {
    String? uidEsperado,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (uidEsperado != null && user.uid != uidEsperado) return; // B50

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

  // ==================== 3B: VÍNCULO CENTRAL LEGADO ====================

  /// L1: a HomePage legada informa o que achou e a compatibilidade avaliada.
  void registrarVinculoCentralLegado({
    required bool detectado,
    ResultadoCompat? compat,
    String? motivo,
    String? codigo,
    String? paraUid,
  }) {
    // B47: resultado de outro usuário (troca durante o await) é descartado
    if (paraUid != null &&
        !resultadoDoMesmoUsuario(paraUid, _auth.currentUser?.uid)) {
      debugPrint('🔒 Resultado da L1 descartado: usuário mudou');
      return;
    }
    _garantirUsuario3B();
    _inventarioLegadoDetectado = detectado;
    _compatCentralLegado = detectado ? compat : null;
    _motivoBloqueioCentral = detectado ? motivo : null;
    _codigoInventarioBloqueado = detectado ? codigo : null;
  }

  /// Autorização de gravação NOVA no fluxo legado (B39, B41, B42).
  /// [inventarioId]/[contagemId]: os IDs que a tela usaria hoje.
  AutorizacaoMutacao autorizarGravacaoLegada(String inventarioId, String contagemId) {
    _garantirUsuario3B();
    final decisao = decidirGravacaoLegada(
      inventarioAtivoDetectado: _inventarioLegadoDetectado,
      compat: _compatCentralLegado,
      autonomoExplicito: _autonomoExplicito,
      vinculoControladoBloqueado: _vinculoControladoBloqueado != null, // B45
    );
    // Sem inventário detectado: exatamente como hoje. Autônomo explícito com
    // inventário bloqueado: IDs vazios.
    final motivo = _vinculoControladoBloqueado ?? _motivoBloqueioCentral ?? '';
    final conferindo = bloqueioLegadoConferindo;
    return switch (decisao) {
      DecisaoGravacaoLegada.vincular =>
        AutorizacaoMutacao.legado(inventarioId, contagemId),
      DecisaoGravacaoLegada.semVinculo => _inventarioLegadoDetectado
          ? AutorizacaoMutacao.legado('', '')
          : AutorizacaoMutacao.legado(inventarioId, contagemId),
      DecisaoGravacaoLegada.negar => AutorizacaoMutacao.negada(conferindo
          ? 'Aguarde: conferindo a compatibilidade deste aparelho com o '
              'inventário em andamento.'
          : 'Modo Controlado bloqueado: atualização necessária. $motivo'.trim()),
    };
  }

  /// Editar/excluir um lançamento legado existente (B41).
  bool podeAlterarLegado(String? lancInventarioId) {
    _garantirUsuario3B();
    // Enquanto a compatibilidade do inventário detectado é conferida,
    // registro vinculado também espera (falha fechada).
    if (_inventarioLegadoDetectado &&
        _compatCentralLegado == null &&
        inventarioIdEhCentral(lancInventarioId)) {
      return false;
    }
    return podeAlterarLancamentoLegado(
      lancInventarioId: lancInventarioId,
      compat: _compatCentralLegado,
      vinculoControladoBloqueado: _vinculoControladoBloqueado != null, // B45
    );
  }

  /// L4: nova tentativa de validar o vínculo Controlado salvo (botão
  /// "Verificar de novo" da faixa de bloqueio).
  Future<void> revalidarVinculoControlado() async {
    _garantirUsuario3B();
    final id = _inventarioVinculadoId;
    if (_modoAtual != ModoOperacao.controlado || id == null) return;
    // B48: vínculo de outro usuário ou sem dono não é revalidado aqui; exige
    // escolher o inventário de novo (L3), que grava o novo dono.
    final dono = avaliarDonoVinculo(_donoVinculo, _auth.currentUser?.uid);
    if (dono != DonoVinculo.mesmoUsuario) {
      _vinculoControladoBloqueado = motivoDonoVinculo(dono);
      _validandoL4 = false;
      _modoController.add(ModoOperacao.controlado);
      return;
    }
    _vinculoControladoBloqueado = 'Validando o vínculo com o inventário...';
    _validandoL4 = true;
    _modoController.add(ModoOperacao.controlado);
    await _validarRestauracaoControlado(id, _novaGeracao());
  }

  /// L4: valida o vínculo Controlado salvo antes de restaurá-lo.
  Future<void> _validarRestauracaoControlado(String inventarioId, int geracao) async {
    final uidInicio = _auth.currentUser?.uid;
    // B53: esta validação só vale enquanto for a transição vigente
    bool vigente() =>
        operacaoVigente(
          uidInicio: uidInicio,
          uidAtual: _auth.currentUser?.uid,
          geracaoInicio: geracao,
          geracaoAtual: _geracaoVinculo,
        ) &&
        _modoAtual == ModoOperacao.controlado &&
        _inventarioVinculadoId == inventarioId;
    String? motivo;
    try {
      final doc = await _firestore
          .collection('inventarios')
          .doc(inventarioId)
          .get()
          .timeout(const Duration(seconds: 8));
      if (!doc.exists && !doc.metadata.isFromCache) {
        // Inexistência CONFIRMADA pelo servidor: não há inventário central a
        // proteger. Mesmo comportamento de antes do 3B (o monitor voltava
        // para Autônomo, não explícito). Ausência só no cache continua
        // bloqueando abaixo.
        if (vigente()) {
          debugPrint('⚠️ Inventário vinculado não existe mais; voltando para Autônomo');
          await setModoAutonomo(
              uidEsperado: uidInicio, geracaoEsperada: geracao); // B50/B53
        }
        return;
      } else if (!doc.exists) {
        motivo = 'O inventário vinculado não foi encontrado (sem confirmação '
            'do servidor).';
      } else if (ehFluxo2(doc.data())) {
        motivo = 'O vínculo salvo aponta para um Inventário Completo do fluxo '
            'novo; o modo Controlado não pode ser restaurado.';
      }
    } catch (e) {
      motivo = 'Não foi possível confirmar o inventário vinculado '
          '(sem conexão ou sem permissão).';
    }

    if (motivo == null) {
      final d = await CompatibilidadeService()
          .avaliarComCache(PlataformaCompat.mobile);
      if (!d.liberado) motivo = d.mensagem;
    }

    // O operador pode ter mudado de modo, de vínculo ou de usuário durante a
    // validação (B53: inclusive uma nova L3 do mesmo usuário).
    if (!vigente()) return;

    _garantirUsuario3B();
    _validandoL4 = false;
    if (motivo != null) {
      _vinculoControladoBloqueado = motivo;
      debugPrint('🔒 Controlado NÃO restaurado: $motivo');
      _modoController.add(ModoOperacao.controlado);
      return;
    }

    _vinculoControladoBloqueado = null;
    await _iniciarMonitoramento(inventarioId,
        uidEsperado: uidInicio, geracao: geracao);
    if (!vigente()) return; // B50/B53: depois do monitor
    _modoController.add(ModoOperacao.controlado);
  }

  // ==================== HELPERS PARA LANÇAMENTOS ====================

  /// Retorna inventarioId e contagemId para usar nos lançamentos
  /// Se autônomo, retorna valores padrão
  @Deprecated('Fluxo 1. No fluxo 2 os IDs vêm de iniciarMutacao() (T18).')
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

  /// Verifica se pode fazer lançamentos (fluxo 1)
  @Deprecated('Fluxo 1. No fluxo 2 use podeMutarAgora / iniciarMutacao().')
  Future<bool> podeRegistrarLancamento() async {
    if (isAutonomo) return true;
    
    if (_inventarioVinculadoId == null) return false;

    final status = await verificarStatusParticipacao(_inventarioVinculadoId!);
    return status == StatusParticipacao.aprovado;
  }
}
