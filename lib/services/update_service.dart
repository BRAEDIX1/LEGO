// lib/services/update_service.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class ReleaseInfo {
  final String versao;
  final String descricao;
  final String apkUrl;

  const ReleaseInfo({
    required this.versao,
    required this.descricao,
    required this.apkUrl,
  });
}

class UpdateService {
  static const _apiUrl =
      'https://api.github.com/repos/BRAEDIX1/LEGO/releases/latest';

  /// Verifica se há uma versão nova disponível no GitHub.
  /// Retorna [ReleaseInfo] se houver atualização, ou null se estiver na versão mais recente.
  Future<ReleaseInfo?> verificarAtualizacao() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final versaoInstalada = packageInfo.version; // ex: "1.0.0"

      final response = await http
          .get(Uri.parse(_apiUrl), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (json['tag_name'] as String? ?? '').replaceAll('v', '');
      final body = json['body'] as String? ?? '';

      if (tagName.isEmpty) return null;

      // Compara versões
      if (!_isNewer(tagName, versaoInstalada)) return null;

      // Busca o .apk nos assets da release
      final assets = json['assets'] as List<dynamic>? ?? [];
      final apkAsset = assets.firstWhere(
        (a) => (a['name'] as String).endsWith('.apk'),
        orElse: () => null,
      );
      if (apkAsset == null) return null;

      return ReleaseInfo(
        versao: tagName,
        descricao: body,
        apkUrl: apkAsset['browser_download_url'] as String,
      );
    } catch (e) {
      debugPrint('[UpdateService] Erro ao verificar atualização: $e');
      return null;
    }
  }

  /// Baixa o .apk e reporta o progresso via stream (0.0 a 1.0).
  Stream<double> baixarApk(
    String url, {
    required void Function(File arquivo) onConcluido,
  }) async* {
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await request.send();
      final total = response.contentLength ?? 0;

      final dir = await getTemporaryDirectory();
      final arquivo = File('${dir.path}/lego_update.apk');
      final sink = arquivo.openWrite();

      int recebido = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        recebido += chunk.length;
        if (total > 0) yield recebido / total;
      }
      await sink.close();

      yield 1.0;
      onConcluido(arquivo);
    } catch (e) {
      debugPrint('[UpdateService] Erro ao baixar APK: $e');
      yield -1.0; // sinal de erro
    }
  }

  /// Compara duas versões semânticas. Retorna true se [nova] > [atual].
  bool _isNewer(String nova, String atual) {
    final n = _partes(nova);
    final a = _partes(atual);
    for (int i = 0; i < 3; i++) {
      if (n[i] > a[i]) return true;
      if (n[i] < a[i]) return false;
    }
    return false;
  }

  List<int> _partes(String v) {
    final partes = v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (partes.length < 3) partes.add(0);
    return partes;
  }
}
