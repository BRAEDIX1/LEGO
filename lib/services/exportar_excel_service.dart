// lib/services/exportar_excel_service.dart

import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'package:lego/services/relatorio_service.dart';
import 'package:lego/models/divergencia.dart';

/// Serviço para exportação de relatórios em Excel
class ExportarExcelService {
  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _formatoNumero = NumberFormat.decimalPattern('pt_BR');
  final _formatoData = DateFormat('dd/MM/yyyy HH:mm');

  // ==================== EXPORTAÇÃO COMPLETA ====================

  /// Exporta relatório completo com todas as abas
  Future<String> exportarCompleto(ResultadoRelatorio relatorio) async {
    final excel = Excel.createExcel();

    // Remove sheet padrão
    excel.delete('Sheet1');

    // Aba 1: Resumo
    _criarAbaResumo(excel, relatorio);

    // Aba 2: Todos os Itens
    _criarAbaItens(excel, relatorio, 'Todos os Itens', relatorio.itens);

    // Aba 3: Sobras
    _criarAbaItens(excel, relatorio, 'Sobras', relatorio.itensSobra);

    // Aba 4: Faltas
    _criarAbaItens(excel, relatorio, 'Faltas', relatorio.itensFalta);

    // Aba 5: Divergências (se houver)
    if (relatorio.divergencias.isNotEmpty) {
      _criarAbaDivergencias(excel, relatorio);
    }

    // Salva arquivo
    return await _salvarExcel(excel, 'relatorio_completo_${relatorio.codigoInventario}');
  }

  // ==================== EXPORTAÇÃO DE DIVERGÊNCIAS ====================

  /// Exporta apenas divergências
  Future<String> exportarDivergencias(ResultadoRelatorio relatorio) async {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    // Aba de divergências
    _criarAbaDivergencias(excel, relatorio);

    // Aba de itens pendentes
    final pendentes = relatorio.itens
        .where((i) => i.status == StatusApuracao.aguardandoC3)
        .toList();
    _criarAbaItens(excel, relatorio, 'Itens Pendentes', pendentes);

    return await _salvarExcel(excel, 'divergencias_${relatorio.codigoInventario}');
  }

  // ==================== EXPORTAÇÃO FINANCEIRA ====================

  /// Exporta resumo financeiro
  Future<String> exportarFinanceiro(ResultadoRelatorio relatorio) async {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    // Aba de resumo financeiro
    _criarAbaResumoFinanceiro(excel, relatorio);

    // Aba de sobras detalhada
    _criarAbaItens(excel, relatorio, 'Detalhamento Sobras', relatorio.itensSobra);

    // Aba de faltas detalhada
    _criarAbaItens(excel, relatorio, 'Detalhamento Faltas', relatorio.itensFalta);

    // Aba de itens críticos
    final criticos = relatorio.itens
        .where((i) => i.status == StatusApuracao.naoEncontrado)
        .toList();
    if (criticos.isNotEmpty) {
      _criarAbaItens(excel, relatorio, 'Itens Criticos', criticos);
    }

    return await _salvarExcel(excel, 'financeiro_${relatorio.codigoInventario}');
  }

  // ==================== CRIAÇÃO DE ABAS ====================

