// lib/config/planta_diadema_config.dart

import 'package:flutter/material.dart';

/// Coordenadas relativas (0.0 a 1.0) = porcentagem da imagem
class RectRelativo {
  final double left;
  final double top;
  final double right;
  final double bottom;

  RectRelativo(this.left, this.top, this.right, this.bottom);

  /// Converte para Rect absoluto baseado no tamanho da imagem
  Rect toAbsolute(Size imageSize) {
    return Rect.fromLTRB(
      left * imageSize.width,
      top * imageSize.height,
      right * imageSize.width,
      bottom * imageSize.height,
    );
  }
}

/// Representa uma área clicável na planta
class AreaMapa {
  final String id;
  final String nome;
  final RectRelativo rect;
  final Color cor;
  final List<SubArea>? subareas;

  AreaMapa({
    required this.id,
    required this.nome,
    required this.rect,
    this.cor = Colors.blue,
    this.subareas,
  });
}

/// Representa uma subárea com pontos específicos
class SubArea {
  final String id;
  final String nome;
  final RectRelativo rect;
  final int gridLinhas;
  final int gridColunas;
  final String prefixoCodigo;

  SubArea({
    required this.id,
    required this.nome,
    required this.rect,
    required this.gridLinhas,
    required this.gridColunas,
    required this.prefixoCodigo,
  });

  /// Gera lista de pontos automaticamente
  List<String> get pontos {
    final lista = <String>[];
    for (int linha = 0; linha < gridLinhas; linha++) {
      for (int col = 0; col < gridColunas; col++) {
        final letraLinha = String.fromCharCode(65 + linha); // A, B, C...
        final numero = (col + 1).toString().padLeft(2, '0'); // 01, 02, 03...
        lista.add('$prefixoCodigo-$letraLinha$numero');
      }
    }
    return lista;
  }
}

/// Configuração da Planta de Diadema - TESTE INICIAL
class PlantaDiademaConfig {
  static const String imagemPath = 'assets/plantas/PLANTA_ATUAL_DE_DIADEMA.png';

  /// 🧪 ÁREAS DE TESTE (baseado na visualização da planta)
  /// Estas coordenadas são APROXIMADAS para teste
  static final List<AreaMapa> areas = [
    // ÁREA 1: Estoque Clientes (lado esquerdo)
    AreaMapa(
      id: 'estoque_clientes',
      nome: 'Estoque Clientes',
      rect: RectRelativo(0.15, 0.35, 0.30, 0.70),
      cor: Colors.blue,
      subareas: [
        SubArea(
          id: 'rua_a',
          nome: 'Rua A',
          rect: RectRelativo(0.16, 0.40, 0.29, 0.50),
          gridLinhas: 2,
          gridColunas: 5,
          prefixoCodigo: 'RUA-A',
        ),
        SubArea(
          id: 'rua_b',
          nome: 'Rua B',
          rect: RectRelativo(0.16, 0.55, 0.29, 0.65),
          gridLinhas: 2,
          gridColunas: 5,
          prefixoCodigo: 'RUA-B',
        ),
      ],
    ),

    // ÁREA 2: Pavilhão Central (área grande no centro)
    AreaMapa(
      id: 'pavilhao_central',
      nome: 'Pavilhão Central',
      rect: RectRelativo(0.35, 0.30, 0.60, 0.65),
      cor: Colors.orange,
      subareas: [
        SubArea(
          id: 'zona_norte',
          nome: 'Zona Norte',
          rect: RectRelativo(0.36, 0.32, 0.59, 0.42),
          gridLinhas: 2,
          gridColunas: 6,
          prefixoCodigo: 'ZN',
        ),
        SubArea(
          id: 'zona_sul',
          nome: 'Zona Sul',
          rect: RectRelativo(0.36, 0.50, 0.59, 0.63),
          gridLinhas: 2,
          gridColunas: 6,
          prefixoCodigo: 'ZS',
        ),
      ],
    ),

    // ÁREA 3: Expedição (parte inferior direita)
    AreaMapa(
      id: 'expedicao',
      nome: 'Expedição',
      rect: RectRelativo(0.55, 0.70, 0.75, 0.85),
      cor: Colors.green,
      subareas: [
        SubArea(
          id: 'docas',
          nome: 'Docas',
          rect: RectRelativo(0.56, 0.72, 0.74, 0.83),
          gridLinhas: 2,
          gridColunas: 4,
          prefixoCodigo: 'DOCA',
        ),
      ],
    ),

    // ÁREA 4: Área Administrativa (superior direita)
    AreaMapa(
      id: 'administrativa',
      nome: 'Área Administrativa',
      rect: RectRelativo(0.65, 0.15, 0.85, 0.35),
      cor: Colors.purple,
      subareas: [
        SubArea(
          id: 'escritorios',
          nome: 'Escritórios',
          rect: RectRelativo(0.66, 0.17, 0.84, 0.33),
          gridLinhas: 3,
          gridColunas: 3,
          prefixoCodigo: 'ESC',
        ),
      ],
    ),
  ];

  /// Retorna todas as áreas em formato de mapa
  static Map<String, AreaMapa> get areasMap {
    return {for (var area in areas) area.id: area};
  }

  /// Busca uma área por ID
  static AreaMapa? getArea(String areaId) {
    return areasMap[areaId];
  }

  /// Busca uma subárea dentro de uma área
  static SubArea? getSubArea(String areaId, String subAreaId) {
    final area = getArea(areaId);
    if (area?.subareas == null) return null;
    
    try {
      return area!.subareas!.firstWhere((s) => s.id == subAreaId);
    } catch (e) {
      return null;
    }
  }
}
