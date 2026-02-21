import 'package:lego/ui/mobile/screens/plant_map_page.dart';
import 'package:lego/services/inventario_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lego/data/repositories/produtos_repository.dart';
import 'package:lego/data/repositories/barras_repository.dart';
import 'package:lego/data/repositories/lancamentos_repository.dart';
import 'package:lego/data/local/lanc_local.dart';
import 'package:lego/services/sync_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:collection';
import 'dart:async';
import 'package:lego/data/repositories/lancamentos_repository.dart' show CleanupStats, CleanupResult;
import 'package:hive/hive.dart';
import 'package:flutter/services.dart';

class _Lancamento {
  final LancStatus status;
  final String codigo;
  final String descricao;
  final String unidade;
  final double quantidade;
  final String prateleira;
  final double cheio;
  final double vazio;
  final String lote;
  final String tag;
  final DateTime hora;
  final TipoRegistro registro;
  final String? localizacaoId;
  final String? localizacaoNome;

  const _Lancamento({
    required this.status,
    required this.codigo,
    required this.descricao,
    required this.unidade,
    required this.quantidade,
    required this.prateleira,
    required this.cheio,
    required this.vazio,
    required this.lote,
    required this.tag,
    required this.hora,
    required this.registro,
    this.localizacaoId,
    this.localizacaoNome,
  });

  _Lancamento copyWith({
    LancStatus? status,
    String? codigo,
    String? descricao,
    String? unidade,
    double? quantidade,
    String? prateleira,
    double? cheio,
    double? vazio,
    String? lote,
    String? tag,
    DateTime? hora,
    TipoRegistro? registro,
    Object? localizacaoId  = const _Unset(),
    Object? localizacaoNome = const _Unset(),
  }) {
    return _Lancamento(
      status:          status    ?? this.status,
      codigo:          codigo    ?? this.codigo,
      descricao:       descricao ?? this.descricao,
      unidade:         unidade   ?? this.unidade,
      quantidade:      quantidade ?? this.quantidade,
      prateleira:      prateleira ?? this.prateleira,
      cheio:           cheio  ?? this.cheio,
      vazio:           vazio  ?? this.vazio,
      lote:            lote   ?? this.lote,
      tag:             tag    ?? this.tag,
      hora:            hora   ?? this.hora,
      registro:        registro ?? this.registro,
      localizacaoId:   localizacaoId   is _Unset ? this.localizacaoId   : localizacaoId   as String?,
      localizacaoNome: localizacaoNome is _Unset ? this.localizacaoNome : localizacaoNome as String?,
    );
  }
}

// Sentinel para distinguir "não passou" de "passou null" no copyWith
class _Unset { const _Unset(); }

class _LancamentoDoc {
  final String id;
  final _Lancamento data;
  const _LancamentoDoc(this.id, this.data);
}

// Adicionar após a classe _LancamentoDoc

class _CadastroManualDialog extends StatefulWidget {
  final String? codigoInicial;
  final String? tagInicial;

  const _CadastroManualDialog({
    this.codigoInicial,
    this.tagInicial,
  });

  @override
  State<_CadastroManualDialog> createState() => _CadastroManualDialogState();
}

