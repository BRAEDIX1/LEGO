// lib/ui/update_checker_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:lego/services/update_service.dart';

/// Tela de verificação de atualização exibida antes do login.
/// Quando concluída (atualização dispensada ou não disponível),
/// navega para [proximaTela].
class UpdateCheckerScreen extends StatefulWidget {
  final Widget proximaTela;

  const UpdateCheckerScreen({super.key, required this.proximaTela});

  @override
  State<UpdateCheckerScreen> createState() => _UpdateCheckerScreenState();
}

class _UpdateCheckerScreenState extends State<UpdateCheckerScreen> {
  final _service = UpdateService();

  @override
  void initState() {
    super.initState();
    _verificar();
  }

  Future<void> _verificar() async {
    final release = await _service.verificarAtualizacao();

    if (!mounted) return;

    if (release == null) {
      // Sem atualização — segue direto
      _prosseguir();
      return;
    }

    // Há atualização — exibe dialog
    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogAtualizacao(release: release),
    );

    if (!mounted) return;

    if (confirmar == true) {
      await _baixarEInstalar(release);
    } else {
      _prosseguir();
    }
  }

  Future<void> _baixarEInstalar(ReleaseInfo release) async {
    // Exibe dialog de progresso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogProgresso(
        service: _service,
        release: release,
        onConcluido: (arquivo) {
          Navigator.of(context, rootNavigator: true).pop();
          OpenFilex.open(arquivo.path);
          // Segue para o login enquanto o Android trata a instalação
          _prosseguir();
        },
        onErro: () {
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erro ao baixar atualização. Tente novamente.')),
          );
          _prosseguir();
        },
      ),
    );
  }

  void _prosseguir() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => widget.proximaTela),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 24),
            Text('Verificando atualizações...', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

// ─── Dialog: nova versão disponível ────────────────────────────────────────

class _DialogAtualizacao extends StatelessWidget {
  final ReleaseInfo release;

  const _DialogAtualizacao({required this.release});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.system_update, color: Colors.blue),
          SizedBox(width: 8),
          Text('Nova versão disponível'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Versão ${release.versao}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          if (release.descricao.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              release.descricao,
              style: TextStyle(color: Colors.grey[700], fontSize: 14),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 16),
          const Text('Deseja atualizar agora?'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Depois'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Atualizar agora'),
        ),
      ],
    );
  }
}

// ─── Dialog: progresso do download ─────────────────────────────────────────

class _DialogProgresso extends StatefulWidget {
  final UpdateService service;
  final ReleaseInfo release;
  final void Function(File arquivo) onConcluido;
  final VoidCallback onErro;

  const _DialogProgresso({
    required this.service,
    required this.release,
    required this.onConcluido,
    required this.onErro,
  });

  @override
  State<_DialogProgresso> createState() => _DialogProgressoState();
}

class _DialogProgressoState extends State<_DialogProgresso> {
  double _progresso = 0;

  @override
  void initState() {
    super.initState();
    _iniciarDownload();
  }

  void _iniciarDownload() {
    widget.service
        .baixarApk(widget.release.apkUrl, onConcluido: widget.onConcluido)
        .listen((p) {
      if (p < 0) {
        widget.onErro();
        return;
      }
      if (mounted) setState(() => _progresso = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_progresso * 100).toStringAsFixed(0);
    return AlertDialog(
      title: const Text('Baixando atualização...'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: _progresso),
          const SizedBox(height: 12),
          Text('$pct%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
