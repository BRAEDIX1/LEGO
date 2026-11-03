// lib/services/relatorio_inventario_xlsx.dart
//
// Grava as abas do relatório (relatorio_inventario.dart) num .xlsx, com o
// pacote `excel` que o projeto já usa.
//
// Abas "C3 Consolidado [tipo]" e "Final [tipo]": formatação definida pelo
// Djalma em 13/10/2026 (Arial 10, título mesclado, cabeçalho azul, bordas,
// linhas com C3 em amarelo, larguras, cor da aba, painel congelado e filtro).
// Onde a aba traz fórmulas ([AbaRelatorio.formulas]) elas são gravadas no
// lugar do valor: corrigir a "C3 consolidada" no Excel recalcula Final,
// volume e a aba Final.

import 'dart:convert';

import 'package:archive/archive.dart'
    show Archive, ArchiveFile, ZipDecoder, ZipEncoder;
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

/// Abas com o formato do Djalma.
bool abaFormatada(AbaRelatorio a) =>
    a.nome.startsWith('C3 Consolidado') ||
    (a.nome.startsWith('Final') && !a.nome.startsWith('Final por Local'));

const _azul = '#1F4E78';
const _amarelo = '#FFF2CC';
const _laranja = '#FCE4D6';
const _corAba = 'FFFFFFCC';

double _largura(String cabecalho) => switch (cabecalho) {
      'Código' => 9.8,
      'Descrição' => 45.8,
      'Situação da C3' => 27.4,
      'Origem' => 13.8,
      _ => 11.8,
    };

String _letra(int c) => String.fromCharCode(65 + c);

/// Bytes do .xlsx. Null se o pacote não conseguir gerar.
List<int>? gerarXlsx(List<AbaRelatorio> abas) {
  final excel = Excel.createExcel();
  final padrao = excel.getDefaultSheet();
  final fino = Border(
      borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.black);

  CellStyle estilo({
    bool negrito = false,
    ExcelColor fonte = ExcelColor.black,
    ExcelColor fundo = ExcelColor.none,
    HorizontalAlign h = HorizontalAlign.Left,
    VerticalAlign v = VerticalAlign.Bottom,
    bool quebra = false,
    bool borda = false,
  }) =>
      CellStyle(
        fontFamily: 'Arial',
        fontSize: 10,
        bold: negrito,
        fontColorHex: fonte,
        backgroundColorHex: fundo,
        horizontalAlign: h,
        verticalAlign: v,
        textWrapping: quebra ? TextWrapping.WrapText : null,
        leftBorder: borda ? fino : null,
        rightBorder: borda ? fino : null,
        topBorder: borda ? fino : null,
        bottomBorder: borda ? fino : null,
      );

  final negrito = CellStyle(bold: true);
  final cabecalhoAzul = estilo(
    negrito: true,
    fonte: ExcelColor.fromHexString('#FFFFFF'),
    fundo: ExcelColor.fromHexString(_azul),
    h: HorizontalAlign.Center,
    v: VerticalAlign.Top,
    quebra: true,
    borda: true,
  );
  final extras = <String, _Extras>{};

  for (final aba in abas) {
    final sheet = excel[aba.nome];
    final fmt = abaFormatada(aba);
    final cab = aba.linhaCabecalho;
    final ncol = aba.linhas.isEmpty
        ? 0
        : aba.linhas.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    final centrar = <int>{
      if (fmt && aba.linhas.isNotEmpty)
        for (var c = 0; c < aba.linhas[cab].length; c++)
          if (const ['Código', 'Lote', 'Prateleira', 'Prateleiras']
              .contains(aba.linhas[cab][c]))
            c,
    };

    for (var r = 0; r < aba.linhas.length; r++) {
      final linha = aba.linhas[r];
      final ehCab = r == cab;
      final ehTitulo = r < cab && linha.isNotEmpty;
      final ehDado = r > cab;
      final comC3 = ehDado && linhaComC3(aba, linha);
      final parcial = fmt &&
          ehDado &&
          linha.isNotEmpty &&
          '${linha.last}'.startsWith('PARCIAL');

      CellStyle? estiloDe(int c) {
        if (!fmt) {
          return (ehCab || (r == 0 && cab > 0)) ? negrito : null;
        }
        if (ehCab) return cabecalhoAzul;
        if (ehTitulo) {
          return estilo(
              negrito: r == 0,
              quebra: aba.nome.startsWith('C3 Consolidado'));
        }
        if (!ehDado) return estilo();
        return estilo(
          fundo: comC3
              ? ExcelColor.fromHexString(_amarelo)
              : parcial
                  ? ExcelColor.fromHexString(_laranja)
                  : ExcelColor.none,
          h: centrar.contains(c) ? HorizontalAlign.Center : HorizontalAlign.Left,
          borda: true,
        );
      }

      // Linhas de dados de abas formatadas: todas as colunas, mesmo vazias,
      // para a grade e o amarelo ficarem completos.
      final ate = (fmt && (ehDado || ehCab)) ? ncol : linha.length;
      for (var c = 0; c < ate; c++) {
        final formula = aba.formulas[(r, c)];
        final v = formula != null
            ? FormulaCellValue(formula)
            : _celula(c < linha.length ? linha[c] : null);
        if (v == null && !(fmt && (ehDado || ehCab))) continue;
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
          v,
          cellStyle: estiloDe(c),
        );
      }
    }

    if (fmt && aba.linhas.isNotEmpty && ncol > 0) {
      for (var c = 0; c < ncol; c++) {
        final h = c < aba.linhas[cab].length ? '${aba.linhas[cab][c]}' : '';
        sheet.setColumnWidth(c, _largura(h));
      }
      sheet.setRowHeight(cab, 39.6);
      for (var r = 0; r < cab; r++) {
        if (aba.linhas[r].isEmpty) continue;
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
          CellIndex.indexByColumnRow(columnIndex: ncol - 1, rowIndex: r),
        );
      }
      extras[aba.nome] = _Extras(
        congelarAbaixoDe: cab + 1,
        filtro: 'A${cab + 1}:${_letra(ncol - 1)}${aba.linhas.length}',
      );
    }
  }
  if (abas.isNotEmpty) {
    excel.setDefaultSheet(abas.first.nome);
    if (padrao != null && !abas.any((a) => a.nome == padrao)) {
      excel.delete(padrao);
    }
  }
  final bytes = excel.save();
  if (bytes == null) return null;
  return extras.isEmpty ? bytes : _posProcessar(bytes, extras);
}

