// lib/firebase_options_teste.dart
//
// Lote 3C (T44): opções do Firebase do projeto de TESTE (lego-teste).
// Só Android: o ambiente de teste não tem desktop nem iOS neste lote (D16).
//
// Valores do google-services.json do app `com.example.lego.teste`
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
    throw UnsupportedError(
        'O ambiente de teste do LEGO existe só para Android.');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA_uHwZx-b3gcSQwyxWQMwMAK4iIrCild8',
    appId: '1:155608278634:android:0aacb8e34d3f1f48e5cc13',
    messagingSenderId: '155608278634',
    projectId: 'lego-teste',
    storageBucket: 'lego-teste.firebasestorage.app',
  );
}