class _CadastroManualDialogState extends State<_CadastroManualDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codigoCtrl;
  late final TextEditingController _descricaoCtrl;
  final _unidadeCtrl = TextEditingController();
  final _volumeCtrl = TextEditingController();
  final _quantidadeCtrl = TextEditingController();
  final _prateleiraCtrl = TextEditingController();
  final _loteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _codigoCtrl = TextEditingController(text: widget.codigoInicial ?? widget.tagInicial);
    _descricaoCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _descricaoCtrl.dispose();
    _unidadeCtrl.dispose();
    _volumeCtrl.dispose();
    _quantidadeCtrl.dispose();
    _prateleiraCtrl.dispose();
    _loteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.add_box, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(
                      'Cadastro Manual de Item',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Item não encontrado no sistema. Preencha os dados conhecidos:',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),

                // Código
                TextFormField(
                  controller: _codigoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Código *',
                    hintText: 'Digite o código do produto',
                    prefixIcon: Icon(Icons.qr_code),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Código é obrigatório';
                    }
                    return null;
                  },
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),

                // Descrição
                TextFormField(
                  controller: _descricaoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Descrição *',
                    hintText: 'Digite a descrição do produto',
                    prefixIcon: Icon(Icons.description),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Descrição é obrigatória';
                    }
                    return null;
                  },
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),

                // Unidade e Volume
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _unidadeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Unidade *',
                          hintText: 'Ex: UN, KG, L',
                          prefixIcon: Icon(Icons.straighten),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Obrigatório';
                          }
                          return null;
                        },
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _volumeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Volume (L)',
                          hintText: 'Opcional',
                          prefixIcon: Icon(Icons.water_drop),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Quantidade e Prateleira
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quantidadeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Quantidade',
                          hintText: 'Ex: 1, 2.5 (opcional)',
                          prefixIcon: Icon(Icons.numbers),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _prateleiraCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Prateleira',
                          hintText: 'Ex: 6K9 (opcional)',
                          prefixIcon: Icon(Icons.shelves),
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Lote
                TextFormField(
                  controller: _loteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lote',
                    hintText: 'Opcional',
                    prefixIcon: Icon(Icons.inventory),
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),

                const SizedBox(height: 24),

                // Botões
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () async {
                        if (!_formKey.currentState!.validate()) return;

                        final qtdText = _quantidadeCtrl.text.trim();
                        final pratText = _prateleiraCtrl.text.trim();

                        final resultado = {
                          'codigo': _codigoCtrl.text.trim().toUpperCase(),
                          'descricao': _descricaoCtrl.text.trim(),
                          'unidade': _unidadeCtrl.text.trim().toUpperCase(),
                          'quantidade': qtdText.isEmpty ? 0.0 : (double.tryParse(qtdText.replaceAll(',', '.')) ?? 0.0),
                          'prateleira': pratText.isEmpty ? '' : pratText.toUpperCase(),
                          'lote': _loteCtrl.text.trim(),
                          'volume': double.tryParse(_volumeCtrl.text.replaceAll(',', '.')),
                          'tag': widget.tagInicial ?? '',
                        };

                        Navigator.of(context).pop(resultado);
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Salvar e Lançar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ========== WIDGET DE LIMPEZA MANUAL ==========
// ========== SUBSTITUIR CLASSE _ManualCleanupDialog COMPLETA ==========
// Localização: Dentro de home_page.dart

class _ManualCleanupDialog extends StatefulWidget {
  final LancamentosRepository repo;

  const _ManualCleanupDialog({required this.repo});

  @override
  State<_ManualCleanupDialog> createState() => _ManualCleanupDialogState();
}

class _ManualCleanupDialogState extends State<_ManualCleanupDialog> {
  CleanupStats? stats;
  final passwordController = TextEditingController();
  bool isProcessing = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final s = await widget.repo.getCleanupStats();

    debugPrint('===== CLEANUP STATS =====');
    debugPrint('Total dispositivo: ${s.totalDevice}');
    debugPrint('Sincronizados: ${s.syncedDevice}');
    debugPrint('Pendentes: ${s.pendingDevice}');
    debugPrint('Erros: ${s.errorsDevice}');
    debugPrint('Usuários: ${s.perUser.length}');
    for (final u in s.perUser) {
      debugPrint('  - ${u.displayName}: ${u.total} registros');
    }
    debugPrint('========================');

    setState(() {
      stats = s;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || stats == null) {
      return const AlertDialog(
        content: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.cleaning_services, color: Colors.blue),
          SizedBox(width: 8),
          Text('Limpeza do Dispositivo'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats do dispositivo
            _buildDeviceStatsCard(),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Breakdown por usuário
            Text(
              '👥 Por Usuário',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildUserBreakdown(),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Aviso
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Esta ação apagará TODOS os ${stats!.totalDevice} registros de TODOS os usuários!',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Campo de senha
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Senha de confirmação *',
                hintText: 'Digite a senha de 4 dígitos',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              keyboardType: TextInputType.number,
              maxLength: 4,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isProcessing ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: isProcessing ? null : _performCleanup,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
          ),
          icon: isProcessing
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Icon(Icons.delete_forever),
          label: const Text('APAGAR TUDO'),
        ),
      ],
    );
  }

  Widget _buildDeviceStatsCard() {
    return Card(
      color: Colors.blue.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📊 Estatísticas do Dispositivo',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildStatRow(
              'Total de registros',
              stats!.totalDevice,
              Icons.storage,
            ),
            const Divider(height: 16),
            _buildStatRow(
              '✅ Sincronizados',
              stats!.syncedDevice,
              Icons.cloud_done,
              color: Colors.green,
            ),
            _buildStatRow(
              '⏳ Pendentes',
              stats!.pendingDevice,
              Icons.cloud_upload,
              color: Colors.orange,
            ),
            _buildStatRow(
              '❌ Erros',
              stats!.errorsDevice,
              Icons.error_outline,
              color: Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserBreakdown() {
    if (stats!.perUser.isEmpty) {
      return const Text('Nenhum usuário com registros');
    }

    return Card(
      color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            for (final user in stats!.perUser)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          user.isCurrentUser ? Icons.person : Icons.person_outline,
                          size: 18,
                          color: user.isCurrentUser ? Colors.blue : Colors.grey[600],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          user.displayName,
                          style: TextStyle(
                            fontWeight: user.isCurrentUser ? FontWeight.bold : FontWeight.normal,
                            color: user.isCurrentUser ? Colors.blue : Colors.black,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${user.total} registros',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 24),
                      child: Text(
                        '✅${user.synced} ⏳${user.pending} ❌${user.errors}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    if (user != stats!.perUser.last)
                      const Divider(height: 12),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, int value, IconData icon, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(
            value.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performCleanup() async {
    if (passwordController.text != '0179') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Senha incorreta'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => isProcessing = true);

    final result = await widget.repo.manualCleanup(
      includePending: true, // Parâmetro mantido por compatibilidade (ignorado)
      password: passwordController.text,
    );

    if (!mounted) return;

    Navigator.pop(context, result);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    passwordController.dispose();
    super.dispose();
  }
}

// ========== SUBSTITUIR CLASSE _FormPane COMPLETA ==========
// Localização: dentro de home_page.dart

class _FormPane extends StatelessWidget {
  const _FormPane({
    required this.formKey,
    required this.codigoCtrl,
    required this.barrasCtrl,
    required this.qtdCtrl,
    required this.enderecoCtrl,
    required this.cheioCtrl,
    required this.vazioCtrl,
    required this.loteCtrl,
    required this.codigoFocus,
    required this.barrasFocus,
    required this.qtdFocus,
    required this.enderecoFocus,
    required this.cheioFocus,
    required this.vazioFocus,
    required this.loteFocus,
    required this.descricao,
    required this.unidade,
    required this.onBuscar,
    required this.onBuscarBarras,
    required this.onConfirmar,
    required this.validarCodigo,
    required this.validarQuantidade,
    required this.validarEndereco,
    required this.validarCheio,
    required this.validarVazio,
    required this.codigoEnabled,
    required this.barrasEnabled,
    required this.qtdPratEnabled,
    required this.cheioEnabled,
    required this.vazioEnabled,
    required this.loteEnabled,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController codigoCtrl;
  final TextEditingController barrasCtrl;
  final TextEditingController qtdCtrl;
  final TextEditingController enderecoCtrl;
  final TextEditingController cheioCtrl;
  final TextEditingController vazioCtrl;
  final TextEditingController loteCtrl;
  final FocusNode codigoFocus;
  final FocusNode barrasFocus;
  final FocusNode qtdFocus;
  final FocusNode enderecoFocus;
  final FocusNode cheioFocus;
  final FocusNode vazioFocus;
  final FocusNode loteFocus;
  final String? descricao;
  final String? unidade;
  final VoidCallback onBuscar;
  final VoidCallback onBuscarBarras;
  final VoidCallback onConfirmar;
  final String? Function(String?) validarCodigo;
  final String? Function(String?) validarQuantidade;
  final String? Function(String?) validarEndereco;
  final String? Function(String?) validarCheio;
  final String? Function(String?) validarVazio;
  final bool codigoEnabled;
  final bool barrasEnabled;
  final bool qtdPratEnabled;
  final bool cheioEnabled;
  final bool vazioEnabled;
  final bool loteEnabled;

  InputDecoration _dec(
      BuildContext context, {
        required String label,
        String? hint,
        Widget? suffix,
        bool readOnly = false,
      }) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffix,
      filled: true,
      isDense: true,
      enabled: !readOnly,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 2.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Form(
          key: formKey,
          child: LayoutBuilder(builder: (context, constraints) {
            // Usa layout compacto para telas pequenas/médias ou em portrait
            final useCompactLayout = constraints.maxWidth < 800 ||
                MediaQuery.of(context).orientation == Orientation.portrait;

            if (useCompactLayout) {
              return _buildSmartphoneLayout(context);
            } else {
              return _buildDesktopLayout(context);
            }
          }),
        ),
      ),
    );
  }

  // ========== LAYOUT SMARTPHONE PORTRAIT ==========
  Widget _buildSmartphoneLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // LINHA 1: Código + Tag
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: codigoCtrl,
                focusNode: codigoFocus,
                enabled: codigoEnabled,
                maxLength: 8,
                decoration: _dec(
                  context,
                  label: 'Código',
                  hint: '8 dígitos',
                  suffix: IconButton(
                    tooltip: 'Buscar',
                    onPressed: onBuscar,
                    icon: const Icon(Icons.search, size: 18),
                  ),
                ),
                textInputAction: TextInputAction.search,
                onFieldSubmitted: (_) => onBuscar(),
                validator: validarCodigo,
                style: const TextStyle(fontSize: 12),
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: barrasCtrl,
                focusNode: barrasFocus,
                enabled: barrasEnabled,
                maxLength: 10,
                decoration: _dec(
                  context,
                  label: 'Tag',
                  hint: '10 dígitos',
                  suffix: IconButton(
                    tooltip: 'Buscar por tag',
                    onPressed: onBuscarBarras,
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                  ),
                ),
                textInputAction: TextInputAction.search,
                onFieldSubmitted: (_) => onBuscarBarras(),
                autofocus: true,
                style: const TextStyle(fontSize: 12),
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // LINHA 2: Descrição (full width)
        TextFormField(
          readOnly: true,
          decoration: _dec(context, label: 'Descrição', hint: '—', readOnly: true),
          controller: TextEditingController(text: descricao ?? ''),
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 8),

        // LINHA 3: Unidade + Quantidade + Prateleira (tamanhos iguais)
        Row(
          children: [
            Expanded(
              child: TextFormField(
                readOnly: true,
                decoration: _dec(context, label: 'Unid', readOnly: true),
                controller: TextEditingController(text: unidade ?? ''),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: qtdCtrl,
                focusNode: qtdFocus,
                enabled: qtdPratEnabled,
                decoration: _dec(context, label: 'Qtd', hint: '1,5'),
                keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: true),
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => enderecoFocus.requestFocus(),
                validator: qtdPratEnabled ? validarQuantidade : null,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: enderecoCtrl,
                focusNode: enderecoFocus,
                enabled: qtdPratEnabled,
                maxLength: 3,
                decoration: _dec(context, label: 'Prat', hint: '6K9'),
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                validator: qtdPratEnabled ? validarEndereco : null,
                style: const TextStyle(fontSize: 12),
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // LINHA 4: Cheio + Vazio + Lote + Botão Circular
        Row(
          children: [
            // Cheio (menor)
            SizedBox(
              width: 70,
              child: TextFormField(
                controller: cheioCtrl,
                focusNode: cheioFocus,
                enabled: cheioEnabled,
                maxLength: 4,
                decoration: _dec(context, label: 'Cheio'),
                keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),  // ✅ MUDADO: decimal: false
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],  // ✅ ADICIONADO: Só dígitos
                textInputAction: TextInputAction.next,
                validator: cheioEnabled ? validarCheio : null,
                style: const TextStyle(fontSize: 12),
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
              ),
            ),
            const SizedBox(width: 8),
// Vazio (menor)
            SizedBox(
              width: 70,
              child: TextFormField(
                controller: vazioCtrl,
                focusNode: vazioFocus,
                enabled: vazioEnabled,
                maxLength: 4,
                decoration: _dec(context, label: 'Vazio'),
                keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),  // ✅ MUDADO: decimal: false
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],  // ✅ ADICIONADO: Só dígitos
                textInputAction: TextInputAction.next,
                validator: vazioEnabled ? validarVazio : null,
                style: const TextStyle(fontSize: 12),
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
              ),
            ),
            const SizedBox(width: 8),
            // Lote (maior - referência)
            Expanded(
              child: TextFormField(
                controller: loteCtrl,
                focusNode: loteFocus,
                enabled: loteEnabled,
                maxLength: 10,
                decoration: _dec(context, label: 'Lote'),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => onConfirmar(),
                style: const TextStyle(fontSize: 12),
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
              ),
            ),
            const SizedBox(width: 8),
            // Botão Circular (○→)
            FloatingActionButton(
              onPressed: onConfirmar,
              mini: true,
              tooltip: 'Confirmar',
              child: const Icon(Icons.arrow_forward, size: 20),
            ),
          ],
        ),
      ],
    );
  }

  // ========== LAYOUT DESKTOP/TABLET (ORIGINAL) ==========
  Widget _buildDesktopLayout(BuildContext context) {
    const double _wCodigo = 200;
    const double _wUnidade = 160;
    const double _wQtd = 140;
    const double _wPrateleira = 120;
    const double _wLote = 200;
    const double _wConfirm = 240;

    final codigo = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _wCodigo),
      child: TextFormField(
        controller: codigoCtrl,
        focusNode: codigoFocus,
        enabled: codigoEnabled,
        maxLength: 10,
        decoration: _dec(
          context,
          label: 'Código',
          hint: '10 dígitos',
          suffix: IconButton(
            tooltip: 'Buscar',
            onPressed: onBuscar,
            icon: const Icon(Icons.search, size: 18),
          ),
        ),
        textInputAction: TextInputAction.search,
        onFieldSubmitted: (_) => onBuscar(),
        validator: validarCodigo,
        autofocus: false,
        style: const TextStyle(fontSize: 12),
        buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
      ),
    );

    final barras = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _wCodigo),
      child: TextFormField(
        controller: barrasCtrl,
        focusNode: barrasFocus,
        enabled: barrasEnabled,
        maxLength: 10,
        decoration: _dec(
          context,
          label: 'Tag',
          hint: '10 dígitos',
          suffix: IconButton(
            tooltip: 'Buscar por tag',
            onPressed: onBuscarBarras,
            icon: const Icon(Icons.qr_code_scanner, size: 18),
          ),
        ),
        textInputAction: TextInputAction.search,
        onFieldSubmitted: (_) => onBuscarBarras(),
        autofocus: true,
        style: const TextStyle(fontSize: 12),
        buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
      ),
    );

    final desc = TextFormField(
      readOnly: true,
      decoration: _dec(context, label: 'Descrição', hint: '—', readOnly: true),
      controller: TextEditingController(text: descricao ?? ''),
      style: const TextStyle(fontSize: 14),
    );

    final unidadeField = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _wUnidade),
      child: TextFormField(
        readOnly: true,
        decoration: _dec(context, label: 'Unidade', readOnly: true),
        controller: TextEditingController(text: unidade ?? ''),
        style: const TextStyle(fontSize: 12),
      ),
    );

    final qtd = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _wQtd),
      child: TextFormField(
        controller: qtdCtrl,
        focusNode: qtdFocus,
        enabled: qtdPratEnabled,
        decoration: _dec(context, label: 'Qtd', hint: 'Ex.: 1,5'),
        keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: true),
        textInputAction: TextInputAction.next,
        onFieldSubmitted: (_) => enderecoFocus.requestFocus(),
        validator: qtdPratEnabled ? validarQuantidade : null,
        style: const TextStyle(fontSize: 12),
      ),
    );

    final cheio = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _wQtd),
      child: TextFormField(
        controller: cheioCtrl,
        focusNode: cheioFocus,
        enabled: cheioEnabled,
        maxLength: 4,
        decoration: _dec(context, label: 'Cheio'),
        keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: true),
        textInputAction: TextInputAction.next,
        validator: cheioEnabled ? validarCheio : null,
        style: const TextStyle(fontSize: 12),
        buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
      ),
    );

    final vazio = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _wQtd),
      child: TextFormField(
        controller: vazioCtrl,
        focusNode: vazioFocus,
        enabled: vazioEnabled,
        maxLength: 4,
        decoration: _dec(context, label: 'Vazio'),
        keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: true),
        textInputAction: TextInputAction.next,
        validator: vazioEnabled ? validarVazio : null,
        style: const TextStyle(fontSize: 12),
        buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
      ),
    );

    final lote = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _wLote),
      child: TextFormField(
        controller: loteCtrl,
        focusNode: loteFocus,
        enabled: loteEnabled,
        maxLength: 10,
        decoration: _dec(context, label: 'Lote'),
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => onConfirmar(),
        style: const TextStyle(fontSize: 12),
        buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
      ),
    );

    final endereco = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _wPrateleira),
      child: TextFormField(
        controller: enderecoCtrl,
        focusNode: enderecoFocus,
        enabled: qtdPratEnabled,
        maxLength: 3,
        decoration: _dec(context, label: 'Prat', hint: 'Ex.: 6K9'),
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.next,
        validator: qtdPratEnabled ? validarEndereco : null,
        style: const TextStyle(fontSize: 12),
        buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
      ),
    );

    final confirm = Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _wConfirm),
        child: FilledButton.icon(
          onPressed: onConfirmar,
          icon: const Icon(Icons.check_circle),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('CONFIRMA'),
          ),
        ),
      ),
    );

    const gap = 8.0;
    // constraints não está disponível aqui, usar MediaQuery
    final screenWidth = MediaQuery.of(context).size.width;
    final enoughWidth = screenWidth >= (_wCodigo + _wCodigo + gap + 360);

    final primeiraLinha = enoughWidth
        ? Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        codigo,
        const SizedBox(width: gap),
        barras,
        const SizedBox(width: gap),
        Expanded(child: desc),
      ],
    )
        : Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        codigo,
        const SizedBox(height: gap),
        barras,
        const SizedBox(height: gap),
        desc,
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        primeiraLinha,
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            unidadeField,
            qtd,
            cheio,
            vazio,
            endereco,
            lote,
            confirm,
          ],
        ),
      ],
    );
  }
}

