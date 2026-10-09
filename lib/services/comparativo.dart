// lib/services/comparativo.dart
//
// Comparativo C1 × C2 — funções PURAS (sem Firebase), testáveis.
//
// L3 (orientação "3 consolidados", 09/10/2026): o estoque tem três naturezas
// e cada uma é um consolidado separado, com a sua métrica:
//
//   MATERIAL  (coleção `materiais`) → QUANTIDADE
//             chave (Djalma, 09/10): código + prateleira
//   GÁS       (coleção `gases`)     → só CHEIOS (vazio não tem gás)
//             chave: código + lote + localização
//             também guarda o VOLUME contado (cheios × volume unitário)
//   CILINDRO  (coleção `gases`)     → CHEIOS + VAZIOS (o ativo físico)
//             chave: código do produto + localização
//             Decisão do Djalma (09/10): por enquanto não se tenta achar uma
//             família física comum entre produtos diferentes. O ponto de
//             extensão [ClassificadorCilindro] fica para quando houver regra.
//
// Um lançamento de gás alimenta DOIS consolidados ao mesmo tempo (gás e
// cilindro). Ex.: C1 8 cheios + 5 vazios, C2 7 cheios + 6 vazios →
// cilindro 13 × 13 (consenso) e gás 8 × 7 (divergência → C3).
//
// Soma pura: a contagem é orquestrada por quadrante; o app já bloqueia a
// mesma TAG duas vezes para o mesmo usuário na rodada.

import 'dart:convert';

enum Natureza { material, cilindro, gas }

extension NaturezaRotulo on Natureza {
  String get rotulo => switch (this) {
        Natureza.material => 'Materiais',
        Natureza.cilindro => 'Cilindros',
        Natureza.gas => 'Gases',
      };

  /// O que a C3 pede ao operador.
  String get metrica => switch (this) {
        Natureza.material => 'quantidade',
        Natureza.cilindro => 'cilindros (cheios + vazios)',
        Natureza.gas => 'cheios',
      };

  static Natureza? deNome(Object? n) {
    for (final v in Natureza.values) {
      if (v.name == n) return v;
    }
    return null;
  }
}

enum ResultadoLinha { encerrada, emAnalise }

/// `conflito` e `local` ficam só para ler documentos antigos.
enum MotivoAnalise { soC1, soC2, divergente, conflito, local }

/// Origem do produto (coleção do cadastro).
const origemGases = 'gases';
const origemMateriais = 'materiais';

/// Tipo físico do cilindro a partir da descrição do produto. Devolve null
/// quando não dá para determinar com segurança (não inventa).
typedef ClassificadorCilindro = String? Function(String descricao);

/// Regra de produção (decisão de 09/10): o cilindro é o do próprio produto
/// de gás — sem agrupar produtos diferentes. Devolver null mantém a linha de
/// cilindro por código do produto, com a descrição do gás.
String? tipoCilindroDaDescricao(String descricao) => null;

/// Um lançamento já reduzido ao que o comparativo usa.
class LancResumo {
  final String? tag;
  final String codigo;
  final String? lote;
  final String descricao;
  final double quantidade;
  final double cheio;
  final double vazio;
  final String? quem;
  final String? localId;
  final String? localNome;
  final String prateleira;
  /// `gases` | `materiais` (cadastro). Null = não informado.
  final String? origem;
  /// Volume unitário do produto (m³/kg por cilindro), quando houver.
  final double? volume;

  const LancResumo({
    this.tag,
    required this.codigo,
    this.lote,
    this.descricao = '',
    this.quantidade = 0,
    this.cheio = 0,
    this.vazio = 0,
    this.quem,
    this.localId,
    this.localNome,
    this.prateleira = '',
    this.origem,
    this.volume,
  });

