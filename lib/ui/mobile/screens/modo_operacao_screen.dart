// lib/ui/mobile/screens/modo_operacao_screen.dart

import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:lego/config/ambiente.dart';
import 'package:lego/config/fluxo2_config.dart';
import 'package:lego/models/inventario.dart';
import 'package:lego/models/participante.dart';
import 'package:lego/models/sessao_contagem.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lego/services/auth_service.dart';
import 'package:lego/services/c3_service.dart';
import 'package:lego/services/compatibilidade_service.dart'
    show CompatibilidadeException;
import 'package:lego/services/inventario_service.dart';
import 'package:lego/services/mobile_sync_service.dart';
import 'package:lego/ui/home_page.dart';
import 'package:lego/ui/mobile/screens/c3_screen.dart';
import 'package:lego/ui/mobile/screens/monitor_screen.dart';

/// Tela de escolha do tipo de contagem.
///
/// Chave LEGO_FLUXO2 ligada: Contagem Simples ou Completa → C1/C2 (Lote 3A).
/// Chave desligada: tela legada de modo Autônomo/Controlado, sem mudança.
class ModoOperacaoScreen extends StatelessWidget {
  const ModoOperacaoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Fluxo2Config.habilitado
        ? const EscolhaContagemScreen()
        : const _ModoOperacaoLegadoScreen();
  }
}

// =====================================================================
// FLUXO 2: ESCOLHA SIMPLES / COMPLETA → C1 / C2
// =====================================================================

class EscolhaContagemScreen extends StatefulWidget {
  const EscolhaContagemScreen({super.key});

  @override
  State<EscolhaContagemScreen> createState() => _EscolhaContagemScreenState();
}

class _EscolhaContagemScreenState extends State<EscolhaContagemScreen> {
  final _sync = MobileSyncService();
  final _inventarioService = InventarioService();

  bool _carregando = true;
  bool _processando = false;
  String? _erroCompleta; // falha ao consultar a Contagem Completa
  Inventario? _ativo;
  Participante? _eu;

