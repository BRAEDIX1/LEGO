// lib/services/compatibilidade.dart
//
// Lote 3B (D11): regras PURAS de compatibilidade. Sem Firebase, sem Hive,
// sem Flutter: tudo aqui é testável em test/compatibilidade_test.dart.

/// Resultado da avaliação de compatibilidade (T32).
enum ResultadoCompat {
  liberado,
  versaoAbaixoDoMinimo,
  preparacaoIncompleta,
  configuracaoInvalida,
  versaoInstaladaInvalida,

  /// Política não pôde ser obtida (servidor fora e sem cache). Falha fechada.
  politicaIndisponivel,
}

/// Decisão com o motivo legível para o operador.
class DecisaoCompat {
  final ResultadoCompat resultado;
  final String mensagem;

  const DecisaoCompat(this.resultado, this.mensagem);

  bool get liberado => resultado == ResultadoCompat.liberado;

  @override
  String toString() => 'DecisaoCompat(${resultado.name}: $mensagem)';
}

// ---------------------------------------------------------------------------
// Versões
// ---------------------------------------------------------------------------

/// Lê uma versão `X.Y.Z` (aceita `v` inicial e 1 a 3 partes: `1.2` = `1.2.0`).
/// Qualquer outro formato devolve null (falha fechada na política).
List<int>? lerVersao(Object? valor) {
  if (valor is! String) return null;
  var v = valor.trim();
  if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
  if (v.isEmpty) return null;
  final partes = v.split('.');
  if (partes.isEmpty || partes.length > 3) return null;
  final numeros = <int>[];
  for (final p in partes) {
    if (p.isEmpty || !RegExp(r'^\d+$').hasMatch(p)) return null;
    numeros.add(int.parse(p));
  }
  while (numeros.length < 3) {
    numeros.add(0);
  }
  return numeros;
}

/// Compara duas versões já lidas: negativo se a < b, zero se iguais.
int compararVersoes(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}

