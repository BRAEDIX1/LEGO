"""
svg_to_areas_json.py
────────────────────
Lê um SVG do Inkscape, extrai todos os <rect> e gera o JSON de áreas
para o PlantMapPage do Flutter.

Uso (sem argumento — usa o caminho padrão):
    python svg_to_areas_json.py

Uso (com argumento — sobrescreve o caminho padrão):
    python svg_to_areas_json.py "C:\\outro\\caminho\\PLANTA.svg"

Saída:
    PLANTA_ATUAL_DE_DIADEMA_areas.json  (mesmo diretório do SVG)

Requisito:
    pip install lxml
"""

import json
import sys
import os
import re
from lxml import etree

# ─── Caminho padrão do SVG ─────────────────────────────────────────────────
DEFAULT_SVG = r"C:\Users\djast\LEGO\assets\plantas\PLANTA_ATUAL_DE_DIADEMA.svg"

# ─── Namespaces do Inkscape/SVG ────────────────────────────────────────────
INKSCAPE_LABEL = "{http://www.inkscape.org/namespaces/inkscape}label"


def log(msg: str):
    print(msg, flush=True)


def parse_transform_translate(transform_str: str) -> tuple[float, float]:
    """Extrai tx, ty de 'translate(tx, ty)' ou 'translate(tx)'."""
    if not transform_str:
        return 0.0, 0.0
    m = re.search(
        r"translate\(\s*([+-]?\d*\.?\d+)\s*(?:,\s*([+-]?\d*\.?\d+))?\s*\)",
        transform_str,
    )
    if m:
        tx = float(m.group(1))
        ty = float(m.group(2)) if m.group(2) else 0.0
        return tx, ty
    return 0.0, 0.0


def get_parent_translate(elem) -> tuple[float, float]:
    """Sobe na árvore acumulando translates de camadas pai."""
    tx, ty = 0.0, 0.0
    parent = elem.getparent()
    while parent is not None:
        t = parent.get("transform", "")
        if t:
            dx, dy = parse_transform_translate(t)
            tx += dx
            ty += dy
        parent = parent.getparent()
    return tx, ty


def extract_svg_dimensions(root) -> tuple[float, float, float, float]:
    """Retorna (vb_x, vb_y, vb_w, vb_h) do viewBox, ou (0,0,w,h) pelo width/height."""
    vb = root.get("viewBox")
    if vb:
        parts = vb.replace(",", " ").split()
        return float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3])

    def parse_dim(v: str) -> float:
        return float("".join(c for c in v if c in "0123456789."))

    w = parse_dim(root.get("width", "1"))
    h = parse_dim(root.get("height", "1"))
    return 0.0, 0.0, w, h


def extract_rects(svg_path: str) -> dict:
    tree = etree.parse(svg_path)
    root = tree.getroot()

    vb_x, vb_y, vb_w, vb_h = extract_svg_dimensions(root)
    log(f"  viewBox: x={vb_x} y={vb_y} w={vb_w} h={vb_h}")

    planta_id = os.path.splitext(os.path.basename(svg_path))[0].upper()

    # Imagem PNG referenciada no SVG
    image_asset = f"assets/plantas/{planta_id}.png"
    image_elem = root.find(".//{http://www.w3.org/2000/svg}image")
    if image_elem is not None:
        href = (
            image_elem.get("{http://www.w3.org/1999/xlink}href")
            or image_elem.get("href", "")
        )
        if href:
            image_asset = f"assets/plantas/{os.path.basename(href)}"

    img_w = float(image_elem.get("width", vb_w)) if image_elem is not None else vb_w
    img_h = float(image_elem.get("height", vb_h)) if image_elem is not None else vb_h

    areas = []
    skipped = 0

    all_rects = root.findall(".//{http://www.w3.org/2000/svg}rect")
    log(f"  {len(all_rects)} <rect> encontrados no SVG")

    for rect in all_rects:
        layer = rect.getparent()
        layer_label = ""
        if layer is not None:
            layer_label = layer.get(INKSCAPE_LABEL, "") or layer.get("id", "")

        # Ignora retângulos na camada da imagem
        if layer_label.lower() in ("image", "imagem", "background", "fundo"):
            log(f"  ⏭  Ignorado (camada '{layer_label}'): {rect.get('id', '?')}")
            skipped += 1
            continue

        rx = float(rect.get("x", 0))
        ry = float(rect.get("y", 0))
        rw = float(rect.get("width", 0))
        rh = float(rect.get("height", 0))

        if rw <= 0 or rh <= 0:
            log(f"  ⏭  Ignorado (sem dimensão): {rect.get('id', '?')}")
            skipped += 1
            continue

        # Aplica transform do próprio rect
        self_tx, self_ty = parse_transform_translate(rect.get("transform", ""))
        rx += self_tx
        ry += self_ty

        # Aplica translates de camadas pai
        parent_tx, parent_ty = get_parent_translate(rect)
        rx += parent_tx
        ry += parent_ty

        # Ajuste de origem do viewBox
        rx -= vb_x
        ry -= vb_y

        # Converte para relativo (0..1)
        rel_x = rx / vb_w
        rel_y = ry / vb_h
        rel_w = rw / vb_w
        rel_h = rh / vb_h

        # Clamp 0..1
        rel_x = max(0.0, min(1.0, rel_x))
        rel_y = max(0.0, min(1.0, rel_y))
        rel_w = max(0.0, min(1.0 - rel_x, rel_w))
        rel_h = max(0.0, min(1.0 - rel_y, rel_h))

        area_id   = rect.get("id", f"AREA_{len(areas)+1:03d}")
        area_nome = rect.get(INKSCAPE_LABEL) or area_id

        areas.append({
            "id":     area_id.upper().replace("-", "_"),
            "nome":   area_nome,
            "x":      round(rel_x, 5),
            "y":      round(rel_y, 5),
            "w":      round(rel_w, 5),
            "h":      round(rel_h, 5),
            # Debug — remova antes de produção
            "_layer": layer_label,
            "_abs":   {
                "x": round(rx, 1),
                "y": round(ry, 1),
                "w": round(rw, 1),
                "h": round(rh, 1),
            },
        })

    log(f"  {len(areas)} áreas extraídas | {skipped} ignoradas")

    return {
        "plantaId": planta_id,
        "image": {
            "asset":  image_asset,
            "width":  round(img_w),
            "height": round(img_h),
        },
        "areas": areas,
    }