  LancResumo comOrigem(String? o,
          {String? descricaoCadastro, double? volumeCadastro}) =>
      LancResumo(
        tag: tag,
        codigo: codigo,
        lote: lote,
        descricao: descricao.isNotEmpty ? descricao : (descricaoCadastro ?? ''),
        quantidade: quantidade,
        cheio: cheio,
        vazio: vazio,
        quem: quem,
        localId: localId,
        localNome: localNome,
        prateleira: prateleira,
        origem: o,
        volume: volume ?? volumeCadastro,
      );

  /// Lê um documento de `lancamentos`. Null se não houver código nem TAG.
  static LancResumo? deMapa(Map<String, dynamic> d) {
    String? txt(Object? v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    double num_(Object? v) =>
        v is num ? v.toDouble() : (double.tryParse('$v') ?? 0.0);

    final tag = txt(d['tag']);
    final codigo = txt(d['codigo']);
    if (tag == null && codigo == null) return null;
    return LancResumo(
      tag: tag,
      codigo: codigo ?? '',
      lote: txt(d['lote']),
      descricao: txt(d['descricao']) ?? '',
      quantidade: num_(d['quantidade']),
      cheio: num_(d['cheio']),
      vazio: num_(d['vazio']),
      quem: txt(d['nickname']) ?? txt(d['uid']),
      localId: txt(d['localizacaoId']),
      localNome: txt(d['localizacaoNome']),
      prateleira: (txt(d['prateleira']) ?? '').toUpperCase(),
      origem: txt(d['origem']),
      volume: d['volume'] is num ? (d['volume'] as num).toDouble() : null,
    );
  }

  /// Gás quando o cadastro diz `gases`. Sem cadastro: lançamento com
  /// cheio/vazio é gás (só gases têm esses campos); senão, material.
  bool get ehGas =>
      origem != null ? origem == origemGases : (cheio > 0 || vazio > 0);
}

/// Totais de um item numa rodada. [quantidade] é a MÉTRICA da natureza
/// (material: quantidade; gás: cheios; cilindro: cheios + vazios).
class TotaisRodada {
  final double quantidade;
  /// Composição, só informativa (gás/cilindro). Não entra na comparação.
  final double cheio;
  final double vazio;
  final int ocorrencias;
  final Set<String> quem;
  /// C3: tarefa concluída como "NÃO encontrado".
  final bool naoEncontrado;
  /// Produtos que formaram a linha (cilindro junta vários gases).
  final Set<String> codigos;
  /// Gás: volume contado (cheios × volume unitário). Null = sem volume no
  /// cadastro. Informativo: a comparação é pelos cheios.
  final double? volume;

  const TotaisRodada({
    this.quantidade = 0,
    this.cheio = 0,
    this.vazio = 0,
    this.ocorrencias = 0,
    this.quem = const <String>{},
    this.naoEncontrado = false,
    this.codigos = const <String>{},
    this.volume,
  });

  Map<String, dynamic> toMap() => {
        'quantidade': quantidade,
        'cheio': cheio,
        'vazio': vazio,
        'ocorrencias': ocorrencias,
        'quem': quem.toList()..sort(),
        if (naoEncontrado) 'nao_encontrado': true,
        if (codigos.isNotEmpty) 'codigos': codigos.toList()..sort(),
        if (volume != null) 'volume': volume,
      };

  static TotaisRodada? deMapa(Object? m) {
    if (m is! Map) return null;
    double n(Object? v) => v is num ? v.toDouble() : 0.0;
    Set<String> s(Object? v) =>
        v is List ? v.map((e) => e.toString()).toSet() : const <String>{};
    return TotaisRodada(
      quantidade: n(m['quantidade']),
      cheio: n(m['cheio']),
      vazio: n(m['vazio']),
      ocorrencias: (m['ocorrencias'] as num?)?.toInt() ?? 0,
      quem: s(m['quem']),
      naoEncontrado: m['nao_encontrado'] == true,
      codigos: s(m['codigos']),
      volume: m['volume'] is num ? (m['volume'] as num).toDouble() : null,
    );
  }

  static const double _eps = 0.0001;

