// lib/services/c3.dart
//
// Entrega 3 (teste acelerado): regras PURAS da C3 distribuída/offline.
// - distribuição justa (máx − mín ≤ 1), aleatória dentro do balanceamento;
// - tarefa local do aparelho (pode ser concluída sem internet);
// - decisão de aceitar/recusar uma sincronização (versão da atribuição).

import 'dart:math';

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
  final String tipo; // 'tag' | 'material'
  final String? tag;
  final String codigo;
  final String? lote;
  final String descricao;
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
