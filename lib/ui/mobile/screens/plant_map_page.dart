// lib/ui/mobile/screens/plant_map_page.dart
//
// Tela de seleção de área geográfica via mapa interativo da planta.
// Carrega o JSON de áreas, exibe a PNG de fundo no InteractiveViewer,
// detecta toque → zoom animado → retorna PlantArea via Navigator.pop.
//
// USO:
//   final area = await Navigator.push<PlantArea>(
//     context,
//     MaterialPageRoute(builder: (_) => PlantMapPage(
//       jsonAsset: 'assets/plantas/PLANTA_ATUAL_DE_DIADEMA_areas.json',
//     )),
//   );
//   if (area != null) {
//     setState(() {
//       _localizacaoId   = area.id;
//       _localizacaoNome = area.nome;
//     });
//   }
//
// C3 (só visualizar): PlantMapPage(jsonAsset: ..., destaqueAreaId: id)
//   abre com zoom na área e um alfinete vermelho no centro dela, sem seleção.

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELOS
// ─────────────────────────────────────────────────────────────────────────────

class PlantArea {
  final String id;
  final String nome;
  final double x; // relativo 0..1
  final double y;
  final double w;
  final double h;
  /// Área desenhada como círculo (JSON: "forma": "circulo"). x/y/w/h são o
  /// quadrado que envolve o círculo. Sem o campo = retângulo (como sempre).
  final bool circulo;
  /// Giro do retângulo em graus, sentido horário, em torno do centro
  /// (JSON: "rot"). x/y/w/h descrevem o retângulo antes de girar.
  final double rot;

  const PlantArea({
    required this.id,
    required this.nome,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.circulo = false,
    this.rot = 0,
  });

  factory PlantArea.fromJson(Map<String, dynamic> j) => PlantArea(
        id:   j['id']   as String,
        nome: j['nome'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        w: (j['w'] as num).toDouble(),
        h: (j['h'] as num).toDouble(),
        circulo: j['forma'] == 'circulo',
        rot: j['forma'] == 'circulo' ? 0 : ((j['rot'] as num?)?.toDouble() ?? 0),
      );

  bool get girada => !circulo && rot.abs() > 1e-6;
  double get _rad => rot * pi / 180;

  /// Retângulo que envolve a área já girada, em pixels de [imageSize].
  Rect envoltorio(Size imageSize) {
    final r = toRect(imageSize);
    if (!girada) return r;
    final c = cos(_rad).abs(), s = sin(_rad).abs();
    return Rect.fromCenter(
        center: r.center,
        width: r.width * c + r.height * s,
        height: r.width * s + r.height * c);
  }

  Rect toRect(Size imageSize) => Rect.fromLTWH(
        x * imageSize.width,
        y * imageSize.height,
        w * imageSize.width,
        h * imageSize.height,
      );

  /// [aspecto] = largura/altura da imagem: o giro é feito em pixels, não
  /// em coordenadas relativas.
  bool contains(double rx, double ry, {double aspecto = 1}) {
    if (girada) {
      final cx = (x + w / 2) * aspecto, cy = y + h / 2;
      final dx = rx * aspecto - cx, dy = ry - cy;
      final lx = dx * cos(-_rad) - dy * sin(-_rad);
      final ly = dx * sin(-_rad) + dy * cos(-_rad);
      return lx.abs() <= w * aspecto / 2 && ly.abs() <= h / 2;
    }
    if (circulo) {
      final cx = x + w / 2, cy = y + h / 2;
      final dx = (rx - cx) / (w / 2), dy = (ry - cy) / (h / 2);
      return dx * dx + dy * dy <= 1;
    }
    return rx >= x && rx <= x + w && ry >= y && ry <= y + h;
  }
}

class PlantLayout {
  final String plantaId;
  final String imageAsset;
  final double imageWidth;
  final double imageHeight;
  final List<PlantArea> areas;

  const PlantLayout({
    required this.plantaId,
    required this.imageAsset,
    required this.imageWidth,
    required this.imageHeight,
    required this.areas,
  });

