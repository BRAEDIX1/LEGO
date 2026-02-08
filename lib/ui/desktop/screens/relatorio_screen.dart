// lib/ui/desktop/screens/relatorio_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:lego/models/balanco_financeiro.dart';
import 'package:lego/models/divergencia.dart';
import 'package:lego/services/relatorio_service.dart';
import 'package:lego/services/exportar_excel_service.dart';

/// Tela de relatórios do inventário
class RelatorioScreen extends StatefulWidget {
  final String inventarioId;

  const RelatorioScreen({
    super.key,
    required this.inventarioId,
  });

  @override
  State<RelatorioScreen> createState() => _RelatorioScreenState();
}

class _RelatorioScreenState extends State<RelatorioScreen> with SingleTickerProviderStateMixin {
  final _relatorioService = RelatorioService();
  final _exportService = ExportarExcelService();

  late TabController _tabController;

  ResultadoRelatorio? _relatorio;
  bool _carregando = true;
  String? _erro;
  bool _exportando = false;

  // Filtros
  String _filtroStatus = 'todos';
  String _busca = '';
  String _ordenacao = 'codigo';
  bool _ordenacaoAsc = true;

  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _formatoNumero = NumberFormat.decimalPattern('pt_BR');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _carregarRelatorio();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _carregarRelatorio() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final relatorio = await _relatorioService.gerarRelatorio(widget.inventarioId);
      setState(() {
        _relatorio = relatorio;
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Gerando relatório...'),
            ],
          ),
        ),
      );
    }

    if (_erro != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Relatório')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Erro: $_erro'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _carregarRelatorio,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final relatorio = _relatorio!;

    return Scaffold(
      appBar: AppBar(
        title: Text('Relatório - ${relatorio.codigoInventario}'),
        actions: [
          // Atualizar
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _carregarRelatorio,
          ),
          const SizedBox(width: 8),
          // Exportar
          PopupMenuButton<String>(
            icon: _exportando
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.download),
            tooltip: 'Exportar',
            enabled: !_exportando,
            onSelected: _exportar,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'excel_completo',
                child: ListTile(
                  leading: Icon(Icons.table_chart),
                  title: Text('Excel Completo'),
                  subtitle: Text('Todos os dados'),
                ),
              ),
              const PopupMenuItem(
                value: 'excel_divergencias',
                child: ListTile(
                  leading: Icon(Icons.warning),
                  title: Text('Excel Divergências'),
                  subtitle: Text('Apenas itens divergentes'),
                ),
              ),
              const PopupMenuItem(
                value: 'excel_financeiro',
                child: ListTile(
                  leading: Icon(Icons.attach_money),
                  title: Text('Excel Financeiro'),
                  subtitle: Text('Sobras e faltas'),
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.dashboard),
              text: 'Resumo',
            ),
            Tab(
              icon: Badge(
                label: Text('${relatorio.itens.length}'),
                child: const Icon(Icons.list_alt),
              ),
              text: 'Itens',
            ),
            if (relatorio.tipo == TipoRelatorio.divergenciasC2)
              Tab(
                icon: Badge(
                  label: Text('${relatorio.divergencias.length}'),
                  backgroundColor: Colors.orange,
                  child: const Icon(Icons.compare_arrows),
                ),
                text: 'Divergências',
              )
            else
              Tab(
                icon: const Icon(Icons.analytics),
                text: 'Análise',
              ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTabResumo(relatorio),
          _buildTabItens(relatorio),
          relatorio.tipo == TipoRelatorio.divergenciasC2
              ? _buildTabDivergencias(relatorio)
              : _buildTabAnalise(relatorio),
        ],
      ),
    );
  }

  // ==================== TAB RESUMO ====================

  Widget _buildTabResumo(ResultadoRelatorio relatorio) {
    final balanco = relatorio.balanco;
    final stats = relatorio.estatisticas;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header com tipo de relatório
          _buildHeaderTipoRelatorio(relatorio),
          const SizedBox(height: 24),

          // Cards de resumo financeiro
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sobras
              Expanded(
                child: _buildCardFinanceiro(
                  'Sobras',
                  balanco.totalSobras,
                  balanco.quantidadeSobras,
                  Colors.green,
                  Icons.trending_up,
                  subtitulo: 'Sem imposto',
                ),
              ),
              const SizedBox(width: 16),
              // Faltas
              Expanded(
                child: _buildCardFinanceiro(
                  'Faltas',
                  balanco.totalFaltas,
                  balanco.quantidadeFaltas,
                  Colors.red,
                  Icons.trending_down,
                  subtitulo: 'Com imposto (21,95%)',
                  detalhe: 'Base: ${_formatoMoeda.format(balanco.subtotalFaltas)}\n'
                      'Imposto: ${_formatoMoeda.format(balanco.impostoFaltas)}',
                ),
              ),
              const SizedBox(width: 16),
              // Saldo
              Expanded(
                child: _buildCardFinanceiro(
                  'Saldo Líquido',
                  balanco.saldoLiquido,
                  null,
                  balanco.isPrejuizo ? Colors.red : Colors.green,
                  balanco.isPrejuizo ? Icons.remove_circle : Icons.add_circle,
                  destaque: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Estatísticas de itens
          _buildSecaoEstatisticas(stats, balanco),

          // Alertas
          if (balanco.temItensCriticos || balanco.temItensPendentes) ...[
            const SizedBox(height: 24),
            _buildAlertas(balanco),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderTipoRelatorio(ResultadoRelatorio relatorio) {
    IconData icone;
    Color cor;
    String titulo;
    String descricao;

    switch (relatorio.tipo) {
      case TipoRelatorio.simples:
        icone = Icons.check_circle;
        cor = Colors.green;
        titulo = 'Relatório de Contagem Simples';
        descricao = 'Resultado direto da contagem única';
        break;
      case TipoRelatorio.divergenciasC2:
        icone = Icons.compare_arrows;
        cor = Colors.orange;
        titulo = 'Relatório de Divergências (C1 vs C2)';
        descricao = '${relatorio.divergencias.length} item(s) divergente(s) identificado(s) para C3';
        break;
      case TipoRelatorio.apuracaoFinal:
        icone = Icons.fact_check;
        cor = Colors.blue;
        titulo = 'Apuração Final';
        descricao = 'Resultado consolidado após todas as contagens';
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icone, color: cor, size: 32),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    descricao,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Gerado em',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(relatorio.dataGeracao),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardFinanceiro(
      String titulo,
      double valor,
      int? quantidade,
      Color cor,
      IconData icone, {
        String? subtitulo,
        String? detalhe,
        bool destaque = false,
      }) {
    return Card(
      color: destaque ? cor.withOpacity(0.1) : null,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: cor),
                const SizedBox(width: 8),
                Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            if (subtitulo != null) ...[
              const SizedBox(height: 4),
              Text(subtitulo, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
            const SizedBox(height: 12),
            Text(
              _formatoMoeda.format(valor.abs()),
              style: TextStyle(
                fontSize: destaque ? 28 : 24,
                fontWeight: FontWeight.bold,
                color: cor,
              ),
            ),
            if (quantidade != null) ...[
              const SizedBox(height: 4),
              Text(
                '$quantidade item(s)',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
            if (detalhe != null) ...[
              const SizedBox(height: 8),
              Text(
                detalhe,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSecaoEstatisticas(Map<String, dynamic> stats, BalancoFinanceiro balanco) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Distribuição dos Itens',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildEstatItem('OK', stats['itens_ok'], Colors.green, Icons.check_circle),
                ),
                Expanded(
                  child: _buildEstatItem('Sobras', stats['itens_sobra'], Colors.blue, Icons.add_circle),
                ),
                Expanded(
                  child: _buildEstatItem('Faltas', stats['itens_falta'], Colors.orange, Icons.remove_circle),
                ),
                Expanded(
                  child: _buildEstatItem('Não Encontrados', stats['itens_nao_encontrados'], Colors.red, Icons.error),
                ),
                if (stats['itens_aguardando_c3'] > 0)
                  Expanded(
                    child: _buildEstatItem('Aguardando C3', stats['itens_aguardando_c3'], Colors.purple, Icons.hourglass_empty),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Barra de progresso
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: balanco.percentualProcessado / 100,
                minHeight: 12,
                backgroundColor: Colors.grey[200],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${balanco.percentualProcessado.toStringAsFixed(1)}% processado',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstatItem(String label, int valor, Color cor, IconData icone) {
    return Column(
      children: [
        Icon(icone, color: cor, size: 28),
        const SizedBox(height: 4),
        Text(
          valor.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: cor,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildAlertas(BalancoFinanceiro balanco) {
    return Column(
      children: [
        if (balanco.temItensCriticos)
          Card(
            color: Colors.red.shade50,
            child: ListTile(
              leading: const Icon(Icons.warning, color: Colors.red),
              title: Text(
                '${balanco.itensNaoEncontrados} item(s) crítico(s)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Itens do sistema que não foram encontrados na contagem'),
            ),
          ),
        if (balanco.temItensPendentes) ...[
          const SizedBox(height: 8),
          Card(
            color: Colors.purple.shade50,
            child: ListTile(
              leading: const Icon(Icons.hourglass_empty, color: Colors.purple),
              title: Text(
                '${balanco.itensAguardandoC3} item(s) aguardando C3',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Divergências entre C1 e C2 precisam de recontagem'),
              trailing: FilledButton(
                onPressed: _marcarParaC3,
                child: const Text('Preparar C3'),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ==================== TAB ITENS ====================

  Widget _buildTabItens(ResultadoRelatorio relatorio) {
    var itens = relatorio.itens.toList();

    // Aplica filtro de status
    if (_filtroStatus != 'todos') {
      itens = itens.where((i) {
        switch (_filtroStatus) {
          case 'ok':
            return i.status == StatusApuracao.ok;
          case 'sobra':
            return i.status == StatusApuracao.sobra || i.status == StatusApuracao.naoNoSistema;
          case 'falta':
            return i.status == StatusApuracao.falta || i.status == StatusApuracao.naoEncontrado;
          case 'critico':
            return i.status == StatusApuracao.naoEncontrado;
          case 'pendente':
            return i.status == StatusApuracao.aguardandoC3;
          default:
            return true;
        }
      }).toList();
    }

    // Aplica busca
    if (_busca.isNotEmpty) {
      final buscaLower = _busca.toLowerCase();
      itens = itens.where((i) =>
      i.codigo.toLowerCase().contains(buscaLower) ||
          i.descricao.toLowerCase().contains(buscaLower)).toList();
    }

    // Aplica ordenação
    itens.sort((a, b) {
      int comp;
      switch (_ordenacao) {
        case 'codigo':
          comp = a.codigo.compareTo(b.codigo);
          break;
        case 'diferenca':
          comp = a.diferenca.abs().compareTo(b.diferenca.abs());
          break;
        case 'impacto':
          comp = a.impactoFinanceiro.abs().compareTo(b.impactoFinanceiro.abs());
          break;
        default:
          comp = 0;
      }
      return _ordenacaoAsc ? comp : -comp;
    });

    return Column(
      children: [
        // Filtros
        Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Busca
                Expanded(
                  flex: 2,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Buscar código ou descrição...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _busca = v),
                  ),
                ),
                const SizedBox(width: 16),
                // Filtro status
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _filtroStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'todos', child: Text('Todos')),
                      DropdownMenuItem(value: 'ok', child: Text('OK')),
                      DropdownMenuItem(value: 'sobra', child: Text('Sobras')),
                      DropdownMenuItem(value: 'falta', child: Text('Faltas')),
                      DropdownMenuItem(value: 'critico', child: Text('Críticos')),
                      DropdownMenuItem(value: 'pendente', child: Text('Pendentes')),
                    ],
                    onChanged: (v) => setState(() => _filtroStatus = v ?? 'todos'),
                  ),
                ),
                const SizedBox(width: 16),
                // Ordenação
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _ordenacao,
                    decoration: const InputDecoration(
                      labelText: 'Ordenar por',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'codigo', child: Text('Código')),
                      DropdownMenuItem(value: 'diferenca', child: Text('Diferença')),
                      DropdownMenuItem(value: 'impacto', child: Text('Impacto')),
                    ],
                    onChanged: (v) => setState(() => _ordenacao = v ?? 'codigo'),
                  ),
                ),
                IconButton(
                  icon: Icon(_ordenacaoAsc ? Icons.arrow_upward : Icons.arrow_downward),
                  onPressed: () => setState(() => _ordenacaoAsc = !_ordenacaoAsc),
                ),
              ],
            ),
          ),
        ),

        // Tabela
        Expanded(
          child: Card(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: itens.isEmpty
                ? const Center(child: Text('Nenhum item encontrado'))
                : SingleChildScrollView(
              child: DataTable(
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('Código')),
                  DataColumn(label: Text('Descrição')),
                  DataColumn(label: Text('Lote')),
                  DataColumn(label: Text('Sistema'), numeric: true),
                  DataColumn(label: Text('Contado'), numeric: true),
                  DataColumn(label: Text('Diferença'), numeric: true),
                  DataColumn(label: Text('Impacto'), numeric: true),
                  DataColumn(label: Text('Status')),
                ],
                rows: itens.map((item) {
                  return DataRow(cells: [
                    DataCell(Text(item.codigo)),
                    DataCell(
                      SizedBox(
                        width: 200,
                        child: Text(
                          item.descricao,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(item.lote.isEmpty ? '-' : item.lote)),
                    DataCell(Text(_formatoNumero.format(item.quantidadeSistema))),
                    DataCell(Text(_formatoNumero.format(item.quantidadeContada))),
                    DataCell(_buildCelulaDiferenca(item.diferenca)),
                    DataCell(_buildCelulaImpacto(item.impactoFinanceiro)),
                    DataCell(_buildChipStatus(item.status)),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCelulaDiferenca(double diferenca) {
    if (diferenca == 0) return const Text('-');

    final cor = diferenca > 0 ? Colors.green : Colors.red;
    final sinal = diferenca > 0 ? '+' : '';

    return Text(
      '$sinal${_formatoNumero.format(diferenca)}',
      style: TextStyle(color: cor, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildCelulaImpacto(double impacto) {
    if (impacto == 0) return const Text('-');

    final cor = impacto > 0 ? Colors.green : Colors.red;

    return Text(
      _formatoMoeda.format(impacto),
      style: TextStyle(color: cor, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildChipStatus(StatusApuracao status) {
    Color cor;
    String label;
    IconData icone;

    switch (status) {
      case StatusApuracao.ok:
        cor = Colors.green;
        label = 'OK';
        icone = Icons.check_circle;
        break;
      case StatusApuracao.sobra:
        cor = Colors.blue;
        label = 'Sobra';
        icone = Icons.add_circle;
        break;
      case StatusApuracao.falta:
        cor = Colors.orange;
        label = 'Falta';
        icone = Icons.remove_circle;
        break;
      case StatusApuracao.naoEncontrado:
        cor = Colors.red;
        label = 'Crítico';
        icone = Icons.error;
        break;
      case StatusApuracao.naoNoSistema:
        cor = Colors.purple;
        label = 'Novo';
        icone = Icons.new_releases;
        break;
      case StatusApuracao.aguardandoC3:
        cor = Colors.grey;
        label = 'Pendente';
        icone = Icons.hourglass_empty;
        break;
    }

    return Chip(
      avatar: Icon(icone, size: 16, color: cor),
      label: Text(label, style: TextStyle(color: cor, fontSize: 12)),
      backgroundColor: cor.withOpacity(0.1),
      side: BorderSide(color: cor),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  // ==================== TAB DIVERGÊNCIAS ====================

  Widget _buildTabDivergencias(ResultadoRelatorio relatorio) {
    final divergencias = relatorio.divergencias;

    if (divergencias.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text('Nenhuma divergência encontrada!'),
            Text('C1 e C2 estão iguais para todos os itens.'),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${divergencias.length} divergência(s) identificada(s)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const Text(
                          'Itens com diferença entre C1 e C2 precisam de recontagem (C3)',
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _marcarParaC3,
                    icon: const Icon(Icons.playlist_add_check),
                    label: const Text('Preparar C3'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Lista de divergências
          ...divergencias.map((div) => _buildCardDivergencia(div)),
        ],
      ),
    );
  }

  Widget _buildCardDivergencia(Divergencia div) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: div.isSignificativa ? Colors.red : Colors.orange,
          child: Icon(
            div.isSignificativa ? Icons.priority_high : Icons.compare_arrows,
            color: Colors.white,
          ),
        ),
        title: Text(
          '${div.codigo} - ${div.descricao}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'C1: ${_formatoNumero.format(div.totalContagem1)} | '
              'C2: ${_formatoNumero.format(div.totalContagem2)} | '
              'Diff: ${_formatoNumero.format(div.diferencaTotal)}',
        ),
        trailing: div.isSignificativa
            ? const Chip(
          label: Text('Significativa', style: TextStyle(fontSize: 10)),
          backgroundColor: Colors.red,
          labelStyle: TextStyle(color: Colors.white),
        )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Localizações divergentes:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...div.locaisDivergentes.values.map((local) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 150,
                          child: Text(
                            local.localizacao,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Text('C1: ${_formatoNumero.format(local.quantidadeC1)}'),
                        const SizedBox(width: 16),
                        Text('C2: ${_formatoNumero.format(local.quantidadeC2)}'),
                        const SizedBox(width: 16),
                        Text(
                          'Diff: ${_formatoNumero.format(local.diferenca)}',
                          style: TextStyle(
                            color: local.diferenca > 0 ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TAB ANÁLISE ====================

  Widget _buildTabAnalise(ResultadoRelatorio relatorio) {
    final sobras = relatorio.itensSobra;
    final faltas = relatorio.itensFalta;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top 10 Sobras
          _buildSecaoTop(
            'Top 10 Maiores Sobras',
            sobras.take(10).toList(),
            Colors.green,
            Icons.trending_up,
          ),
          const SizedBox(height: 24),

          // Top 10 Faltas
          _buildSecaoTop(
            'Top 10 Maiores Faltas',
            faltas.take(10).toList(),
            Colors.red,
            Icons.trending_down,
          ),
        ],
      ),
    );
  }

  Widget _buildSecaoTop(String titulo, List<ItemApurado> itens, Color cor, IconData icone) {
    // Ordena por impacto absoluto
    itens.sort((a, b) => b.impactoFinanceiro.abs().compareTo(a.impactoFinanceiro.abs()));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: cor),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(),
            if (itens.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nenhum item'),
              )
            else
              ...itens.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cor.withOpacity(0.1),
                    child: Text(
                      '${idx + 1}',
                      style: TextStyle(color: cor, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(item.codigo),
                  subtitle: Text(
                    item.descricao,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatoMoeda.format(item.impactoFinanceiro.abs()),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: cor,
                        ),
                      ),
                      Text(
                        'Diff: ${_formatoNumero.format(item.diferenca.abs())}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ==================== AÇÕES ====================

  Future<void> _exportar(String tipo) async {
    setState(() => _exportando = true);

    try {
      String? caminho;

      switch (tipo) {
        case 'excel_completo':
          caminho = await _exportService.exportarCompleto(_relatorio!);
          break;
        case 'excel_divergencias':
          caminho = await _exportService.exportarDivergencias(_relatorio!);
          break;
        case 'excel_financeiro':
          caminho = await _exportService.exportarFinanceiro(_relatorio!);
          break;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exportado: $caminho'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Abrir',
              textColor: Colors.white,
              onPressed: () {
                // TODO: Abrir arquivo
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao exportar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _exportando = false);
    }
  }

  Future<void> _marcarParaC3() async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Preparar Contagem 3'),
        content: Text(
          'Marcar ${_relatorio!.divergencias.length} item(s) para recontagem na C3?\n\n'
              'Os contadores verão apenas estes itens durante a terceira contagem.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirma != true) return;

    try {
      await _relatorioService.marcarDivergenciasParaC3(widget.inventarioId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Itens marcados para C3!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}