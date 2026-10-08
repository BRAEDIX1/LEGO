// lib/config/ambiente.dart
//
// Lote 3C (D13): em qual ambiente este build roda.
//
// FONTE ÚNICA: o `appFlavor` do Flutter, preenchido pelo próprio `--flavor`
// do build (`prod` ou `homolog`; sem `--flavor`, o `default-flavor: prod` do
// pubspec). Nada mais decide o ambiente;
// o resto do app lê [ambienteAtual].
//
// O desktop roda sem sabor: `appFlavor` nulo → produção.
//
// As funções daqui são puras (sem Firebase nem Hive) e testáveis.

import 'package:flutter/services.dart' show appFlavor;

enum Ambiente { producao, teste }

/// `null` ou `'prod'` → produção; `'homolog'` → teste; qualquer outro → `null`
/// (inválido: o app não abre).
Ambiente? resolverAmbiente(String? flavor) {
  if (flavor == null || flavor == 'prod') return Ambiente.producao;
  // O sabor Android do teste chama-se `homolog`: o AGP proíbe sabores que
  // começam com "test" (B59).
  if (flavor == 'homolog') return Ambiente.teste;
  return null;
}

/// Ambiente deste build, resolvido uma única vez.
final Ambiente? ambienteAtual = resolverAmbiente(appFlavor);

/// Projeto do Firebase que cada ambiente PRECISA usar.
String projetoEsperado(Ambiente ambiente) => switch (ambiente) {
      Ambiente.producao => 'murilo-21h52m',
      Ambiente.teste => 'lego-teste',
    };

/// Pacote Android que cada ambiente PRECISA ter (sabores do build.gradle.kts).
String pacoteEsperado(Ambiente ambiente) => switch (ambiente) {
      Ambiente.producao => 'com.example.lego',
      Ambiente.teste => 'com.example.lego.teste',
    };

// ---------------------------------------------------------------------------
// Portões da inicialização (T45 / B55). Qualquer bloqueio → tela fixa
// "Build inconsistente", sem Hive, login ou sincronização.
// ---------------------------------------------------------------------------

enum MotivoBloqueioInicial {
  ambienteInvalido,
  pacoteDivergente,
  configuracaoIncompleta,
  firebaseFalhou,
  projetoDivergente,
  appIdDivergente,
}

class ResultadoPortao {
  final MotivoBloqueioInicial? motivo;
  final String detalhe;

  const ResultadoPortao.liberado()
      : motivo = null,
        detalhe = '';
  const ResultadoPortao.bloqueado(MotivoBloqueioInicial this.motivo, this.detalhe);

  bool get liberado => motivo == null;

  @override
  String toString() => liberado ? 'liberado' : '${motivo!.name}: $detalhe';
}

/// Marcador dos valores ainda não preenchidos em `firebase_options_teste.dart`.
const String valorNaoPreenchido = 'PREENCHER';

/// Portões 1 e 2: rodam ANTES de `Firebase.initializeApp`.
/// Ambiente inválido não tem opção segura de Firebase para escolher.
/// O pacote é um fato físico do APK: um `.teste` que se ache produção é pego aqui.
ResultadoPortao portaoPreFirebase({
  required Ambiente? ambiente,
  required String? packageName,
}) {
  if (ambiente == null) {
    return const ResultadoPortao.bloqueado(
      MotivoBloqueioInicial.ambienteInvalido,
      'sabor do build não reconhecido',
    );
  }
  final esperado = pacoteEsperado(ambiente);
  if (packageName != esperado) {
    return ResultadoPortao.bloqueado(
      MotivoBloqueioInicial.pacoteDivergente,
      'ambiente ${ambiente.name} exige o pacote $esperado; '
      'este APK é ${packageName ?? "(desconhecido)"}',
    );
  }
  return const ResultadoPortao.liberado();
}

/// appId Android que cada ambiente PRECISA ter (B56). É uma fonte
/// INDEPENDENTE das `FirebaseOptions`: os portões comparam as opções e o app
/// inicializado com este valor, e nunca as opções com elas mesmas.
/// Produção: o app Android `com.example.lego` do projeto `murilo-21h52m`.
/// Teste: o app Android `com.example.lego.teste` do projeto `lego-teste`
/// (S2, 07/10/2026).
String appIdEsperado(Ambiente ambiente) => switch (ambiente) {
      Ambiente.producao => '1:1082826789172:android:ec3446a0b183cd75369561',
      Ambiente.teste => '1:155608278634:android:0aacb8e34d3f1f48e5cc13',
    };

bool _ausenteOuPendente(String? v) =>
    v == null || v.isEmpty || v == valorNaoPreenchido;

/// Portão das opções: roda ANTES de `Firebase.initializeApp` (B56).
/// 1. Campos obrigatórios presentes (projectId, appId, apiKey,
///    messagingSenderId) e o appId esperado já definido.
///    `storageBucket` é opcional (B57): ausente não bloqueia; só o marcador
///    [valorNaoPreenchido] esquecido bloqueia.
/// 2. `projectId` das opções == [projetoEsperado].
/// 3. `appId` das opções == [appIdEsperado].
ResultadoPortao portaoOpcoes({
  required Ambiente ambiente,
  required String projectId,
  required String appId,
  required String apiKey,
  required String messagingSenderId,
  required String? storageBucket,
}) {
  final esperadoApp = appIdEsperado(ambiente);
  final obrigatorios = [projectId, appId, apiKey, messagingSenderId];
  if (obrigatorios.any(_ausenteOuPendente) ||
      _ausenteOuPendente(esperadoApp) ||
      storageBucket == valorNaoPreenchido) {
    return const ResultadoPortao.bloqueado(
      MotivoBloqueioInicial.configuracaoIncompleta,
      'opções do Firebase deste ambiente não preenchidas',
    );
  }
  final projeto = projetoEsperado(ambiente);
  if (projectId != projeto) {
    return ResultadoPortao.bloqueado(
      MotivoBloqueioInicial.projetoDivergente,
      'ambiente ${ambiente.name} exige o projeto $projeto; '
      'as opções apontam para $projectId',
    );
  }
  if (appId != esperadoApp) {
    return ResultadoPortao.bloqueado(
      MotivoBloqueioInicial.appIdDivergente,
      'as opções têm o appId $appId; o ambiente ${ambiente.name} exige '
      '$esperadoApp',
    );
  }
  return const ResultadoPortao.liberado();
}

/// Portão 3: roda DEPOIS de `Firebase.initializeApp`, com o app de fato
/// inicializado (no Android, valores do `google-services.json` nativo).
/// Projeto e appId conferidos de novo contra as fontes independentes.
ResultadoPortao portaoPosFirebase({
  required Ambiente ambiente,
  required String projectId,
  required String appId,
}) {
  final projeto = projetoEsperado(ambiente);
  if (projectId != projeto) {
    return ResultadoPortao.bloqueado(
      MotivoBloqueioInicial.projetoDivergente,
      'ambiente ${ambiente.name} exige o projeto $projeto; '
      'o Firebase iniciou em $projectId',
    );
  }
  final esperadoApp = appIdEsperado(ambiente);
  if (appId != esperadoApp) {
    return ResultadoPortao.bloqueado(
      MotivoBloqueioInicial.appIdDivergente,
      'o Firebase iniciou com o appId $appId; o ambiente ${ambiente.name} '
      'exige $esperadoApp',
    );
  }
  return const ResultadoPortao.liberado();
}