/// Comparação TOLERANTE usada pela tela de atualização (GitHub), idêntica à
/// antiga `UpdateService._isNewer`: partes não numéricas valem 0.
/// Não usar na política de compatibilidade (lá vale [lerVersao], estrita).
bool versaoMaisNova(String nova, String atual) {
  List<int> partes(String v) {
    final p = v.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    while (p.length < 3) {
      p.add(0);
    }
    return p;
  }

  final n = partes(nova);
  final a = partes(atual);
  for (var i = 0; i < 3; i++) {
    if (n[i] > a[i]) return true;
    if (n[i] < a[i]) return false;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Avaliação (T32)
// ---------------------------------------------------------------------------

/// Avalia se o aparelho pode se vincular a um inventário central.
///
/// - [versaoMinima]: valor bruto do Firestore (`versao_minima_mobile` ou
///   `_desktop`). Ausente, vazio ou malformado = configuração inválida.
/// - [exigirPreparacao]: mobile = true (semente da build no Hive);
///   desktop = false.
/// - Preparação válida SÓ com `buildPreparado == buildInstalado` (cobre
///   downgrade e semente de outra build).
DecisaoCompat avaliarCompatibilidade({
  required String? versaoInstalada,
  required Object? versaoMinima,
  required bool exigirPreparacao,
  int? buildInstalado,
  int? buildPreparado,
}) {
  final minima = lerVersao(versaoMinima);
  if (minima == null) {
    return const DecisaoCompat(
      ResultadoCompat.configuracaoInvalida,
      'Configuração de compatibilidade inválida ou ausente no servidor. '
      'Procure o responsável pelo LEGO.',
    );
  }

  final instalada = lerVersao(versaoInstalada);
  if (instalada == null) {
    return DecisaoCompat(
      ResultadoCompat.versaoInstaladaInvalida,
      'Versão instalada não reconhecida ("${versaoInstalada ?? ''}").',
    );
  }

  if (compararVersoes(instalada, minima) < 0) {
    return DecisaoCompat(
      ResultadoCompat.versaoAbaixoDoMinimo,
      'Este aparelho está na versão ${instalada.join('.')}; '
      'a versão mínima exigida é ${minima.join('.')}. '
      'Feche o LEGO e abra com internet para atualizar.',
    );
  }

  if (exigirPreparacao) {
    if (buildInstalado != null &&
        buildPreparado != null &&
        buildPreparado > buildInstalado) {
      // Downgrade: reabrir não refaz a preparação (main.dart só prepara
      // quando o build instalado é MAIOR que o preparado).
      return const DecisaoCompat(
        ResultadoCompat.preparacaoIncompleta,
        'Este aparelho foi preparado por uma versão mais nova do LEGO do que '
        'a instalada. Instale a versão atual do LEGO.',
      );
    }
    if (buildInstalado == null ||
        buildPreparado == null ||
        buildPreparado != buildInstalado) {
      return const DecisaoCompat(
        ResultadoCompat.preparacaoIncompleta,
        'A preparação das coleções desta versão não terminou. '
        'Feche e abra o LEGO com internet.',
      );
    }
  }

  return const DecisaoCompat(ResultadoCompat.liberado, 'Compatível.');
}

/// Guarda única: só `liberado` permite vínculo com inventário central
/// (Completa, Controlado, lançamento legado vinculado).
bool podeVincularCentral(ResultadoCompat? resultado) =>
    resultado == ResultadoCompat.liberado;

// ---------------------------------------------------------------------------
// Fluxo legado (B39, B41, B42)
// ---------------------------------------------------------------------------

/// Como gravar um lançamento NOVO no fluxo legado (chave desligada).
enum DecisaoGravacaoLegada {
  /// Grava vinculado ao inventário legado ativo (compatível).
  vincular,

  /// Grava sem vínculo: não há inventário ativo, ou o operador ESCOLHEU
  /// Autônomo explicitamente (B42).
  semVinculo,

  /// Há inventário ativo, mas o vínculo central está bloqueado e não houve
  /// escolha explícita de Autônomo. Nunca vira "semVinculo" sozinho (B41).
  negar,
}

DecisaoGravacaoLegada decidirGravacaoLegada({
  required bool inventarioAtivoDetectado,
  required ResultadoCompat? compat,
  required bool autonomoExplicito,
  bool vinculoControladoBloqueado = false,
}) {
  // B45: um vínculo Controlado salvo que não pôde ser validado (L4) bloqueia
  // mesmo que a L1 não tenha achado inventário (R27 não fura a L4).
  if (vinculoControladoBloqueado && !autonomoExplicito) {
    return DecisaoGravacaoLegada.negar;
  }
  if (!inventarioAtivoDetectado) return DecisaoGravacaoLegada.semVinculo;
  if (podeVincularCentral(compat)) return DecisaoGravacaoLegada.vincular;
  if (autonomoExplicito) return DecisaoGravacaoLegada.semVinculo;
  return DecisaoGravacaoLegada.negar;
}

/// Valores de `inventarioId` que NÃO são inventário central.
bool inventarioIdEhCentral(String? inventarioId) {
  final id = inventarioId ?? '';
  return id.isNotEmpty && id != 'local_autonomo';
}

/// Editar/excluir um lançamento legado existente. Lançamento sem vínculo:
/// sempre. Vinculado: bloqueado quando a compatibilidade JÁ foi avaliada e
/// não liberou (escolher Autônomo não destrava registros vinculados).
bool podeAlterarLancamentoLegado({
  required String? lancInventarioId,
  required ResultadoCompat? compat,
  bool vinculoControladoBloqueado = false,
}) {
  if (!inventarioIdEhCentral(lancInventarioId)) return true;
  if (vinculoControladoBloqueado) return false; // B45
  return compat == null || podeVincularCentral(compat);
}

/// B48: situação do dono persistido de um vínculo Controlado salvo.
enum DonoVinculo {
  /// Salvo por este usuário: a L4 pode validar e restaurar.
  mesmoUsuario,

  /// Salvo por outro usuário neste aparelho: não restaurar.
  outroUsuario,

  /// Sem dono gravado (vínculo de APK anterior ao 3B): não inferir o dono.
  semDono,

  /// Ninguém logado: não restaurar.
  semUsuario,
}

DonoVinculo avaliarDonoVinculo(String? donoSalvo, String? uidAtual) {
  if (uidAtual == null || uidAtual.isEmpty) return DonoVinculo.semUsuario;
  if (donoSalvo == null || donoSalvo.isEmpty) return DonoVinculo.semDono;
  return donoSalvo == uidAtual ? DonoVinculo.mesmoUsuario : DonoVinculo.outroUsuario;
}

/// Mensagem do bloqueio quando o vínculo salvo não pertence ao usuário atual.
String? motivoDonoVinculo(DonoVinculo d) => switch (d) {
      DonoVinculo.mesmoUsuario => null,
      DonoVinculo.outroUsuario =>
        'Vínculo Controlado salvo por outro usuário neste aparelho. Escolha o '
            'inventário de novo para validar, ou escolha Autônomo.',
      DonoVinculo.semDono =>
        'Vínculo Controlado salvo antes desta versão, sem dono registrado. '
            'Escolha o inventário de novo para validar, ou escolha Autônomo.',
      DonoVinculo.semUsuario => 'Nenhum usuário logado.',
    };

/// B52/B53: uma operação assíncrona de vínculo legado (L3, L4, monitor,
/// transição para Autônomo) só produz efeito se continua sendo DO MESMO
/// usuário e da MESMA geração de vínculo em que começou. Qualquer transição
/// nova incrementa a geração e torna as anteriores obsoletas.
bool operacaoVigente({
  required String? uidInicio,
  required String? uidAtual,
  required int geracaoInicio,
  required int geracaoAtual,
}) =>
    resultadoDoMesmoUsuario(uidInicio, uidAtual) && geracaoInicio == geracaoAtual;

/// B47: um resultado assíncrono só vale para o usuário que o iniciou.
bool resultadoDoMesmoUsuario(String? uidInicio, String? uidAtual) =>
    uidInicio != null && uidInicio.isNotEmpty && uidInicio == uidAtual;

// ---------------------------------------------------------------------------
// Filtro de fluxo (B40, B43)
// ---------------------------------------------------------------------------

/// Lê `fluxo_versao` de um documento bruto: ausente ou não numérico = 1
/// (legado), como o `Inventario.fromFirestore`.
int lerFluxoVersao(Map<String, dynamic>? dados) {
  final v = dados?['fluxo_versao'];
  return v is num ? v.toInt() : 1;
}

bool ehFluxo2(Map<String, dynamic>? dados) => lerFluxoVersao(dados) >= 2;

/// B43: entre candidatos ativos JÁ ordenados do mais recente para o mais
/// antigo, devolve o primeiro que NÃO é do fluxo 2. Um inventário do fluxo 2
/// mais novo não esconde um legado mais antigo.
T? escolherLegadoAtivo<T>(List<T> candidatos, int Function(T) fluxoVersao) {
  for (final c in candidatos) {
    if (fluxoVersao(c) < 2) return c;
  }
  return null;
}
