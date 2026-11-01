// lib/services/acompanhamento_sync_service.dart
//
// Pacote 1 (fila offline), lado do Desktop/analista:
// - o que cada coletor INFORMOU sobre as próprias pendências de envio
//   (`sync_status/{uid}`). Nada aqui enxerga o Hive dos aparelhos: um
//   aparelho offline só aparece com o último informe que conseguiu enviar;
// - os lançamentos recusados em definitivo que os aparelhos mandaram para a
//   Recuperação (`lancamentos_recuperacao`). Eles NÃO entram no resultado do
//   inventário; servem para o analista decidir.

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:lego/services/sincronizacao/pendencias_sync.dart';

class StatusSyncInformado {
  final String uid;
  final String? nome;
  final ContagemPendencias total;
  final Map<String, ContagemPendencias> escopos;
  final List<Map<String, dynamic>> itens;
  final int itensOmitidos;
  final DateTime? informadoEm; // hora do servidor ao RECEBER o informe
  final DateTime? aparelhoEm; // hora do aparelho (só informativa)
  /// rev3: hora do SERVIDOR obtida pelo aparelho imediatamente antes de
  /// produzir o conteúdo. É a idade real dos dados.
  final DateTime? baseServidor;
  final DateTime? ultimoSucesso;
  final String? ultimaFalhaCodigo;
  final DateTime? ultimaFalhaEm;
  /// rev2: formato do informe (2 = com escopos verificados).
  final int formato;
  /// rev2: escopos que o aparelho verificou (zero confirmado quando a
  /// contagem do escopo é 0).
  final Set<String> escoposVerificados;

  const StatusSyncInformado({
    required this.uid,
    this.nome,
    this.total = const ContagemPendencias(),
    this.escopos = const {},
    this.itens = const [],
    this.itensOmitidos = 0,
    this.informadoEm,
    this.aparelhoEm,
    this.baseServidor,
    this.ultimoSucesso,
    this.ultimaFalhaCodigo,
    this.ultimaFalhaEm,
    this.formato = 1,
    this.escoposVerificados = const {},
  });

  /// O aparelho confirmou explicitamente a situação deste escopo?
  bool confirmouEscopo(String escopo) =>
      formato >= 2 && escoposVerificados.contains(escopo);

  /// Pendências sem escopo identificado (exclusões antigas).
  int get naoClassificadas => doEscopo(kEscopoNaoClassificado).total;

  ContagemPendencias doEscopo(String escopo) =>
      escopos[escopo] ?? const ContagemPendencias();

  static DateTime? _d(Object? v) => v is Timestamp ? v.toDate() : null;

  static StatusSyncInformado deMapa(String uid, Map<String, dynamic> m) {
    final esc = <String, ContagemPendencias>{};
    final e = m['escopos'];
    if (e is Map) {
      for (final k in e.keys) {
        final v = e[k];
        if (v is Map) esc['$k'] = ContagemPendencias.deMapa(v);
      }
    }
    final falha = m['ultima_falha'];
    return StatusSyncInformado(
      uid: uid,
      nome: m['nome'] as String?,
      total: ContagemPendencias.deMapa(m),
      escopos: esc,
      itens: [
        for (final i in (m['itens'] as List? ?? const []))
          if (i is Map) Map<String, dynamic>.from(i),
      ],
      itensOmitidos: (m['itens_omitidos'] as num?)?.toInt() ?? 0,
      informadoEm: _d(m['atualizado_em']),
      aparelhoEm: _d(m['aparelho_em']),
      baseServidor: _d(m['base_servidor']),
      ultimoSucesso: _d(m['ultimo_sucesso']),
      ultimaFalhaCodigo: falha is Map ? falha['codigo'] as String? : null,
      ultimaFalhaEm: falha is Map ? _d(falha['em']) : null,
      formato: (m['formato'] as num?)?.toInt() ?? 1,
      escoposVerificados: {
        for (final e in (m['escopos_verificados'] as List? ?? const []))
          '$e',
      },
    );
  }
}

class LancamentoRecuperacao {
  final String docId;
  final Map<String, dynamic> dados;
  const LancamentoRecuperacao(this.docId, this.dados);

  String get uid => '${dados['uid'] ?? ''}';
  String get operador =>
      '${dados['nomeCompleto'] ?? dados['nickname'] ?? dados['uid'] ?? '?'}';
  String? get contagemId => dados['contagemId'] as String?;
  DateTime? get criadoEm => (dados['createdAt'] as Timestamp?)?.toDate();
  DateTime? get recebidoEm => (dados['recebido_em'] as Timestamp?)?.toDate();
  String get motivo =>
      '${dados['motivo_codigo'] ?? ''} ${dados['motivo_mensagem'] ?? ''}'.trim();
}

