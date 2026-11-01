// lib/data/local/registro_sync.dart
//
// Pacote 1 (fila offline): estado de sincronização de cada lançamento e o
// histórico das tentativas, no Hive do aparelho (funciona offline).
//
// Fica FORA do LancLocal de propósito: o registro do lançamento (adapter
// Hive typeId 42) não muda de formato. Duas caixas por usuário, de mapas
// simples (sem adapter):
//   sync_meta_<uid>  idLocal → EstadoSync (situação atual)
//   sync_log_<uid>   histórico das tentativas (somente inclusão, limitado)

import 'package:hive/hive.dart';

import 'package:lego/services/sincronizacao/falha_sync.dart';

/// Situação de sincronização de UM lançamento.
class EstadoSync {
  final int tentativas;
  final DateTime? ultimaTentativa;
  final DateTime? proximaTentativa;
  final TipoFalhaSync? tipo;
  final String? codigo;
  final String? mensagem;
  /// Transitório que parou de tentar sozinho (só reenvio manual).
  final bool esgotado;
  final DateTime? ultimoSucesso;
  /// Recusa definitiva: cópia enviada à Recuperação (fora do resultado).
  final DateTime? recuperacaoEnviadaEm;
  final String? recuperacaoErro;
  /// rev2: escopo identificado (`simples` ou `<inventarioId>__<rodada>`) de
  /// uma exclusão antiga — só ela precisa disso (o lançamento do Hive já
  /// carrega o próprio escopo). Null = não classificado.
  final String? escopo;

  const EstadoSync({
    this.tentativas = 0,
    this.ultimaTentativa,
    this.proximaTentativa,
    this.tipo,
    this.codigo,
    this.mensagem,
    this.esgotado = false,
    this.ultimoSucesso,
    this.recuperacaoEnviadaEm,
    this.recuperacaoErro,
    this.escopo,
  });

  bool get definitivo => tipo == TipoFalhaSync.definitivo;

  EstadoSync comFalha(FalhaSync f, DateTime agora) {
    final n = tentativas + 1;
    final esgota = f.tipo == TipoFalhaSync.transitorio &&
        n >= maxTentativasTransitorio;
    return EstadoSync(
      tentativas: n,
      ultimaTentativa: agora,
      proximaTentativa: f.tipo == TipoFalhaSync.definitivo || esgota
          ? null
          : agora.add(esperaAntesDeReenviar(f.tipo, n)),
      tipo: f.tipo,
      codigo: f.codigo,
      mensagem: f.mensagem,
      esgotado: esgota,
      ultimoSucesso: ultimoSucesso,
      recuperacaoEnviadaEm: recuperacaoEnviadaEm,
      recuperacaoErro: recuperacaoErro,
      escopo: escopo,
    );
  }

  /// Envio aceito: some o erro; guarda quantas tentativas foram precisas.
  EstadoSync comSucesso(DateTime agora) => EstadoSync(
        tentativas: tentativas + 1,
        ultimaTentativa: agora,
        ultimoSucesso: agora,
        recuperacaoEnviadaEm: recuperacaoEnviadaEm,
        escopo: escopo,
      );

  /// Reenvio manual: libera a próxima tentativa já, sem apagar o histórico.
  EstadoSync liberadoParaReenvio() => EstadoSync(
        tentativas: tentativas,
        ultimaTentativa: ultimaTentativa,
        tipo: tipo,
        codigo: codigo,
        mensagem: mensagem,
        ultimoSucesso: ultimoSucesso,
        recuperacaoEnviadaEm: recuperacaoEnviadaEm,
        recuperacaoErro: recuperacaoErro,
        escopo: escopo,
      );

  EstadoSync comRecuperacao({DateTime? enviadaEm, String? erro}) => EstadoSync(
        tentativas: tentativas,
        ultimaTentativa: ultimaTentativa,
        proximaTentativa: proximaTentativa,
        tipo: tipo,
        codigo: codigo,
        mensagem: mensagem,
        esgotado: esgotado,
        ultimoSucesso: ultimoSucesso,
        recuperacaoEnviadaEm: enviadaEm ?? recuperacaoEnviadaEm,
        recuperacaoErro: enviadaEm != null ? null : erro,
        escopo: escopo,
      );

  /// rev2: guarda o escopo identificado (exclusão antiga).
  EstadoSync comEscopo(String? e) => EstadoSync(
        tentativas: tentativas,
        ultimaTentativa: ultimaTentativa,
        proximaTentativa: proximaTentativa,
        tipo: tipo,
        codigo: codigo,
        mensagem: mensagem,
        esgotado: esgotado,
        ultimoSucesso: ultimoSucesso,
        recuperacaoEnviadaEm: recuperacaoEnviadaEm,
        recuperacaoErro: recuperacaoErro,
        escopo: e ?? escopo,
      );