  @override
  void dispose() {
    _autoAtualizar?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _carregar();
    // T19: mensagem de inventário encerrado/cancelado, se for o motivo da volta
    final motivo = _sync.ultimoMotivoFimSessao;
    if (motivo != null) {
      _sync.ultimoMotivoFimSessao = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(motivo), backgroundColor: Colors.orange),
          );
        }
      });
    }
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erroCompleta = null;
    });
    if (ambienteAtual == Ambiente.teste) {
      await _carregarLocalC3(); // independe de internet
    }
    try {
      final inv = await _inventarioService.buscarInventarioCompletoAtivo(
          propagarErros: true);
      final eu = inv != null
          ? await _inventarioService.buscarMeuParticipante(inv.id,
              somenteServidor: true)
          : null;
      if (!mounted) return;
      setState(() {
        _ativo = inv;
        _eu = eu;
        _carregando = false;
      });
      // Item 4: leitura do servidor OK → C3 que já acabou sai do aparelho.
      if (ambienteAtual == Ambiente.teste) {
        final descartou = await _c3.descartarLocalObsoleto(
          inventarioAtivoId: inv?.id,
          statusC3Ativo: inv?.statusRodada(Rodadas.c3),
        );
        if (descartou) await _carregarLocalC3();
      }
      if (inv != null && ambienteAtual == Ambiente.teste) {
        _carregarProntoC3(inv);
      }
    } catch (e) {
      debugPrint('❌ Tela de escolha: falha ao consultar a Completa: $e');
      if (!mounted) return;
      setState(() {
        _erroCompleta = _mensagemErro(e);
        _carregando = false;
      });
    }
  }

  /// B34: mensagem de rede só quando o Firestore devolve 'unavailable' (servidor
  /// ou internet). Qualquer outra falha mostra o motivo real.
  /// [acao] completa a frase: "consultar o" (carga da tela) ou "entrar no"
  /// (entrada em C1/C2, B34-B).
  String _mensagemErro(Object e, {String acao = 'consultar o'}) {
    // 3B (T33a): recusa por compatibilidade já vem com a mensagem final
    if (e is CompatibilidadeException) return e.mensagem;
    if (e is FirebaseException) {
      switch (e.code) {
        case 'unavailable':
          // B34-A: 'unavailable' não prova falta de rede no aparelho.
          return 'Servidor Firestore indisponível ou sem conexão com a '
              'internet. A Contagem Completa precisa do servidor; a '
              'Contagem Simples funciona offline.';
        case 'permission-denied':
          return 'Sem permissão para $acao Inventário Completo '
              '(regras do Firestore). Detalhe: ${e.message}';
        default:
          return 'Erro ao $acao Inventário Completo (${e.code}): ${e.message}';
      }
    }
    return 'Erro ao $acao Inventário Completo: $e';
  }

  void _abrirHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: erro ? Colors.red : null),
    );
  }

  Future<void> _escolherSimples() async {
    setState(() => _processando = true);
    try {
      await _sync.escolherSimples();
      _abrirHome();
    } catch (e) {
      _snack('Erro: $e', erro: true);
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  /// L4: tipo da Contagem Completa, escolhido por quem ABRE o inventário.
  Future<String?> _escolherNatureza() => showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Tipo da Contagem Completa'),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                  'Vale para C1, C2 e C3 deste inventário e não pode ser '
                  'trocado depois.',
                  style: TextStyle(fontSize: 13)),
            ),
            for (final (valor, titulo, detalhe, icone) in const [
              ('material', 'Materiais', 'Só produtos de materiais. '
                  'Compara quantidade por local e prateleira.', Icons.category),
              ('cilindro', 'Cilindros', 'Só produtos de gás. Compara o total '
                  'de cilindros (cheio e vazio valem igual) por local.',
                  Icons.propane_tank),
              ('gas', 'Gases', 'Só produtos de gás. Compara só os CHEIOS; '
                  'vazios são desprezados.', Icons.local_gas_station),
            ])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, valor),
                child: ListTile(
                  leading: Icon(icone, color: Colors.deepPurple),
                  title: Text(titulo,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(detalhe),
                ),
              ),
          ],
        ),
      );

  Future<void> _escolherRodada(String rodada) async {
    final rotulo = Rodadas.rotulo(rodada);
    // L4: sem inventário ativo, quem abre escolhe o tipo.
    String? natureza;
    if (_ativo == null) {
      natureza = await _escolherNatureza();
      if (natureza == null) return;
    }
    final alvo = _ativo != null
        ? 'no Inventário ${_ativo!.numeroFormatado}'
        : 'num novo Inventário Completo de '
            '${SessaoContagem.rotuloNatureza(natureza)}';
    final jaEstou = _eu?.rodadaBase == rodada;

    if (!jaEstou) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Entrar na $rotulo?'),
          content: Text(
            'Você vai contar a $rotulo $alvo.\n\n'
            'Depois de entrar, você não poderá contar a '
            '${Rodadas.rotulo(rodada == Rodadas.c1 ? Rodadas.c2 : Rodadas.c1)} '
            'deste inventário.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Entrar na $rotulo'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _processando = true);
    try {
      final sessao =
          await _sync.entrarContagemCompleta(rodada, natureza: natureza);
      // Corrida: outro aparelho abriu o inventário antes, com outro tipo.
      if (natureza != null && sessao.natureza != natureza) {
        _snack('O inventário já tinha sido aberto por outra pessoa como '
            '${SessaoContagem.rotuloNatureza(sessao.natureza)}. '
            'Vale esse tipo.');
      }
      _abrirHome();
    } on InventarioLegadoAtivoException catch (e) {
      _snack(e.toString(), erro: true);
    } on RodadaBaseConflitoException catch (e) {
      _snack(e.toString(), erro: true);
      await _carregar();
    } on OperacaoNaoPermitidaException catch (e) {
      _snack(e.motivo, erro: true);
      await _carregar();
    } catch (e) {
      // B34-B: mesma classificação da carga; não presume falta de conexão.
      debugPrint('❌ Tela de escolha: falha ao entrar na $rotulo: $e');
      _snack(_mensagemErro(e, acao: 'entrar no'), erro: true);
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  /// B66: o logout nunca pode ficar preso. Cada etapa é isolada; se alguma
  /// falhar, o signOut do Firebase é feito mesmo assim e a tela de login abre.
  /// O erro aparece na tela para diagnóstico.
  Future<void> _sair() async {
    final erros = <String>[];
    try {
      await _sync.limparSessao();
    } catch (e) {
      erros.add('limparSessao: $e');
    }
    try {
      // B60: fecha a caixa local do usuário (ver home_page).
      await AuthService().signOut();
    } catch (e) {
      erros.add('signOut: $e');
    }
    if (FirebaseAuth.instance.currentUser != null) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        erros.add('FirebaseAuth.signOut: $e');
      }
    }
    if (!mounted) return;
    if (erros.isNotEmpty) {
      debugPrint('⚠️ Logout com falhas: ${erros.join(' | ')}');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Logout com aviso (B66)'),
          content: SingleChildScrollView(child: Text(erros.join('\n\n'))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      if (!mounted) return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final sessao = _sync.sessaoAtual;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tipo de contagem'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _processando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: _processando ? null : _sair,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _processando,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_processando) const LinearProgressIndicator(),
            // T22: voltar à sessão em curso sem finalizar nada
            if (sessao != null) ...[
              Card(
                color: Colors.green.withValues(alpha: 0.08),
                child: ListTile(
                  leading: const Icon(Icons.play_circle, color: Colors.green),
                  title: Text('Continuar: ${sessao.rotuloCabecalho}'),
                  subtitle: const Text('Retoma a sessão atual deste aparelho'),
                  onTap: _abrirHome,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (ambienteAtual == Ambiente.teste && _tarefasLocais > 0) ...[
              _cardTarefasLocais(),
              const SizedBox(height: 16),
            ],
            const Text(
              'Como você vai contar?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.smartphone, color: Colors.blue, size: 32),
                title: const Text('Contagem Simples',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text(
                    'Sem inventário numerado. Funciona sem internet.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _escolherSimples,
              ),
            ),
            const SizedBox(height: 12),
            _buildCardCompleta(),
          ],
        ),
      ),
    );
  }

  Widget _buildCardCompleta() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.inventory_2, color: Colors.deepPurple, size: 32),
                SizedBox(width: 12),
                Text('Contagem Completa',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (_carregando)
              const Center(child: CircularProgressIndicator())
            else if (_erroCompleta != null)
              Text(_erroCompleta!, style: const TextStyle(color: Colors.red))
            else ...[
              Text(
                _ativo != null
                    ? 'Inventário ${_ativo!.numeroFormatado} em andamento'
                    : 'Nenhum Inventário Completo ativo. '
                        'Um novo será aberto quando você escolher a rodada.',
              ),
              if (_ativo?.naturezaContagem != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Tipo: ${SessaoContagem.rotuloNatureza(_ativo!.naturezaContagem)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
              if (_eu?.rodadaBase != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Você participa da ${Rodadas.rotulo(_eu!.rodadaBase!)} '
                  'deste inventário.',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _botaoRodada(Rodadas.c1)),
                  const SizedBox(width: 12),
                  Expanded(child: _botaoRodada(Rodadas.c2)),
                ],
              ),
              // Entrega 1 (teste em campo): só no LEGO TESTE.
              if (_ativo != null && ambienteAtual == Ambiente.teste) ...[
                const SizedBox(height: 16),
                _buildPainelTeste(_ativo!),
              ],
            ],
          ],
        ),
      ),
    );
  }

  // ===================================================================
  // ENTREGA 3 (TESTE): monitor do analista + C3 do operador.
  // Visível só no ambiente de teste (lego-teste). Sem regra de perfil (R14).
  // As regras ficam nos serviços (monitor/comparativo/c3).
  // ===================================================================

  final _c3 = C3Service();
  int _tarefasLocais = 0;
  String? _numeroLocal;
  bool? _prontoC3;

  /// Tarefas C3 guardadas no aparelho: funciona sem internet.
  Future<void> _carregarLocalC3() async {
    try {
      final (inv, numero, lista) = await _c3.lerLocal();
      if (!mounted) return;
      setState(() {
        _tarefasLocais = inv == null ? 0 : lista.length;
        _numeroLocal = numero;
      });
    } catch (_) {}
  }

  bool _finalizeiC3 = false;
  /// B77: o servidor confirmou que não recebi itens nesta C3.
  bool _semTarefasC3 = false;
  Timer? _autoAtualizar;

  Future<void> _carregarProntoC3(Inventario inv) async {
    final st = inv.statusRodada(Rodadas.c3);
    // Sem botão "atualizar": enquanto a C3 espera o analista, a tela se
    // atualiza sozinha.
    _autoAtualizar?.cancel();
    if (st == StatusRodada.aguardandoParticipantes ||
        st == StatusRodada.distribuindo ||
        st == StatusRodada.redistribuindo) {
      _autoAtualizar = Timer(const Duration(seconds: 8), () {
        if (mounted && !_processando) _carregar();
      });
    }
    if (st != StatusRodada.aguardandoParticipantes &&
        st != StatusRodada.emAndamento) {
      return;
    }
    try {
      final (pronto, finalizado) = await _c3.meuStatusC3(inv.id);
      if (!mounted) return;
      setState(() {
        _prontoC3 = pronto;
        _finalizeiC3 = finalizado;
      });
      // Item 6: C3 em andamento e eu participo → baixa sozinho (uma vez).
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final euNaC3 =
          inv.contagens[Rodadas.c3]?.usuarios.contains(uid) ?? false;
      if (st == StatusRodada.emAndamento &&
          euNaC3 &&
          !finalizado &&
          _tarefasLocais == 0) {
        final t = await _c3.baixarMinhasTarefas(inv.id, inv.numeroFormatado);
        await _carregarLocalC3();
        if (mounted) setState(() => _semTarefasC3 = t.isEmpty);
      }
    } catch (_) {}
  }

  Widget _cardTarefasLocais() => Card(
        color: Colors.deepPurple.withValues(alpha: 0.06),
        child: ListTile(
          leading: const Icon(Icons.fact_check, color: Colors.deepPurple),
          title: Text('Minhas tarefas C3'
              '${_numeroLocal != null ? ' · Inv. $_numeroLocal' : ''}'),
          subtitle: Text('$_tarefasLocais tarefa(s) neste aparelho. '
              'Funciona sem internet.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _abrirMinhasTarefas,
        ),
      );

  void _abrirMinhasTarefas() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const MinhasTarefasC3Screen()))
        // B76: relê também o status no servidor (finalizei?), não só o local.
        .then((_) => _carregar());
  }

  Widget _buildPainelTeste(Inventario inv) {
    final st = inv.statusRodada(Rodadas.c3);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final euNaC3 = inv.contagens[Rodadas.c3]?.usuarios.contains(uid) ?? false;

    final filhos = <Widget>[
      OutlinedButton.icon(
        icon: const Icon(Icons.monitor_heart),
        label: const Text('Abrir monitor do analista'),
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(
                builder: (_) => MonitorScreen(inventarioId: inv.id)))
            .then((_) => _carregar()),
      ),
    ];

    if (st == StatusRodada.aguardandoParticipantes ||
        (st == StatusRodada.emAndamento && !euNaC3)) {
      filhos.add(const SizedBox(height: 8));
      if (_prontoC3 == true) {
        filhos.add(Text(st == StatusRodada.emAndamento
            ? 'A C3 começou sem você. Você está pronto: peça ao analista '
                'para "Redistribuir pendentes".'
            : 'Você está pronto para a C3. Aguarde o analista iniciar.'));
      } else {
        filhos.add(FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple),
          icon: const Icon(Icons.how_to_reg),
          label: const Text('Estou pronto para a C3'),
          onPressed: () async {
            setState(() => _processando = true);
            try {
              await _c3.marcarPronto(inv.id);
              if (mounted) setState(() => _prontoC3 = true);
              _snack('Confirmado. Aguarde o analista iniciar a C3.');
            } catch (e) {
              _snack('Erro: $e', erro: true);
            } finally {
              if (mounted) setState(() => _processando = false);
            }
          },
        ));
      }
    }

    if (st == StatusRodada.distribuindo || st == StatusRodada.redistribuindo) {
      filhos.addAll(const [
        SizedBox(height: 8),
        Text('O analista está distribuindo as tarefas da C3. A tela se '
            'atualiza sozinha.'),
      ]);
    }

    if (st == StatusRodada.emAndamento && euNaC3 && _finalizeiC3) {
      filhos.addAll(const [
        SizedBox(height: 8),
        Text('✅ Você finalizou a sua C3.'),
      ]);
    }

    // B77: 0 de 0 = participação concluída (confirmado no servidor).
    if (st == StatusRodada.emAndamento && euNaC3 && !_finalizeiC3 &&
        _tarefasLocais == 0 && _semTarefasC3) {
      filhos.addAll([
        const SizedBox(height: 8),
        const Text('Você não recebeu itens nesta C3.'),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.orange),
          icon: const Icon(Icons.check_circle),
          label: const Text('Finalizar minha C3'),
          onPressed: () async {
            setState(() => _processando = true);
            try {
              await _c3.finalizarSemTarefas(inv.id);
              _snack('C3 finalizada.');
              await _carregar();
            } catch (e) {
              _snack('Não foi possível finalizar: $e', erro: true);
            } finally {
              if (mounted) setState(() => _processando = false);
            }
          },
        ),
      ]);
    }

    if (st == StatusRodada.emAndamento && euNaC3 && !_finalizeiC3 &&
        _tarefasLocais == 0 && !_semTarefasC3) {
      filhos.addAll([
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple),
          icon: const Icon(Icons.download),
          label: const Text('Baixar minhas tarefas C3'),
          onPressed: () async {
            setState(() => _processando = true);
            try {
              final t =
                  await _c3.baixarMinhasTarefas(inv.id, inv.numeroFormatado);
              await _carregarLocalC3();
              if (t.isEmpty) {
                if (mounted) setState(() => _semTarefasC3 = true);
                _snack('Você não recebeu itens nesta C3.');
              } else {
                _snack('${t.length} tarefa(s) no aparelho.');
                _abrirMinhasTarefas();
              }
            } catch (e) {
              _snack('Erro ao baixar (precisa de internet): $e', erro: true);
            } finally {
              if (mounted) setState(() => _processando = false);
            }
          },
        ),
      ]);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(8),
        color: Colors.red.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ambiente de teste · C3: ${StatusRodada.rotulo(st)}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...filhos,
        ],
      ),
    );
  }

  Widget _botaoRodada(String rodada) {
    final rotulo = Rodadas.rotulo(rodada);
    String? bloqueio;
    String legenda = rotulo;

    final status = _ativo?.statusRodada(rodada);
    if (status == StatusRodada.encerrada) {
      bloqueio = '$rotulo encerrada';
    } else if (_eu?.rodadaBase != null && _eu!.rodadaBase != rodada) {
      bloqueio = 'Você está na ${Rodadas.rotulo(_eu!.rodadaBase!)}'; // D4
    } else if (_eu?.estaFinalizadoEm(rodada) ?? false) {
      legenda = '$rotulo (finalizada: só consulta)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: bloqueio == null ? () => _escolherRodada(rodada) : null,
          child: Text(legenda, textAlign: TextAlign.center),
        ),
        if (bloqueio != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(bloqueio,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ),
      ],
    );
  }
}

