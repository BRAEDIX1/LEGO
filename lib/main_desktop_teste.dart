// lib/main_desktop_teste.dart
//
// D16-1: ponto de entrada do LEGO TESTE no desktop (projeto lego-teste).
// Build:  flutter build windows -t lib/main_desktop_teste.dart
// O ambiente está fixado aqui; não depende de nenhum parâmetro de build.

import 'package:lego/config/ambiente.dart';
import 'package:lego/main_desktop.dart' show iniciarLegoDesktop;

Future<void> main() => iniciarLegoDesktop(Ambiente.teste);