  /// Compara SÓ a métrica da natureza.
  bool mesmoValor(TotaisRodada o) => (quantidade - o.quantidade).abs() < _eps;
}

/// Uma linha do comparativo.
class LinhaComparativo {
  final String chave;
  final Natureza natureza;
  final String codigo; // material/gás: o produto; cilindro: '' ou o produto
  final String? lote;
  final String descricao;
  final String? localId;
  final String? localNome;
  final String prateleira; // só material
  /// Cilindro: tipo físico tirado da descrição; null se não classificado.
  final String? tipoCilindro;
  /// Gás: volume unitário do produto (para o volume contado na C3).
  final double? volumeUnitario;
  final TotaisRodada? c1;
  final TotaisRodada? c2;
  final ResultadoLinha resultado;
  final MotivoAnalise? motivo;

  // C3
  final TotaisRodada? c3;
  final String? c3Quem;
  final DateTime? c3Em;
  final String? c3ResponsavelUid;
  final String? c3ResponsavelNome;
  final int? c3Versao;
  final String? c3Status; // StatusTarefaC3
  /// L3: divergência de natureza NÃO escolhida pelo analista para a C3.
  final bool foraDaC3;

  const LinhaComparativo({
    required this.chave,
    required this.natureza,
    required this.codigo,
    this.lote,
    this.descricao = '',
    this.localId,
    this.localNome,
    this.prateleira = '',
    this.tipoCilindro,
    this.volumeUnitario,
    this.c1,
    this.c2,
    required this.resultado,
    this.motivo,
    this.c3,
    this.c3Quem,
    this.c3Em,
    this.c3ResponsavelUid,
    this.c3ResponsavelNome,
    this.c3Versao,
    this.c3Status,
    this.foraDaC3 = false,
  });

  bool get emAnalise => resultado == ResultadoLinha.emAnalise;

  /// Cilindro pelo próprio produto (sem família física comum).
  bool get cilindroPorProduto =>
      natureza == Natureza.cilindro && tipoCilindro == null;

  /// É (ou será) tarefa da C3.
  bool get naC3 => emAnalise && !foraDaC3;

  bool get contadaNaC3 => emAnalise && c3 != null;

  /// A1: pendência ATUAL (divergiu, está na C3 e ainda não foi recontada).
  bool get pendenteAtual => naC3 && c3 == null;

  /// Valor final definido (consenso ou C3).
  bool get resolvida => !emAnalise || c3 != null;

  /// Divergência que o analista deixou fora da C3: sem valor final.
  bool get semC3 => emAnalise && foraDaC3 && c3 == null;

  TotaisRodada? get valorFinal => emAnalise ? c3 : (c1 ?? c2);

  String get origemFinal => !emAnalise
      ? 'C1 = C2'
      : c3 != null
          ? (c3!.naoEncontrado ? 'C3: não encontrado' : 'C3')
          : (foraDaC3 ? 'sem C3 (não selecionado)' : 'pendente na C3');

  String get localFinal => localNome ?? localId ?? '';

  /// Nome do item para tela e planilha.
  String get identificacao => switch (natureza) {
        Natureza.cilindro =>
          tipoCilindro != null ? 'Cilindro $tipoCilindro' : codigo,
        _ => codigo,
      };

  String get docId => idDocumento(chave);

  Map<String, dynamic> toMap() => {
        'chave': chave,
        'natureza': natureza.name,
        'codigo': codigo,
        'lote': lote,
        'descricao': descricao,
        'local_id': localId,
        'local_nome': localNome,
        'prateleira': prateleira,
        'tipo_cilindro': tipoCilindro,
        if (volumeUnitario != null) 'volume_unitario': volumeUnitario,
        'c1': c1?.toMap(),
        'c2': c2?.toMap(),
        'resultado':
            resultado == ResultadoLinha.encerrada ? 'encerrada' : 'em_analise',
        'motivo': motivo?.name,
        if (foraDaC3) 'c3_fora': true,
      };

