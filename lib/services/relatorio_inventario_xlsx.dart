// lib/services/relatorio_inventario_xlsx.dart
//
// Grava as abas do relatório (relatorio_inventario.dart) num .xlsx, com o
// pacote `excel` que o projeto já usa.

import 'package:excel/excel.dart';

import 'package:lego/services/relatorio_inventario.dart';

CellValue? _celula(Object? v) {
  if (v == null) return null;
  if (v is int) return IntCellValue(v);
  if (v is double) return DoubleCellValue(v);
  if (v is DateTime) {
    return DateCellValue(year: v.year, month: v.month, day: v.day);
  }
  return TextCellValue(v.toString());
}

/// Bytes do .xlsx. Null se o pacote não conseguir gerar.
List<int>? gerarXlsx(List<AbaRelatorio> abas) {
  final excel = Excel.createExcel();
  final padrao = excel.getDefaultSheet();
  final negrito = CellStyle(bold: true);

  for (final aba in abas) {
    final sheet = excel[aba.nome];
    // Posição explícita (updateCell): linha em branco do modelo não some.
    for (var r = 0; r < aba.linhas.length; r++) {
      final titulo = r == aba.linhaCabecalho ||
          (r == 0 && aba.linhaCabecalho > 0);
      final linha = aba.linhas[r];
      for (var c = 0; c < linha.length; c++) {
        final v = _celula(linha[c]);
        if (v == null) continue;
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
          v,
          cellStyle: titulo ? negrito : null,
        );
      }
    }
  }
  if (abas.isNotEmpty) {
    excel.setDefaultSheet(abas.first.nome);
    if (padrao != null && !abas.any((a) => a.nome == padrao)) {
      excel.delete(padrao);
    }
  }
  return excel.save();
}
