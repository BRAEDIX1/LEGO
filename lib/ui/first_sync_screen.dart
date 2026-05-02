// lib/ui/first_sync_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:lego/ui/login_page.dart';
import 'package:flutter/material.dart';
import 'package:lego/services/seed_bootstrap.dart';
import 'package:lego/services/seed_importer.dart';
import 'package:lego/ui/home_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

class FirstSyncScreen extends StatelessWidget {
  const FirstSyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<SyncProgress>(
          stream: SeedBootstrap.ensureSeedOnceWithProgress(),
          builder: (context, snapshot) {
            // Estado inicial: aguardando primeiro evento
            if (!snapshot.hasData) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 24),
                    Text(
                      'Iniciando sincronização...',
                      style: TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              );
            }

            final progress = snapshot.data!;

            // Se concluiu, navegar para HomePage
            if (progress.percentual >= 1.0 && progress.etapa == 'concluido') {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                final packageInfo = await PackageInfo.fromPlatform();
                final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
                final state = Hive.isBoxOpen('app_state')
                    ? Hive.box('app_state')
                    : await Hive.openBox('app_state');
                await state.put('last_seeded_version_code', currentBuild);
                final user = FirebaseAuth.instance.currentUser;
                if (!context.mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => user != null ? const HomePage() : const LoginPage(),
                  ),
                );
              });
            }

            // Se deu erro
            if (progress.etapa == 'erro') {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 80, color: Colors.red),
                      const SizedBox(height: 24),
                      const Text(
                        'Erro na sincronização',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        progress.mensagem,
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () {
                          // Recarregar a tela para tentar novamente
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const FirstSyncScreen()),
                          );
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar Novamente'),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Mostrando progresso
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo ou ícone
                    const Icon(Icons.cloud_download, size: 80, color: Colors.blue),

                    const SizedBox(height: 32),

                    // Título
                    const Text(
                      'Configurando o inventário',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    // Mensagem atual
                    Text(
                      progress.mensagem,
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 32),

                    // Barra de progresso
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress.percentual,
                        minHeight: 12,
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Percentual
                    Text(
                      progress.percentualFormatado,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Detalhes por etapa
                    _buildEtapaDetalhes(progress),

                    const SizedBox(height: 32),

                    // Banner informativo
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[100]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Esta sincronização acontece apenas na primeira vez que você instala o aplicativo.',
                              style: TextStyle(
                                color: Colors.blue[900],
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Tempo estimado
                    if (progress.percentual > 0.1 && progress.percentual < 0.95)
                      Text(
                        'Tempo estimado: ${_calcularTempoEstimado(progress.percentual)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEtapaDetalhes(SyncProgress progress) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildEtapaRow(
            'Lendo arquivo',
            progress.etapa == 'lendo_arquivo' || progress.etapa == 'decodificando',
            progress.etapa != 'lendo_arquivo' && progress.etapa != 'decodificando',
          ),
          const Divider(height: 16),
          _buildEtapaRow(
            'Importando materiais',
            progress.etapa == 'materiais',
            _etapaConcluida(progress.etapa, 'materiais'),
          ),
          const Divider(height: 16),
          _buildEtapaRow(
            'Importando gases',
            progress.etapa == 'gases',
            _etapaConcluida(progress.etapa, 'gases'),
          ),
          const Divider(height: 16),
          _buildEtapaRow(
            'Códigos de barras',
            progress.etapa == 'barras',
            _etapaConcluida(progress.etapa, 'barras'),
          ),
        ],
      ),
    );
  }

  bool _etapaConcluida(String etapaAtual, String etapaVerificar) {
    const ordem = ['lendo_arquivo', 'decodificando', 'materiais', 'gases', 'barras', 'concluido'];
    final indexAtual = ordem.indexOf(etapaAtual);
    final indexVerificar = ordem.indexOf(etapaVerificar);
    return indexAtual > indexVerificar;
  }

  Widget _buildEtapaRow(String nome, bool ativo, bool concluido) {
    return Row(
      children: [
        Icon(
          concluido
              ? Icons.check_circle
              : ativo
              ? Icons.downloading
              : Icons.radio_button_unchecked,
          color: concluido
              ? Colors.green
              : ativo
              ? Colors.blue
              : Colors.grey[300],
          size: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            nome,
            style: TextStyle(
              fontSize: 16,
              fontWeight: ativo ? FontWeight.bold : FontWeight.normal,
              color: concluido
                  ? Colors.green[700]
                  : ativo
                  ? Colors.black87
                  : Colors.grey[500],
            ),
          ),
        ),
        if (ativo)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[400]!),
            ),
          ),
      ],
    );
  }

  String _calcularTempoEstimado(double percentual) {
    if (percentual <= 0) return 'Calculando...';

    // Estima baseado em 5 minutos total
    final tempoTotalSegundos = 300; // 5 minutos
    final tempoRestanteSegundos = (tempoTotalSegundos * (1 - percentual)).round();

    if (tempoRestanteSegundos < 60) {
      return 'menos de 1 minuto';
    } else if (tempoRestanteSegundos < 120) {
      return 'cerca de 1 minuto';
    } else {
      final minutos = (tempoRestanteSegundos / 60).round();
      return 'cerca de $minutos minutos';
    }
  }
}