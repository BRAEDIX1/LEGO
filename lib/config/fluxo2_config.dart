// lib/config/fluxo2_config.dart

import 'package:lego/config/ambiente.dart';

/// Chave de ativação do fluxo 2 (Contagem Completa com máquina de estados).
///
/// DESLIGADA por padrão. Enquanto estiver desligada, nenhuma tela cria
/// inventário `fluxo_versao: 2`: o wizard do desktop segue no fluxo legado.
///
/// Parecer do revisor (Lote 1, §8.3): o fluxo 2 não pode ir para uso real
/// antes de a Fase 3 ligar o home_page.dart à sessão controlada.
///
/// 3C (T49): trava de intenção. O Inventário 001 nasceu de um build de
/// PRODUÇÃO com `LEGO_FLUXO2=true`. Agora:
///   - teste:    `LEGO_FLUXO2=true` basta;
///   - produção: `LEGO_FLUXO2=true` E `LEGO_FLUXO2_PRODUCAO=true`;
///   - ambiente inválido: sempre desligado.
/// O ambiente NÃO é resolvido aqui: vem de [ambienteAtual] (fonte única).
///
/// Comandos:
///   flutter build apk --flavor homolog --dart-define=LEGO_FLUXO2=true
///   flutter build apk --dart-define=LEGO_FLUXO2=true \
///                     --dart-define=LEGO_FLUXO2_PRODUCAO=true   (só na N+1 do 3B)
class Fluxo2Config {
  Fluxo2Config._();

  static const bool _flag =
      bool.fromEnvironment('LEGO_FLUXO2', defaultValue: false);
  static const bool _flagProducao =
      bool.fromEnvironment('LEGO_FLUXO2_PRODUCAO', defaultValue: false);

  static bool get habilitado => fluxo2Habilitado(
        ambiente: ambienteAtual,
        flag: _flag,
        flagProducao: _flagProducao,
      );
}

/// Regra pura da T49.
bool fluxo2Habilitado({
  required Ambiente? ambiente,
  required bool flag,
  required bool flagProducao,
}) {
  return switch (ambiente) {
    null => false,
    Ambiente.teste => flag,
    Ambiente.producao => flag && flagProducao,
  };
}