  /// Cópia com [foraDaC3] (B73: marcado já na geração do comparativo).
  LinhaComparativo comForaDaC3(bool fora) => LinhaComparativo(
        chave: chave,
        natureza: natureza,
        codigo: codigo,
        lote: lote,
        descricao: descricao,
        localId: localId,
        localNome: localNome,
        prateleira: prateleira,
        tipoCilindro: tipoCilindro,
        volumeUnitario: volumeUnitario,
        c1: c1,
        c2: c2,
        resultado: resultado,
        motivo: motivo,
        c3: c3,
        c3Quem: c3Quem,
        c3Em: c3Em,
        c3ResponsavelUid: c3ResponsavelUid,
        c3ResponsavelNome: c3ResponsavelNome,
        c3Versao: c3Versao,
        c3Status: c3Status,
        foraDaC3: fora,
      );

  static LinhaComparativo deMapa(Map<String, dynamic> m) {
    final motivoTxt = m['motivo'] as String?;
    return LinhaComparativo(
      chave: (m['chave'] ?? '').toString(),
      natureza: NaturezaRotulo.deNome(m['natureza']) ?? Natureza.material,
      codigo: (m['codigo'] ?? '').toString(),
      lote: m['lote'] as String?,
      descricao: (m['descricao'] ?? '').toString(),
      localId: m['local_id'] as String?,
      localNome: m['local_nome'] as String?,
      prateleira: (m['prateleira'] ?? '').toString(),
      tipoCilindro: m['tipo_cilindro'] as String?,
      volumeUnitario: m['volume_unitario'] is num
          ? (m['volume_unitario'] as num).toDouble()
          : null,
      c1: TotaisRodada.deMapa(m['c1']),
      c2: TotaisRodada.deMapa(m['c2']),
      resultado: m['resultado'] == 'encerrada'
          ? ResultadoLinha.encerrada
          : ResultadoLinha.emAnalise,
      motivo: motivoTxt == null
          ? null
          : MotivoAnalise.values.firstWhere((e) => e.name == motivoTxt,
              orElse: () => MotivoAnalise.divergente),
      c3: TotaisRodada.deMapa(m['c3']),
      c3Quem: m['c3_quem'] as String?,
      c3Em: _data(m['c3_em']),
      c3ResponsavelUid: m['c3_responsavel_uid'] as String?,
      c3ResponsavelNome: m['c3_responsavel_nome'] as String?,
      c3Versao: (m['c3_versao'] as num?)?.toInt(),
      c3Status: m['c3_status'] as String?,
      foraDaC3: m['c3_fora'] == true,
    );
  }

