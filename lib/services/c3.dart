// lib/services/c3.dart
//
// Entrega 3 (teste acelerado): regras PURAS da C3 distribuída/offline.
// - distribuição justa (máx − mín ≤ 1), aleatória dentro do balanceamento;
// - tarefa local do aparelho (pode ser concluída sem internet);
// - decisão de aceitar/recusar uma sincronização (versão da atribuição).

import 'dart:math';
import 'package:lego/services/comparativo.dart';

/// Estados da tarefa NO SERVIDOR (campo `c3_status` da linha do comparativo).
class StatusTarefaC3 {
  StatusTarefaC3._();
  static const String atribuida = 'atribuida';
  static const String sincronizada = 'sincronizada';
}

/// Distribui [chaves] entre [uids] de forma que
/// max(tarefas por usuário) − min(tarefas por usuário) ≤ 1.
/// A ordem é embaralhada (sem viés operacional). Todo uid aparece no mapa,
/// mesmo com zero tarefas.
Map<String, List<String>> distribuirTarefas(
  List<String> chaves,
  List<String> uids, {
  Random? rng,
}) {
  if (uids.isEmpty) {
    throw ArgumentError('distribuição sem participantes');
  }
  final r = rng ?? Random();
  final c = [...chaves]..shuffle(r);
  final u = [...uids.toSet()]..shuffle(r);
  final out = {for (final x in u) x: <String>[]};
  for (var i = 0; i < c.length; i++) {
    out[u[i % u.length]]!.add(c[i]);
  }
  return out;
}

/// Estado da tarefa NO APARELHO.
enum EstadoLocalC3 { atribuida, concluidaLocal, sincronizada, recusada }

/// Tarefa C3 guardada no aparelho (SharedPreferences), para trabalhar offline.
/// Contagem às cegas: não carrega valores de C1 nem C2.
class TarefaC3Local {
  final String docId;
  final String chave;
  final String tipo; // L3: natureza — 'material' | 'cilindro' | 'gas'
  final String? tag;
  final String codigo;
  final String? lote;
  final String descricao;
  /// L1: local da linha de material (onde contar).
  final String? localId;
  final String? localNome;
  /// L3: prateleira (material).
  final String prateleira;
  /// Gás: volume unitário (para o volume contado).
  final double? volumeUnitario;
  /// L1: TAG — locais onde a C1/C2 viram o cilindro (pista para achar;
  /// não revela quantidades).
  final List<String> locaisVistos;
  final int versao;
  final EstadoLocalC3 estado;
  final Map<String, dynamic>? resultado; // TotaisRodada.toMap()
  final String? concluidaEm; // ISO, hora do aparelho
  final String? motivoRecusa;

  const TarefaC3Local({
    required this.docId,
    required this.chave,
    required this.tipo,
    this.tag,
    required this.codigo,
    this.lote,
    this.descricao = '',
    this.localId,
    this.localNome,
    this.prateleira = '',
    this.volumeUnitario,
    this.locaisVistos = const [],
    required this.versao,
    this.estado = EstadoLocalC3.atribuida,
    this.resultado,
    this.concluidaEm,
    this.motivoRecusa,
  });

  TarefaC3Local copyWith({
    EstadoLocalC3? estado,
    Map<String, dynamic>? resultado,
    String? concluidaEm,
    String? motivoRecusa,
  }) =>
      TarefaC3Local(
        docId: docId,
        chave: chave,
        tipo: tipo,
        tag: tag,
        codigo: codigo,
        lote: lote,
        descricao: descricao,
        localId: localId,
        localNome: localNome,
        prateleira: prateleira,
        volumeUnitario: volumeUnitario,
        locaisVistos: locaisVistos,
        versao: versao,
        estado: estado ?? this.estado,
        resultado: resultado ?? this.resultado,
        concluidaEm: concluidaEm ?? this.concluidaEm,
        motivoRecusa: motivoRecusa ?? this.motivoRecusa,
      );

