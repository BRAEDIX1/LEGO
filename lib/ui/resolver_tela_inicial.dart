// lib/ui/resolver_tela_inicial.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:lego/config/fluxo2_config.dart';
import 'package:lego/services/mobile_sync_service.dart';
import 'package:lego/ui/home_page.dart';
import 'package:lego/ui/login_page.dart';
import 'package:lego/ui/mobile/screens/modo_operacao_screen.dart';

/// Regra ÚNICA da tela de entrada após autenticação (B18).
///
/// Chamada por: `_Bootstrapper` (main.dart), login por e-mail, cadastro,
/// login Google (login_page.dart) e fim do FirstSyncScreen.
/// Nenhum outro ponto do app deve abrir a HomePage direto.
///
/// - Chave LEGO_FLUXO2 desligada: HomePage, como antes, mas DEPOIS de
///   inicializar o MobileSyncService para o usuário logado (B44).
/// - Chave ligada e sessão válida do usuário logado: HomePage.
/// - Chave ligada e sem sessão válida: tela de escolha Simples/Completa.
Future<Widget> resolverTelaInicial() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    // Chave desligada: como antes (a HomePage legada lida com isso).
    return Fluxo2Config.habilitado ? const LoginPage() : const HomePage();
  }

  // B44 (3B): o serviço é inicializado para TODO usuário autenticado, antes
  // de decidir o fluxo. Com a chave desligada, isso restaura o modo
  // Controlado salvo e inicia a validação L4 (cold start, login e fim da
  // FirstSyncScreen passam todos por aqui).
  try {
    // Idempotente por usuário: restaura a sessão só se for deste UID (B16).
    await MobileSyncService().inicializar();
  } catch (e) {
    debugPrint('⚠️ Falha ao inicializar a sessão: $e');
  }

  if (!Fluxo2Config.habilitado) return const HomePage();

  final sessao = MobileSyncService().sessaoAtual;
  return (sessao != null && sessao.pertenceA(user.uid))
      ? const HomePage()
      : const ModoOperacaoScreen();
}