  static DateTime? _data(Object? v) {
    if (v is DateTime) return v;
    try {
      final dynamic d = v;
      final r = d?.toDate();
      return r is DateTime ? r : null;
    } catch (_) {
      return null;
    }
  }
}

/// base64url sem '=' da chave em UTF-8.
String idDocumento(String chave) =>
    base64Url.encode(utf8.encode(chave)).replaceAll('=', '');

/// Uma contribuição de um lançamento para um consolidado.
class _Entrada {
  final String chave;
  final Natureza natureza;
  final double valor;
  final String? tipoCilindro;
  _Entrada(this.chave, this.natureza, this.valor, this.tipoCilindro);
}

/// L5: consolidados que um inventário do [tipo] gera.
///   Materiais → só Materiais.
///   Gases ou Cilindros → Gases E Cilindros (a coleta é a mesma: cheios e
///   vazios); o tipo só define qual deles vai para a C3.
///   Sem tipo (inventário antigo) → os três.
Set<Natureza> consolidadosDoTipo(Natureza? tipo) => switch (tipo) {
      null => Natureza.values.toSet(),
      Natureza.material => {Natureza.material},
      Natureza.gas || Natureza.cilindro => {Natureza.gas, Natureza.cilindro},
    };

/// L5: divergências que pedem C3 — só as da natureza do tipo (sem tipo:
/// todas; o analista escolhe no monitor).
int divergenciasParaC3(List<LinhaComparativo> linhas, Natureza? tipo) =>
    linhas
        .where((l) => l.emAnalise && (tipo == null || l.natureza == tipo))
        .length;

/// B73: inventário com tipo → a divergência do OUTRO consolidado já nasce
/// fora da C3 (informativa), mesmo que a C3 nunca seja chamada (C3 não
/// necessária). Sem tipo: nada é marcado (o analista escolhe no monitor).
List<LinhaComparativo> marcarForaDaC3(
        List<LinhaComparativo> linhas, Natureza? tipo) =>
    tipo == null
        ? linhas
        : [
            for (final l in linhas)
              l.emAnalise ? l.comForaDaC3(l.natureza != tipo) : l
          ];

/// Um lançamento → 1 entrada (material) ou 2 (gás + cilindro).
List<_Entrada> _entradas(LancResumo l, ClassificadorCilindro tipoCilindro) {
  final lote = l.lote ?? '';
  final local = l.localId ?? '';
  if (!l.ehGas) {
    // Djalma (09/10): material = código + prateleira (sem lote/localização).
    return [
      _Entrada('MAT:${l.codigo}|${l.prateleira}', Natureza.material,
          l.quantidade, null),
    ];
  }
  final tipo = tipoCilindro(l.descricao);
  return [
    // B70 (defensivo): lançamento só de vazios não cria linha de gás com
    // zero — vazio não tem gás. Ele continua contando no cilindro.
    if (l.cheio > 0)
      _Entrada('GAS:${l.codigo}|$lote|$local', Natureza.gas, l.cheio, null),
    _Entrada(
        tipo != null ? 'CILT:$tipo|$local' : 'CIL:${l.codigo}|$local',
        Natureza.cilindro,
        l.cheio + l.vazio,
        tipo),
  ];
}

class _Acumulador {
  double valor = 0, cheio = 0, vazio = 0;
  double volume = 0;
  bool temVolume = false;
  int n = 0;
  final Set<String> quem = {};
  final Set<String> codigos = {};

  void somar(LancResumo l, double v) {
    n++;
    valor += v;
    cheio += l.cheio;
    vazio += l.vazio;
    if (l.volume != null) {
      temVolume = true;
      volume += l.cheio * l.volume!;
    }
    if (l.quem != null) quem.add(l.quem!);
    if (l.codigo.isNotEmpty) codigos.add(l.codigo);
  }