  Map<String, dynamic> toJson() => {
        'docId': docId,
        'chave': chave,
        'tipo': tipo,
        'tag': tag,
        'codigo': codigo,
        'lote': lote,
        'descricao': descricao,
        'localId': localId,
        'localNome': localNome,
        'prateleira': prateleira,
        'volumeUnitario': volumeUnitario,
        'locaisVistos': locaisVistos,
        'versao': versao,
        'estado': estado.name,
        'resultado': resultado,
        'concluidaEm': concluidaEm,
        'motivoRecusa': motivoRecusa,
      };

  static TarefaC3Local fromJson(Map<String, dynamic> j) => TarefaC3Local(
        docId: j['docId'] as String,
        chave: j['chave'] as String,
        tipo: j['tipo'] as String,
        tag: j['tag'] as String?,
        codigo: (j['codigo'] ?? '') as String,
        lote: j['lote'] as String?,
        descricao: (j['descricao'] ?? '') as String,
        localId: j['localId'] as String?,
        localNome: j['localNome'] as String?,
        prateleira: (j['prateleira'] ?? '') as String,
        volumeUnitario: (j['volumeUnitario'] as num?)?.toDouble(),
        locaisVistos: (j['locaisVistos'] is List)
            ? (j['locaisVistos'] as List).map((e) => e.toString()).toList()
            : const [],
        versao: (j['versao'] as num).toInt(),
        estado: EstadoLocalC3.values.firstWhere((e) => e.name == j['estado'],
            orElse: () => EstadoLocalC3.atribuida),
        resultado: j['resultado'] == null
            ? null
            : Map<String, dynamic>.from(j['resultado'] as Map),
        concluidaEm: j['concluidaEm'] as String?,
        motivoRecusa: j['motivoRecusa'] as String?,
      );
}

/// Junta a lista que veio do servidor com o que está no aparelho.
/// - mesma tarefa e mesma versão → mantém o trabalho local;
/// - versão nova do servidor → tarefa reaberta (o trabalho antigo seria recusado);
/// - já sincronizada no servidor → marca sincronizada;
/// - tarefa concluída localmente que saiu da minha lista (redistribuída) →
///   fica como recusada, para o operador ver.
List<TarefaC3Local> mesclarTarefas({
  required List<TarefaC3Local> doServidor,
  required Set<String> sincronizadasNoServidor,
  required List<TarefaC3Local> locais,
}) {
  final porId = {for (final t in locais) t.docId: t};
  final out = <TarefaC3Local>[];
  final vistos = <String>{};
  for (final s in doServidor) {
    vistos.add(s.docId);
    final l = porId[s.docId];
    if (sincronizadasNoServidor.contains(s.docId)) {
      out.add((l != null && l.versao == s.versao ? l : s)
          .copyWith(estado: EstadoLocalC3.sincronizada));
    } else if (l != null && l.versao == s.versao) {
      out.add(l.estado == EstadoLocalC3.sincronizada
          ? l.copyWith(estado: EstadoLocalC3.concluidaLocal)
          : l);
    } else {
      out.add(s);
    }
  }
  for (final l in locais) {
    if (vistos.contains(l.docId)) continue;
    if (l.estado == EstadoLocalC3.concluidaLocal) {
      out.add(l.copyWith(
          estado: EstadoLocalC3.recusada,
          motivoRecusa: 'tarefa redistribuída para outro operador'));
    } else if (l.estado == EstadoLocalC3.recusada) {
      out.add(l);
    }
  }
  return out;
}

/// Decisão do servidor ao receber um resultado da C3 (dentro da transação).
enum DecisaoSync { aceitar, recusar, aguardar }

