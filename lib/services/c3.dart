// lib/services/c3.dart
//
// Entrega 3 (teste acelerado): regras PURAS da C3 distribuída/offline.
// - distribuição POR LOCAL com peso de esforço (C3-D, item 2 de 03/11):
//   [distribuirPorLocal]. O sorteio linha a linha ([distribuirTarefas])
//   fica só para compatibilidade dos testes antigos;
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

/// Item 2 (03/11) — C3-D: uma linha da C3 para a divisão por local.
/// [local]: chave TÉCNICA da área (`localizacaoId`; o nome visível só como
/// reserva). [produto]: o pacote indivisível dentro da área — Gás/Cilindro =
/// o produto; Material = a prateleira. [esforco]: volume a recontar (≥ 1).
class ItemDistribuicaoC3 {
  final String id;
  final String local;
  final String produto;
  final double esforco;
  const ItemDistribuicaoC3({
    required this.id,
    required this.local,
    required this.produto,
    required this.esforco,
  });
}

/// Item 2 — monta o item de distribuição de uma linha do comparativo.
/// Esforço = max(C1, C2) na métrica da linha, com mínimo 1 (a C3 reconta a
/// linha inteira, não só a diferença).
ItemDistribuicaoC3 itemDistribuicaoDe(LinhaComparativo l) {
  String limpo(String? s) => (s ?? '').trim().toUpperCase();
  // 03/11 (piloto do 009): o LOCAL é a ÁREA (localizacaoId) para todas as
  // naturezas. Antes, em Material o local era a prateleira, e prateleiras da
  // mesma área iam para pessoas diferentes — as duas pessoas percorriam as
  // duas áreas. A prateleira passa a ser o pacote indivisível dentro da área
  // (uma prateleira nunca é dividida entre duas pessoas).
  final id = limpo(l.localId);
  final nome = limpo(l.localNome);
  final prat = limpo(l.prateleira);
  final String local;
  if (id.isNotEmpty) {
    local = 'LOC:$id';
  } else if (nome.isNotEmpty) {
    local = 'LOC:$nome';
  } else if (l.natureza == Natureza.material && prat.isNotEmpty) {
    local = 'PRAT:$prat'; // material sem área: a prateleira é o local
  } else {
    local = 'LOC:(sem local)';
  }
  // Gás e Cilindro do mesmo código no mesmo local são a mesma pilha física:
  // mesma chave de produto, para irem à mesma pessoa.
  final cod = l.codigo.trim().isNotEmpty
      ? l.codigo.trim().toUpperCase()
      : (l.tipoCilindro ?? l.chave);
  final String produto;
  if (l.natureza == Natureza.material) {
    produto = prat.isNotEmpty ? 'PRAT:$prat' : 'MAT:$cod';
  } else {
    produto = 'GC:$cod';
  }
  final a = l.c1?.quantidade ?? 0;
  final b = l.c2?.quantidade ?? 0;
  final esforco = a > b ? a : b;
  return ItemDistribuicaoC3(
    id: l.docId,
    local: local,
    produto: produto,
    esforco: esforco < 1 ? 1 : esforco,
  );
}

/// Item 2 (03/11) — C3-D: divisão da C3 POR LOCAL, com peso de esforço.
/// Substitui o sorteio linha a linha ([distribuirTarefas]), que mandava
/// várias pessoas aos mesmos locais (piloto 007).
///
/// Regras (proposta C3 v2, aprovada na revisão):
/// 1. Unidade de trabalho = local: todas as linhas de um local vão para a
///    mesma pessoa.
/// 2. Esforço do local = soma do esforço das linhas.
/// 3. LPT: locais do mais pesado ao mais leve, cada um para quem estiver com
///    menos carga.
/// 4. Local maior que 1,5 × a parte justa (esforço total / participantes):
///    é dividido POR PRODUTO entre k pessoas DIFERENTES, com
///    k = min(ceil(esforço do local / (1,5 × parte justa)), produtos no
///    local, participantes). Um produto num local nunca é dividido.
/// 5. Determinística (sem sorteio). Desempate: menor carga, depois menos
///    locais já recebidos, depois o uid em ordem alfabética. Locais de mesmo
///    esforço: ordem alfabética da chave.
/// Invariantes (testadas): (local, produto) → exatamente 1 responsável; toda
/// linha tem exatamente 1 responsável; todo uid aparece no mapa (mesmo com
/// zero); a lista de cada pessoa sai em ordem local → produto → id.
/// Um local só é dividido quando passa de [fatorDivisaoLocal] × a parte
/// justa (revisão de 03/11: evitar dividir local só um pouco acima da média).
const double fatorDivisaoLocal = 1.5;

