"""
watch_documentacao.py  v1.0
─────────────────────────────────────────────────────────────────────────────
Monitora arquivos-sentinela do projeto LEGO em segundo plano.
Quando detecta que qualquer sentinela foi modificado após o último registro
na DOCUMENTACAO_TECNICA.md, regenera a documentação automaticamente.

Uso:
    python watch_documentacao.py             # monitora LEGO (padrão)
    python watch_documentacao.py -p C:\\outro\\projeto
    python watch_documentacao.py --intervalo 30   # checar a cada 30s (padrão: 10s)

Parar: Ctrl+C
─────────────────────────────────────────────────────────────────────────────
"""

import re
import sys
import io
import time
import argparse
import subprocess
from pathlib import Path
from datetime import datetime

# ─── Log file (usado quando rodando via pythonw sem console) ─────────────────
LOG_FILE = Path(r"C:\Users\djast\watcher_log.txt")

def _setup_output():
    """Redireciona stdout/stderr para log se não houver console (pythonw)."""
    try:
        # Testa se stdout funciona
        sys.stdout.write("")
        sys.stdout.flush()
        # Tem console — força UTF-8
        if hasattr(sys.stdout, 'reconfigure'):
            sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        # Sem console (pythonw) — redireciona para arquivo de log
        log = open(LOG_FILE, 'a', encoding='utf-8', buffering=1)
        sys.stdout = log
        sys.stderr = log

_setup_output()

# ─── Caminho padrão ───────────────────────────────────────────────────────────
PROJETO_DEFAULT = Path(r"C:\Users\djast\LEGO")

# Caminho do gerador — assume que está na mesma pasta que este script
GERADOR = Path(__file__).parent / "gerar_documentacao_V4.py"

# ─── Arquivos sentinela ───────────────────────────────────────────────────────
# Escolhidos pelo mapa de impacto: arquivos centrais cuja mudança
# torna a documentação desatualizada imediatamente.
SENTINELAS_RELATIVOS = [
    # Modelos de dados
    "lib/data/local/lanc_local.dart",        # modelo principal (24 campos)
    "lib/data/local/app_state.dart",          # estado da app
    "lib/data/local/produto_local.dart",      # produto Hive
    "lib/data/local/barra_local.dart",        # barra Hive
    "lib/data/local/hive_boxes.dart",         # núcleo crítico (13 dependentes)
    # Modelos de domínio
    "lib/models/inventario.dart",             # mais importado (14 dependentes)
    # Repositórios
    "lib/data/repositories/lancamentos_repository.dart",
    "lib/data/repositories/produtos_repository.dart",
    "lib/data/repositories/barras_repository.dart",
    # Serviços centrais
    "lib/services/inventario_service.dart",   # 8 dependentes
    "lib/services/sync_service.dart",
    "lib/services/mobile_sync_service.dart",
    "lib/services/auth_service.dart",
    # Tela principal
    "lib/ui/home_page.dart",
    # Entry points
    "lib/main.dart",
    "lib/main_desktop.dart",
]


def ler_data_geracao(doc_path: Path) -> datetime | None:
    """Lê a data de geração registrada no topo da DOCUMENTACAO_TECNICA.md."""
    if not doc_path.exists():
        return None
    try:
        with open(doc_path, encoding="utf-8") as f:
            for linha in f:
                # Linha: > **Gerado em:** 10/04/2026 22:53:01
                m = re.search(r'Gerado em:\*\*\s+(\d{2}/\d{2}/\d{4})\s+(\d{2}:\d{2}:\d{2})', linha)
                if m:
                    return datetime.strptime(f"{m.group(1)} {m.group(2)}", "%d/%m/%Y %H:%M:%S")
    except Exception:
        pass
    return None


def checar_sentinelas(raiz: Path, desde: datetime | None) -> list[tuple[Path, datetime]]:
    """Retorna lista de (arquivo, mtime) para sentinelas modificados após 'desde'."""
    modificados = []
    for rel in SENTINELAS_RELATIVOS:
        p = raiz / rel.replace("/", "\\") if sys.platform == "win32" else raiz / rel
        if not p.exists():
            continue
        mtime = datetime.fromtimestamp(p.stat().st_mtime)
        # Se não há doc ainda, qualquer arquivo existente é "modificado"
        if desde is None or mtime > desde:
            modificados.append((p, mtime))
    return modificados


def regenerar(raiz: Path) -> bool:
    """Chama o gerador V4. Retorna True se bem-sucedido."""
    cmd = [sys.executable, str(GERADOR), "--projeto", str(raiz)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        return True
    print(f"  ❌ Erro ao gerar:\n{result.stderr.strip()}")
    return False


def fmt_hora(dt: datetime) -> str:
    return dt.strftime("%d/%m/%Y %H:%M:%S")


def main():
    parser = argparse.ArgumentParser(
        description="Watcher de documentação automático para projetos Flutter (v1.0)."
    )
    parser.add_argument("--projeto", "-p", default=str(PROJETO_DEFAULT),
                        help=f"Pasta raiz do projeto (padrão: {PROJETO_DEFAULT})")
    parser.add_argument("--intervalo", "-i", type=int, default=10,
                        help="Intervalo de verificação em segundos (padrão: 10)")
    args = parser.parse_args()

    raiz = Path(args.projeto).resolve()
    if not raiz.exists():
        print(f"❌ Projeto não encontrado: {raiz}")
        sys.exit(1)

    if not GERADOR.exists():
        print(f"❌ Gerador não encontrado: {GERADOR}")
        print("   Certifique-se de que gerar_documentacao_V4.py está na mesma pasta.")
        sys.exit(1)

    doc_path = raiz / "DOCUMENTACAO_TECNICA.md"

    print("═" * 60)
    print("📡 WATCHER DE DOCUMENTAÇÃO — LEGO")
    print("═" * 60)
    print(f"  Projeto  : {raiz}")
    print(f"  Intervalo: {args.intervalo}s")
    print(f"  Sentinelas: {len(SENTINELAS_RELATIVOS)} arquivos monitorados")
    print(f"  Gerador  : {GERADOR.name}")
    print("  Pressione Ctrl+C para parar.")
    print("─" * 60)

    # Gera imediatamente se não existir documentação
    if not doc_path.exists():
        print(f"\n⚠️  DOCUMENTACAO_TECNICA.md não encontrada. Gerando agora...")
        if regenerar(raiz):
            print(f"  ✅ Documentação criada em {fmt_hora(datetime.now())}")

    try:
        while True:
            data_doc = ler_data_geracao(doc_path)
            modificados = checar_sentinelas(raiz, data_doc)

            if modificados:
                print(f"\n🔔 [{fmt_hora(datetime.now())}] Mudança detectada:")
                for p, mtime in modificados:
                    doc_str = f" (doc: {fmt_hora(data_doc)})" if data_doc else " (sem doc prévia)"
                    print(f"   📝 {p.name} — modificado em {fmt_hora(mtime)}{doc_str}")

                print("  🔄 Regenerando documentação...")
                if regenerar(raiz):
                    nova_data = ler_data_geracao(doc_path)
                    print(f"  ✅ Documentação atualizada em {fmt_hora(nova_data or datetime.now())}")
            else:
                # Feedback silencioso — só imprime se houver mudança
                pass

            time.sleep(args.intervalo)

    except KeyboardInterrupt:
        print(f"\n\n⏹  Watcher encerrado em {fmt_hora(datetime.now())}.")


if __name__ == "__main__":
    main()