  factory PlantLayout.fromJson(Map<String, dynamic> j) => PlantLayout(
        plantaId:    j['plantaId'] as String,
        imageAsset:  j['image']['asset'] as String,
        imageWidth:  (j['image']['width']  as num).toDouble(),
        imageHeight: (j['image']['height'] as num).toDouble(),
        areas: (j['areas'] as List)
            .map((a) => PlantArea.fromJson(a as Map<String, dynamic>))
            .toList(),
      );

  double get aspectRatio => imageWidth / imageHeight;
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────

class PlantMapPage extends StatefulWidget {
  final String jsonAsset;
  /// C3: área da divergência. Com ela, o mapa só mostra (não seleciona):
  /// abre com zoom na área e um alfinete vermelho no centro.
  final String? destaqueAreaId;

  const PlantMapPage({
    super.key,
    required this.jsonAsset,
    this.destaqueAreaId,
  });

  @override
  State<PlantMapPage> createState() => _PlantMapPageState();
}

class _PlantMapPageState extends State<PlantMapPage>
    with SingleTickerProviderStateMixin {
  PlantLayout? _layout;
  PlantArea?   _selected;
  bool _loading = true;

  /// C3: área com o alfinete (null = modo seleção normal).
  PlantArea? _destaque;
  bool _zoomInicialFeito = false;
  Size? _tamanhoMapa; // área do mapa (sem a barra), para re-centralizar
  bool get _soVisualizar => widget.destaqueAreaId != null;

  // Scale atual do InteractiveViewer (para decidir visibilidade dos labels)
  double _currentScale = 1.0;

  final TransformationController _transformCtrl = TransformationController();
  late final AnimationController _animCtrl;
  Animation<Matrix4>? _animation;

  static const double _minScale = 1.0;
  static const double _maxScale = 8.0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(() {
        if (_animation != null) {
          _transformCtrl.value = _animation!.value;
          // Atualiza o scale atual para o painter
          final scale = _transformCtrl.value.getMaxScaleOnAxis();
          if (scale != _currentScale) {
            setState(() => _currentScale = scale);
          }
        }
      });

    // Listener para quando o usuário faz pan/zoom manual
    _transformCtrl.addListener(() {
      final scale = _transformCtrl.value.getMaxScaleOnAxis();
      if ((scale - _currentScale).abs() > 0.05) {
        setState(() => _currentScale = scale);
      }
    });

    _loadJson();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _transformCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadJson() async {
    try {
      final raw  = await rootBundle.loadString(widget.jsonAsset);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final layout = PlantLayout.fromJson(json);
      PlantArea? destaque;
      final alvo = widget.destaqueAreaId?.trim();
      if (alvo != null && alvo.isNotEmpty) {
        for (final a in layout.areas) {
          if (a.id == alvo) {
            destaque = a;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _layout   = layout;
        _destaque = destaque;
        _loading  = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      debugPrint('PlantMapPage: erro ao carregar JSON – $e');
    }
  }

  // ─── Hit-test ─────────────────────────────────────────────────────────────

  PlantArea? _hitTest(Offset localPos, Size widgetSize) {
    final layout = _layout!;
    final invertedMatrix = Matrix4.tryInvert(_transformCtrl.value);
    if (invertedMatrix == null) return null;

    final transformed = MatrixUtils.transformPoint(invertedMatrix, localPos);
    final imageRect   = _imageRectInWidget(widgetSize, layout.aspectRatio);
    if (!imageRect.contains(transformed)) return null;

    final rx = (transformed.dx - imageRect.left) / imageRect.width;
    final ry = (transformed.dy - imageRect.top)  / imageRect.height;

    // A menor área sob o dedo ganha: uma área desenhada dentro de outra
    // continua selecionável.
    PlantArea? melhor;
    for (final area in layout.areas) {
      if (area.contains(rx, ry, aspecto: layout.aspectRatio) &&
          (melhor == null || area.w * area.h < melhor.w * melhor.h)) {
        melhor = area;
      }
    }
    return melhor;
  }

  Rect _imageRectInWidget(Size widgetSize, double aspectRatio) {
    final widgetAspect = widgetSize.width / widgetSize.height;
    double imgW, imgH;
    if (aspectRatio > widgetAspect) {
      imgW = widgetSize.width;
      imgH = widgetSize.width / aspectRatio;
    } else {
      imgH = widgetSize.height;
      imgW = widgetSize.height * aspectRatio;
    }
    final left = (widgetSize.width  - imgW) / 2;
    final top  = (widgetSize.height - imgH) / 2;
    return Rect.fromLTWH(left, top, imgW, imgH);
  }

  // ─── Zoom animado ─────────────────────────────────────────────────────────

  void _zoomToArea(PlantArea area, Size widgetSize) {
    final layout    = _layout!;
    final imageRect = _imageRectInWidget(widgetSize, layout.aspectRatio);

    final env = area.envoltorio(imageRect.size);
    final areaCenterX = imageRect.left + env.center.dx;
    final areaCenterY = imageRect.top  + env.center.dy;

    final scaleByWidth  = widgetSize.width  / env.width  * 0.8;
    final scaleByHeight = widgetSize.height / env.height * 0.8;
    final targetScale   = min(max(min(scaleByWidth, scaleByHeight), _minScale), _maxScale);

    final tx = widgetSize.width  / 2 - areaCenterX * targetScale;
    final ty = widgetSize.height / 2 - areaCenterY * targetScale;

    final targetMatrix = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(targetScale);

    _animation = Matrix4Tween(
      begin: _transformCtrl.value,
      end:   targetMatrix,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOutCubic));

    _animCtrl.forward(from: 0);
  }

  void _resetZoom() {
    _animation = Matrix4Tween(
      begin: _transformCtrl.value,
      end:   Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOutCubic));
    _animCtrl.forward(from: 0);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_layout == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mapa da Planta')),
        body: const Center(child: Text('Erro ao carregar o mapa.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
        title: Text(
          _soVisualizar
              ? 'Divergência: ${(_destaque?.nome ?? widget.destaqueAreaId!).replaceAll('_', ' ')}'
              : _layout!.plantaId.replaceAll('_', ' '),
          style: const TextStyle(fontSize: 15, color: Colors.white70),
        ),
        actions: [
          if (_soVisualizar && _destaque != null)
            IconButton(
              icon: const Icon(Icons.place, color: Colors.redAccent),
              tooltip: 'Voltar ao alfinete',
              onPressed: () {
                final t = _tamanhoMapa;
                if (t != null) _zoomToArea(_destaque!, t);
              },
            ),
          if (!_soVisualizar && _selected != null) ...[
            // Botão confirmar
            TextButton.icon(
              icon: const Icon(Icons.check_circle, color: Color(0xFF00D4AA)),
              label: const Text(
                'Confirmar',
                style: TextStyle(color: Color(0xFF00D4AA)),
              ),
              onPressed: () => Navigator.of(context).pop(_selected),
            ),
            // Botão cancelar seleção
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              tooltip: 'Cancelar seleção',
              onPressed: () {
                setState(() => _selected = null);
                _resetZoom();
              },
            ),
          ],
          // Reset zoom
          IconButton(
            icon: const Icon(Icons.fit_screen, color: Colors.white54),
            tooltip: 'Ver tudo',
            onPressed: () {
              setState(() => _selected = null);
              _resetZoom();
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);
          _tamanhoMapa = widgetSize;
          if (_destaque != null && !_zoomInicialFeito) {
            _zoomInicialFeito = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _zoomToArea(_destaque!, widgetSize);
            });
          }
          return Stack(
            children: [
              // InteractiveViewer com imagem + overlays
              InteractiveViewer(
                transformationController: _transformCtrl,
                minScale: _minScale,
                maxScale: _maxScale,
                constrained: false,
                child: SizedBox(
                  width:  widgetSize.width,
                  height: widgetSize.height,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          _layout!.imageAsset,
                          fit: BoxFit.contain,
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _AreaOverlayPainter(
                            layout:       _layout!,
                            selected:     _soVisualizar ? _destaque : _selected,
                            currentScale: _currentScale,
                            alfinete:     _destaque,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Camada de toque
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (details) {
                  if (_soVisualizar) return; // C3: só mostra
                  final area = _hitTest(details.localPosition, widgetSize);
                  if (area != null) {
                    setState(() => _selected = area);
                    _zoomToArea(area, widgetSize);
                  } else if (_selected != null) {
                    setState(() => _selected = null);
                    _resetZoom();
                  }
                },
                child: const SizedBox.expand(),
              ),
            ],
          );
        },
      ),
      // Barra inferior com área selecionada
      bottomNavigationBar: _soVisualizar
          ? _BarraDivergencia(
              areaId: widget.destaqueAreaId!, area: _destaque)
          : _selected == null
              ? null
              : _SelectedAreaBar(area: _selected!),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAINTER DOS OVERLAYS
// ─────────────────────────────────────────────────────────────────────────────

class _AreaOverlayPainter extends CustomPainter {
  final PlantLayout layout;
  final PlantArea?  selected;
  final double      currentScale;
  /// C3: alfinete vermelho no centro desta área.
  final PlantArea?  alfinete;

  // Tamanho mínimo da área em pixels na tela para mostrar label
  // Ex: área de 80x80px visíveis antes de mostrar o texto
  static const double _minPxParaLabel = 80.0;

  const _AreaOverlayPainter({
    required this.layout,
    required this.currentScale,
    this.selected,
    this.alfinete,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final aspectRatio  = layout.aspectRatio;
    final widgetAspect = size.width / size.height;
    double imgW, imgH;
    if (aspectRatio > widgetAspect) {
      imgW = size.width;
      imgH = size.width / aspectRatio;
    } else {
      imgH = size.height;
      imgW = size.height * aspectRatio;
    }
    final left      = (size.width  - imgW) / 2;
    final top       = (size.height - imgH) / 2;
    final imageSize = Size(imgW, imgH);

    for (final area in layout.areas) {
      final rect       = area.toRect(imageSize).translate(left, top);
      final isSelected = area.id == selected?.id;

      // Tamanho real que a área ocupa na tela (com zoom aplicado)
      final pxW = rect.width  * currentScale;
      final pxH = rect.height * currentScale;
      final areaVisivel = pxW >= _minPxParaLabel && pxH >= _minPxParaLabel;

      void desenhar(Paint p) {
        if (area.circulo) {
          canvas.drawOval(rect, p);
        } else if (area.girada) {
          canvas.save();
          canvas.translate(rect.center.dx, rect.center.dy);
          canvas.rotate(area.rot * pi / 180);
          canvas.drawRect(
              Rect.fromCenter(center: Offset.zero, width: rect.width, height: rect.height), p);
          canvas.restore();
        } else {
          canvas.drawRect(rect, p);
        }
      }

      // Fill — cinza visível sempre, verde quando selecionada
      desenhar(
        Paint()
          ..color = isSelected
              ? const Color(0xFF00D4AA).withOpacity(0.40)
              : Colors.grey.withOpacity(0.28),
      );

      // Border — sempre visível, destaca quando selecionada
      desenhar(
        Paint()
          ..color = isSelected
              ? const Color(0xFF00D4AA)
              : Colors.grey.shade300.withOpacity(0.75)
          ..style       = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2.5 : 1.2,
      );

      // Label — só exibe se área grande o suficiente na tela, ou se selecionada
      if (!isSelected && !areaVisivel) continue;

      final nomeFormatado = area.nome.replaceAll('_', ' ');

      final label = TextPainter(
        text: TextSpan(
          text: nomeFormatado,
          style: TextStyle(
            color:      isSelected ? const Color(0xFF00D4AA) : Colors.white70,
            fontSize:   isSelected ? 12 : 9,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            shadows: const [
              Shadow(blurRadius: 3, color: Colors.black),
              Shadow(blurRadius: 6, color: Colors.black),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign:     TextAlign.center,
      )..layout(maxWidth: rect.width);

      if (area.girada && label.height <= rect.height) {
        var g = area.rot;
        if (g > 90) g -= 180;
        if (g < -90) g += 180;
        canvas.save();
        canvas.translate(rect.center.dx, rect.center.dy);
        canvas.rotate(g * pi / 180);
        label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
        canvas.restore();
        continue;
      }

      // Só pinta o label se ele couber verticalmente na área
      if (label.height <= rect.height) {
        label.paint(
          canvas,
          Offset(
            rect.left + (rect.width  - label.width)  / 2,
            rect.top  + (rect.height - label.height) / 2,
          ),
        );
      }
    }

    final pin = alfinete;
    if (pin != null) {
      final rect = pin.toRect(imageSize).translate(left, top);
      _pintarAlfinete(canvas, rect.center);
    }
  }

  /// Alfinete vermelho com a ponta no ponto [p]. O tamanho é compensado
  /// pelo zoom, para ficar sempre do mesmo tamanho na tela.
  void _pintarAlfinete(Canvas canvas, Offset p) {
    final k = 1 / currentScale;
    final r = 11.0 * k;          // raio da cabeça
    final altura = 30.0 * k;     // da ponta ao centro da cabeça... + raio
    final cabeca = Offset(p.dx, p.dy - altura + r);

    // sombra
    canvas.drawOval(
      Rect.fromCenter(center: p, width: 14 * k, height: 5 * k),
      Paint()..color = Colors.black.withOpacity(0.45),
    );
    // corpo (gota)
    final corpo = Path()
      ..moveTo(p.dx, p.dy)
      ..lineTo(cabeca.dx - r * 0.82, cabeca.dy + r * 0.55)
      ..arcToPoint(
        Offset(cabeca.dx + r * 0.82, cabeca.dy + r * 0.55),
        radius: Radius.circular(r),
        largeArc: true,
      )
      ..close();
    canvas.drawPath(corpo, Paint()..color = const Color(0xFFE53935));
    canvas.drawPath(
      corpo,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * k,
    );
    // miolo
    canvas.drawCircle(cabeca, r * 0.38, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_AreaOverlayPainter old) =>
      old.selected?.id != selected?.id ||
      old.alfinete?.id != alfinete?.id ||
      (old.currentScale - currentScale).abs() > 0.05;
}

// ─────────────────────────────────────────────────────────────────────────────
// BARRA INFERIOR
// ─────────────────────────────────────────────────────────────────────────────

class _SelectedAreaBar extends StatelessWidget {
  final PlantArea area;
  const _SelectedAreaBar({required this.area});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF16213E),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Color(0xFF00D4AA), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize:      MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  area.nome.replaceAll('_', ' '),
                  style: const TextStyle(
                    color:      Colors.white,
                    fontSize:   14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'ID: ${area.id}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          const Text(
            'Toque em Confirmar para selecionar',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BARRA INFERIOR — C3 (só visualizar)
// ─────────────────────────────────────────────────────────────────────────────

class _BarraDivergencia extends StatelessWidget {
  final String areaId;
  final PlantArea? area;
  const _BarraDivergencia({required this.areaId, required this.area});

  @override
  Widget build(BuildContext context) {
    final noMapa = area != null;
    return Container(
      color: const Color(0xFF16213E),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Icon(noMapa ? Icons.place : Icons.location_off,
              color: noMapa ? Colors.redAccent : Colors.orangeAccent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              noMapa
                  ? 'Divergência em ${area!.nome.replaceAll('_', ' ')}'
                  : 'A área "${areaId.replaceAll('_', ' ')}" ainda não está '
                      'desenhada no mapa.',
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