  TotaisRodada totais(Natureza nat) => TotaisRodada(
        quantidade: valor,
        cheio: nat == Natureza.material ? 0 : cheio,
        vazio: nat == Natureza.cilindro ? vazio : 0,
        ocorrencias: n,
        quem: quem,
        codigos: codigos,
        volume: nat == Natureza.gas && temVolume ? volume : null,
      );
}

/// Compara C1 e C2 nos três consolidados.
/// Ordem: em análise primeiro; depois natureza, local, item.
List<LinhaComparativo> compararC1C2(
  List<LancResumo> c1,
  List<LancResumo> c2, {
  ClassificadorCilindro tipoCilindro = tipoCilindroDaDescricao,
}) {
  final acc1 = <String, _Acumulador>{};
  final acc2 = <String, _Acumulador>{};
  final ident = <String, (LancResumo, _Entrada)>{};

  void totalizar(List<LancResumo> ls, Map<String, _Acumulador> acc) {
    for (final l in ls) {
      for (final e in _entradas(l, tipoCilindro)) {
        acc.putIfAbsent(e.chave, _Acumulador.new).somar(l, e.valor);
        ident.putIfAbsent(e.chave, () => (l, e));
      }
    }
  }

  totalizar(c1, acc1);
  totalizar(c2, acc2);

  final linhas = <LinhaComparativo>[];
  for (final chave in {...acc1.keys, ...acc2.keys}) {
    final (l, e) = ident[chave]!;
    final a = acc1[chave]?.totais(e.natureza);
    final b = acc2[chave]?.totais(e.natureza);

    final ResultadoLinha res;
    MotivoAnalise? motivo;
    if (a != null && b != null) {
      if (a.mesmoValor(b)) {
        res = ResultadoLinha.encerrada;
      } else {
        res = ResultadoLinha.emAnalise;
        motivo = MotivoAnalise.divergente;
      }
    } else {
      res = ResultadoLinha.emAnalise;
      motivo = a != null ? MotivoAnalise.soC1 : MotivoAnalise.soC2;
    }

    final cil = e.natureza == Natureza.cilindro;
    linhas.add(LinhaComparativo(
      chave: chave,
      natureza: e.natureza,
      // Cilindro classificado junta produtos: não tem código único.
      codigo: cil && e.tipoCilindro != null ? '' : l.codigo,
      // Lote só no gás (material: código + prateleira; cilindro: sem lote).
      lote: e.natureza == Natureza.gas ? l.lote : null,
      descricao: cil && e.tipoCilindro != null ? '' : l.descricao,
      localId: l.localId,
      localNome: l.localNome,
      prateleira: e.natureza == Natureza.material ? l.prateleira : '',
      tipoCilindro: e.tipoCilindro,
      volumeUnitario: e.natureza == Natureza.gas ? l.volume : null,
      c1: a,
      c2: b,
      resultado: res,
      motivo: motivo,
    ));
  }

  linhas.sort((x, y) {
    if (x.emAnalise != y.emAnalise) return x.emAnalise ? -1 : 1;
    final n = x.natureza.index.compareTo(y.natureza.index);
    if (n != 0) return n;
    final lc = x.localFinal.compareTo(y.localFinal);
    if (lc != 0) return lc;
    final c = x.identificacao.compareTo(y.identificacao);
    return c != 0 ? c : x.chave.compareTo(y.chave);
  });
  return linhas;
}

/// Resumo numérico do comparativo.
class ResumoComparativo {
  final int total;
  final int encerradas;
  final int emAnalise;
  final int soC1;
  final int soC2;
  final int divergentes;
  /// Divergências por natureza (para o analista escolher a C3).
  final Map<Natureza, int> divergenciasPor;

  const ResumoComparativo({
    required this.total,
    required this.encerradas,
    required this.emAnalise,
    required this.soC1,
    required this.soC2,
    required this.divergentes,
    this.divergenciasPor = const {},
  });

  /// Compatibilidade com telas antigas.
  int get conflitos => 0;

  factory ResumoComparativo.de(List<LinhaComparativo> linhas) {
    int c(bool Function(LinhaComparativo) f) => linhas.where(f).length;
    return ResumoComparativo(
      total: linhas.length,
      encerradas: c((l) => !l.emAnalise),
      emAnalise: c((l) => l.emAnalise),
      soC1: c((l) => l.motivo == MotivoAnalise.soC1),
      soC2: c((l) => l.motivo == MotivoAnalise.soC2),
      divergentes: c((l) => l.motivo == MotivoAnalise.divergente),
      divergenciasPor: {
        for (final n in Natureza.values)
          n: c((l) => l.emAnalise && l.natureza == n),
      },
    );
  }
}

/// B69: situação auditável de cada consolidado na C3.
class ResumoNatureza {
  final Natureza natureza;
  final int divergencias;
  final int recontadas;
  final int resolvidas;
  /// Divergências deixadas fora da C3 (consolidado não selecionado).
  final int semC3;
  /// Este consolidado foi o escolhido para a C3.
  final bool selecionada;

  const ResumoNatureza({
    required this.natureza,
    required this.divergencias,
    required this.recontadas,
    required this.resolvidas,
    required this.semC3,
    required this.selecionada,
  });

