// lib/services/excel_parser_service.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

/// Resultado do parsing de um arquivo Excel de estoque
class ParseResult {
  final List<ItemEstoque> itens;
  final List<String> avisos;
  final List<String> erros;
  final int linhasProcessadas;
  final int linhasIgnoradas;
  final String? nomeArquivo;

  ParseResult({
    required this.itens,
    this.avisos = const [],
    this.erros = const [],
    this.linhasProcessadas = 0,
    this.linhasIgnoradas = 0,
    this.nomeArquivo,
  });

  bool get sucesso => erros.isEmpty;
  bool get temAvisos => avisos.isNotEmpty;

  /// Resumo para exibição
  String get resumo {
    if (!sucesso) return 'Falha: ${erros.length} erro(s)';
    final avisoTxt = temAvisos ? ' (${avisos.length} avisos)' : '';
    return '$linhasProcessadas itens processados$avisoTxt';
  }
}

/// Item de estoque extraído do Excel
class ItemEstoque {
  final String codigo;
  final String descricao;
  final String lote;
  final double quantidade;
  final double valorTotal;
  final double valorUnitario;
  final int linhaOriginal;

  ItemEstoque({
    required this.codigo,
    required this.descricao,
    required this.lote,
    required this.quantidade,
    required this.valorTotal,
    required this.valorUnitario,
    required this.linhaOriginal,
  });

  /// Chave única: codigo + lote (mesmo código pode ter múltiplos lotes)
  String get chaveUnica => lote.isEmpty ? codigo : '${codigo}_$lote';

  /// Converte para Map (formato Firestore)
  Map<String, dynamic> toMap() {
    return {
      'codigo': codigo,
      'descricao': descricao,
      'lote': lote,
      'quantidade': quantidade,
      'valor_total': valorTotal,
      'valor_unitario': valorUnitario,
    };
  }

  @override
  String toString() => 'ItemEstoque($codigo, lote: $lote, qtd: $quantidade)';
}

/// Serviço para parsing de arquivos Excel de estoque
///
/// ESTRUTURA FIXA DO "CARTUCHO":
/// - Coluna A (0): Código do material
/// - Coluna B (1): Descrição
/// - Coluna E (4): Lote (pode ser vazio)
/// - Coluna F (5): Quantidade (saldo do estoque)
/// - Coluna H (7): Valor total
/// - Calculado: Valor unitário = H ÷ F
///
/// Chave única: Código + Lote
class ExcelParserService {

  // Índices das colunas (0-based)
  static const int _colCodigo = 0;      // A
  static const int _colDescricao = 1;   // B
  static const int _colLote = 4;        // E
  static const int _colQuantidade = 5;  // F
  static const int _colValorTotal = 7;  // H

  // Linha onde começam os dados (após cabeçalho)
  static const int _linhaInicio = 1; // 0 = cabeçalho, 1 = primeiro dado

  /// Processa arquivo Excel a partir de bytes
  Future<ParseResult> processarBytes(Uint8List bytes, {String? nomeArquivo}) async {
    try {
      final excel = Excel.decodeBytes(bytes);
      return _processarExcel(excel, nomeArquivo: nomeArquivo);
    } catch (e) {
      debugPrint('❌ Erro ao decodificar Excel: $e');
      return ParseResult(
        itens: [],
        erros: ['Erro ao ler arquivo: $e'],
        nomeArquivo: nomeArquivo,
      );
    }
  }

  /// Processa arquivo Excel a partir de caminho (desktop)
  Future<ParseResult> processarArquivo(String caminho) async {
    try {
      final file = File(caminho);
      if (!await file.exists()) {
        return ParseResult(
          itens: [],
          erros: ['Arquivo não encontrado: $caminho'],
          nomeArquivo: caminho.split('/').last,
        );
      }

      final bytes = await file.readAsBytes();
      return processarBytes(bytes, nomeArquivo: caminho.split('/').last);
    } catch (e) {
      debugPrint('❌ Erro ao ler arquivo: $e');
      return ParseResult(
        itens: [],
        erros: ['Erro ao ler arquivo: $e'],
      );
    }
  }

