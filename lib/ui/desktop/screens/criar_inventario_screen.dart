// lib/ui/desktop/screens/criar_inventario_screen.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';

import 'package:lego/models/inventario.dart';
import 'package:lego/services/excel_parser_service.dart';
import 'package:lego/services/inventario_service.dart';
import 'package:lego/services/estoque_service.dart';

/// Tela para criação de novo inventário (wizard em etapas)
class CriarInventarioScreen extends StatefulWidget {
  const CriarInventarioScreen({super.key});

  @override
  State<CriarInventarioScreen> createState() => _CriarInventarioScreenState();
}

class _CriarInventarioScreenState extends State<CriarInventarioScreen> {
  final _inventarioService = InventarioService();
  final _estoqueService = EstoqueService();
  final _parserService = ExcelParserService();

  // Estado do wizard
  int _etapaAtual = 0;
  bool _processando = false;
  String? _erro;

  // Etapa 1: Configuração
  String _tipoMaterial = TiposMaterial.almoxarifado;
  TipoContagem _tipoContagem = TipoContagem.completa;
  final _depositoController = TextEditingController();
  final _descricaoController = TextEditingController();

  // Etapa 2: Importação
  String? _nomeArquivo;
  Uint8List? _arquivoBytes;
  ParseResult? _parseResult;

  // Etapa 3: Confirmação
  String? _inventarioId;

  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _formatoNumero = NumberFormat.decimalPattern('pt_BR');

