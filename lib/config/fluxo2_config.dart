// lib/config/fluxo2_config.dart

/// Chave de ativação do fluxo 2 (Contagem Completa com máquina de estados).
///
/// DESLIGADA por padrão. Enquanto estiver desligada, nenhuma tela cria
/// inventário `fluxo_versao: 2`: o wizard do desktop segue no fluxo legado.
///
/// Parecer do revisor (Lote 1, §8.3): o fluxo 2 não pode ir para uso real
/// antes de a Fase 3 ligar o home_page.dart à sessão controlada.
///
/// Para ligar em desenvolvimento:
///   flutter run --dart-define=LEGO_FLUXO2=true
///   flutter build apk --dart-define=LEGO_FLUXO2=true
class Fluxo2Config {
  Fluxo2Config._();

  static const bool habilitado =
      bool.fromEnvironment('LEGO_FLUXO2', defaultValue: false);
}