  /// Processa o Excel já decodificado
  ParseResult _processarExcel(Excel excel, {String? nomeArquivo}) {
    final itens = <ItemEstoque>[];
    final avisos = <String>[];
    final erros = <String>[];
    int linhasIgnoradas = 0;

    // Pega primeira sheet (ou a única)
    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName];

    if (sheet == null || sheet.rows.isEmpty) {
      return ParseResult(
        itens: [],
        erros: ['Planilha vazia ou não encontrada'],
        nomeArquivo: nomeArquivo,
      );
    }

    debugPrint('📊 Processando sheet: $sheetName (${sheet.rows.length} linhas)');

    // Valida estrutura mínima
    if (sheet.rows.length < 2) {
      return ParseResult(
        itens: [],
        erros: ['Arquivo deve ter pelo menos cabeçalho + 1 linha de dados'],
        nomeArquivo: nomeArquivo,
      );
    }

    // Valida colunas necessárias (verifica cabeçalho)
    final cabecalho = sheet.rows[0];
    final validacaoColunas = _validarColunas(cabecalho);
    if (validacaoColunas != null) {
      avisos.add(validacaoColunas);
    }

    // Processa cada linha de dados
    for (int i = _linhaInicio; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      final linhaExcel = i + 1; // Para mensagens (1-based como no Excel)

      try {
        final item = _processarLinha(row, linhaExcel);

        if (item == null) {
          linhasIgnoradas++;
          continue;
        }

        // Validações de negócio
        if (item.quantidade < 0) {
          avisos.add('Linha $linhaExcel: Quantidade negativa (${item.quantidade})');
        }
        if (item.valorTotal < 0) {
          avisos.add('Linha $linhaExcel: Valor total negativo (${item.valorTotal})');
        }

        itens.add(item);

      } catch (e) {
        erros.add('Linha $linhaExcel: $e');
      }
    }

    // Verifica duplicatas
    final duplicatas = _verificarDuplicatas(itens);
    if (duplicatas.isNotEmpty) {
      avisos.addAll(duplicatas);
    }

    debugPrint('✅ Parsing concluído: ${itens.length} itens, ${avisos.length} avisos, ${erros.length} erros');

