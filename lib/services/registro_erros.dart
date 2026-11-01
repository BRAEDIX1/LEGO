// lib/services/registro_erros.dart
//
// Pacote 1 (P0-06, instrumentação): registro persistente de erros do
// Desktop. Antes não havia nenhum tratador global: um fechamento ou erro não
// deixava rastro no app. Agora cada erro não tratado (Flutter, plataforma ou
// zona) vai para um arquivo de texto local, com data/hora, ambiente e pilha.
//
// Arquivo: <pasta de suporte do app>/logs/lego_erros.log (troca para
// lego_erros.1.log ao passar de 2 MB). Nunca lança erro.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class RegistroErros {
  RegistroErros._();

  static const int tamanhoMaximo = 2 * 1024 * 1024;

  static File? _arquivo;
  static String _ambiente = '?';
  static Future<void> _fila = Future<void>.value();

  /// Caminho do arquivo (null antes de [instalar]).
  static String? get caminho => _arquivo?.path;
  static String? get pasta => _arquivo?.parent.path;

  /// Prepara o arquivo e liga os tratadores globais. Chamar logo depois de
  /// `WidgetsFlutterBinding.ensureInitialized()`, DENTRO da zona do app.
  static Future<void> instalar(String ambiente) async {
    _ambiente = ambiente;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}logs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _arquivo = File('${dir.path}${Platform.pathSeparator}lego_erros.log');
    } catch (e) {
      debugPrint('RegistroErros: sem pasta de log: $e');
    }

    final anteriorFlutter = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails d) {
      registrar('flutter', d.exception, d.stack,
          contexto: d.context?.toDescription());
      if (anteriorFlutter != null) {
        anteriorFlutter(d);
      } else {
        FlutterError.presentError(d);
      }
    };
    PlatformDispatcher.instance.onError = (Object e, StackTrace st) {
      registrar('plataforma', e, st);
      return true; // tratado: o app segue
    };
    await registrarTexto('inicio', 'App iniciado ($ambiente) · '
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  }

  /// Erro com pilha. [origem]: `flutter` | `plataforma` | `zona` | `<tela>`.
  static void registrar(String origem, Object erro, StackTrace? pilha,
      {String? contexto}) {
    debugPrint('⛔ [$origem] $erro');
    final b = StringBuffer()
      ..writeln('=== ${DateTime.now().toIso8601String()} · $_ambiente · '
          '$origem${contexto == null ? '' : ' · $contexto'}')
      ..writeln('$erro');
    if (pilha != null) b.writeln(pilha);
    _gravar(b.toString());
  }

  /// Linha informativa (início, ação relevante).
  static Future<void> registrarTexto(String origem, String texto) {
    _gravar('--- ${DateTime.now().toIso8601String()} · $_ambiente · '
        '$origem · $texto\n');
    return _fila;
  }

  /// Gravações em fila (uma por vez), com troca de arquivo por tamanho.
  static void _gravar(String texto) {
    final f = _arquivo;
    if (f == null) return;
    _fila = _fila.then((_) async {
      try {
        if (f.existsSync() && f.lengthSync() > tamanhoMaximo) {
          final antigo = File(f.path.replaceFirst('.log', '.1.log'));
          if (antigo.existsSync()) antigo.deleteSync();
          f.renameSync(antigo.path);
        }
        await f.writeAsString(texto, mode: FileMode.append, flush: true);
      } catch (_) {
        // registrar nunca pode derrubar o app
      }
    });
  }

  /// Executa [corpo] numa zona que registra erros assíncronos não tratados.
  static Future<void> executarProtegido(Future<void> Function() corpo) {
    final c = Completer<void>();
    runZonedGuarded(() async {
      try {
        await corpo();
      } finally {
        if (!c.isCompleted) c.complete();
      }
    }, (e, st) {
      registrar('zona', e, st);
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }
}