/// B62: durante `distribuindo`/`redistribuindo` o resultado NÃO é recusado:
/// fica no aparelho e é reenviado depois ([DecisaoSync.aguardar]).
(DecisaoSync, String?) decidirSync({
  required String? statusC3Inventario, // contagens.contagem_3.status
  required String? responsavelLinha,
  required int? versaoLinha,
  required String? statusLinha,
  required String uid,
  required int versaoTarefa,
}) {
  if (statusC3Inventario == 'distribuindo' ||
      statusC3Inventario == 'redistribuindo') {
    return (DecisaoSync.aguardar, 'distribuição em andamento; tente de novo');
  }
  if (statusC3Inventario != 'em_andamento') {
    return (DecisaoSync.recusar, 'a C3 não está em andamento');
  }
  if (statusLinha == StatusTarefaC3.sincronizada) {
    return (DecisaoSync.recusar, 'tarefa já sincronizada');
  }
  if (responsavelLinha != uid) {
    return (DecisaoSync.recusar, 'tarefa atribuída a outro operador');
  }
  if (versaoLinha != versaoTarefa) {
    return (DecisaoSync.recusar,
        'distribuição mudou (versão $versaoTarefa → $versaoLinha)');
  }
  return (DecisaoSync.aceitar, null);
}

/// Campos que a tela de lançamento da C3 libera (o resto vem travado).
/// Djalma (09/10): Gases e Cilindros → só Cheio e Vazio; Materiais → só
/// Quantidade. Lote nunca é editável na C3.
enum CampoC3 { quantidade, cheioVazio }

CampoC3 campoC3Para(String tipo) =>
    tipo == 'material' ? CampoC3.quantidade : CampoC3.cheioVazio;

/// Resultado da C3 a partir do lançamento (Enter). A métrica do consolidado
/// vai em `quantidade` (é o que o comparativo compara):
///   material → quantidade
///   gas      → cheios (vazios ficam registrados, mas não contam); volume =
///              cheios × volume unitário
///   cilindro → cheios + vazios
/// Só na C3 o lançamento 0 e 0 é aceito: vale "não encontrado".
TotaisRodada resultadoC3(
  String tipo, {
  double quantidade = 0,
  double cheio = 0,
  double vazio = 0,
  double? volumeUnitario,
}) {
  final double metrica;
  switch (tipo) {
    case 'gas':
      metrica = cheio;
    case 'cilindro':
      metrica = cheio + vazio;
    default:
      metrica = quantidade;
  }
  final material = campoC3Para(tipo) == CampoC3.quantidade;
  final zero = material ? quantidade == 0 : (cheio == 0 && vazio == 0);
  return TotaisRodada(
    quantidade: metrica,
    cheio: material ? 0 : cheio,
    vazio: material ? 0 : vazio,
    ocorrencias: 1,
    naoEncontrado: zero,
    volume: tipo == 'gas' && volumeUnitario != null
        ? cheio * volumeUnitario
        : null,
  );
}

/// Item 4: as tarefas C3 do aparelho só continuam válidas se forem do
/// inventário ativo e a C3 dele ainda estiver aberta. Inventário encerrado,
/// cancelado ou substituído, ou C3 encerrada/não necessária → descartar.
bool tarefasLocaisAindaValidas({
  required String inventarioLocal,
  required String? inventarioAtivoId,
  required String? statusC3Ativo,
}) {
  if (inventarioAtivoId == null || inventarioLocal != inventarioAtivoId) {
    return false;
  }
  const abertos = {
    'aguardando_participantes',
    'distribuindo',
    'em_andamento',
    'redistribuindo',
  };
  return abertos.contains(statusC3Ativo);
}

/// Item 6: "Finalizar" só habilita com 100% de certeza: há tarefas e nenhuma
/// está "a fazer" ou "concluída sem enviar". (Recusada = saiu da minha lista.)
bool todasSincronizadas(List<TarefaC3Local> lista) =>
    lista.isNotEmpty &&
    lista.every((t) =>
        t.estado == EstadoLocalC3.sincronizada ||
        t.estado == EstadoLocalC3.recusada);

/// B77: "0 de 0 = participação concluída", mas só com confirmação do
/// servidor (C3 em andamento, eu congelado nela e nenhuma linha minha).
bool podeFinalizarSemTarefas({
  required String? statusC3,
  required List<String> participantes,
  required String uid,
  required int atribuidasNoServidor,
}) =>
    statusC3 == 'em_andamento' &&
    participantes.contains(uid) &&
    atribuidasNoServidor == 0;
