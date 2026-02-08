// lib/ui/desktop/screens/importar_estoque_screen.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lego/services/estoque_service.dart';
import 'dart:convert';
// Para usar Excel quando adicionar dependência:
// import 'package:excel/excel.dart';

/// Aba de Importação: Upload de Excel/CSV para atualizar estoque
class ImportarEstoqueScreen extends StatefulWidget {
  const ImportarEstoqueScreen({super.key});

  @override
  State<ImportarEstoqueScreen> createState() => _ImportarEstoqueScreenState();
}

class _ImportarEstoqueScreenState extends State<ImportarEstoqueScreen> {
  final _estoqueService = EstoqueService();

  // Estado do processo
  String? _nomeArquivo;
  List<Map<String, dynamic>>? _dadosPreview;
  bool _processando = false;
  String? _erro;
  Map<String, dynamic>? _resultado;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(),
          const SizedBox(height: 24),

          // Área de upload ou preview
          if (_dadosPreview == null)
            _buildAreaUpload()
          else
            _buildPreviewEValidacao(),

          // Resultado da importação
          if (_resultado != null) ...[
            const SizedBox(height: 24),
            _buildResultado(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.upload_file,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Importar Estoque',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Faça upload de um arquivo Excel ou CSV para atualizar o estoque do sistema',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAreaUpload() {
    return Card(
      child: InkWell(
        onTap: _processando ? null : _selecionarArquivo,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(
                Icons.cloud_upload,
                size: 80,
                color: _processando ? Colors.grey : Colors.blue,
              ),
              const SizedBox(height: 16),
              Text(
                _processando ? 'Processando...' : 'Clique para selecionar arquivo',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Formatos aceitos: .xlsx, .xls, .csv',
                style: TextStyle(color: Colors.grey[600]),
              ),
              if (_nomeArquivo != null) ...[
                const SizedBox(height: 16),
                Chip(
                  label: Text(_nomeArquivo!),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: _limparArquivo,
                ),
              ],
              if (_erro != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _erro!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_processando)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewEValidacao() {
    final errosValidacao = _estoqueService.validarArquivoImportacao(
      _dadosPreview!,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Info do arquivo
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nomeArquivo ?? 'Arquivo selecionado',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_dadosPreview!.length} linhas detectadas',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancelar',
                  onPressed: _limparArquivo,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Erros de validação
        if (errosValidacao.isNotEmpty) ...[
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.error, color: Colors.red),
                      SizedBox(width: 8),
                      Text(
                        'Erros encontrados',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...errosValidacao.take(10).map((erro) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $erro', style: const TextStyle(fontSize: 13)),
                    );
                  }),
                  if (errosValidacao.length > 10)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'E mais ${errosValidacao.length - 10} erros...',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Preview dos dados
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Preview dos dados',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Código')),
                      DataColumn(label: Text('Quantidade')),
                      DataColumn(label: Text('Valor Unit.')),
                      DataColumn(label: Text('Depósito')),
                    ],
                    rows: _dadosPreview!.take(10).map((item) {
                      return DataRow(cells: [
                        DataCell(Text(item['codigo']?.toString() ?? '-')),
                        DataCell(Text(item['quantidade']?.toString() ?? '-')),
                        DataCell(Text(item['valor_unitario']?.toString() ?? '-')),
                        DataCell(Text(item['deposito']?.toString() ?? '-')),
                      ]);
                    }).toList(),
                  ),
                ),
                if (_dadosPreview!.length > 10)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Mostrando 10 de ${_dadosPreview!.length} linhas',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Botões de ação
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: _limparArquivo,
              icon: const Icon(Icons.cancel),
              label: const Text('Cancelar'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: errosValidacao.isEmpty && !_processando
                  ? _confirmarImportacao
                  : null,
              icon: _processando
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.check),
              label: const Text('Confirmar Importação'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultado() {
    final sucesso = _resultado!['sucesso'] as int;
    final falhas = _resultado!['falhas'] as int;
    final total = _resultado!['total'] as int;
    final erros = _resultado!['erros'] as List<dynamic>;

    final cor = falhas == 0 ? Colors.green : Colors.orange;

    return Card(
      color: cor.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  falhas == 0 ? Icons.check_circle : Icons.warning,
                  color: cor,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Text(
                  'Importação Concluída',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: cor.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStatChip('Total', total.toString(), Colors.blue),
                const SizedBox(width: 12),
                _buildStatChip('Sucesso', sucesso.toString(), Colors.green),
                const SizedBox(width: 12),
                if (falhas > 0)
                  _buildStatChip('Falhas', falhas.toString(), Colors.red),
              ],
            ),
            if (erros.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Erros:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...erros.take(5).map((erro) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $erro', style: const TextStyle(fontSize: 13)),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String valor, MaterialColor cor) {
    return Chip(
      label: Text('$label: $valor'),
      backgroundColor: cor.withOpacity(0.1),
      side: BorderSide(color: cor),
      labelStyle: TextStyle(
        color: cor[900] ?? cor,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Future<void> _selecionarArquivo() async {
    setState(() {
      _erro = null;
      _resultado = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;

      setState(() {
        _nomeArquivo = file.name;
        _processando = true;
      });

      // Processar arquivo
      // TODO: Implementar parsing real de Excel/CSV
      // Por ora, dados de exemplo
      await Future.delayed(const Duration(seconds: 1));

      setState(() {
        _dadosPreview = [
          {
            'codigo': 'PROD001',
            'quantidade': 100,
            'valor_unitario': 50.0,
            'deposito': 'DEP01',
          },
          {
            'codigo': 'PROD002',
            'quantidade': 200,
            'valor_unitario': 25.0,
            'deposito': 'DEP01',
          },
        ];
        _processando = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Erro ao ler arquivo: $e';
        _processando = false;
      });
    }
  }

  Future<void> _confirmarImportacao() async {
    if (_dadosPreview == null) return;

    setState(() => _processando = true);

    try {
      final resultado = await _estoqueService.importarEstoque(_dadosPreview!);

      setState(() {
        _resultado = resultado;
        _processando = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Erro ao importar: $e';
        _processando = false;
      });
    }
  }

  void _limparArquivo() {
    setState(() {
      _nomeArquivo = null;
      _dadosPreview = null;
      _erro = null;
      _resultado = null;
    });
  }
}