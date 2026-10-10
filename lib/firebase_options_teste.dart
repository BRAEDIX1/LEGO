// lib/firebase_options_teste.dart
//
// Lote 3C (T44): opções do Firebase do projeto de TESTE (lego-teste).
// Android (celular) e Windows (desktop de teste, D16). Sem iOS.
//
// Android: valores do google-services.json do app `com.example.lego.teste`
// (S1/S2, 07/10/2026). O MESMO appId está em `appIdEsperado` em
// lib/config/ambiente.dart (fonte independente, B56): se os dois divergirem,
// o app de teste não abre.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class TesteFirebaseOptions {
  TesteFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return windows;
    }
    throw UnsupportedError(
        'O ambiente de teste do LEGO existe só para Android e Windows.');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA_uHwZx-b3gcSQwyxWQMwMAK4iIrCild8',
    appId: '1:155608278634:android:0aacb8e34d3f1f48e5cc13',
    messagingSenderId: '155608278634',
    projectId: 'lego-teste',
    storageBucket: 'lego-teste.firebasestorage.app',
  );

  /// D16: app Web "LEGO Desktop Teste" do lego-teste (o Windows usa a
  /// configuração Web; registrado em 09/10/2026).
  /// O appId daqui TEM de ser igual ao `appIdEsperadoDesktop(Ambiente.teste)`.
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDrv262kuWIgnZ95Dr2nRGNhPXoAzuIsyg',
    appId: '1:155608278634:web:6ebbd7c38e1e0a7ae5cc13',
    messagingSenderId: '155608278634',
    projectId: 'lego-teste',
    authDomain: 'lego-teste.firebaseapp.com',
    storageBucket: 'lego-teste.firebasestorage.app',
  );
}