// =====================================================================
// FLUXO 1 (LEGADO): MODO AUTÔNOMO / CONTROLADO — sem alteração funcional
// =====================================================================

/// Tela de seleção do modo de operação (Mobile)
class _ModoOperacaoLegadoScreen extends StatefulWidget {
  const _ModoOperacaoLegadoScreen();

  @override
  State<_ModoOperacaoLegadoScreen> createState() => _ModoOperacaoLegadoScreenState();
}

class _ModoOperacaoLegadoScreenState extends State<_ModoOperacaoLegadoScreen> {
  final _syncService = MobileSyncService();
  final _formatoData = DateFormat('dd/MM/yyyy HH:mm');

  bool _carregando = true;
  Inventario? _inventarioAtivo;
  String? _erro;
  bool _processando = false;
  StreamSubscription<ModoOperacao>? _modoSub;

  @override
  void initState() {
    super.initState();
    _carregarDados();
    // 3B: a validação do vínculo salvo (L4) termina em segundo plano
    _modoSub = _syncService.modoStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _modoSub?.cancel();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final inv = await _syncService.buscarInventarioAtivo();
      setState(() {
        _inventarioAtivo = inv;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modo de Operação'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? _buildErro()
              : _buildConteudo(),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text('Erro: $_erro'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _carregarDados,
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildConteudo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status atual
          _buildStatusAtual(),
          const SizedBox(height: 24),

          // Opções
          const Text(
            'Escolha como deseja operar:',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Card Modo Autônomo
          _buildCardModo(
            titulo: 'Modo Autônomo',
            descricao: 'Contagem independente, sem vínculo com inventário central. '
                'Os dados ficam apenas neste dispositivo.',
            icone: Icons.smartphone,
            cor: Colors.blue,
            selecionado: _syncService.isAutonomo,
            onTap: _selecionarAutonomo,
            badges: const ['Offline', 'Local'],
          ),
          const SizedBox(height: 16),

          // Card Modo Controlado
          _buildCardModoControlado(),
        ],
      ),
    );
  }

  Widget _buildStatusAtual() {
    final modo = _syncService.modoAtual;
    final cor = modo == ModoOperacao.controlado ? Colors.green : Colors.blue;
    final label = modo == ModoOperacao.controlado ? 'CONTROLADO' : 'AUTÔNOMO';

    return Card(
      color: cor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              modo == ModoOperacao.controlado ? Icons.cloud_done : Icons.smartphone,
              color: cor,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Modo atual',
                    style: TextStyle(fontSize: 12),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: cor,
                    ),
                  ),
                  if (modo == ModoOperacao.controlado && _syncService.inventarioVinculadoId != null)
                    Text(
                      'Vinculado: ${_syncService.inventarioVinculadoId}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  // 3B (B41): vínculo salvo não restaurado; não vira Autônomo
                  if (modo == ModoOperacao.controlado &&
                      _syncService.vinculoControladoBloqueado != null)
                    Text(
                      'BLOQUEADO: ${_syncService.vinculoControladoBloqueado}\n'
                      'Escolha Autônomo abaixo para contar sem vínculo.',
                      style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardModo({
    required String titulo,
    required String descricao,
    required IconData icone,
    required Color cor,
    required bool selecionado,
    required VoidCallback onTap,
    List<String> badges = const [],
  }) {
    return Card(
      elevation: selecionado ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selecionado ? cor : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: _processando ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: cor, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (selecionado) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.check_circle, color: cor, size: 20),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      descricao,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                    if (badges.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: badges.map((badge) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(fontSize: 11, color: cor),
                          ),
                        )).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              if (!selecionado)
                Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardModoControlado() {
    final temInventarioAtivo = _inventarioAtivo != null;
    final cor = temInventarioAtivo ? Colors.green : Colors.grey;

    return Card(
      elevation: _syncService.isControlado ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _syncService.isControlado ? cor : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: temInventarioAtivo && !_processando
                ? () => _selecionarControlado(_inventarioAtivo!)
                : null,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.cloud_sync, color: cor, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Modo Controlado',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_syncService.isControlado) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.check_circle, color: cor, size: 20),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          temInventarioAtivo
                              ? 'Vincular a inventário ativo. Os dados sincronizam com o servidor.'
                              : 'Nenhum inventário ativo no momento.',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Online',
                                style: TextStyle(fontSize: 11, color: cor),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Sincronizado',
                                style: TextStyle(fontSize: 11, color: cor),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (temInventarioAtivo &&
                      (!_syncService.isControlado ||
                          _syncService.vinculoControladoBloqueado != null))
                    Icon(Icons.chevron_right, color: Colors.grey[400]),
                ],
              ),
            ),
          ),

          // Detalhes do inventário ativo
          if (temInventarioAtivo) ...[
            const Divider(height: 1),
            _buildDetalhesInventario(_inventarioAtivo!),
          ] else ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[400]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aguarde o analista criar e iniciar um inventário para usar este modo.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
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

  Widget _buildDetalhesInventario(Inventario inv) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.green.withOpacity(0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2, size: 20, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                'Inventário Ativo',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildLinhaDetalhe('Código', inv.codigo),
          _buildLinhaDetalhe('Status', inv.statusLabel),
          _buildLinhaDetalhe('Contagem', inv.contagemAtivaLabel),
          if (inv.tipoMaterial != null)
            _buildLinhaDetalhe('Material', TiposMaterial.label(inv.tipoMaterial!)),
          _buildLinhaDetalhe('Itens', '${inv.totalItensEstoque}'),
          _buildLinhaDetalhe('Início', _formatoData.format(inv.dataInicio)),
        ],
      ),
    );
  }

  Widget _buildLinhaDetalhe(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ),
          Expanded(
            child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ==================== AÇÕES ====================

  Future<void> _selecionarAutonomo() async {
    // 3B (B42/B46): toda confirmação MANUAL de Autônomo é escolha explícita.
    // Com bloqueio (L1 ou L4) a tela deixa escolher mesmo que o modo salvo
    // já seja Autônomo. Chamadas automáticas do sistema seguem explicito:false.
    final bloqueado = (_syncService.motivoBloqueioCentral != null &&
            _syncService.compatCentralLegado != null) ||
        _syncService.vinculoControladoBloqueado != null;
    if (_syncService.isAutonomo &&
        (!bloqueado || _syncService.autonomoExplicito)) {
      return;
    }

    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mudar para Autônomo'),
        content: const Text(
          'Deseja desconectar do inventário e operar de forma independente?\n\n'
          'Os lançamentos feitos neste modo ficarão apenas neste dispositivo.',
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

    setState(() => _processando = true);

    // B46: confirmação manual = escolha explícita (transição oficial)
    // B52: troca de usuário no meio = no-op, sem mensagem de sucesso
    final feito = await _syncService.setModoAutonomo(explicito: true);

    if (!mounted) return;
    setState(() => _processando = false);

    if (feito) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modo Autônomo ativado'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  Future<void> _selecionarControlado(Inventario inv) async {
    // 3B: vínculo bloqueado na restauração (L4) pode passar de novo pelas
    // verificações escolhendo o mesmo inventário.
    if (_syncService.isControlado &&
        _syncService.inventarioVinculadoId == inv.id &&
        _syncService.vinculoControladoBloqueado == null) {
      return;
    }

    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vincular ao Inventário'),
        content: Text(
          'Deseja vincular este dispositivo ao inventário ${inv.codigo}?\n\n'
          'Você precisará de aprovação do analista para começar a contar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Vincular'),
          ),
        ],
      ),
    );

    if (confirma != true) return;

    setState(() => _processando = true);

    // ignore: deprecated_member_use_from_same_package
    final resultado = await _syncService.setModoControlado(inv.id);

    setState(() => _processando = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resultado.mensagem),
          backgroundColor: resultado.sucesso ? Colors.green : Colors.red,
        ),
      );

      if (resultado.sucesso) {
        Navigator.pop(context, true);
      }
    }
  }
}