class _LancamentosPane extends StatelessWidget {
  const _LancamentosPane({
    required this.uid,
    required this.listScroll,
  });

  final String? uid;
  final ScrollController listScroll;

  @override
  Widget build(BuildContext context) {
    if (uid == null) {
      return const Center(child: Text('Faça login para ver seus lançamentos.'));
    }

    final repo = LancamentosRepository(uid: uid!);
    return StreamBuilder<List<LancLocal>>(
      stream: repo.watchAllSorted(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Erro ao carregar: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!;
        if (docs.isEmpty) {
          return const Center(child: Text('Nenhum lançamento encontrado.'));
        }

        final rows = docs.map<_LancamentoDoc>((m) {
          return _LancamentoDoc(
            m.idLocal,
            _Lancamento(
              status: m.status,
              codigo: m.codigo,
              descricao: m.descricao,
              unidade: m.unidade,
              quantidade: m.quantidade,
              prateleira: m.prateleira,
              cheio: m.cheio,
              vazio: m.vazio,
              lote: m.lote ?? '',
              tag: m.tag ?? '',
              hora: m.createdAtLocal,
              registro: m.registro,  // ADICIONAR ESTA LINHA
            ),
          );
        }).toList();

        return _LancamentosListAndTable(
          itens: rows,
          listScroll: listScroll,
        );
      },
    );
  }
}

String _fmtQtde(double v) {
  return v.toString().replaceAll('.', ',');
}