  Map<String, dynamic> toMap() => {
        'tentativas': tentativas,
        'ultimaTentativa': ultimaTentativa,
        'proximaTentativa': proximaTentativa,
        'tipo': tipo?.name,
        'codigo': codigo,
        'mensagem': mensagem,
        'esgotado': esgotado,
        'ultimoSucesso': ultimoSucesso,
        'recuperacaoEnviadaEm': recuperacaoEnviadaEm,
        'recuperacaoErro': recuperacaoErro,
        'escopo': escopo,
      };

  static EstadoSync deMapa(Map m) {
    TipoFalhaSync? tipo;
    for (final t in TipoFalhaSync.values) {
      if (t.name == m['tipo']) tipo = t;
    }
    DateTime? d(Object? v) => v is DateTime ? v : null;
    return EstadoSync(
      tentativas: (m['tentativas'] as num?)?.toInt() ?? 0,
      ultimaTentativa: d(m['ultimaTentativa']),
      proximaTentativa: d(m['proximaTentativa']),
      tipo: tipo,
      codigo: m['codigo'] as String?,
      mensagem: m['mensagem'] as String?,
      esgotado: m['esgotado'] == true,
      ultimoSucesso: d(m['ultimoSucesso']),
      recuperacaoEnviadaEm: d(m['recuperacaoEnviadaEm']),
      recuperacaoErro: m['recuperacaoErro'] as String?,
      escopo: m['escopo'] as String?,
    );
  }
}

/// Uma tentativa registrada no histórico.
class EventoSync {
  final String idLocal;
  final DateTime em;
  /// envio | exclusao | recuperacao
  final String acao;
  /// ok | rede | transitorio | definitivo
  final String resultado;
  final bool manual;
  final String? codigo;
  final String? mensagem;

  const EventoSync({
    required this.idLocal,
    required this.em,
    required this.acao,
    required this.resultado,
    this.manual = false,
    this.codigo,
    this.mensagem,
  });

  Map<String, dynamic> toMap() => {
        'idLocal': idLocal,
        'em': em,
        'acao': acao,
        'resultado': resultado,
        'manual': manual,
        'codigo': codigo,
        'mensagem': mensagem,
      };

  static EventoSync deMapa(Map m) => EventoSync(
        idLocal: '${m['idLocal']}',
        em: m['em'] is DateTime ? m['em'] as DateTime : DateTime(2000),
        acao: '${m['acao']}',
        resultado: '${m['resultado']}',
        manual: m['manual'] == true,
        codigo: m['codigo'] as String?,
        mensagem: m['mensagem'] as String?,
      );
}

class RegistroSync {
  /// Histórico máximo por usuário (as mais antigas saem).
  static const int maxEventos = 3000;

  final String uid;
  RegistroSync(this.uid);

  String get _metaNome => 'sync_meta_$uid';
  String get _logNome => 'sync_log_$uid';

  Future<Box> _abrir(String nome) async =>
      Hive.isBoxOpen(nome) ? Hive.box(nome) : await Hive.openBox(nome);

  Future<Map<String, EstadoSync>> todos() async {
    final b = await _abrir(_metaNome);
    return {
      for (final k in b.keys)
        if (b.get(k) is Map) '$k': EstadoSync.deMapa(b.get(k) as Map),
    };
  }

  Future<EstadoSync?> de(String idLocal) async {
    final v = (await _abrir(_metaNome)).get(idLocal);
    return v is Map ? EstadoSync.deMapa(v) : null;
  }

  Future<void> gravar(String idLocal, EstadoSync e) async =>
      (await _abrir(_metaNome)).put(idLocal, e.toMap());

  Future<void> remover(String idLocal) async =>
      (await _abrir(_metaNome)).delete(idLocal);

  /// Escuta das mudanças de estado (tentativa, motivo, próxima hora,
  /// Recuperação), mesmo sem mudança no lançamento. Emite uma vez ao começar.
  Stream<void> mudancas() async* {
    final b = await _abrir(_metaNome);
    yield null;
    yield* b.watch().map((_) {});
  }

  Future<void> registrar(EventoSync e) async {
    final b = await _abrir(_logNome);
    await b.add(e.toMap());
    final excesso = b.length - maxEventos;
    if (excesso > 0) await b.deleteAll(b.keys.take(excesso).toList());
  }

  Future<List<EventoSync>> historico({String? idLocal}) async {
    final b = await _abrir(_logNome);
    final out = <EventoSync>[];
    for (final v in b.values) {
      if (v is! Map) continue;
      if (idLocal != null && v['idLocal'] != idLocal) continue;
      out.add(EventoSync.deMapa(v));
    }
    out.sort((a, b) => b.em.compareTo(a.em));
    return out;
  }
}
