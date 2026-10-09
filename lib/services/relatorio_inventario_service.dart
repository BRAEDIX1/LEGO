// lib/services/relatorio_inventario_service.dart
//
// Carrega os dados do inventário e grava o relatório .xlsx no aparelho
// (formato do modelo do Djalma). Exige internet (lê do servidor).

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

import 'package:lego/models/inventario.dart';
import 'package:lego/services/comparativo.dart';
import 'package:lego/services/comparativo_rodadas_service.dart';
import 'package:lego/services/relatorio_inventario.dart';
import 'package:lego/services/relatorio_inventario_xlsx.dart';

class RelatorioInventarioService {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final ComparativoRodadasService _cmp = ComparativoRodadasService();

  /// Gera o .xlsx e devolve o caminho do arquivo.
  Future<String> exportar(String inventarioId) async {
    final inv = Inventario.fromFirestore(await _fs
        .collection('inventarios')
        .doc(inventarioId)
        .get(const GetOptions(source: Source.server)));
    final tipo = NaturezaRotulo.deNome(inv.naturezaContagem);
    final (raw1, res1) = await _cmp.carregarRodadaCompleta(inventarioId, Rodadas.c1);
    final (raw2, res2) = await _cmp.carregarRodadaCompleta(inventarioId, Rodadas.c2);
    final linhas = await _cmp.lerComparativo(inventarioId);
    final agora = DateTime.now();

    final abas = montarRelatorio(
      numero: inv.numeroFormatado,
      tipo: tipo,
      geradoEm: agora,
      lancsC1: raw1,
      lancsC2: raw2,
      resumoC1: res1,
      resumoC2: res2,
      comparativo: linhas,
    );
    final bytes = gerarXlsx(abas);
    if (bytes == null) throw Exception('não foi possível gerar o .xlsx');

    Directory? dir;
    try {
      dir = await getExternalStorageDirectory();
    } catch (_) {} // só existe no Android
    dir ??= await getApplicationDocumentsDirectory();
    String dd(int v) => v.toString().padLeft(2, '0');
    final nome = 'LEGO_Inventario_${inv.numeroFormatado}_'
        '${agora.year}${dd(agora.month)}${dd(agora.day)}_'
        '${dd(agora.hour)}${dd(agora.minute)}.xlsx';
    final arq = File('${dir.path}/$nome');
    await arq.writeAsBytes(bytes, flush: true);
    return arq.path;
  }
}