def main():
    log("\n" + "=" * 60)
    log("  svg_to_areas_json.py")
    log("=" * 60)

    script_dir = os.path.abspath(os.path.dirname(__file__))
    log(f"\n📂 Script localizado em: {script_dir}")
    log(f"📂 Diretório atual:      {os.path.abspath(os.getcwd())}")

    # Caminho do SVG: argumento ou padrão
    if len(sys.argv) >= 2:
        svg_path = os.path.abspath(sys.argv[1])
        log(f"\n📄 SVG (via argumento):  {svg_path}")
    else:
        svg_path = os.path.abspath(DEFAULT_SVG)
        log(f"\n📄 SVG (caminho padrão): {svg_path}")

    if not os.path.exists(svg_path):
        log(f"\n❌ Arquivo não encontrado: {svg_path}")
        log("   Verifique se o SVG foi salvo no caminho correto.")
        sys.exit(1)

    log(f"✅ Arquivo encontrado. Tamanho: {os.path.getsize(svg_path):,} bytes")

    log("\n─── Extraindo retângulos... ─────────────────────────────")
    result = extract_rects(svg_path)

    out_path = os.path.splitext(svg_path)[0] + "_areas.json"
    log(f"\n─── Salvando JSON... ────────────────────────────────────")
    log(f"📝 Destino: {out_path}")

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    log(f"✅ JSON salvo com sucesso!")
    log(f"   Tamanho: {os.path.getsize(out_path):,} bytes")
    log(f"   Áreas:   {len(result['areas'])}")

    log("\n─── Áreas extraídas: ────────────────────────────────────")
    if not result["areas"]:
        log("  ⚠️  Nenhuma área encontrada! Verifique:")
        log("     - Se os retângulos estão em camada separada da imagem")
        log("     - Se a camada da imagem se chama 'Image' ou 'Imagem'")
    else:
        for i, a in enumerate(result["areas"], 1):
            log(f"\n  [{i}] ID:     {a['id']}")
            log(f"       Nome:   {a['nome']}")
            log(f"       Rel:    x={a['x']} y={a['y']} w={a['w']} h={a['h']}")
            log(f"       Abs:    x={a['_abs']['x']} y={a['_abs']['y']} "
                f"w={a['_abs']['w']} h={a['_abs']['h']}")
            log(f"       Camada: {a['_layer']}")

    log("\n─── Próximos passos: ────────────────────────────────────")
    log(f"  1. Abra o JSON e valide as áreas:")
    log(f"     {out_path}")
    log(f"  2. Remova '_layer' e '_abs' antes de usar em produção")
    log(f"  3. O JSON já está na pasta assets/ do Flutter ✅")
    log("\n" + "=" * 60 + "\n")


if __name__ == "__main__":
    main()