Map<String, List<String>> distribuirPorLocal(
  List<ItemDistribuicaoC3> itens,
  List<String> uids,
) {
  final pessoas = uids.toSet().toList()..sort();
  if (pessoas.isEmpty) {
    throw ArgumentError('distribuição sem participantes');
  }
  final carga = {for (final u in pessoas) u: 0.0};
  final unidades = {for (final u in pessoas) u: 0};
  final atrib = {for (final u in pessoas) u: <ItemDistribuicaoC3>[]};

  // local → produto → itens
  final porLocal = <String, Map<String, List<ItemDistribuicaoC3>>>{};
  for (final it in itens) {
    porLocal
        .putIfAbsent(it.local, () => {})
        .putIfAbsent(it.produto, () => [])
        .add(it);
  }
  double soma(Iterable<ItemDistribuicaoC3> xs) =>
      xs.fold(0.0, (s, x) => s + x.esforco);
  final total = soma(itens);
  final parteJusta = total / pessoas.length;
  final limiteDivisao = parteJusta * fatorDivisaoLocal;

  String menosCarregado(Set<String> excluir) {
    String? melhor;
    for (final u in pessoas) {
      if (excluir.contains(u)) continue;
      if (melhor == null) {
        melhor = u;
        continue;
      }
      final cu = carga[u]!, cm = carga[melhor]!;
      if (cu < cm - 1e-9 ||
          ((cu - cm).abs() <= 1e-9 && unidades[u]! < unidades[melhor]!)) {
        melhor = u;
      }
    }
    return melhor!;
  }

  void entregar(String u, Iterable<ItemDistribuicaoC3> xs) {
    atrib[u]!.addAll(xs);
    carga[u] = carga[u]! + soma(xs);
    unidades[u] = unidades[u]! + 1;
  }

  final locais = porLocal.keys.toList()
    ..sort((a, b) {
      final ea = soma(porLocal[a]!.values.expand((x) => x));
      final eb = soma(porLocal[b]!.values.expand((x) => x));
      final c = eb.compareTo(ea);
      return c != 0 ? c : a.compareTo(b);
    });

  for (final local in locais) {
    final produtos = porLocal[local]!;
    final esforcoLocal = soma(produtos.values.expand((x) => x));
    // Revisão de 03/11: só divide o local quando ele passa CLARAMENTE da
    // parte justa (limite = 1,5 × parte justa), para não espalhar gente
    // num local só um pouco maior que a média (ex.: 51 com média 50).
    final k = esforcoLocal <= limiteDivisao + 1e-9
        ? 1
        : [
            (esforcoLocal / limiteDivisao).ceil(),
            produtos.length,
            pessoas.length,
          ].reduce((a, b) => a < b ? a : b);
    if (k <= 1) {
      entregar(menosCarregado(const {}),
          produtos.values.expand((x) => x).toList());
      continue;
    }
    // Divide os pacotes de produto do local em k grupos (LPT interno)...
    final pacotes = produtos.entries.toList()
      ..sort((a, b) {
        final c = soma(b.value).compareTo(soma(a.value));
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    final grupos = List.generate(k, (_) => <ItemDistribuicaoC3>[]);
    final pesoGrupo = List.filled(k, 0.0);
    for (final p in pacotes) {
      var g = 0;
      for (var i = 1; i < k; i++) {
        if (pesoGrupo[i] < pesoGrupo[g] - 1e-9) g = i;
      }
      grupos[g].addAll(p.value);
      pesoGrupo[g] += soma(p.value);
    }
    // ...e entrega cada grupo, do mais pesado ao mais leve, a pessoas
    // DIFERENTES (as menos carregadas).
    final ordem = List.generate(k, (i) => i)
      ..sort((a, b) {
        final c = pesoGrupo[b].compareTo(pesoGrupo[a]);
        return c != 0 ? c : a.compareTo(b);
      });
    final usados = <String>{};
    for (final g in ordem) {
      if (grupos[g].isEmpty) continue;
      final u = menosCarregado(usados);
      usados.add(u);
      entregar(u, grupos[g]);
    }
  }

  return {
    for (final u in pessoas)
      u: (atrib[u]!
            ..sort((a, b) {
              final c = a.local.compareTo(b.local);
              if (c != 0) return c;
              final d = a.produto.compareTo(b.produto);
              return d != 0 ? d : a.id.compareTo(b.id);
            }))
          .map((x) => x.id)
          .toList(),
  };
}

/// Item 2 (03/11) — ordem de execução no aparelho: área → prateleira →
/// produto → lote (antes era só por código, e o operador ia e voltava entre
/// locais).
int ordemDeExecucaoC3(TarefaC3Local a, TarefaC3Local b) {
  // 03/11: área → prateleira (material) → produto → lote.
  String area(TarefaC3Local t) =>
      (t.localNome ?? t.localId ?? '').trim().toUpperCase();
  for (final c in [
    area(a).compareTo(area(b)),
    a.prateleira.trim().toUpperCase().compareTo(b.prateleira.trim().toUpperCase()),
    a.codigo.compareTo(b.codigo),
    (a.lote ?? '').compareTo(b.lote ?? ''),
    a.docId.compareTo(b.docId),
  ]) {
    if (c != 0) return c;
  }
  return 0;
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
