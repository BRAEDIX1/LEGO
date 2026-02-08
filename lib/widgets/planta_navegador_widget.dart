// lib/widgets/planta_navegador_widget.dart - VERSÃO CORRIGIDA

import 'package:flutter/material.dart';
import 'package:lego/config/planta_diadema_config.dart';

/// Resultado da seleção de localização
class LocalizacaoSelecionada {
  final String areaId;
  final String areaNome;
  final String? subAreaId;
  final String? subAreaNome;
  final String? ponto;
  
  LocalizacaoSelecionada({
    required this.areaId,
    required this.areaNome,
    this.subAreaId,
    this.subAreaNome,
    this.ponto,
  });

  String get pathCompleto {
    final parts = <String>[areaNome];
    if (subAreaNome != null) parts.add(subAreaNome!);
    if (ponto != null) parts.add(ponto!);
    return parts.join(' > ');
  }

  String get codigoFinal => ponto ?? subAreaId ?? areaId;
}

/// Widget de navegação pela planta (3 níveis)
class PlantaNavegadorWidget extends StatefulWidget {
  final String? localizacaoAtual;

  const PlantaNavegadorWidget({
    Key? key,
    this.localizacaoAtual,
  }) : super(key: key);

  @override
  State<PlantaNavegadorWidget> createState() => _PlantaNavegadorWidgetState();
}

class _PlantaNavegadorWidgetState extends State<PlantaNavegadorWidget> {
  int _nivelAtual = 1;
  AreaMapa? _areaSelecionada;
  SubArea? _subAreaSelecionada;
  