  void _criarAbaResumo(Excel excel, ResultadoRelatorio relatorio) {
    final sheet = excel['Resumo'];
    final balanco = relatorio.balanco;
    final stats = relatorio.estatisticas;
    int linha = 0;

    // Título
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: linha))
      ..value = TextCellValue('RELATÓRIO DE INVENTÁRIO')
      ..cellStyle = CellStyle(bold: true, fontSize: 14);
    linha += 2;

    // Informações gerais
    _addLinhaResumo(sheet, linha++, 'Código do Inventário', relatorio.codigoInventario);
    _addLinhaResumo(sheet, linha++, 'Data de Geração', _formatoData.format(relatorio.dataGeracao));
    _addLinhaResumo(sheet, linha++, 'Tipo de Relatório', _getTipoRelatorioLabel(relatorio.tipo));
    linha++;

    // Resumo financeiro
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: linha))
      ..value = TextCellValue('RESUMO FINANCEIRO')
      ..cellStyle = CellStyle(bold: true);
    linha++;

    _addLinhaResumo(sheet, linha++, 'Total de Sobras', _formatoMoeda.format(balanco.totalSobras));
    _addLinhaResumo(sheet, linha++, 'Quantidade de Sobras', balanco.quantidadeSobras.toString());
    _addLinhaResumo(sheet, linha++, 'Subtotal de Faltas', _formatoMoeda.format(balanco.subtotalFaltas));
    _addLinhaResumo(sheet, linha++, 'Imposto (21,95%)', _formatoMoeda.format(balanco.impostoFaltas));
    _addLinhaResumo(sheet, linha++, 'Total de Faltas', _formatoMoeda.format(balanco.totalFaltas));
    _addLinhaResumo(sheet, linha++, 'Quantidade de Faltas', balanco.quantidadeFaltas.toString());
    _addLinhaResumo(sheet, linha++, 'SALDO LÍQUIDO', _formatoMoeda.format(balanco.saldoLiquido));
    linha++;

    // Estatísticas
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: linha))
      ..value = TextCellValue('ESTATÍSTICAS')
      ..cellStyle = CellStyle(bold: true);
    linha++;

    _addLinhaResumo(sheet, linha++, 'Total de Itens', stats['total_itens'].toString());
    _addLinhaResumo(sheet, linha++, 'Itens OK', stats['itens_ok'].toString());
    _addLinhaResumo(sheet, linha++, 'Itens com Sobra', stats['itens_sobra'].toString());
    _addLinhaResumo(sheet, linha++, 'Itens com Falta', stats['itens_falta'].toString());
    _addLinhaResumo(sheet, linha++, 'Itens Não Encontrados', stats['itens_nao_encontrados'].toString());
    _addLinhaResumo(sheet, linha++, 'Itens Aguardando C3', stats['itens_aguardando_c3'].toString());

    // Ajusta largura das colunas
    sheet.setColumnWidth(0, 25);
    sheet.setColumnWidth(1, 20);
  }

  void _criarAbaResumoFinanceiro(Excel excel, ResultadoRelatorio relatorio) {
    final sheet = excel['Resumo Financeiro'];
    final balanco = relatorio.balanco;
    int linha = 0;

    // Título
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: linha))
      ..value = TextCellValue('BALANÇO FINANCEIRO DO INVENTÁRIO')
      ..cellStyle = CellStyle(bold: true, fontSize: 14);
    linha += 2;

    // Cabeçalho de sobras
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: linha))
      ..value = TextCellValue('SOBRAS (sem imposto)')
      ..cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColors.green100);
    linha++;

    _addLinhaResumo(sheet, linha++, 'Valor', _formatoMoeda.format(balanco.totalSobras));
    _addLinhaResumo(sheet, linha++, 'Quantidade de itens', balanco.quantidadeSobras.toString());
    linha++;

    // Cabeçalho de faltas
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: linha))
      ..value = TextCellValue('FALTAS (com imposto 21,95%)')
      ..cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColors.red100);
    linha++;

    _addLinhaResumo(sheet, linha++, 'Subtotal (base)', _formatoMoeda.format(balanco.subtotalFaltas));
    _addLinhaResumo(sheet, linha++, 'Imposto (21,95%)', _formatoMoeda.format(balanco.impostoFaltas));
    _addLinhaResumo(sheet, linha++, 'Total com imposto', _formatoMoeda.format(balanco.totalFaltas));
    _addLinhaResumo(sheet, linha++, 'Quantidade de itens', balanco.quantidadeFaltas.toString());
    linha++;

    // Saldo
    final corSaldo = balanco.isPrejuizo ? ExcelColors.red100 : ExcelColors.green100;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: linha))
      ..value = TextCellValue('SALDO LÍQUIDO')
      ..cellStyle = CellStyle(bold: true, backgroundColorHex: corSaldo);
    linha++;

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: linha))
      ..value = TextCellValue(balanco.isPrejuizo ? 'PREJUÍZO' : 'LUCRO');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: linha))
      ..value = TextCellValue(_formatoMoeda.format(balanco.saldoLiquido.abs()))
      ..cellStyle = CellStyle(bold: true);
    linha += 2;

    // Itens críticos
    if (balanco.itensNaoEncontrados > 0) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: linha))
        ..value = TextCellValue('⚠️ ALERTA: ${balanco.itensNaoEncontrados} item(s) não encontrado(s)')
        ..cellStyle = CellStyle(bold: true, fontColorHex: ExcelColors.red);
    }

    sheet.setColumnWidth(0, 30);
    sheet.setColumnWidth(1, 20);
  }

  void _criarAbaItens(
      Excel excel,
      ResultadoRelatorio relatorio,
      String nomeAba,
      List<ItemApurado> itens,
      ) {
    final sheet = excel[nomeAba];
    int linha = 0;

    // Cabeçalho
    final cabecalho = [
      'Código',
      'Descrição',
      'Lote',
      'Qtd Sistema',
      'Qtd Contada',
      'Diferença',
      'Valor Unitário',
      'Impacto Financeiro',
      'Status',
      'Localização',
    ];

    for (var col = 0; col < cabecalho.length; col++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: linha))
        ..value = TextCellValue(cabecalho[col])
        ..cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColors.blue100);
    }
    linha++;

    // Dados
    for (final item in itens) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: linha))
        ..value = TextCellValue(item.codigo);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: linha))
        ..value = TextCellValue(item.descricao);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: linha))
        ..value = TextCellValue(item.lote);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: linha))
        ..value = DoubleCellValue(item.quantidadeSistema);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: linha))
        ..value = DoubleCellValue(item.quantidadeContada);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: linha))
        ..value = DoubleCellValue(item.diferenca);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: linha))
        ..value = DoubleCellValue(item.valorUnitario);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: linha))
        ..value = DoubleCellValue(item.impactoFinanceiro);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: linha))
        ..value = TextCellValue(_getStatusLabel(item.status));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: linha))
        ..value = TextCellValue(item.localizacao ?? '');

      linha++;
    }

    // Ajusta larguras
    sheet.setColumnWidth(0, 15);  // Código
    sheet.setColumnWidth(1, 40);  // Descrição
    sheet.setColumnWidth(2, 12);  // Lote
    sheet.setColumnWidth(3, 12);  // Qtd Sistema
    sheet.setColumnWidth(4, 12);  // Qtd Contada
    sheet.setColumnWidth(5, 12);  // Diferença
    sheet.setColumnWidth(6, 15);  // Valor Unitário
    sheet.setColumnWidth(7, 18);  // Impacto
    sheet.setColumnWidth(8, 15);  // Status
    sheet.setColumnWidth(9, 20);  // Localização
  }

  void _criarAbaDivergencias(Excel excel, ResultadoRelatorio relatorio) {
    final sheet = excel['Divergencias C1 vs C2'];
    int linha = 0;

    // Cabeçalho
    final cabecalho = [
      'Código',
      'Descrição',
      'Total C1',
      'Total C2',
      'Diferença',
      'Qtd Locais Divergentes',
      'Significativa',
    ];

    for (var col = 0; col < cabecalho.length; col++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: linha))
        ..value = TextCellValue(cabecalho[col])
        ..cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColors.orange100);
    }
    linha++;

    // Dados
    for (final div in relatorio.divergencias) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: linha))
        ..value = TextCellValue(div.codigo);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: linha))
        ..value = TextCellValue(div.descricao);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: linha))
        ..value = DoubleCellValue(div.totalContagem1);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: linha))
        ..value = DoubleCellValue(div.totalContagem2);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: linha))
        ..value = DoubleCellValue(div.diferencaTotal);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: linha))
        ..value = IntCellValue(div.quantidadeLocaisDivergentes);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: linha))
        ..value = TextCellValue(div.isSignificativa ? 'SIM' : 'Não');

      linha++;
    }

    // Ajusta larguras
    sheet.setColumnWidth(0, 15);
    sheet.setColumnWidth(1, 40);
    sheet.setColumnWidth(2, 12);
    sheet.setColumnWidth(3, 12);
    sheet.setColumnWidth(4, 12);
    sheet.setColumnWidth(5, 20);
    sheet.setColumnWidth(6, 12);

    // Aba com detalhes por localização
    if (relatorio.divergencias.any((d) => d.locaisDivergentes.isNotEmpty)) {
      _criarAbaLocaisDivergentes(excel, relatorio);
    }
  }

  void _criarAbaLocaisDivergentes(Excel excel, ResultadoRelatorio relatorio) {
    final sheet = excel['Locais Divergentes'];
    int linha = 0;

    // Cabeçalho
    final cabecalho = ['Código', 'Descrição', 'Localização', 'Qtd C1', 'Qtd C2', 'Diferença', 'Tipo'];

    for (var col = 0; col < cabecalho.length; col++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: linha))
        ..value = TextCellValue(cabecalho[col])
        ..cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColors.yellow100);
    }
    linha++;

    // Dados
    for (final div in relatorio.divergencias) {
      for (final local in div.locaisDivergentes.values) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: linha))
          ..value = TextCellValue(div.codigo);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: linha))
          ..value = TextCellValue(div.descricao);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: linha))
          ..value = TextCellValue(local.localizacao);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: linha))
          ..value = DoubleCellValue(local.quantidadeC1);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: linha))
          ..value = DoubleCellValue(local.quantidadeC2);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: linha))
          ..value = DoubleCellValue(local.diferenca);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: linha))
          ..value = TextCellValue(_getTipoDivergenciaLabel(local.tipo));

        linha++;
      }
    }

    // Ajusta larguras
    sheet.setColumnWidth(0, 15);
    sheet.setColumnWidth(1, 35);
    sheet.setColumnWidth(2, 20);
    sheet.setColumnWidth(3, 10);
    sheet.setColumnWidth(4, 10);
    sheet.setColumnWidth(5, 10);
    sheet.setColumnWidth(6, 15);
  }

  // ==================== HELPERS ====================

  void _addLinhaResumo(Sheet sheet, int linha, String label, String valor) {
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: linha))
      ..value = TextCellValue(label);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: linha))
      ..value = TextCellValue(valor);
  }

  String _getTipoRelatorioLabel(TipoRelatorio tipo) {
    switch (tipo) {
      case TipoRelatorio.simples:
        return 'Contagem Simples';
      case TipoRelatorio.divergenciasC2:
        return 'Divergências (C1 vs C2)';
      case TipoRelatorio.apuracaoFinal:
        return 'Apuração Final';
    }
  }

  String _getStatusLabel(StatusApuracao status) {
    switch (status) {
      case StatusApuracao.ok:
        return 'OK';
      case StatusApuracao.sobra:
        return 'Sobra';
      case StatusApuracao.falta:
        return 'Falta';
      case StatusApuracao.naoEncontrado:
        return 'Não Encontrado';
      case StatusApuracao.naoNoSistema:
        return 'Não no Sistema';
      case StatusApuracao.aguardandoC3:
        return 'Aguardando C3';
    }
  }

  Future<String> _salvarExcel(Excel excel, String nomeBase) async {
    try {
      // Gera nome do arquivo com timestamp
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final nomeArquivo = '${nomeBase}_$timestamp.xlsx';

      // Obtém diretório de downloads ou documentos
      Directory diretorio;
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        // Desktop: usa diretório de downloads
        final downloads = await getDownloadsDirectory();
        diretorio = downloads ?? await getApplicationDocumentsDirectory();
      } else {
        // Mobile: usa documentos
        diretorio = await getApplicationDocumentsDirectory();
      }

      final caminho = '${diretorio.path}/$nomeArquivo';
      final arquivo = File(caminho);

      // Salva
      final bytes = excel.save();
      if (bytes != null) {
        await arquivo.writeAsBytes(bytes);
        debugPrint('✅ Excel salvo: $caminho');
        return caminho;
      } else {
        throw Exception('Falha ao gerar bytes do Excel');
      }
    } catch (e) {
      debugPrint('❌ Erro ao salvar Excel: $e');
      rethrow;
    }
  }
}

/// Helper para obter label do tipo de divergência
String _getTipoDivergenciaLabel(TipoDivergenciaLocal tipo) {
  switch (tipo) {
    case TipoDivergenciaLocal.apenasC1:
      return 'Apenas em C1';
    case TipoDivergenciaLocal.apenasC2:
      return 'Apenas em C2';
    case TipoDivergenciaLocal.c1Maior:
      return 'C1 > C2';
    case TipoDivergenciaLocal.c2Maior:
      return 'C2 > C1';
  }
}

/// Cores para o Excel (usando formato ARGB hex)
class ExcelColors {
  static ExcelColor get blue100 => ExcelColor.fromHexString('FFBBDEFB');
  static ExcelColor get green100 => ExcelColor.fromHexString('FFC8E6C9');
  static ExcelColor get red100 => ExcelColor.fromHexString('FFFFCDD2');
  static ExcelColor get orange100 => ExcelColor.fromHexString('FFFFE0B2');
  static ExcelColor get yellow100 => ExcelColor.fromHexString('FFFFF9C4');
  static ExcelColor get red => ExcelColor.fromHexString('FFF44336');
}