  @override
  void dispose() {
    _depositoController.dispose();
    _descricaoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar Novo Inventário'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _confirmarSaida(context),
        ),
      ),
      body: Column(
        children: [
          // Stepper visual
          _buildStepper(),
          const Divider(height: 1),

          // Conteúdo da etapa
          Expanded(
            child: _processando
                ? const Center(child: CircularProgressIndicator())
                : _buildEtapaAtual(),
          ),

          // Erro se houver
          if (_erro != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.red.shade50,
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_erro!, style: const TextStyle(color: Colors.red)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _erro = null),
                  ),
                ],
              ),
            ),

          // Botões de navegação
          _buildBotoesNavegacao(),
        ],
      ),
    );
  }

  Widget _buildStepper() {
    final etapas = ['Configuração', 'Importar Estoque', 'Confirmação'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        children: List.generate(etapas.length, (index) {
          final isCurrent = index == _etapaAtual;
          final isCompleted = index < _etapaAtual;

          return Expanded(
            child: Row(
              children: [
                // Círculo
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCompleted
                        ? Colors.green
                        : isCurrent
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade300,
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: isCurrent ? Colors.white : Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Label
                Expanded(
                  child: Text(
                    etapas[index],
                    style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? Colors.black : Colors.grey.shade600,
                    ),
                  ),
                ),
                // Linha conectora
                if (index < etapas.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: index < _etapaAtual ? Colors.green : Colors.grey.shade300,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildEtapaAtual() {
    switch (_etapaAtual) {
      case 0:
        return _buildEtapaConfiguracao();
      case 1:
        return _buildEtapaImportacao();
      case 2:
        return _buildEtapaConfirmacao();
      default:
        return const SizedBox();
    }
  }

  // ==================== ETAPA 1: CONFIGURAÇÃO ====================

  Widget _buildEtapaConfiguracao() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tipo de Material
          Text(
            'Tipo de Material',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Selecione o tipo de material que será inventariado:',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: TiposMaterial.todos.map((tipo) {
              final isSelected = _tipoMaterial == tipo;
              return ChoiceChip(
                label: Text(TiposMaterial.label(tipo)),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _tipoMaterial = tipo;
                      // Sugere tipo de contagem
                      _tipoContagem = TiposMaterial.tipoContagemSugerido(tipo);
                    });
                  }
                },
                selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
                avatar: isSelected ? const Icon(Icons.check, size: 18) : null,
              );
            }).toList(),
          ),

          const SizedBox(height: 32),

          // Tipo de Contagem
          Text(
            'Tipo de Contagem',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Defina como serão realizadas as contagens:',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),

          _buildOpcaoContagem(
            TipoContagem.simples,
            'Contagem Simples',
            'Uma única contagem. Ideal para conferências rápidas e cilindros.',
            Icons.looks_one,
          ),
          const SizedBox(height: 12),
          _buildOpcaoContagem(
            TipoContagem.completa,
            'Contagem Completa',
            'Até 3 contagens independentes com verificação de divergências. '
                'Recomendado para almoxarifado e gases.',
            Icons.looks_3,
          ),

          const SizedBox(height: 32),

          // Campos opcionais
          Text(
            'Informações Adicionais',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _depositoController,
                  decoration: const InputDecoration(
                    labelText: 'Código do Depósito',
                    hintText: 'Ex: A421, I421',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.warehouse),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _descricaoController,
                  decoration: const InputDecoration(
                    labelText: 'Descrição (opcional)',
                    hintText: 'Ex: Inventário mensal do almoxarifado',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOpcaoContagem(
      TipoContagem tipo,
      String titulo,
      String descricao,
      IconData icone,
      ) {
    final isSelected = _tipoContagem == tipo;

    return InkWell(
      onTap: () => setState(() => _tipoContagem = tipo),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? Theme.of(context).primaryColor.withOpacity(0.05)
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).primaryColor.withOpacity(0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icone,
                color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Theme.of(context).primaryColor : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    descricao,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Radio<TipoContagem>(
              value: tipo,
              groupValue: _tipoContagem,
              onChanged: (value) {
                if (value != null) setState(() => _tipoContagem = value);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ETAPA 2: IMPORTAÇÃO ====================

  Widget _buildEtapaImportacao() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Importar Base de Estoque',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Faça upload do arquivo Excel com a base de estoque atual do SAP.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),

          // Info sobre estrutura esperada
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Estrutura esperada: Coluna A = Código, B = Descrição, '
                        'E = Lote, F = Quantidade, H = Valor Total',
                    style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Área de upload
          if (_parseResult == null)
            _buildAreaUpload()
          else
            _buildPreviewEstoque(),
        ],
      ),
    );
  }

  Widget _buildAreaUpload() {
    return InkWell(
      onTap: _selecionarArquivo,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.shade300,
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_upload_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'Clique para selecionar arquivo',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Formatos aceitos: .xlsx, .xls',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewEstoque() {
    final result = _parseResult!;
    final stats = _parserService.calcularEstatisticas(result);
    final preview = _parserService.gerarPreview(result, limite: 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info do arquivo
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file, color: Colors.green, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nomeArquivo ?? 'Arquivo carregado',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result.resumo,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _limparArquivo,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Trocar arquivo'),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Estatísticas
        Row(
          children: [
            _buildStatCard('Total de Itens', _formatoNumero.format(stats['total_itens']), Icons.inventory),
            const SizedBox(width: 12),
            _buildStatCard('Valor Total', _formatoMoeda.format(stats['valor_total']), Icons.attach_money),
            const SizedBox(width: 12),
            _buildStatCard('Com Lote', '${stats['itens_com_lote']}', Icons.qr_code),
            const SizedBox(width: 12),
            _buildStatCard('Sem Lote', '${stats['itens_sem_lote']}', Icons.qr_code_2),
          ],
        ),

        // Avisos
        if (result.temAvisos) ...[
          const SizedBox(height: 16),
          ExpansionTile(
            leading: Icon(Icons.warning_amber, color: Colors.orange.shade700),
            title: Text('${result.avisos.length} aviso(s)'),
            children: result.avisos.map((aviso) {
              return ListTile(
                dense: true,
                leading: const Icon(Icons.circle, size: 8),
                title: Text(aviso, style: const TextStyle(fontSize: 13)),
              );
            }).toList(),
          ),
        ],

        const SizedBox(height: 16),

        // Preview dos dados
        const Text(
          'Preview dos dados:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 24,
              columns: const [
                DataColumn(label: Text('Linha')),
                DataColumn(label: Text('Código')),
                DataColumn(label: Text('Descrição')),
                DataColumn(label: Text('Lote')),
                DataColumn(label: Text('Qtd'), numeric: true),
                DataColumn(label: Text('Valor Unit.'), numeric: true),
              ],
              rows: preview.map((item) {
                return DataRow(cells: [
                  DataCell(Text('${item['linha']}')),
                  DataCell(Text(item['codigo'])),
                  DataCell(Text(item['descricao'])),
                  DataCell(Text(item['lote'])),
                  DataCell(Text(_formatoNumero.format(item['quantidade']))),
                  DataCell(Text(_formatoMoeda.format(item['valor_unitario']))),
                ]);
              }).toList(),
            ),
          ),
        ),

        if (result.itens.length > 10)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Mostrando 10 de ${result.itens.length} itens',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildStatCard(String label, String valor, IconData icone) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icone, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(label, style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== ETAPA 3: CONFIRMAÇÃO ====================

  Widget _buildEtapaConfirmacao() {
    final stats = _parseResult != null
        ? _parserService.calcularEstatisticas(_parseResult!)
        : <String, dynamic>{};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Resumo
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, color: Colors.green, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tudo pronto para criar o inventário!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Revise as informações abaixo e confirme.',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Detalhes
          _buildSecaoResumo('Configuração', [
            _buildLinhaResumo('Tipo de Material', TiposMaterial.label(_tipoMaterial)),
            _buildLinhaResumo('Tipo de Contagem', _tipoContagem == TipoContagem.simples
                ? 'Simples (1 contagem)'
                : 'Completa (até 3 contagens)'),
            if (_depositoController.text.isNotEmpty)
              _buildLinhaResumo('Depósito', _depositoController.text),
            if (_descricaoController.text.isNotEmpty)
              _buildLinhaResumo('Descrição', _descricaoController.text),
          ]),

          const SizedBox(height: 16),

          _buildSecaoResumo('Estoque Importado', [
            _buildLinhaResumo('Arquivo', _nomeArquivo ?? '-'),
            _buildLinhaResumo('Total de Itens', _formatoNumero.format(stats['total_itens'] ?? 0)),
            _buildLinhaResumo('Valor Total', _formatoMoeda.format(stats['valor_total'] ?? 0)),
            _buildLinhaResumo('Itens com Lote', '${stats['itens_com_lote'] ?? 0}'),
            _buildLinhaResumo('Itens sem Lote', '${stats['itens_sem_lote'] ?? 0}'),
          ]),

          const SizedBox(height: 24),

          // Aviso
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade800),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Após a criação, os participantes poderão entrar pelo app mobile '
                        'e iniciar as contagens. O inventário ficará disponível até ser finalizado.',
                    style: TextStyle(color: Colors.amber.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecaoResumo(String titulo, List<Widget> linhas) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Divider(),
            ...linhas,
          ],
        ),
      ),
    );
  }

  Widget _buildLinhaResumo(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== NAVEGAÇÃO ====================

  Widget _buildBotoesNavegacao() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Botão voltar
          if (_etapaAtual > 0)
            TextButton.icon(
              onPressed: _voltarEtapa,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Voltar'),
            )
          else
            const SizedBox(width: 100),

          // Botão avançar/confirmar
          FilledButton.icon(
            onPressed: _podeAvancar() ? _avancarEtapa : null,
            icon: Icon(_etapaAtual == 2 ? Icons.check : Icons.arrow_forward),
            label: Text(_etapaAtual == 2 ? 'Criar Inventário' : 'Avançar'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  bool _podeAvancar() {
    switch (_etapaAtual) {
      case 0: // Configuração sempre pode avançar
        return true;
      case 1: // Importação precisa de arquivo válido
        return _parseResult != null && _parseResult!.sucesso;
      case 2: // Confirmação sempre pode criar
        return true;
      default:
        return false;
    }
  }

  void _voltarEtapa() {
    setState(() {
      _etapaAtual--;
      _erro = null;
    });
  }

  Future<void> _avancarEtapa() async {
    if (_etapaAtual < 2) {
      setState(() {
        _etapaAtual++;
        _erro = null;
      });
    } else {
      // Etapa final: criar inventário
      await _criarInventario();
    }
  }

  // ==================== AÇÕES ====================

  Future<void> _selecionarArquivo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        setState(() => _erro = 'Não foi possível ler o arquivo');
        return;
      }

      setState(() {
        _processando = true;
        _erro = null;
      });

      final parseResult = await _parserService.processarBytes(
        file.bytes!,
        nomeArquivo: file.name,
      );

      setState(() {
        _nomeArquivo = file.name;
        _arquivoBytes = file.bytes;
        _parseResult = parseResult;
        _processando = false;

        if (!parseResult.sucesso) {
          _erro = parseResult.erros.join('\n');
        }
      });
    } catch (e) {
      setState(() {
        _erro = 'Erro ao processar arquivo: $e';
        _processando = false;
      });
    }
  }

  void _limparArquivo() {
    setState(() {
      _nomeArquivo = null;
      _arquivoBytes = null;
      _parseResult = null;
      _erro = null;
    });
  }

  Future<void> _criarInventario() async {
    if (_parseResult == null || !_parseResult!.sucesso) {
      setState(() => _erro = 'Dados de estoque inválidos');
      return;
    }

    setState(() {
      _processando = true;
      _erro = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final stats = _parserService.calcularEstatisticas(_parseResult!);

      // 1. Criar inventário
      final inventarioId = await _inventarioService.criarInventarioCompleto(
        tipoContagem: _tipoContagem,
        tipoMaterial: _tipoMaterial,
        deposito: _depositoController.text.isEmpty ? null : _depositoController.text,
        descricao: _descricaoController.text.isEmpty ? null : _descricaoController.text,
        totalItensEstoque: stats['total_itens'] as int,
        valorTotalEstoque: stats['valor_total'] as double,
        criadoPor: user?.uid,
      );

      // 2. Salvar estoque na subcoleção do inventário
      await _estoqueService.importarEstoqueParaInventario(
        inventarioId: inventarioId,
        itens: _parseResult!.itens.map((e) => e.toMap()).toList(),
      );

      setState(() {
        _inventarioId = inventarioId;
        _processando = false;
      });

      // Mostrar sucesso e voltar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Inventário criado com sucesso! ID: $inventarioId'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(inventarioId);
      }
    } catch (e) {
      setState(() {
        _erro = 'Erro ao criar inventário: $e';
        _processando = false;
      });
    }
  }

  Future<void> _confirmarSaida(BuildContext context) async {
    if (_etapaAtual == 0 && _parseResult == null) {
      Navigator.of(context).pop();
      return;
    }

    final confirma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar inventário?'),
        content: const Text(
          'Você tem alterações não salvas. Deseja realmente sair?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );

    if (confirma == true && mounted) {
      Navigator.of(context).pop();
    }
  }
}