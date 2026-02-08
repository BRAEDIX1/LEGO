import 'package:flutter/material.dart';
import 'dart:developer';
import 'package:lego/data/repositories/produtos_repository.dart';
import 'package:lego/data/repositories/barras_repository.dart';
import 'package:lego/data/local/produto_local.dart';
import 'package:lego/data/local/barra_local.dart';

class HomePageHive extends StatefulWidget {
  const HomePageHive({super.key});

  @override
  State<HomePageHive> createState() => _HomePageHiveState();
}

class _HomePageHiveState extends State<HomePageHive> {
  final _searchCtrl = TextEditingController();
  ProdutoLocal? _produto;
  BarraLocal? _barra;
  bool _isLoading = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String input) async {
    if (input.isEmpty) return;
    setState(() => _isLoading = true);
    final produtosRepo = ProdutosRepository();
    final barrasRepo = BarrasRepository();

    // Logar chaves disponíveis para depuração
    produtosRepo.logAvailableKeys();
    barrasRepo.logAvailableKeys();

    try {
      final produto = await produtosRepo.getByCodigoPreferGases(input);
      final barra = await barrasRepo.getByTag(input);
      setState(() {
        _produto = produto;
        _barra = barra;
        _isLoading = false;
      });
      log('[HOME] Busca: $input, Produto: ${produto?.codigo}, Barra: ${barra?.tag}');
      if (produto == null && barra == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum produto ou barra encontrado')),
        );
      }
    } catch (e, st) {
      log('[HOME] Erro na busca: $e', stackTrace: st);
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro na busca: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Busca Offline')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                labelText: 'Buscar produto ou barra',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _search(_searchCtrl.text),
                ),
              ),
              onSubmitted: _search,
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_produto != null)
              ListTile(
                title: Text(_produto!.descricao),
                subtitle: Text('Código: ${_produto!.codigo}, Unidade: ${_produto!.unidade}'),
              )
            else if (_barra != null)
                ListTile(
                  title: Text('Barra: ${_barra!.tag}'),
                  subtitle: Text('Código: ${_barra!.codigo}, Lote: ${_barra!.lote}'),
                )
              else
                const Text('Nenhum resultado encontrado'),
          ],
        ),
      ),
    );
  }
}