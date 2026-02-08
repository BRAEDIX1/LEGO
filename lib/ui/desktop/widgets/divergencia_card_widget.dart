// lib/ui/desktop/widgets/divergencia_card_widget.dart

import 'package:flutter/material.dart';
import 'package:lego/models/divergencia.dart';

/// Card expansível mostrando divergência entre C1 e C2
class DivergenciaCardWidget extends StatefulWidget {
  final Divergencia divergencia;
  final VoidCallback? onMarcarParaC3;
  final bool jaMarcado;

  const DivergenciaCardWidget({
    super.key,
    required this.divergencia,
    this.onMarcarParaC3,
    this.jaMarcado = false,
  });

  @override
  State<DivergenciaCardWidget> createState() => _DivergenciaCardWidgetState();
}

class _DivergenciaCardWidgetState extends State<DivergenciaCardWidget> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    final div = widget.divergencia;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          // Header (sempre visível)
          InkWell(
            onTap: () => setState(() => _expandido = !_expandido),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Ícone de expansão
                  Icon(
                    _expandido ? Icons.expand_more : Icons.chevron_right,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),

                  // Código e descrição
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              div.codigo,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (widget.jaMarcado)
                              const Chip(
                                label: Text(
                                  'Marcado para C3',
                                  style: TextStyle(fontSize: 10),
                                ),
                                backgroundColor: Colors.orange,
                                labelStyle: TextStyle(color: Colors.white),
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          div.descricao,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Resumo da divergência
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: div.isSignificativa
                          ? Colors.red.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: div.isSignificativa
                            ? Colors.red.shade300
                            : Colors.orange.shade300,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'C1: ${div.totalContagem1.toStringAsFixed(1)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.arrow_forward, size: 16),
                            const SizedBox(width: 12),
                            Text(
                              'C2: ${div.totalContagem2.toStringAsFixed(1)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Diff: ${div.diferencaTotal >= 0 ? '+' : ''}${div.diferencaTotal.toStringAsFixed(1)} ${div.unidade}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Botão marcar para C3
                  if (widget.onMarcarParaC3 != null && !widget.jaMarcado)
                    FilledButton.icon(
                      onPressed: widget.onMarcarParaC3,
                      icon: const Icon(Icons.fact_check, size: 18),
                      label: const Text('Marcar para C3'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Detalhes (quando expandido)
          if (_expandido)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Divergências por Localização',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tabela de locais divergentes
                  DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 48,
                    columns: const [
                      DataColumn(label: Text('Localização')),
                      DataColumn(label: Text('Contagem 1')),
                      DataColumn(label: Text('Contagem 2')),
                      DataColumn(label: Text('Diferença')),
                      DataColumn(label: Text('Tipo')),
                    ],
                    rows: div.locaisDivergentes.entries.map((entry) {
                      final local = entry.value;
                      return DataRow(
                        cells: [
                          DataCell(Text(
                            local.localizacao,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          )),
                          DataCell(Text(local.quantidadeC1.toStringAsFixed(1))),
                          DataCell(Text(local.quantidadeC2.toStringAsFixed(1))),
                          DataCell(
                            Text(
                              '${local.diferenca >= 0 ? '+' : ''}${local.diferenca.toStringAsFixed(1)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: local.diferenca.abs() > 0
                                    ? Colors.red
                                    : Colors.black,
                              ),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(local.tipo.emoji),
                                const SizedBox(width: 4),
                                Text(
                                  local.tipo.label,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 12),

                  // Instruções para C3
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ao marcar para C3, o Grupo C deverá recontar APENAS '
                                'nas localizações: ${div.nomesLocaisDivergentes.join(', ')}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}