Future<void> _editar(BuildContext context, _LancamentoDoc doc, LancamentosRepository repo) async {
  // Cheio e vazio são sempre inteiros (cilindros não têm fração)
  final qtdCtrl   = TextEditingController(text: doc.data.quantidade == doc.data.quantidade.truncateToDouble()
      ? doc.data.quantidade.toInt().toString()
      : doc.data.quantidade.toString());
  final endCtrl   = TextEditingController(text: doc.data.prateleira);
  final cheioCtrl = TextEditingController(text: doc.data.cheio.toInt().toString());
  final vazioCtrl = TextEditingController(text: doc.data.vazio.toInt().toString());
  final loteCtrl = TextEditingController(text: doc.data.lote);
  // ⭐ Localização editável
  String? localizacaoId   = doc.data.localizacaoId;
  String? localizacaoNome = doc.data.localizacaoNome;

  double _parsePos(String s) {
    final v = double.tryParse(s.replaceAll(',', '.')) ?? 0.0;
    return v < 0 ? 0.0 : v;
  }

  final edited = await showModalBottomSheet<_Lancamento>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Editar lançamento', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: loteCtrl,
                    decoration: const InputDecoration(labelText: 'Lote'),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qtdCtrl,
                    decoration: const InputDecoration(labelText: 'Quantidade'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: endCtrl,
                    decoration: const InputDecoration(labelText: 'Prateleira'),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: cheioCtrl,
                    decoration: const InputDecoration(labelText: 'Cheio'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: vazioCtrl,
                    decoration: const InputDecoration(labelText: 'Vazio'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ⭐ Campo de localização
            StatefulBuilder(
              builder: (ctx2, setStateLocal) {
                return InkWell(
                  onTap: () async {
                    final area = await Navigator.of(ctx).push<PlantArea>(
                      MaterialPageRoute(
                        builder: (_) => const PlantMapPage(
                          jsonAsset: 'assets/plantas/PLANTA_ATUAL_DE_DIADEMA_areas.json',
                        ),
                      ),
                    );
                    if (area != null) {
                      setStateLocal(() {
                        localizacaoId   = area.id;
                        localizacaoNome = area.nome;
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: localizacaoId != null ? Colors.green : Colors.grey,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      color: localizacaoId != null
                          ? Colors.green.withOpacity(0.05)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 18,
                          color: localizacaoId != null ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            localizacaoNome?.replaceAll('_', ' ') ??
                                localizacaoId ??
                                'Toque para alterar localização',
                            style: TextStyle(
                              color: localizacaoId != null
                                  ? Colors.green.shade800
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        const Icon(Icons.edit_location, size: 16, color: Colors.grey),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      final q = _parsePos(qtdCtrl.text);
                      final ch = _parsePos(cheioCtrl.text);
                      final vz = _parsePos(vazioCtrl.text);
                      Navigator.pop<_Lancamento?>(
                        ctx,
                        doc.data.copyWith(
                          quantidade: q,
                          prateleira: endCtrl.text.trim().toUpperCase(),
                          cheio: ch,
                          vazio: vz,
                          lote: loteCtrl.text.trim(),
                          registro: doc.data.registro,
                          localizacaoId:   localizacaoId,
                          localizacaoNome: localizacaoNome,
                        ),
                      );
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('Salvar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );

  if (edited != null) {
    try {
      await repo.updatePartial(
        doc.id,
        quantidade:      edited.quantidade,
        prateleira:      edited.prateleira,
        cheio:           edited.cheio,
        vazio:           edited.vazio,
        lote:            edited.lote,
        localizacaoId:   edited.localizacaoId,
        localizacaoNome: edited.localizacaoNome,
      );
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Lançamento atualizado')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao atualizar: $e')));
    }
  }
}

Future<void> _excluir(BuildContext context, _LancamentoDoc doc, LancamentosRepository repo) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Excluir lançamento'),
      content: Text('Remover ${doc.data.codigo} • ${doc.data.descricao}? Esta ação não pode ser desfeita.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
      ],
    ),
  );
  if (ok != true) return;

  try {
    await repo.delete(doc.id);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lançamento excluído')));
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
  }
}

class _LancamentosListAndTable extends StatelessWidget {
  const _LancamentosListAndTable({
    required this.itens,
    required this.listScroll,
  });

  final List<_LancamentoDoc> itens;
  final ScrollController listScroll;

  String _fmtHora(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(builder: (context, c) {
          final isWideTable = c.maxWidth >= 960;
          return isWideTable ? _buildTable(context) : _buildList(context);
        }),
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    final repo = LancamentosRepository(uid: FirebaseAuth.instance.currentUser!.uid);
    final hdrStyle = Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600);

    Widget _right(String s) => Align(
      alignment: Alignment.centerRight,
      child: Text(s, textAlign: TextAlign.right),
    );

    final table = DataTable(
      columns: [
        DataColumn(label: Text('Status', style: hdrStyle)),
        DataColumn(label: Text('Tipo', style: hdrStyle)),
        DataColumn(label: Text('Tag', style: hdrStyle)),
        DataColumn(label: Text('Descrição', style: hdrStyle)),
        DataColumn(label: Text('Unid.', style: hdrStyle)),
        DataColumn(label: Text('Lote', style: hdrStyle)),
        DataColumn(label: Text('Código', style: hdrStyle)),
        DataColumn(label: Text('Prateleira', style: hdrStyle)),
        DataColumn(label: Text('Vazio', style: hdrStyle)),
        DataColumn(label: Text('Cheio', style: hdrStyle)),
        DataColumn(label: Text('Qtde', style: hdrStyle)),
        DataColumn(label: Text('Data/Hora', style: hdrStyle)),
        const DataColumn(label: Text('Ações')),
      ],
      rows: [
        for (int i = 0; i < itens.length; i++)
          DataRow(
            cells: [
              DataCell(_StatusButton(doc: itens[i], repo: repo)),
              DataCell(
                Chip(
                  label: Text(
                    itens[i].data.registro == TipoRegistro.manual ? 'Manual' : 'Auto',
                    style: const TextStyle(fontSize: 11),
                  ),
                  backgroundColor: itens[i].data.registro == TipoRegistro.manual
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.green.withOpacity(0.2),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              DataCell(Text(itens[i].data.tag)),
              DataCell(Text(itens[i].data.descricao)),
              DataCell(Text(itens[i].data.unidade)),
              DataCell(Text(itens[i].data.lote)),
              DataCell(Text(itens[i].data.codigo)),
              DataCell(Text(itens[i].data.prateleira)),
              DataCell(_right(_fmtQtde(itens[i].data.vazio))),
              DataCell(_right(_fmtQtde(itens[i].data.cheio))),
              DataCell(_right(_fmtQtde(itens[i].data.quantidade))),
              DataCell(Text(_fmtHora(itens[i].data.hora))),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Editar',
                    onPressed: () => _editar(context, itens[i], repo),
                    icon: const Icon(Icons.edit),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: 'Excluir',
                    onPressed: () => _excluir(context, itens[i], repo),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              )),
            ],
          ),
      ],
    );

    final hCtrl = ScrollController();

    return Scrollbar(
      controller: listScroll,
      interactive: true,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: listScroll,
        child: Scrollbar(
          controller: hCtrl,
          interactive: true,
          thumbVisibility: true,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: hCtrl,
            scrollDirection: Axis.horizontal,
            child: table,
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final repo = LancamentosRepository(uid: FirebaseAuth.instance.currentUser!.uid);
    final c = Theme.of(context).colorScheme;

    return Scrollbar(
      controller: listScroll,
      interactive: true,
      thumbVisibility: true,
      child: ListView.separated(
        controller: listScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: itens.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: c.outlineVariant),
        itemBuilder: (context, i) {
          final it = itens[i];

          final linha1 = '${it.data.tag} • ${it.data.descricao}';
          final linha2 = 'Código: ${it.data.codigo} • Unid: ${it.data.unidade} • Lote: ${it.data.lote}';
          final linha3 =
              'Prat: ${it.data.prateleira} • Vazio: ${_fmtQtde(it.data.vazio)} • Cheio: ${_fmtQtde(it.data.cheio)} • Qtde: ${_fmtQtde(it.data.quantidade)}';
          final linha4 = _fmtHora(it.data.hora);

          return ListTile(
            leading: _StatusButton(doc: it, repo: repo),
            title: Text(linha1, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(linha2, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(linha3, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(linha4, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
            isThreeLine: true,
            trailing: Wrap(
              spacing: 8,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Editar',
                  onPressed: () => _editar(context, it, repo),
                  icon: const Icon(Icons.edit),
                ),
                IconButton.filledTonal(
                  tooltip: 'Excluir',
                  onPressed: () => _excluir(context, it, repo),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({required this.doc, required this.repo});
  final _LancamentoDoc doc;
  final LancamentosRepository repo;

  @override
  Widget build(BuildContext context) {
    Icon icon;
    String tooltip;
    switch (doc.data.status) {
      case LancStatus.pending:
        icon = const Icon(Icons.access_time);
        tooltip = 'Pendente';
        break;
      case LancStatus.synced:
        icon = const Icon(Icons.check_circle);
        tooltip = 'Sincronizado';
        break;
      case LancStatus.error:
        icon = const Icon(Icons.error_outline, color: Colors.red);
        tooltip = 'Erro na sincronização';
        break;
    }

    return IconButton(
      tooltip: tooltip,
      onPressed: doc.data.status == LancStatus.error
          ? null
          : () async {
        try {
          final newStatus =
          doc.data.status == LancStatus.synced ? LancStatus.pending : LancStatus.synced;
          await repo.updatePartial(doc.id, status: newStatus);
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Status atualizado')));
        } catch (e) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Erro ao alterar status: $e')));
        }
      },
      icon: icon,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _formKey = GlobalKey<FormState>();
  final _codigoCtrl = TextEditingController();
  final _barrasCtrl = TextEditingController();
  final _qtdCtrl = TextEditingController();
  final _enderecoCtrl = TextEditingController();
  final _cheioCtrl = TextEditingController();
  final _vazioCtrl = TextEditingController();
  final _loteCtrl = TextEditingController();
  final _codigoFocus = FocusNode();
  final _barrasFocus = FocusNode();
  final _qtdFocus = FocusNode();
  final _enderecoFocus = FocusNode();
  final _cheioFocus = FocusNode();
  final _vazioFocus = FocusNode();
  final _loteFocus = FocusNode();
  final _listScroll = ScrollController();
  final _tagQueue = Queue<String>();
  final _cache = <String, Map<String, dynamic>>{};
  final _inventarioService = InventarioService();
  TextEditingController? _buscaCtrl;
  bool _isProcessingQueue = false;
  String? _descricao;
  String? _unidade;
  bool _viaTag = false;
  bool _viaCodigo = false;
  String? _colecaoEncontrada;
  bool _isSubmitting = false;
  String? _tagAtual;
// ⭐ ADICIONAR ESTAS 2 LINHAS
  String? _inventarioAtivo;
  String? _contagemAtiva;
  String? _codigoInventario;
  String? _nomeParticipante;
  String? _statusContagem;
  String? _localizacaoId;    // ⭐ ID da área (ex: ENCHIMENTO_OXIGENIO)
  String? _localizacaoNome;  // ⭐ Nome da área para exibição
  DateTime? _localizacaoSetadaEm; // ⭐ Momento em que a localização foi setada

  // Tempo máximo de validade da localização (minutos)
  static const int _localizacaoTimeoutMin = 10;
  int _totalLancamentos = 0;
  bool _podeContar = false;
  bool _aguardandoLiberacao = false;
  // ✅ ADICIONAR: Cache de TAGs já lançadas
  Set<String>? _tagsCache;
  // Solicitação de participação
  String? _contagemSolicitada;
  String? get _contagemSolicitadaLabel {
    if (_contagemSolicitada == null) return null;
    return _getLabelContagem(_contagemSolicitada!);
  }

  StreamSubscription<DocumentSnapshot>? _participanteListener;

  void _setupParticipanteListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _inventarioAtivo == null) return;

    // Cancela listener anterior se existir
    _participanteListener?.cancel();

    // Escuta mudanças no documento do participante
    _participanteListener = FirebaseFirestore.instance
        .collection('inventarios')
        .doc(_inventarioAtivo)
        .collection('participantes')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || !mounted) return;

      debugPrint('🔄 Participante atualizado em tempo real');
      _buscarDadosParticipante();
    });
  }

  @override
  void initState() {
    super.initState();
    _codigoCtrl.addListener(_onCodigoChanged);
    _barrasCtrl.addListener(_onBarrasChanged);

    // Listeners para exclusão mútua entre código e TAG
    _codigoCtrl.addListener(_checkMutualExclusion);
    _barrasCtrl.addListener(_checkMutualExclusion);

    _barrasFocus.requestFocus();

    // Limpeza automática por inatividade
    _initAutoCleanup();

    // ⭐ Carregar dados
    _buscarInventarioAtivo();

    // ✅ ADICIONAR ESTAS 2 LINHAS
    _buscarDadosParticipante();
    _carregarCacheTags();
  }

// COLE O MÉTODO AQUI ↓
  Future<void> _initAutoCleanup() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final repo = LancamentosRepository(uid: uid);
      await repo.autoCleanupIfInactive();
    }
  }

  Future<void> _abrirSeletorLocalizacao() async {
    final area = await Navigator.of(context).push<PlantArea>(
      MaterialPageRoute(
        builder: (_) => const PlantMapPage(
          jsonAsset: 'assets/plantas/PLANTA_ATUAL_DE_DIADEMA_areas.json',
        ),
      ),
    );

    if (area != null && mounted) {
      setState(() {
        _localizacaoId        = area.id;
        _localizacaoNome      = area.nome;
        _localizacaoSetadaEm  = DateTime.now(); // ⭐ inicia o timer
      });
      debugPrint('✅ Localização selecionada: \${area.id}');
    }
  }

  // Verifica se a localização ainda está dentro do prazo de validade
  bool _localizacaoValida() {
    if (_localizacaoId == null || _localizacaoSetadaEm == null) return false;
    final diferenca = DateTime.now().difference(_localizacaoSetadaEm!);
    return diferenca.inMinutes < _localizacaoTimeoutMin;
  }

  // ⭐ ADICIONAR ESTE MÉTODO COMPLETO
  Future<void> _buscarInventarioAtivo() async {
    try {
      final inventario = await _inventarioService.buscarInventarioAtivo();

      if (inventario == null) {
        debugPrint('ℹ️ Nenhum inventário ativo encontrado');
        setState(() {
          _inventarioAtivo = null;
          _codigoInventario = null;
        });
        return;
      }

      setState(() {
        _inventarioAtivo = inventario.id;
        _codigoInventario = inventario.codigo;
        _contagemAtiva = inventario.contagemAtiva;
      });

      debugPrint('Inventário ativo: ${inventario.codigo} (ID: ${inventario.id})');
      debugPrint('Contagem ativa: ${inventario.contagemAtiva}');

      // ⭐ BUSCAR DADOS DO PARTICIPANTE
      await _buscarDadosParticipante();

      // ⭐ ADICIONAR LISTENER EM TEMPO REAL
      _setupParticipanteListener();

    } catch (e) {
      debugPrint('❌ Erro ao buscar inventário ativo: $e');
    }
  }

  /// Carrega cache de TAGs já utilizadas (UMA VEZ na inicialização)
  Future<void> _carregarCacheTags() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // ✅ Abrir box diretamente do Hive
      final box = await Hive.openBox<LancLocal>('lancamentos_${user.uid}');

      // ✅ Construir Set de tags (O(n) UMA VEZ, depois O(1) para sempre)
      _tagsCache = box.values
          .where((lanc) => lanc.tag != null && lanc.tag!.isNotEmpty)
          .map((lanc) => lanc.tag!)
          .toSet();

      debugPrint('✅ Cache de tags carregado: ${_tagsCache!.length} tags');
    } catch (e) {
      debugPrint('⚠️ Erro ao carregar cache de tags: $e');
      _tagsCache = <String>{};  // Cache vazio em caso de erro
    }
  }

  /// Busca dados do participante atual
  Future<void> _buscarDadosParticipante() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || _inventarioAtivo == null) {
        setState(() {
          _statusContagem = 'nao_iniciada';
          _podeContar = false;
        });
        return;
      }

      final participanteDoc = await FirebaseFirestore.instance
          .collection('inventarios')
          .doc(_inventarioAtivo)
          .collection('participantes')
          .doc(user.uid)
          .get();

      // ✅ VERIFICAR SE DOCUMENTO EXISTE
      if (!participanteDoc.exists) {
        debugPrint('⚠️ Participante não encontrado no inventário');
        setState(() {
          _statusContagem = 'nao_iniciada';
          _podeContar = false;
        });
        return;
      }

      // ✅ SAFE UNWRAP - verificar se data() não é null
      final data = participanteDoc.data();
      if (data == null) {
        debugPrint('⚠️ Documento existe mas data() é null');
        setState(() {
          _statusContagem = 'nao_iniciada';
          _podeContar = false;
        });
        return;
      }

      // ✅ EXTRAIR DADOS COM SEGURANÇA
      _nomeParticipante = data['displayName'] as String?;
      _contagemAtiva = data['contagem_atual'] as String? ?? 'contagem_1';
      _contagemSolicitada = data['contagem_solicitada'] as String?;

      // ✅ SAFE KEY ACCESS - verificar se chave existe
      final contagemSuffix = _contagemAtiva?.replaceAll('contagem_', 'c') ?? 'c1';
      final statusKey = 'status_$contagemSuffix';

      final statusAtual = data.containsKey(statusKey)
          ? (data[statusKey] as String? ?? 'nao_iniciada')
          : 'nao_iniciada';

      // ✅ VERIFICAR LIBERAÇÕES
      final liberadoParaC2 = data['liberado_para_c2'] as bool? ?? false;
      final liberadoParaC3 = data['liberado_para_c3'] as bool? ?? false;

      setState(() {
        _statusContagem = statusAtual;

        // ✅ LÓGICA DE PERMISSÃO
        if (_contagemAtiva == 'contagem_1') {
          _podeContar = (statusAtual == 'nao_iniciada' || statusAtual == 'em_andamento');
        } else if (_contagemAtiva == 'contagem_2') {
          _podeContar = liberadoParaC2 && (statusAtual == 'nao_iniciada' || statusAtual == 'em_andamento');
        } else if (_contagemAtiva == 'contagem_3') {
          _podeContar = liberadoParaC3 && (statusAtual == 'nao_iniciada' || statusAtual == 'em_andamento');
        } else {
          _podeContar = false;
        }

        debugPrint('Status: $_statusContagem, Pode contar: $_podeContar, Contagem: $_contagemAtiva');
      });

    } catch (e, stackTrace) {
      debugPrint('❌ ERRO ao buscar participante: $e');
      debugPrint('Stack: $stackTrace');

      // ✅ ESTADO SEGURO EM CASO DE ERRO
      if (mounted) {
        setState(() {
          _statusContagem = 'erro';
          _podeContar = false;
        });
      }
    }
  }

  /// Iniciar participação no inventário (chamado via botão)
  Future<void> _iniciarParticipacao() async {
    try {
      if (_inventarioAtivo == null) {
        _snack('Erro: Inventário não carregado');
        return;
      }

      await _inventarioService.iniciarParticipante(_inventarioAtivo!);

      // ⭐ ATUALIZAR ESTADO IMEDIATAMENTE
      await _buscarDadosParticipante();

      _snack('Participação iniciada! Você está na $_contagemAtiva');
    } catch (e) {
      debugPrint('❌ Erro ao iniciar participação: $e');
      _snack('Erro ao iniciar participação: $e');
    }
  }

  /// Finalizar contagem atual
  Future<void> _finalizarContagem() async {
    try {
      if (_inventarioAtivo == null || _contagemAtiva == null) {
        _snack('Erro: Inventário não carregado');
        return;
      }

      // Contar lançamentos SINCRONIZADOS no Firestore desta contagem
      final lancamentosSnapshot = await FirebaseFirestore.instance
          .collection('lancamentos')
          .where('inventarioId', isEqualTo: _inventarioAtivo)
          .where('contagemId', isEqualTo: _contagemAtiva)
          .where('uid', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .get();

      final totalLancamentos = lancamentosSnapshot.size;

      // Validar se tem lançamentos
      if (totalLancamentos == 0) {
        _snack('Você precisa fazer pelo menos 1 lançamento antes de finalizar');
        return;
      }

      // Determinar label da contagem
      final contagemLabel = _contagemAtiva == 'contagem_1'
          ? '1ª Contagem'
          : _contagemAtiva == 'contagem_2'
          ? '2ª Contagem'
          : '3ª Contagem';

      // Confirmar finalização
      final confirma = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Finalizar $contagemLabel?'),
          content: Text(
            'Você fez $totalLancamentos lançamento(s).\n\n'
                'Após finalizar, você não poderá mais fazer lançamentos '
                'até que o analista libere a próxima contagem.\n\n'
                'Deseja continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Finalizar'),
            ),
          ],
        ),
      );

      if (confirma != true) return;

      // Finalizar no service
      await InventarioService().finalizarContagemParticipante(
        _inventarioAtivo!,
        _contagemAtiva!,
      );

      // Atualizar estado local
      await _buscarDadosParticipante();

      _snack('Contagem finalizada com sucesso! ($totalLancamentos lançamentos)');
    } catch (e) {
      debugPrint('❌ Erro ao finalizar contagem: $e');
      _snack('Erro ao finalizar: $e');
    }
  }

  // Método para controlar exclusão mútua entre código e TAG
  void _checkMutualExclusion() {
    setState(() {
      // Se código foi preenchido, desabilita TAG
      if (_codigoCtrl.text.isNotEmpty) {
        _viaCodigo = true;
      } else {
        _viaCodigo = false;
      }

      // Se TAG foi preenchida, desabilita código
      if (_barrasCtrl.text.isNotEmpty) {
        _viaTag = true;
      } else {
        _viaTag = false;
      }
    });
  }

  void _onCodigoChanged() {
    _debounce?.cancel();
    final codigo = _codigoCtrl.text.trim();

    // Trunca automaticamente se ultrapassar 8 dígitos
    if (codigo.length > 8) {
      _codigoCtrl.text = codigo.substring(0, 8);
      _codigoCtrl.selection = TextSelection.collapsed(offset: 8);
      return;
    }

    // Busca automática ao completar 8 dígitos
    if (codigo.length == 8) {
      _debounce = Timer(const Duration(milliseconds: 300), () {
        _buscarProduto();
      });
    }
  }

  Timer? _debounce;

  void _onBarrasChanged() {
    _debounce?.cancel();
    final tag = _barrasCtrl.text;
    if (tag.endsWith('\n')) {
      _debounce = Timer(const Duration(milliseconds: 100), () {
        _buscarBarras();
      });
    }
  }

  @override
  void dispose() {
    _codigoCtrl.removeListener(_onCodigoChanged);
    _barrasCtrl.removeListener(_onBarrasChanged);
    _debounce?.cancel();
    _codigoCtrl.dispose();
    _barrasCtrl.dispose();
    _qtdCtrl.dispose();
    _enderecoCtrl.dispose();
    _cheioCtrl.dispose();
    _vazioCtrl.dispose();
    _loteCtrl.dispose();
    _codigoFocus.dispose();
    _barrasFocus.dispose();
    _qtdFocus.dispose();
    _enderecoFocus.dispose();
    _cheioFocus.dispose();
    _vazioFocus.dispose();
    _loteFocus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  Future<void> _buscarProduto() async {
    final codigo = _codigoCtrl.text.trim();
    if (codigo.isEmpty) {
      setState(() {
        _descricao = null;
        _unidade = null;
        _colecaoEncontrada = null;
        _viaTag = false;
        _viaCodigo = false;
      });
      return;
    }

    // Limpar TAG ao buscar por código
    _barrasCtrl.clear();

    try {
      debugPrint('Buscando produto pelo código: $codigo');
      final repo = ProdutosRepository();
      final p = await repo.getByCodigoPreferGases(codigo);
      if (p == null) {
        // Oferece cadastro manual
        final confirma = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Produto não encontrado'),
            content: Text('O código $codigo não foi encontrado no sistema.\nDeseja cadastrar manualmente?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.add),
                label: const Text('Cadastrar'),
              ),
            ],
          ),
        );

        if (confirma == true) {
          await _mostrarOpcaoCadastroManual(codigo: codigo);
          return;
        }

        // Usuário cancelou — limpa o campo para nova digitação sem interferência
        _codigoCtrl.clear();
        setState(() {
          _descricao = null;
          _unidade = null;
          _colecaoEncontrada = null;
          _viaTag = false;
          _viaCodigo = false;
        });
        _snack('Produto não encontrado. Digite o código novamente.', error: true);
        _codigoFocus.requestFocus();
        return;
      }
      setState(() {
        _descricao = p.descricao;
        _unidade = p.unidade;
        _colecaoEncontrada = p.origem;
        _viaCodigo = true;
        _viaTag = false;
        debugPrint('Produto encontrado: ${_descricao}, coleção: $_colecaoEncontrada');
      });
      if (p.origem == 'gases') {
        _vazioFocus.requestFocus();
      } else {
        _qtdFocus.requestFocus();
      }
    } catch (e) {
      debugPrint('Erro ao buscar produto: $e');
      _snack('Falha ao buscar produto local: $e', error: true);
      _codigoFocus.requestFocus();
    }
  }

  Future<void> _buscarBarras() async {
    final tag = _barrasCtrl.text.trim();
    _tagAtual = tag;
    if (tag.isEmpty) {
      _tagAtual = null;
      setState(() {
        _descricao = null;
        _unidade = null;
        _colecaoEncontrada = null;
        _viaTag = false;
        _viaCodigo = false;
      });
      debugPrint('Tag vazia, limpando campos');
      return;
    }

    // Limpar código ao buscar por TAG
    _codigoCtrl.clear();

    // Verificar se TAG já foi lançada
    try {
      final repo = LancamentosRepository(uid: FirebaseAuth.instance.currentUser!.uid);
      final jaExiste = await repo.tagJaExiste(tag);

      if (jaExiste) {
        setState(() {
          _descricao = null;
          _unidade = null;
          _colecaoEncontrada = null;
          _viaTag = false;
          _viaCodigo = false;
        });
        _snack('⚠️ TAG já foi lançada anteriormente!', error: true);
        _barrasCtrl.clear();
        _barrasFocus.requestFocus();
        return;
      }
    } catch (e) {
      debugPrint('Erro ao verificar TAG repetida: $e');
    }

    try {
      debugPrint('Buscando tag: $tag');
      final repo = BarrasRepository();

      // Tenta buscar com a tag original
      var barra = await repo.getByTag(tag);

      if (barra == null) {
        // Tenta remover zeros à esquerda
        final tagSemZeros = tag.replaceFirst(RegExp(r'^0+'), '');
        if (tagSemZeros != tag && tagSemZeros.isNotEmpty) {
          debugPrint('Tentando buscar sem zeros à esquerda: $tagSemZeros');
          barra = await repo.getByTag(tagSemZeros);
        }
      }

      if (barra == null) {
        // Oferece cadastro manual
        final confirma = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Tag não encontrada'),
            content: Text('A tag $tag não foi encontrada no sistema.\nDeseja cadastrar manualmente?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.add),
                label: const Text('Cadastrar'),
              ),
            ],
          ),
        );

        if (confirma == true) {
          await _mostrarOpcaoCadastroManual(tag: tag);
          return;
        }

        // Usuário cancelou — limpa o campo para nova digitação
        _barrasCtrl.clear();
        setState(() {
          _descricao = null;
          _unidade = null;
          _colecaoEncontrada = null;
          _viaTag = false;
          _viaCodigo = false;
        });
        debugPrint('Tag não encontrada');
        _snack('Tag não encontrada. Digite a tag novamente.', error: true);
        _barrasFocus.requestFocus();
        return;
      }

      debugPrint('Tag encontrada: ${barra!.codigo}, lote: ${barra.lote}');
      final produto = await ProdutosRepository().getByCodigoPreferGases(barra.codigo);

      if (produto == null) {
        setState(() {
          _descricao = null;
          _unidade = null;
          _colecaoEncontrada = null;
          _viaTag = false;
          _viaCodigo = false;
        });
        debugPrint('Produto da tag não encontrado');
        _snack('Produto da tag não encontrado', error: true);
        _barrasFocus.requestFocus();
        return;
      }

      debugPrint('Produto encontrado: ${produto.descricao}, coleção: ${produto.origem}');
      setState(() {
        _viaTag = true;
        _viaCodigo = false;
        _codigoCtrl.text = barra!.codigo;
        _loteCtrl.text = barra!.lote ?? '';
        _descricao = produto.descricao;
        _unidade = produto.unidade;
        _colecaoEncontrada = produto.origem;
        _cheioCtrl.text = '1';
        _vazioCtrl.text = '0';
      });

      if (produto.origem == 'gases') {
        debugPrint('Registrando lançamento automaticamente para gases');
        await Future.delayed(const Duration(milliseconds: 100));
        await _confirmar();
      } else {
        debugPrint('Tag de materiais, aguardando confirmação manual');
        _qtdFocus.requestFocus();
      }
    } catch (e) {
      debugPrint('Erro ao buscar tag: $e');
      _snack('Falha ao buscar tag local: $e', error: true);
      _barrasFocus.requestFocus();
    }
  }

  Future<bool> _mostrarOpcaoCadastroManual({String? codigo, String? tag}) async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CadastroManualDialog(
        codigoInicial: codigo,
        tagInicial: tag,
      ),
    );

    if (resultado != null) {
      // Salvar produto manual
      final prodRepo = ProdutosRepository();
      await prodRepo.addManualProduct(
        codigo: resultado['codigo'],
        descricao: resultado['descricao'],
        unidade: resultado['unidade'],
        volume: resultado['volume'],
      );

      // Registrar lançamento manual
      final repo = LancamentosRepository(uid: FirebaseAuth.instance.currentUser!.uid);
      await repo.addPending(
        uid: FirebaseAuth.instance.currentUser!.uid,  // ✅ ADICIONAR
        inventarioId: _inventarioAtivo ?? '',  // ✅ Garantir não-null
        contagemId: _contagemAtiva ?? '',      // ✅ Garantir não-null
        codigo: resultado['codigo'] ?? '',
        descricao: resultado['descricao'] ?? '',
        unidade: resultado['unidade'] ?? '',
        prateleira: resultado['prateleira'] ?? '',
        quantidade: resultado['quantidade'],
        cheio: 0.0,  // ✅ Campos obrigatórios
        vazio: 0.0,  // ✅ Campos obrigatórios
        lote: resultado['lote'],
        tag: resultado['tag'],
        volume: resultado['volume'],
        registro: TipoRegistro.manual,
        localizacaoId:   _localizacaoId,    // ⭐ LOCALIZAÇÃO
        localizacaoNome: _localizacaoNome,  // ⭐ LOCALIZAÇÃO
      );

      _snack('Produto cadastrado e lançado manualmente');

      // Limpar campos
      _formKey.currentState?.reset();
      _codigoCtrl.clear();
      _barrasCtrl.clear();
      _qtdCtrl.clear();
      _enderecoCtrl.clear();
      _cheioCtrl.clear();
      _vazioCtrl.clear();
      _loteCtrl.clear();
      setState(() {
        _descricao = null;
        _unidade = null;
        _colecaoEncontrada = null;
        _viaTag = false;
        _viaCodigo = false;
      });
      _barrasFocus.requestFocus();

      // Sincronizar
      await _tentarSincronizar(FirebaseAuth.instance.currentUser!.uid);
      return true;
    }
    return false;
  }

  Future<void> _tentarSincronizar(String uid) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      debugPrint('Resultado da conectividade: $connectivityResult');
      if (connectivityResult != ConnectivityResult.none) {
        debugPrint('Sincronizando lançamentos para uid: $uid');
        await SyncService.syncLancamentos(uid);
        if (mounted) {
          _snack('Sincronização concluída');
        }
      } else {
        debugPrint('Sem conexão, sincronização não realizada');
        if (mounted) {
          _snack('Sem conexão. Lançamento salvo localmente.');
        }
      }
    } catch (e) {
      debugPrint('Erro ao verificar conectividade ou sincronizar: $e');
      if (mounted) {
        _snack('Sem conexão. Lançamento salvo localmente.');
      }
    }
  }

  Future<void> _confirmar() async {
    if (_isSubmitting) return;

    // ⭐ Bloquear se localização não selecionada ou expirada
    if (!_localizacaoValida()) {
      setState(() {
        _localizacaoId       = null;
        _localizacaoNome     = null;
        _localizacaoSetadaEm = null;
      });
      _snack(
        _localizacaoId == null
            ? 'Selecione uma localização antes de lançar'
            : 'Localização expirada. Confirme onde você está.',
        error: true,
      );
      return;
    }

    // Validação ajustada: verificar flags ao invés dos campos diretamente
    // porque quando via TAG, o código é preenchido automaticamente

    if (!_formKey.currentState!.validate()) {
      debugPrint('Validação do formulário falhou');
      _snack('Preencha os campos obrigatórios corretamente', error: true);
      return;
    }
    setState(() {
      _isSubmitting = true;
    });

    final codigo = _codigoCtrl.text.trim();
    final tag = _barrasCtrl.text.trim();

    // ✅ Cheio e Vazio: converter para double sem decimais
    final cheioText = _cheioCtrl.text.trim().replaceAll(',', '.');
    final vazioText = _vazioCtrl.text.trim().replaceAll(',', '.');

// Parse como inteiro e depois converte para double (remove .0)
    final cheio = cheioText.isEmpty
        ? 0.0
        : (int.tryParse(cheioText.split('.')[0]) ?? 0).toDouble();

    final vazio = vazioText.isEmpty
        ? 0.0
        : (int.tryParse(vazioText.split('.')[0]) ?? 0).toDouble();

    // Para gases via TAG, quantidade deve ficar 0 (vazio)
    // Para materiais, pega o valor do campo quantidade
    final qtd = _colecaoEncontrada == 'gases' && _viaTag
        ? 0.0
        : (double.tryParse(_qtdCtrl.text.replaceAll(',', '.')) ?? 0.0);

    final endereco = _enderecoCtrl.text.trim().toUpperCase();
    final lote = _loteCtrl.text.trim();

    debugPrint('Registrando lançamento: codigo=$codigo, tag=$tag, qtd=$qtd, endereco=$endereco, cheio=$cheio, vazio=$vazio, lote=$lote, coleção=$_colecaoEncontrada');
    debugPrint('===== DEBUG TAG =====');
    debugPrint('Valor de tag: "$tag"');
    debugPrint('Tamanho: ${tag.length}');
    debugPrint('Bytes: ${tag.codeUnits}');
    debugPrint('_barrasCtrl.text: "${_barrasCtrl.text}"');
    debugPrint('===================');

    try {
      final repo = LancamentosRepository(uid: FirebaseAuth.instance.currentUser!.uid);
      await repo.addPending(
        uid: FirebaseAuth.instance.currentUser!.uid,  // ✅ ADICIONAR
        inventarioId: _inventarioAtivo ?? '',  // ✅ Garantir não-null
        contagemId: _contagemAtiva ?? '',      // ✅ Garantir não-null
        codigo: codigo,
        descricao: _descricao ?? '',
        unidade: _unidade ?? '',
        prateleira: endereco,
        quantidade: qtd,
        cheio: cheio,
        vazio: vazio,
        lote: lote.isEmpty ? null : lote,  // ✅ Null se vazio
        tag: tag.isEmpty ? null : tag,      // ✅ Null se vazio
        volume: null,
        registro: TipoRegistro.automatico,
        localizacaoId:   _localizacaoId,    // ⭐ LOCALIZAÇÃO
        localizacaoNome: _localizacaoNome,  // ⭐ LOCALIZAÇÃO
      );

      debugPrint('Lançamento registrado com sucesso no Hive');
      _snack('Lançamento registrado com sucesso');
      _formKey.currentState!.reset();
      _codigoCtrl.clear();
      _barrasCtrl.clear();
      _qtdCtrl.clear();
      _enderecoCtrl.clear();
      _cheioCtrl.clear();
      _vazioCtrl.clear();
      _loteCtrl.clear();
      setState(() {
        _descricao = null;
        _unidade = null;
        _colecaoEncontrada = null;
        _viaTag = false;
        _viaCodigo = false;
        _tagAtual = null;
      });

      FocusScope.of(context).unfocus();
      _barrasFocus.requestFocus();

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        Future.microtask(() => _tentarSincronizar(uid));
      } else {
        debugPrint('Usuário não autenticado, sincronização não realizada');
        _snack('Faça login para sincronizar', error: true);
      }
    } catch (e) {
      debugPrint('Erro ao registrar lançamento: $e');
      _snack('Erro ao registrar lançamento: $e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        _barrasFocus.requestFocus();
      }
    }
  }

  Future<void> _sincronizar() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('Usuário não autenticado, sincronização cancelada');
      _snack('Faça login para sincronizar', error: true);
      return;
    }
    await _tentarSincronizar(uid);
  }

  String? _validarCodigo(String? value) {
    debugPrint('Validando código: $value');
    if (value == null || value.trim().isEmpty) {
      return 'Digite o código ou tag';
    }
    if (_descricao == null) {
      return 'Produto não encontrado';
    }
    return null;
  }

  String? _validarQuantidade(String? value) {
    debugPrint('Validando quantidade: $value');
    if (_colecaoEncontrada == 'materiais') {
      if (value == null || value.trim().isEmpty) {
        return 'Digite a quantidade';
      }
      final v = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
      if (v <= 0) {
        return 'Quantidade deve ser maior que zero';
      }
    }
    return null;
  }

  String? _validarEndereco(String? value) {
    if (_colecaoEncontrada == 'materiais') {
      if (value == null || value.trim().isEmpty) {
        return 'Digite a prateleira';
      }

      final endereco = value.trim().toUpperCase();

      // ✅ Validação flexível:
      // - Aceita: 6K9, 10A5, ESC, RECEP, 1AA, DEV, etc.
      // - Rejeita: espaços, caracteres especiais, muito longo

      if (endereco.length < 2 || endereco.length > 10) {
        return 'Prateleira deve ter entre 2 e 10 caracteres';
      }

      // ✅ Aceita apenas letras e números (sem espaços/especiais)
      if (!RegExp(r'^[A-Z0-9]+$').hasMatch(endereco)) {
        return 'Use apenas letras e números (ex: 6K9, 10A5, ESC)';
      }

      // ✅ Atualizar controller com versão maiúscula
      if (value != endereco) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _enderecoCtrl.text == value) {
            _enderecoCtrl.value = _enderecoCtrl.value.copyWith(
              text: endereco,
              selection: TextSelection.collapsed(offset: endereco.length),
            );
          }
        });
      }
    }
    return null;
  }

  String? _validarCheio(String? value) {
    debugPrint('Validando cheio: $value');
    if (_colecaoEncontrada == 'gases') {
      final cheio = double.tryParse(value?.replaceAll(',', '.') ?? '') ?? 0.0;
      final vazio = double.tryParse(_vazioCtrl.text.replaceAll(',', '.')) ?? 0.0;
      if (cheio < 0) {
        return 'Cheio não pode ser negativo';
      }
      if (cheio == 0 && vazio == 0) {
        return 'Cheio ou Vazio deve ser maior que zero';
      }
    }
    return null;
  }

  String? _validarVazio(String? value) {
    debugPrint('Validando vazio: $value');
    if (_colecaoEncontrada == 'gases') {
      final vazio = double.tryParse(value?.replaceAll(',', '.') ?? '') ?? 0.0;
      final cheio = double.tryParse(_cheioCtrl.text.replaceAll(',', '.')) ?? 0.0;
      if (vazio < 0) {
        return 'Vazio não pode ser negativo';
      }
      if (vazio == 0 && cheio == 0) {
        return 'Cheio ou Vazio deve ser maior que zero';
      }
    }
    return null;
  }

  void _snack(String msg, {bool error = false}) {
    debugPrint('Exibindo snackbar: $msg, error: $error');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<List<String>> _buscarSugestoes(String query) async {
    if (query.isEmpty) return [];

    try {
      final repo = ProdutosRepository();
      final resultados = await repo.searchCodigosOuDescricoes(query);
      return resultados;
    } catch (e, stackTrace) {
      debugPrint('❌ Erro ao buscar sugestões: $e');
      debugPrint('Stack: $stackTrace');
      return []; // Retorna vazio em caso de erro
    }
  }

  void _selecionarSugestao(String item) async {
    final codigo = item.split('•').first.trim();
    _codigoCtrl.text = codigo;
    _barrasCtrl.clear();  // Limpar TAG ao selecionar código
    debugPrint('Sugestão selecionada: $item, código: $codigo');
    await _buscarProduto();
    FocusScope.of(context).unfocus();
  }

  Widget _buildLocalizacaoWidget() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _localizacaoId != null ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _localizacaoId != null ? Colors.green : Colors.red,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _localizacaoId != null ? Icons.check_circle : Icons.warning,
                color: _localizacaoId != null ? Colors.green : Colors.red,
              ),
              SizedBox(width: 8),
              Text(
                _localizacaoId != null
                    ? '📍 Você está em:'
                    : '⚠️ Selecione sua localização',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),

          if (_localizacaoId != null) ...[
            // Tempo restante de validade
            Builder(builder: (context) {
              final restante = _localizacaoSetadaEm == null
                  ? 0
                  : _localizacaoTimeoutMin -
                    DateTime.now().difference(_localizacaoSetadaEm!).inMinutes;
              final valida = _localizacaoValida();
              return Text(
                valida
                    ? '⏱ Válida por mais $restante min'
                    : '⚠️ Localização expirada',
                style: TextStyle(
                  fontSize: 12,
                  color: valida
                      ? (restante <= 2 ? Colors.orange : Colors.green.shade700)
                      : Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              );
            }),
            const SizedBox(height: 4),
            Text(
              _localizacaoNome ?? _localizacaoId!,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade900,
              ),
            ),
            SizedBox(height: 8),
            TextButton.icon(
              onPressed: _abrirSeletorLocalizacao,
              icon: Icon(Icons.edit_location),
              label: Text('Alterar Localização'),
            ),
          ] else ...[
            SizedBox(height: 4),
            Text(
              'Nenhuma localização selecionada',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
            SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _abrirSeletorLocalizacao,
              icon: Icon(Icons.map),
              label: Text('Selecionar Localização'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lego - Lançamentos'),
        actions: [
          IconButton(
            tooltip: 'Limpeza Manual',
            icon: const Icon(Icons.cleaning_services),
            onPressed: () async {
              final repo = LancamentosRepository(
                uid: FirebaseAuth.instance.currentUser!.uid,
              );
              await showDialog(
                context: context,
                builder: (context) => _ManualCleanupDialog(repo: repo),
              );
            },
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: 'Sincronizar',
                onPressed: _isSubmitting ? null : _sincronizar,
                icon: const Icon(Icons.sync),
              ),
              if (_isSubmitting)
                const Positioned(
                  right: 8,
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: _statusContagem == 'em_andamento' && _podeContar
          ? FloatingActionButton.extended(
        onPressed: _finalizarContagem,
        icon: const Icon(Icons.check_circle),
        label: Text(_contagemAtiva == 'contagem_1'
            ? 'Finalizar 1ª Contagem'
            : _contagemAtiva == 'contagem_2'
            ? 'Finalizar 2ª Contagem'
            : 'Finalizar 3ª Contagem'),
        backgroundColor: Colors.orange,
      )
          : null,
        body: Column(
            children: [if (_statusContagem == 'nao_iniciada')
            // Header do inventário
            if (_inventarioAtivo != null) _buildHeaderInventario(),

            // ⭐ WIDGET DE LOCALIZAÇÃO GEOGRÁFICA
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: _buildLocalizacaoWidget(),
            ),

    // Conteúdo original
    Expanded(
    child: LayoutBuilder(
    builder: (context, constraints) {
          final isSmartphonePortrait =
              constraints.maxWidth < 600 && MediaQuery.of(context).orientation == Orientation.portrait;

          if (isSmartphonePortrait) {
            return Column(
              children: [
                Expanded(
                  flex: 13,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Autocomplete<String>(
                          optionsBuilder: (TextEditingValue textEditingValue) async {
                            if (textEditingValue.text.isEmpty) {
                              debugPrint('Consulta vazia');
                              return const Iterable<String>.empty();
                            }
                            debugPrint('Buscando sugestões para: ${textEditingValue.text}');

                            try {
                              return await _buscarSugestoes(textEditingValue.text);
                            } catch (e) {
                              debugPrint('❌ Erro no Autocomplete (Portrait): $e');
                              return const Iterable<String>.empty();
                            }
                          },
                          onSelected: (String selection) async {
                            debugPrint('Sugestão selecionada: $selection');
                            _selecionarSugestao(selection);
                          },
                          fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                            _buscaCtrl = controller;
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                labelText: 'Buscar produto (cód. ou descrição)',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: controller.text.isNotEmpty
                                    ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    controller.clear();
                                    setState(() {
                                      _descricao = null;
                                      _unidade = null;
                                      _colecaoEncontrada = null;
                                      _viaTag = false;
                                      _viaCodigo = false;
                                      _codigoCtrl.clear();
                                      _barrasCtrl.clear();
                                      _qtdCtrl.clear();
                                      _enderecoCtrl.clear();
                                      _cheioCtrl.clear();
                                      _vazioCtrl.clear();
                                      _loteCtrl.clear();
                                      TextEditingController? _buscaCtrl;
                                    });
                                    focusNode.requestFocus();
                                  },
                                )
                                    : null,
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (value) {
                                debugPrint('Texto digitado: $value');
                                setState(() {});
                              },
                              onSubmitted: (value) {
                                if (value.isNotEmpty) {
                                  _selecionarSugestao(value);
                                  controller.clear();
                                }
                              },
                            );
                          },
                        ),
                      ),
                      Expanded(
                        child: _FormPane(
                          formKey: _formKey,
                          codigoCtrl: _codigoCtrl,
                          barrasCtrl: _barrasCtrl,
                          qtdCtrl: _qtdCtrl,
                          enderecoCtrl: _enderecoCtrl,
                          cheioCtrl: _cheioCtrl,
                          vazioCtrl: _vazioCtrl,
                          loteCtrl: _loteCtrl,
                          codigoFocus: _codigoFocus,
                          barrasFocus: _barrasFocus,
                          qtdFocus: _qtdFocus,
                          enderecoFocus: _enderecoFocus,
                          cheioFocus: _cheioFocus,
                          vazioFocus: _vazioFocus,
                          loteFocus: _loteFocus,
                          descricao: _descricao,
                          unidade: _unidade,
                          onBuscar: _buscarProduto,
                          onBuscarBarras: _buscarBarras,
                          onConfirmar: _confirmar,
                          validarCodigo: _validarCodigo,
                          validarQuantidade: _validarQuantidade,
                          validarEndereco: _validarEndereco,
                          validarCheio: _validarCheio,
                          validarVazio: _validarVazio,
                          codigoEnabled: !_viaTag,
                          barrasEnabled: !_viaCodigo,
                          qtdPratEnabled: _colecaoEncontrada == 'materiais' && !_viaTag,
                          cheioEnabled: _colecaoEncontrada == 'gases' && !_viaTag,
                          vazioEnabled: _colecaoEncontrada == 'gases' && !_viaTag,
                          loteEnabled: _colecaoEncontrada != 'materiais',
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 7,
                  child: _LancamentosPane(
                    uid: FirebaseAuth.instance.currentUser?.uid,
                    listScroll: _listScroll,
                  ),
                ),
              ],
            );
          } else {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) async {
                      if (textEditingValue.text.isEmpty) {
                        debugPrint('Consulta vazia');
                        return const Iterable<String>.empty();
                      }
                      debugPrint('Buscando sugestões para: ${textEditingValue.text}');

                      try {
                        return await _buscarSugestoes(textEditingValue.text);
                      } catch (e) {
                        debugPrint('❌ Erro no Autocomplete (Landscape): $e');
                        return const Iterable<String>.empty();
                      }
                    },
                    onSelected: (String selection) async {
                      debugPrint('Sugestão selecionada: $selection');
                      _selecionarSugestao(selection);
                    },
                    fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'Buscar produto (cód. ou descrição)',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: controller.text.isNotEmpty
                              ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              controller.clear();
                              setState(() {
                                _descricao = null;
                                _unidade = null;
                                _colecaoEncontrada = null;
                                _viaTag = false;
                                _viaCodigo = false;
                                _codigoCtrl.clear();
                                _barrasCtrl.clear();
                                _qtdCtrl.clear();
                                _enderecoCtrl.clear();
                                _cheioCtrl.clear();
                                _vazioCtrl.clear();
                                _loteCtrl.clear();
                              });
                              focusNode.requestFocus();
                            },
                          )
                              : null,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          debugPrint('Texto digitado: $value');
                          setState(() {});
                        },
                        onSubmitted: (value) {
                          if (value.isNotEmpty) {
                            _selecionarSugestao(value);
                            controller.clear();
                          }
                        },
                      );
                    },
                  ),
                ),
                _FormPane(
                  formKey: _formKey,
                  codigoCtrl: _codigoCtrl,
                  barrasCtrl: _barrasCtrl,
                  qtdCtrl: _qtdCtrl,
                  enderecoCtrl: _enderecoCtrl,
                  cheioCtrl: _cheioCtrl,
                  vazioCtrl: _vazioCtrl,
                  loteCtrl: _loteCtrl,
                  codigoFocus: _codigoFocus,
                  barrasFocus: _barrasFocus,
                  qtdFocus: _qtdFocus,
                  enderecoFocus: _enderecoFocus,
                  cheioFocus: _cheioFocus,
                  vazioFocus: _vazioFocus,
                  loteFocus: _loteFocus,
                  descricao: _descricao,
                  unidade: _unidade,
                  onBuscar: _buscarProduto,
                  onBuscarBarras: _buscarBarras,
                  onConfirmar: _confirmar,
                  validarCodigo: _validarCodigo,
                  validarQuantidade: _validarQuantidade,
                  validarEndereco: _validarEndereco,
                  validarCheio: _validarCheio,
                  validarVazio: _validarVazio,
                  codigoEnabled: !_viaTag,
                  barrasEnabled: !_viaCodigo,
                  qtdPratEnabled: _colecaoEncontrada == 'materiais' && !_viaTag,
                  cheioEnabled: _colecaoEncontrada == 'gases' && !_viaTag,
                  vazioEnabled: _colecaoEncontrada == 'gases' && !_viaTag,
                  loteEnabled: _colecaoEncontrada != 'materiais',
                ),
                Expanded(
                  child: _LancamentosPane(
                    uid: FirebaseAuth.instance.currentUser?.uid,
                    listScroll: _listScroll,
                  ),
                ),
              ],
            );
          }
        },
      ),
    ),
    ],
        ),
    );
  }
  Widget _buildHeaderInventario() {
    // DEBUG
    debugPrint('=== HEADER DEBUG ===');
    debugPrint('Status: $_statusContagem');
    debugPrint('Pode contar: $_podeContar');
    debugPrint('Aguardando: $_aguardandoLiberacao');
    debugPrint('===================');

    // Determinar label da contagem
    String contagemLabel = 'Carregando...';
    if (_contagemAtiva == 'contagem_1') {
      contagemLabel = '1ª Contagem';
    } else if (_contagemAtiva == 'contagem_2') {
      contagemLabel = '2ª Contagem';
    } else if (_contagemAtiva == 'contagem_3') {
      contagemLabel = '3ª Contagem';
    }

    // Cor do status
    Color statusColor = Colors.grey;
    String statusText = 'Aguardando início';
    IconData statusIcon = Icons.hourglass_empty;

    if (_aguardandoLiberacao) {
      statusColor = Colors.orange;
      statusText = 'Aguardando liberação';
      statusIcon = Icons.lock_clock;
    } else if (_podeContar) {
      statusColor = Colors.green;
      statusText = 'Em andamento';
      statusIcon = Icons.play_arrow;
    } else if (_statusContagem == 'nao_iniciada') {
      statusColor = Colors.blue;
      statusText = 'Não iniciada';
      statusIcon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.blue.shade200, width: 2),
        ),
      ),
      child: Column(
        children: [
          // Linha 1: Código do inventário
          Row(
            children: [
              Icon(Icons.inventory_2, color: Colors.blue, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _codigoInventario ?? 'Carregando...',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      contagemLabel,
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Total de lançamentos
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Text(
                  '$_totalLancamentos itens',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Linha 2: Status
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 16),
              const SizedBox(width: 6),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              if (_nomeParticipante != null) ...[
                const Spacer(),
                Text(
                  _nomeParticipante!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ],
          ),

          // Botão de iniciar (se não iniciou ainda)
          // Botões de solicitação (se ainda não solicitou)
          if (_statusContagem == 'nao_iniciada') ...[
            const SizedBox(height: 8),
            const Text(
              'Escolha a contagem que deseja participar:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _solicitarParticipacao('contagem_1'),
                    child: const Text('1ª Contagem'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _solicitarParticipacao('contagem_2'),
                    child: const Text('2ª Contagem'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _solicitarParticipacao('contagem_3'),
                    child: const Text('3ª Contagem'),
                  ),
                ),
              ],
            ),
          ],

// Aguardando aprovação
          if (_statusContagem == 'solicitacao_pendente') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  Icon(Icons.hourglass_empty, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aguardando aprovação do analista',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_contagemSolicitadaLabel != null)
                          Text(
                            'Você solicitou: $_contagemSolicitadaLabel',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

// Solicitação rejeitada
          if (_statusContagem == 'rejeitado') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cancel, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Solicitação rejeitada',
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _limparSolicitacao,
                      child: const Text('Solicitar novamente'),
                    ),
                  ),
                ],
              ),
            ),
          ],