    return ParseResult(
      itens: itens,
      avisos: avisos,
      erros: erros,
      linhasProcessadas: itens.length,
      linhasIgnoradas: linhasIgnoradas,
      nomeArquivo: nomeArquivo,
    );
  }

  /// Valida se as colunas esperadas estão presentes
  String? _validarColunas(List<Data?> cabecalho) {
    // Verifica se tem colunas suficientes
    if (cabecalho.length < 8) {
      return 'Aviso: Arquivo com menos de 8 colunas. Esperado: A=Código, B=Descrição, E=Lote, F=Quantidade, H=Valor';
    }
    return null;
  }

  /// Processa uma linha e retorna ItemEstoque ou null se linha vazia/inválida
  ItemEstoque? _processarLinha(List<Data?> row, int linhaExcel) {
    // Extrai valores das colunas fixas
    final codigoRaw = _getCellValue(row, _colCodigo);
    final descricaoRaw = _getCellValue(row, _colDescricao);
    final loteRaw = _getCellValue(row, _colLote);
    final quantidadeRaw = _getCellValue(row, _colQuantidade);
    final valorTotalRaw = _getCellValue(row, _colValorTotal);

    // Linha vazia = código vazio
    if (codigoRaw == null || codigoRaw.toString().trim().isEmpty) {
      return null;
    }

    // Converte código (pode ser numérico no Excel)
    final codigo = _normalizarCodigo(codigoRaw);
    if (codigo.isEmpty) {
      return null;
    }

    // Converte demais campos
    final descricao = descricaoRaw?.toString().trim() ?? '';
    final lote = loteRaw?.toString().trim() ?? '';
    final quantidade = _toDouble(quantidadeRaw);
    final valorTotal = _toDouble(valorTotalRaw);

    // Calcula valor unitário (evita divisão por zero)
    final valorUnitario = quantidade > 0 ? valorTotal / quantidade : 0.0;

    return ItemEstoque(
      codigo: codigo,
      descricao: descricao,
      lote: lote,
      quantidade: quantidade,
      valorTotal: valorTotal,
      valorUnitario: valorUnitario,
      linhaOriginal: linhaExcel,
    );
  }

  /// Obtém valor de uma célula de forma segura
  dynamic _getCellValue(List<Data?> row, int colIndex) {
    if (colIndex >= row.length) return null;
    final cell = row[colIndex];
    return cell?.value;
  }

  /// Normaliza código do material (remove zeros à esquerda desnecessários, etc)
  String _normalizarCodigo(dynamic valor) {
    if (valor == null) return '';

    // Se for número inteiro, converte sem decimais
    if (valor is int) {
      return valor.toString();
    }

    // Se for double mas é inteiro (ex: 123.0), converte sem decimais
    if (valor is double) {
      if (valor == valor.truncateToDouble()) {
        return valor.toInt().toString();
      }
      return valor.toString();
    }

    // String: apenas trim
    return valor.toString().trim();
  }

  /// Converte valor para double de forma robusta
  double _toDouble(dynamic valor) {
    if (valor == null) return 0.0;
    if (valor is double) return valor;
    if (valor is int) return valor.toDouble();
    if (valor is num) return valor.toDouble();

    if (valor is String) {
      // Remove espaços e substitui vírgula por ponto
      final limpo = valor.trim().replaceAll(' ', '').replaceAll(',', '.');
      return double.tryParse(limpo) ?? 0.0;
    }

    return 0.0;
  }

  /// Verifica duplicatas por chave única (codigo + lote)
  List<String> _verificarDuplicatas(List<ItemEstoque> itens) {
    final avisos = <String>[];
    final chaves = <String, List<int>>{};

    for (final item in itens) {
      final chave = item.chaveUnica;
      chaves.putIfAbsent(chave, () => []).add(item.linhaOriginal);
    }

    for (final entry in chaves.entries) {
      if (entry.value.length > 1) {
        avisos.add(
            'Chave duplicada "${entry.key}" nas linhas: ${entry.value.join(", ")}'
        );
      }
    }

    return avisos;
  }

  // ========== MÉTODOS UTILITÁRIOS ==========

  /// Gera preview dos primeiros N itens (para UI)
  List<Map<String, dynamic>> gerarPreview(ParseResult result, {int limite = 10}) {
    return result.itens
        .take(limite)
        .map((item) => {
      'linha': item.linhaOriginal,
      'codigo': item.codigo,
      'descricao': item.descricao.length > 40
          ? '${item.descricao.substring(0, 40)}...'
          : item.descricao,
      'lote': item.lote.isEmpty ? '-' : item.lote,
      'quantidade': item.quantidade,
      'valor_unitario': item.valorUnitario,
      'valor_total': item.valorTotal,
    })
        .toList();
  }

  /// Calcula estatísticas do resultado
  Map<String, dynamic> calcularEstatisticas(ParseResult result) {
    if (result.itens.isEmpty) {
      return {
        'total_itens': 0,
        'total_quantidade': 0.0,
        'valor_total': 0.0,
        'itens_com_lote': 0,
        'itens_sem_lote': 0,
        'itens_zerados': 0,
      };
    }

    double totalQuantidade = 0;
    double valorTotal = 0;
    int comLote = 0;
    int semLote = 0;
    int zerados = 0;

    for (final item in result.itens) {
      totalQuantidade += item.quantidade;
      valorTotal += item.valorTotal;

      if (item.lote.isNotEmpty) {
        comLote++;
      } else {
        semLote++;
      }

      if (item.quantidade == 0) {
        zerados++;
      }
    }

    return {
      'total_itens': result.itens.length,
      'total_quantidade': totalQuantidade,
      'valor_total': valorTotal,
      'itens_com_lote': comLote,
      'itens_sem_lote': semLote,
      'itens_zerados': zerados,
    };
  }
}