class _Extras {
  /// Número de linhas congeladas (cabeçalho incluso).
  final int congelarAbaixoDe;
  final String filtro;
  const _Extras({required this.congelarAbaixoDe, required this.filtro});
}

/// O pacote `excel` não grava cor da aba, painel congelado nem filtro.
/// Acrescenta direto no XML de cada aba. Qualquer falha devolve o arquivo
/// original (sem esses três detalhes), nunca um arquivo quebrado.
List<int> _posProcessar(List<int> bytes, Map<String, _Extras> porAba) {
  try {
    final zip = ZipDecoder().decodeBytes(bytes);
    String? ler(String nome) {
      for (final f in zip.files) {
        if (f.name == nome) return utf8.decode(f.content as List<int>);
      }
      return null;
    }

    final wb = ler('xl/workbook.xml');
    final rels = ler('xl/_rels/workbook.xml.rels');
    if (wb == null || rels == null) return bytes;

    // id da relação -> arquivo
    final alvoDoId = <String, String>{};
    for (final m in RegExp(r'<Relationship\b[^>]*>').allMatches(rels)) {
      final tag = m.group(0)!;
      final id = RegExp(r'\bId="([^"]*)"').firstMatch(tag)?.group(1);
      var alvo = RegExp(r'\bTarget="([^"]*)"').firstMatch(tag)?.group(1);
      if (id == null || alvo == null) continue;
      if (alvo.startsWith('/')) alvo = alvo.substring(1);
      if (!alvo.startsWith('xl/')) alvo = 'xl/$alvo';
      alvoDoId[id] = alvo;
    }
    // arquivo da aba -> extras
    final porArquivo = <String, _Extras>{};
    for (final m in RegExp(r'<sheet\b[^>]*>').allMatches(wb)) {
      final tag = m.group(0)!;
      final nome = RegExp(r'\sname="([^"]*)"').firstMatch(tag)?.group(1);
      final rid = RegExp(r'\br:id="([^"]*)"').firstMatch(tag)?.group(1);
      if (nome == null || rid == null) continue;
      final ex = porAba[nome];
      final arq = alvoDoId[rid];
      if (ex != null && arq != null) porArquivo[arq] = ex;
    }
    if (porArquivo.isEmpty) return bytes;

    final novo = Archive();
    for (final f in zip.files) {
      final ex = porArquivo[f.name];
      if (ex == null) {
        novo.addFile(f);
        continue;
      }
      final xml = _ajustarAba(utf8.decode(f.content as List<int>), ex);
      final b = utf8.encode(xml);
      novo.addFile(ArchiveFile(f.name, b.length, b));
    }
    return ZipEncoder().encode(novo) ?? bytes;
  } catch (_) {
    return bytes;
  }
}

String _ajustarAba(String xml, _Extras ex) {
  var s = xml;
  // 1) cor da aba: sheetPr é o primeiro filho de <worksheet>.
  if (!s.contains('<sheetPr')) {
    final i = s.indexOf('<worksheet');
    final fim = i < 0 ? -1 : s.indexOf('>', i);
    if (fim > 0) {
      s = '${s.substring(0, fim + 1)}'
          '<sheetPr><tabColor rgb="$_corAba"/></sheetPr>'
          '${s.substring(fim + 1)}';
    }
  }
  // 2) painel congelado abaixo do cabeçalho.
  if (!s.contains('<pane ')) {
    final topo = ex.congelarAbaixoDe + 1;
    final pane = '<pane ySplit="${ex.congelarAbaixoDe}" topLeftCell="A$topo" '
        'activePane="bottomLeft" state="frozen"/>'
        '<selection pane="bottomLeft" activeCell="A$topo" sqref="A$topo"/>';
    final m = RegExp(r'<sheetView\b([^>]*?)(/?)>').firstMatch(s);
    if (m != null) {
      final atributos = m.group(1)!;
      final novo = m.group(2) == '/'
          ? '<sheetView$atributos>$pane</sheetView>'
          : '<sheetView$atributos>$pane';
      s = s.replaceRange(m.start, m.end, novo);
    }
  }
  // 3) filtro: logo depois de </sheetData> (antes de mergeCells).
  if (!s.contains('<autoFilter')) {
    const marca = '</sheetData>';
    final i = s.indexOf(marca);
    if (i >= 0) {
      s = s.replaceRange(
          i + marca.length, i + marca.length, '<autoFilter ref="${ex.filtro}"/>');
    }
  }
  return s;
}