class AcompanhamentoSyncService {
  final FirebaseFirestore _fs;
  AcompanhamentoSyncService([FirebaseFirestore? fs])
      : _fs = fs ?? FirebaseFirestore.instance;

  /// Último informe de cada coletor (uma escuta para a coleção inteira; um
  /// documento por usuário).
  Stream<Map<String, StatusSyncInformado>> streamStatus() => _fs
      .collection('sync_status')
      .snapshots()
      .map((s) => {
            for (final d in s.docs)
              d.id: StatusSyncInformado.deMapa(d.id, d.data()),
          });

  /// Recusados em definitivo de um inventário (fora do resultado).
  Stream<List<LancamentoRecuperacao>> streamRecuperacao(String inventarioId) =>
      _fs
          .collection('lancamentos_recuperacao')
          .where('inventarioId', isEqualTo: inventarioId)
          .snapshots()
          .map((s) {
        final l = [
          for (final d in s.docs) LancamentoRecuperacao(d.id, d.data()),
        ];
        l.sort((a, b) => (a.criadoEm ?? DateTime(2000))
            .compareTo(b.criadoEm ?? DateTime(2000)));
        return l;
      });
}

/// Chave de escopo usada pelo coletor no informe.
String escopoInventario(String inventarioId, String rodada) =>
    '${inventarioId}__$rodada';

// ---------------------------------------------------------------------------
// rev1: avaliação de pendências antes de encerrar C1/C2
// ---------------------------------------------------------------------------

enum MotivoPendenciaEncerramento {
  /// Pendência CONHECIDA: o aparelho (sync_status) ou o participante
  /// (pendentes_locais) informou lançamentos não sincronizados.
  pendenciaInformada,
  /// Em andamento e o aparelho nunca enviou informe: não dá para afirmar que
  /// não há pendência.
  semInforme,
  /// Em andamento e o último informe é mais antigo que o limite (idade
  /// medida pela base no relógio do servidor), ou sem base confirmada.
  informeAntigo,
  /// rev3: o informe chegou ao servidor muito depois de produzido (ficou
  /// enfileirado offline): o recebimento recente não prova verificação
  /// recente.
  informeAtrasado,
  /// rev2: informe recente, mas SEM confirmação explícita deste inventário
  /// e rodada (escopo não verificado, ou informe em formato antigo).
  escopoNaoConfirmado,
  /// rev2: pendência sem escopo identificado (exclusão antiga). Não se
  /// presume que seja desta rodada; decisão do analista.
  naoClassificada,
}

class PendenciaEncerramento {
  final String uid;
  final String nome;
  final MotivoPendenciaEncerramento motivo;
  /// Quantidade conhecida (0 quando o motivo é falta/idade do informe).
  final int quantidade;
  final ContagemPendencias? doAparelho;
  final int pendentesParticipante;
  final DateTime? informadoEm;
  final Duration? idade;

  const PendenciaEncerramento({
    required this.uid,
    required this.nome,
    required this.motivo,
    this.quantidade = 0,
    this.doAparelho,
    this.pendentesParticipante = 0,
    this.informadoEm,
    this.idade,
  });

  static String _idadeTxt(Duration d) => d.inMinutes < 1
      ? 'menos de 1 min'
      : d.inMinutes < 120
          ? '${d.inMinutes} min'
          : '${d.inHours} h';

  /// Linha para o diálogo e a auditoria.
  String get texto {
    final quando = idade == null ? '' : ' (informe de ${_idadeTxt(idade!)} atrás)';
    return switch (motivo) {
      MotivoPendenciaEncerramento.pendenciaInformada =>
        '$nome: $quantidade lançamento(s) não sincronizado(s)$quando',
      MotivoPendenciaEncerramento.semInforme =>
        '$nome: aparelho sem informe de envio — pendências desconhecidas',
      MotivoPendenciaEncerramento.informeAntigo =>
        '$nome: último informe antigo$quando — pendências desconhecidas',
      MotivoPendenciaEncerramento.informeAtrasado =>
        '$nome: informe produzido$quando e entregue com atraso — '
            'pendências desconhecidas',
      MotivoPendenciaEncerramento.escopoNaoConfirmado =>
        '$nome: o aparelho não confirmou esta rodada$quando — pendências '
            'desconhecidas',
      MotivoPendenciaEncerramento.naoClassificada =>
        '$nome: $quantidade pendência(s) NÃO CLASSIFICADA(S) (exclusão '
            'antiga sem inventário/rodada identificados)$quando — decisão '
            'do analista',
    };
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'nome': nome,
        'motivo': motivo.name,
        'quantidade': quantidade,
        'pendentes_participante': pendentesParticipante,
        if (doAparelho != null) 'aparelho': doAparelho!.toMap(),
        'informado_em': informadoEm?.toIso8601String(),
        'idade_min': idade?.inMinutes,
      };
}