  /// Texto do relatório, ex.: "Gases: 5 divergências · 5 recontadas ·
  /// 5 resolvidas" ou "Cilindros: 2 divergências · fora da C3 (informativo)".
  String get texto {
    final base = '${natureza.rotulo}: $divergencias divergência(s)';
    if (divergencias == 0) return base;
    if (!selecionada) return '$base · fora da C3 (informativo)';
    return '$base · $recontadas recontada(s) · $resolvidas resolvida(s)';
  }

  Map<String, dynamic> toMap() => {
        'divergencias': divergencias,
        'recontadas': recontadas,
        'resolvidas': resolvidas,
        'sem_c3': semC3,
        'selecionada': selecionada,
      };
}

/// B69: resumo por consolidado. [escolhida] = natureza da C3 (null se a C3
/// ainda não foi aberta).
Map<Natureza, ResumoNatureza> resumoPorNatureza(
    List<LinhaComparativo> linhas, Natureza? escolhida) {
  return {
    for (final n in Natureza.values)
      n: () {
        final div =
            linhas.where((l) => l.emAnalise && l.natureza == n).toList();
        return ResumoNatureza(
          natureza: n,
          divergencias: div.length,
          recontadas: div.where((l) => l.c3 != null).length,
          resolvidas: div.where((l) => l.resolvida).length,
          semC3: div.where((l) => l.semC3).length,
          selecionada: escolhida == n,
        );
      }(),
  };
}

/// Andamento da C3 (só a natureza escolhida).
class ResumoC3 {
  final int total;
  final int contadas;
  int get pendentes => total - contadas;

  const ResumoC3({required this.total, required this.contadas});

  factory ResumoC3.de(List<LinhaComparativo> linhas) {
    final em = linhas.where((l) => l.naC3).toList();
    return ResumoC3(
        total: em.length, contadas: em.where((l) => l.c3 != null).length);
  }
}

/// Planilha (CSV, separador ';') do resultado.
/// [c3Selecionada]: consolidado escolhido para a C3 (coluna de auditoria).
String resultadoCsv(List<LinhaComparativo> linhas, {Natureza? c3Selecionada}) {
  String f(double? v) => v == null
      ? ''
      : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(3))
          .replaceAll('.', ',');
  String esc(String? s) {
    final x = (s ?? '').replaceAll('"', '""');
    return (x.contains(';') || x.contains('"') || x.contains('\n'))
        ? '"$x"'
        : x;
  }

  final b = StringBuffer()
    ..writeln([
      'natureza', 'local', 'item', 'lote', 'prateleira', 'descricao',
      'metrica', 'resultado', 'motivo', 'c1', 'c2', 'c3', 'final',
      'origem_final', 'situacao', 'c3_responsavel',
      'c1_cheio', 'c1_vazio', 'c2_cheio', 'c2_vazio', 'local_id',
      'c3_selecionada',
    ].join(';'));
  for (final l in linhas) {
    final cil = l.natureza == Natureza.cilindro;
    b.writeln([
      l.natureza.name,
      esc(l.localFinal),
      esc(l.identificacao),
      esc(l.lote),
      esc(l.prateleira),
      esc(l.descricao),
      esc(l.natureza.metrica),
      l.emAnalise ? 'em_analise' : 'encerrada',
      l.motivo?.name ?? '',
      f(l.c1?.quantidade),
      f(l.c2?.quantidade),
      f(l.c3?.quantidade),
      f(l.valorFinal?.quantidade),
      l.origemFinal,
      l.resolvida ? 'resolvida' : (l.semC3 ? 'sem_c3' : 'pendente'),
      esc(l.c3ResponsavelNome ?? l.c3Quem),
      cil ? f(l.c1?.cheio) : '',
      cil ? f(l.c1?.vazio) : '',
      cil ? f(l.c2?.cheio) : '',
      cil ? f(l.c2?.vazio) : '',
      esc(l.localId),
      c3Selecionada?.name ?? '',
    ].join(';'));
  }
  return b.toString();
}