  @override
  void initState() {
    super.initState();
    debugPrint('🗺️ Total de áreas carregadas: ${PlantaDiademaConfig.areas.length}');
    for (var area in PlantaDiademaConfig.areas) {
      debugPrint('   - ${area.nome} (${area.id})');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_getTitulo()),
        leading: _nivelAtual > 1
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: _voltarNivel,
              )
            : IconButton(
                icon: Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
      ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            color: Colors.yellow.shade100,
            child: Text(
              '🔍 DEBUG: Nível $_nivelAtual | Áreas: ${PlantaDiademaConfig.areas.length}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          _buildBreadcrumb(),
          Expanded(
            child: _buildConteudo(),
          ),
        ],
      ),
    );
  }

  String _getTitulo() {
    switch (_nivelAtual) {
      case 1:
        return '📍 Selecione a Área';
      case 2:
        return '📍 ${_areaSelecionada?.nome ?? ''} - Selecione Setor';
      case 3:
        return '📍 ${_subAreaSelecionada?.nome ?? ''} - Selecione Ponto';
      default:
        return '📍 Localização';
    }
  }

  Widget _buildBreadcrumb() {
    final parts = <String>[];
    if (_areaSelecionada != null) parts.add(_areaSelecionada!.nome);
    if (_subAreaSelecionada != null) parts.add(_subAreaSelecionada!.nome);

    if (parts.isEmpty) return SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(16),
      color: Colors.blue.shade50,
      child: Row(
        children: [
          Icon(Icons.location_on, color: Colors.blue),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              parts.join(' > '),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConteudo() {
    switch (_nivelAtual) {
      case 1:
        return _buildNivel1_Geral();
      case 2:
        return _buildNivel2_SubAreas();
      case 3:
        return _buildNivel3_Pontos();
      default:
        return Center(child: Text('Erro: nível inválido'));
    }
  }

  /// NÍVEL 1: Mostra todas as áreas principais - CORRIGIDO
  Widget _buildNivel1_Geral() {
    debugPrint('🗺️ Renderizando nível 1 - Visão Geral');
    
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          color: Colors.blue.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '📍 Áreas disponíveis (toque em uma):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              ...PlantaDiademaConfig.areas.map((area) => Padding(
                padding: EdgeInsets.only(left: 16, top: 4),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: area.cor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(area.nome),
                  ],
                ),
              )).toList(),
            ],
          ),
        ),
        
        Expanded(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: _ImagemComOverlays(),
          ),
        ),
      ],
    );
  }

  /// Widget que renderiza imagem com overlays - SEM LayoutBuilder dentro
  Widget _ImagemComOverlays() {
    return Stack(
      children: [
        // Imagem da planta
        Image.asset(
          PlantaDiademaConfig.imagemPath,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('❌ Erro ao carregar imagem: $error');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text('Erro ao carregar planta'),
                  Text(error.toString(), style: TextStyle(fontSize: 10)),
                ],
              ),
            );
          },
        ),
        
        // Overlays calculados diretamente
        ...PlantaDiademaConfig.areas.map((area) {
          return _buildAreaOverlayDireto(area);
        }).toList(),
      ],
    );
  }

  /// Overlay de área SEM LayoutBuilder - usa AspectRatio
  Widget _buildAreaOverlayDireto(AreaMapa area) {
    // Assumindo proporção da imagem (ajuste conforme necessário)
    const imagemLargura = 384.0;  // Largura base da imagem
    const imagemAltura = 521.0;   // Altura base da imagem
    
    final rect = area.rect.toAbsolute(Size(imagemLargura, imagemAltura));

    debugPrint('📐 Área ${area.nome}: left=${rect.left}, top=${rect.top}, width=${rect.width}, height=${rect.height}');

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: GestureDetector(
        onTap: () {
          debugPrint('👆 Clicou em: ${area.nome}');
          _selecionarArea(area);
        },
        child: Container(
          decoration: BoxDecoration(
            color: area.cor.withOpacity(0.3),
            border: Border.all(color: area.cor, width: 3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: area.cor, width: 2),
              ),
              child: Text(
                area.nome,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: area.cor,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// NÍVEL 2: Mostra subáreas da área selecionada
  Widget _buildNivel2_SubAreas() {
    debugPrint('🗺️ Renderizando nível 2 - Sub-áreas de ${_areaSelecionada?.nome}');
    
    if (_areaSelecionada?.subareas == null) {
      return Center(child: Text('Sem subáreas definidas'));
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _areaSelecionada!.subareas!.length,
      itemBuilder: (context, index) {
        final subArea = _areaSelecionada!.subareas![index];
        return Card(
          margin: EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _areaSelecionada!.cor,
              child: Icon(Icons.grid_view, color: Colors.white),
            ),
            title: Text(
              subArea.nome,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${subArea.gridLinhas}x${subArea.gridColunas} posições (${subArea.pontos.length} total)',
            ),
            trailing: Icon(Icons.arrow_forward_ios),
            onTap: () {
              debugPrint('👆 Clicou em subárea: ${subArea.nome}');
              _selecionarSubArea(subArea);
            },
          ),
        );
      },
    );
  }

  /// NÍVEL 3: Mostra grid de pontos
  Widget _buildNivel3_Pontos() {
    debugPrint('🗺️ Renderizando nível 3 - Pontos de ${_subAreaSelecionada?.nome}');
    
    if (_subAreaSelecionada == null) {
      return Center(child: Text('Erro: subárea não selecionada'));
    }

    final pontos = _subAreaSelecionada!.pontos;
    final cols = _subAreaSelecionada!.gridColunas;

    return GridView.builder(
      padding: EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: pontos.length,
      itemBuilder: (context, index) {
        final ponto = pontos[index];
        return _buildPontoCard(ponto);
      },
    );
  }

  Widget _buildPontoCard(String ponto) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: () {
          debugPrint('👆 Clicou em ponto: $ponto');
          _selecionarPonto(ponto);
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue, width: 2),
          ),
          child: Center(
            child: Text(
              ponto.split('-').last,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.blue.shade900,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selecionarArea(AreaMapa area) {
    debugPrint('✅ Área selecionada: ${area.nome}');
    setState(() {
      _areaSelecionada = area;
      _nivelAtual = 2;
    });
  }

  void _selecionarSubArea(SubArea subArea) {
    debugPrint('✅ Sub-área selecionada: ${subArea.nome}');
    setState(() {
      _subAreaSelecionada = subArea;
      _nivelAtual = 3;
    });
  }

  void _selecionarPonto(String ponto) {
    debugPrint('✅ Ponto selecionado: $ponto');
    
    final resultado = LocalizacaoSelecionada(
      areaId: _areaSelecionada!.id,
      areaNome: _areaSelecionada!.nome,
      subAreaId: _subAreaSelecionada!.id,
      subAreaNome: _subAreaSelecionada!.nome,
      ponto: ponto,
    );

    debugPrint('✅ Retornando: ${resultado.pathCompleto}');
    Navigator.pop(context, resultado);
  }

  void _voltarNivel() {
    debugPrint('⬅️ Voltando do nível $_nivelAtual');
    setState(() {
      if (_nivelAtual == 3) {
        _nivelAtual = 2;
        _subAreaSelecionada = null;
      } else if (_nivelAtual == 2) {
        _nivelAtual = 1;
        _areaSelecionada = null;
      }
    });
  }
}