/// Quem impede um encerramento "limpo" da [rodada].
/// [participantes]: (uid, nome, finalizou, pendentesLocais,
/// pendentesInformadosEm) dos participantes da rodada.
/// Regras:
/// - pendência conhecida em QUALQUER fonte bloqueia (nunca é ignorada): vale
///   a maior quantidade entre o informe do aparelho e o do participante;
/// - quem finalizou a própria participação já provou zero pendência (a
///   finalização exige) e não lança mais na rodada;
/// - quem está em andamento sem informe, ou com informe mais velho que
///   [limite], é "desconhecido" — não conta como "sem pendência".
List<PendenciaEncerramento> avaliarPendenciasEncerramento({
  required String inventarioId,
  required String rodada,
  required List<
          ({
            String uid,
            String nome,
            bool finalizou,
            int pendentesLocais,
            DateTime? pendentesInformadosEm,
          })>
      participantes,
  required Map<String, StatusSyncInformado> status,
  /// Hora do SERVIDOR agora (o Desktop obtém por pulso). Nunca o relógio do
  /// aparelho.
  required DateTime agora,
  Duration limite = const Duration(minutes: 15),
  /// Diferença máxima aceitável entre a base e o recebimento.
  Duration limiteAtraso = const Duration(minutes: 2),
}) {
  final escopo = escopoInventario(inventarioId, rodada);
  final out = <PendenciaEncerramento>[];
  for (final p in participantes) {
    final st = status[p.uid];
    // rev3: idade dos DADOS = agora (servidor) − base (servidor). O
    // recebimento (`atualizado_em`) e o relógio do aparelho não contam.
    final informado = st?.baseServidor;
    final idade = informado == null ? null : agora.difference(informado);
    final recebido = st?.informadoEm;
    final atrasado = informado != null &&
        recebido != null &&
        recebido.difference(informado) > limiteAtraso;
    final doAparelho = st?.doEscopo(escopo);
    final nAparelho = doAparelho?.total ?? 0;

    // Nunca ignora pendência conhecida: vale a MAIOR das duas fontes.
    final conhecida =
        nAparelho > p.pendentesLocais ? nAparelho : p.pendentesLocais;

    if (conhecida > 0) {
      out.add(PendenciaEncerramento(
        uid: p.uid,
        nome: p.nome,
        motivo: MotivoPendenciaEncerramento.pendenciaInformada,
        quantidade: conhecida,
        doAparelho: doAparelho,
        pendentesParticipante: p.pendentesLocais,
        informadoEm: informado,
        idade: idade,
      ));
    }
    // rev2: pendência sem escopo identificado nunca escapa — nem por ter
    // finalizado (a finalização só conferiu o escopo da rodada).
    final semEscopo = st?.naoClassificadas ?? 0;
    if (semEscopo > 0) {
      out.add(PendenciaEncerramento(
        uid: p.uid,
        nome: p.nome,
        motivo: MotivoPendenciaEncerramento.naoClassificada,
        quantidade: semEscopo,
        informadoEm: informado,
        idade: idade,
      ));
    }
    if (conhecida > 0 || p.finalizou) continue;
    if (st == null) {
      out.add(PendenciaEncerramento(
        uid: p.uid,
        nome: p.nome,
        motivo: MotivoPendenciaEncerramento.semInforme,
        pendentesParticipante: p.pendentesLocais,
      ));
    } else if (informado == null || idade! > limite) {
      // Sem base confirmada (formato antigo) ou dados velhos.
      out.add(PendenciaEncerramento(
        uid: p.uid,
        nome: p.nome,
        motivo: MotivoPendenciaEncerramento.informeAntigo,
        doAparelho: doAparelho,
        pendentesParticipante: p.pendentesLocais,
        informadoEm: informado,
        idade: idade,
      ));
    } else if (atrasado) {
      out.add(PendenciaEncerramento(
        uid: p.uid,
        nome: p.nome,
        motivo: MotivoPendenciaEncerramento.informeAtrasado,
        doAparelho: doAparelho,
        pendentesParticipante: p.pendentesLocais,
        informadoEm: informado,
        idade: idade,
      ));
    } else if (!st.confirmouEscopo(escopo)) {
      // Informe recente, mas sem confirmação explícita desta rodada: zero
      // não confirmado ≠ zero.
      out.add(PendenciaEncerramento(
        uid: p.uid,
        nome: p.nome,
        motivo: MotivoPendenciaEncerramento.escopoNaoConfirmado,
        pendentesParticipante: p.pendentesLocais,
        informadoEm: informado,
        idade: idade,
      ));
    }
  }
  return out;
}