// Informação de aguardando liberação
          if (_aguardandoLiberacao) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  Icon(Icons.hourglass_empty, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Aguardando analista liberar próxima contagem',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  Future<void> _solicitarParticipacao(String contagemEscolhida) async {
    try {
      if (_inventarioAtivo == null) {
        _snack('Erro: Inventário não carregado');
        return;
      }

      final confirma = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Solicitar ${_getLabelContagem(contagemEscolhida)}?'),
          content: const Text(
            'Sua solicitação será enviada ao analista para aprovação.\n\n'
                'Deseja continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Solicitar'),
            ),
          ],
        ),
      );

      if (confirma != true) return;

      await _inventarioService.solicitarParticipacao(
        _inventarioAtivo!,
        contagemEscolhida,
      );

      await _buscarDadosParticipante();

      _snack('Solicitação enviada! Aguarde aprovação do analista.');
    } catch (e) {
      debugPrint('❌ Erro ao solicitar participação: $e');
      _snack('Erro ao solicitar: $e');
    }
  }

  Future<void> _limparSolicitacao() async {
    try {
      if (_inventarioAtivo == null) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('inventarios')
          .doc(_inventarioAtivo)
          .collection('participantes')
          .doc(user.uid)
          .delete();

      await _buscarDadosParticipante();

      _snack('Solicitação removida. Você pode solicitar novamente.');
    } catch (e) {
      debugPrint('❌ Erro ao limpar solicitação: $e');
      _snack('Erro: $e');
    }
  }

  String _getLabelContagem(String contagem) {
    switch (contagem) {
      case 'contagem_1':
        return '1ª Contagem';
      case 'contagem_2':
        return '2ª Contagem';
      case 'contagem_3':
        return '3ª Contagem';
      default:
        return contagem;
    }
  }
}
/// Formata número removendo .0 desnecessário
String _formatarInteiro(double valor) {
  if (valor == valor.toInt()) {
    return valor.toInt().toString();  // Remove .0
  }
  return valor.toString();  // Mantém decimal se houver
}