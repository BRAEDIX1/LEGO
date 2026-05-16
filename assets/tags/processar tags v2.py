"""
processar_tags.py
-----------------
Processa múltiplos arquivos xlsx de movimentação de TAGs e gera um único
arquivo consolidado com a linha mais recente por Nr. TAG, enriquecido com
produto, volume e unidade vindos do arquivo MARA.xlsx.

Uso:
    python processar_tags.py                          # processa todos os .xlsx da pasta atual
    python processar_tags.py pasta/dos/arquivos       # processa pasta específica
    python processar_tags.py arq1.xlsx arq2.xlsx ...  # arquivos específicos

Saída:
    resultado_consolidado.xlsx  (na pasta atual)

Colunas do resultado (ordem para uso humano):
    Nr. TAG | codigo | produto | volume | unidade | lote | data | hora | ano | centro

Ordem para upload Firestore (futuro):
    ano | centro | codigo | lote | produto | data | hora | unidade | volume
    (Nr. TAG vira o ID do documento)

Dependências:
    pip install polars fastexcel pyarrow xlsxwriter rich
"""

import sys
import math
import datetime as dt
from pathlib import Path
from datetime import datetime

import polars as pl
import xlsxwriter
from rich.console import Console
from rich.progress import (
    Progress, SpinnerColumn, BarColumn, TextColumn,
    TimeElapsedColumn, MofNCompleteColumn,
)
from rich.table import Table
from rich.panel import Panel
from rich import box

console = Console()

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------
COL_TAG      = "Nr. TAG"
COL_MATERIAL = "Material"
COL_LOTE     = "Lote"
COL_CENTRO   = "Centro"
COL_DATA     = "Data"
COL_HORA     = "Hora"
COL_EXERC    = "Exercício"

MARA_FILE    = "MARA.xlsx"
MARA_SHEET   = "Data"
MARA_CODIGO  = "codigo"
MARA_PRODUTO = "produto"
MARA_VOLUME  = "volume"
MARA_UNIDADE = "unidade"

OUTPUT_FILE  = "resultado_consolidado.xlsx"

# Ordem final das colunas no xlsx (uso humano)
COLUNAS_SAIDA = [
    "Nr. TAG", "codigo", "produto", "volume", "unidade",
    "lote", "data", "hora", "ano", "centro",
]


# ---------------------------------------------------------------------------
# Funções auxiliares
# ---------------------------------------------------------------------------
def encontrar_arquivos(args: list) -> tuple:
    excluir = {OUTPUT_FILE, MARA_FILE}

    if not args:
        pasta    = Path(".")
        arquivos = sorted(pasta.glob("*.xlsx"))
    elif len(args) == 1 and Path(args[0]).is_dir():
        pasta    = Path(args[0])
        arquivos = sorted(pasta.glob("*.xlsx"))
    else:
        arquivos = [Path(a) for a in args]
        pasta    = arquivos[0].parent if arquivos else Path(".")

    arquivos = [a for a in arquivos if a.name not in excluir]

    if not arquivos:
        console.print("[bold red]Nenhum arquivo .xlsx encontrado.[/]")
        sys.exit(1)

    return arquivos, pasta


def ler_mara(pasta: Path) -> pl.DataFrame:
    caminho = pasta / MARA_FILE
    if not caminho.exists():
        console.print(f"[bold red]MARA.xlsx não encontrado em: {pasta}[/]")
        console.print("[yellow]Enriquecimento ignorado — produto/volume/unidade ficarão vazios.[/]")
        return pl.DataFrame({
            MARA_CODIGO:  pl.Series([], dtype=pl.Utf8),
            MARA_PRODUTO: pl.Series([], dtype=pl.Utf8),
            MARA_VOLUME:  pl.Series([], dtype=pl.Utf8),
            MARA_UNIDADE: pl.Series([], dtype=pl.Utf8),
        })

    df = pl.read_excel(
        caminho,
        sheet_name=MARA_SHEET,
        engine="calamine",
        schema_overrides={
            MARA_CODIGO:  pl.Utf8,
            MARA_PRODUTO: pl.Utf8,
            MARA_VOLUME:  pl.Utf8,
            MARA_UNIDADE: pl.Utf8,
        },
    )
    df = df.select([MARA_CODIGO, MARA_PRODUTO, MARA_VOLUME, MARA_UNIDADE])
    df = df.unique(subset=[MARA_CODIGO], keep="first")
    console.print(f"  MARA.xlsx lido: [bold]{len(df):,}[/] códigos únicos")
    return df


def ler_arquivo(caminho: Path) -> pl.DataFrame:
    return pl.read_excel(
        caminho,
        engine="calamine",
        schema_overrides={
            COL_TAG:      pl.Utf8,
            COL_MATERIAL: pl.Utf8,
            COL_LOTE:     pl.Utf8,
            COL_CENTRO:   pl.Utf8,
            COL_EXERC:    pl.Utf8,
        },
    )


def limpar(df: pl.DataFrame) -> pl.DataFrame:
    return df.filter(
        pl.col(COL_TAG).is_not_null()
        & (pl.col(COL_TAG).str.strip_chars() != "")
        & (pl.col(COL_TAG).str.strip_chars() != "0")
        & pl.col(COL_LOTE).is_not_null()
        & (pl.col(COL_LOTE).cast(pl.Utf8).str.strip_chars() != "")
    )


def combinar_timestamp(df: pl.DataFrame) -> pl.DataFrame:
    # Hora vem do Excel como Datetime com data fantasma 1899-12-31 — extrai só a parte de tempo
    return (
        df.with_columns(
            pl.col(COL_DATA).cast(pl.Date).alias("_data_norm"),
            pl.col(COL_HORA).cast(pl.Datetime).alias("_hora_dt"),
        ).with_columns(
            pl.datetime(
                year   = pl.col("_data_norm").dt.year(),
                month  = pl.col("_data_norm").dt.month(),
                day    = pl.col("_data_norm").dt.day(),
                hour   = pl.col("_hora_dt").dt.hour(),
                minute = pl.col("_hora_dt").dt.minute(),
                second = pl.col("_hora_dt").dt.second(),
            ).alias("_timestamp")
        ).drop(["_data_norm", "_hora_dt"])
    )


def filtrar_mais_recente(df: pl.DataFrame) -> pl.DataFrame:
    df     = df.unique()
    max_ts = df.group_by(COL_TAG).agg(pl.col("_timestamp").max().alias("_ts_max"))
    df     = (
        df.join(max_ts, on=COL_TAG, how="left")
        .filter(pl.col("_timestamp") == pl.col("_ts_max"))
        .drop(["_timestamp", "_ts_max"])
    )
    return df.unique(subset=[COL_TAG], keep="first")


def enriquecer_com_mara(df: pl.DataFrame, mara: pl.DataFrame) -> tuple:
    df = df.rename({
        COL_MATERIAL: "codigo",
        COL_LOTE:     "lote",
        COL_CENTRO:   "centro",
        COL_EXERC:    "ano",
    })
    df = df.join(mara, on="codigo", how="left")
    df = df.with_columns(pl.col(COL_TAG).str.zfill(9))
    sem_match = df.filter(pl.col(MARA_PRODUTO).is_null()).shape[0]

    # Formata data como string DD/MM/YYYY e hora como HH:MM:SS
    # para garantir exibição correta no xlsx independente de tipo
    df = df.with_columns(
        pl.col(COL_DATA).cast(pl.Date).dt.strftime("%d/%m/%Y").alias("data"),
        pl.col(COL_HORA).cast(pl.Datetime).dt.strftime("%H:%M:%S").alias("hora"),
    ).drop([COL_DATA, COL_HORA])

    df = df.select(COLUNAS_SAIDA)
    return df, sem_match


def _safe_val(valor):
    """Converte NaN/Inf para None antes de gravar no xlsx."""
    if isinstance(valor, float) and (math.isnan(valor) or math.isinf(valor)):
        return None
    return valor


def salvar_xlsx(df: pl.DataFrame, caminho_saida: str, progress, task) -> None:
    colunas     = df.columns
    rows        = df.to_pandas().values.tolist()
    total       = len(rows)
    idx_produto = colunas.index("produto")

    progress.update(task, total=total, description="Gravando xlsx...")

    wb = xlsxwriter.Workbook(caminho_saida, {"constant_memory": True})
    ws = wb.add_worksheet("Consolidado")

    fmt_header = wb.add_format({"bold": True, "bg_color": "#1F4E79",
                                 "font_color": "#FFFFFF", "align": "center", "border": 1})
    fmt_date   = wb.add_format({"num_format": "DD/MM/YYYY"})
    fmt_time   = wb.add_format({"num_format": "HH:MM:SS"})
    fmt_warn   = wb.add_format({"bg_color": "#FFF2CC"})
    fmt_warn_d = wb.add_format({"bg_color": "#FFF2CC", "num_format": "DD/MM/YYYY"})
    fmt_warn_t = wb.add_format({"bg_color": "#FFF2CC", "num_format": "HH:MM:SS"})

    for col_idx, nome in enumerate(colunas):
        ws.write(0, col_idx, nome, fmt_header)
        ws.set_column(col_idx, col_idx, max(len(nome), 14) + 2)

    ws.freeze_panes(1, 0)

    for row_idx, row in enumerate(rows, start=1):
        sem_match_linha = row[idx_produto] is None or str(row[idx_produto]).strip() == ""

        for col_idx, valor in enumerate(row):
            valor = _safe_val(valor)
            fmt   = fmt_warn if sem_match_linha else None
            if valor is None:
                ws.write_blank(row_idx, col_idx, None, fmt)
            else:
                ws.write(row_idx, col_idx, valor, fmt)

        if row_idx % 5000 == 0:
            progress.update(task, completed=row_idx)

    progress.update(task, completed=total)
    wb.close()


# ---------------------------------------------------------------------------
# Pipeline principal
# ---------------------------------------------------------------------------
def main():
    inicio          = datetime.now()
    args            = sys.argv[1:]
    arquivos, pasta = encontrar_arquivos(args)

    console.print(Panel(
        f"[bold cyan]processar_tags.py[/]\n"
        f"Arquivos encontrados: [bold]{len(arquivos)}[/]\n"
        f"Pasta: [bold]{pasta.resolve()}[/]\n"
        f"Saída: [bold]{OUTPUT_FILE}[/]",
        title="Início do processamento",
        border_style="cyan",
    ))

    console.print("\n[bold]Lendo MARA.xlsx...[/]")
    mara = ler_mara(pasta)

    frames = []
    resumo = []
    erros  = []

    with Progress(
        SpinnerColumn(),
        TextColumn("[bold blue]{task.description}"),
        BarColumn(bar_width=35),
        MofNCompleteColumn(),
        TimeElapsedColumn(),
        console=console,
        transient=False,
    ) as progress:

        tarefa_geral = progress.add_task("Processando arquivos...", total=len(arquivos))

        for arq in arquivos:
            progress.update(tarefa_geral, description=f"Lendo {arq.name}")
            try:
                df    = ler_arquivo(arq)
                bruto = len(df)
                progress.update(tarefa_geral, description=f"Limpando {arq.name}")
                df    = limpar(df)
                limpo = len(df)
                frames.append(df)
                resumo.append({"arquivo": arq.name, "bruto": bruto, "limpo": limpo,
                                "removidos": bruto - limpo, "erro": None})
            except Exception as e:
                erros.append(arq.name)
                resumo.append({"arquivo": arq.name, "bruto": 0, "limpo": 0,
                                "removidos": 0, "erro": str(e)})
                console.print(f"  [bold red]ERRO em {arq.name}:[/] {e}")
            progress.advance(tarefa_geral)

        progress.update(tarefa_geral, description="Consolidando arquivos...")
        consolidado       = pl.concat(frames, how="diagonal")
        total_consolidado = len(consolidado)

        progress.update(tarefa_geral, description="Combinando timestamps...")
        consolidado = combinar_timestamp(consolidado)

        progress.update(tarefa_geral, description="Filtrando mais recentes...")
        antes_filtro = len(consolidado)
        consolidado  = filtrar_mais_recente(consolidado)
        final        = len(consolidado)

        progress.update(tarefa_geral, description="Enriquecendo com MARA...")
        consolidado, sem_match = enriquecer_com_mara(consolidado, mara)

        task_salvar = progress.add_task("Gravando xlsx...", total=final)
        salvar_xlsx(consolidado, OUTPUT_FILE, progress, task_salvar)

    # Tabela de resumo
    table = Table(title="Resumo por arquivo", box=box.ROUNDED,
                  border_style="cyan", header_style="bold white on dark_blue")
    table.add_column("Arquivo",   style="cyan",  no_wrap=True)
    table.add_column("Bruto",     style="white",  justify="right")
    table.add_column("Removidos", style="yellow", justify="right")
    table.add_column("Válidas",   style="green",  justify="right")
    table.add_column("Status",    justify="center")

    total_bruto = total_limpo = 0
    for r in resumo:
        status = "[bold red]ERRO[/]" if r["erro"] else "[bold green]OK[/]"
        table.add_row(r["arquivo"], f"{r['bruto']:,}", f"{r['removidos']:,}", f"{r['limpo']:,}", status)
        total_bruto += r["bruto"]
        total_limpo += r["limpo"]

    table.add_section()
    table.add_row("[bold]TOTAL[/]", f"[bold]{total_bruto:,}[/]",
                  f"[bold]{total_bruto - total_limpo:,}[/]", f"[bold]{total_limpo:,}[/]", "")
    console.print(table)

    fim       = datetime.now()
    elapsed   = (fim - inicio).seconds
    tempo_str = f"{elapsed // 60}m {elapsed % 60}s" if elapsed >= 60 else f"{elapsed}s"

    aviso_match = (
        f"\n\n  [bold yellow]TAGs sem match no MARA: {sem_match:,}[/]\n"
        f"  [yellow]  Linhas destacadas em amarelo no xlsx.[/]"
        if sem_match else ""
    )
    aviso_erro = (
        f"\n\n  [bold red]Arquivos com erro ({len(erros)}):[/] {', '.join(erros)}"
        if erros else ""
    )

    console.print(Panel(
        f"[bold green]Processamento concluído![/]\n\n"
        f"  Linhas consolidadas:     [bold]{total_consolidado:,}[/]\n"
        f"  Removidas (filtro):      [bold yellow]{antes_filtro - final:,}[/]\n"
        f"  [bold cyan]TAGs únicos (resultado): {final:,}[/]\n\n"
        f"  Arquivo salvo: [bold]{OUTPUT_FILE}[/]\n"
        f"  Tempo total:   [bold]{tempo_str}[/]"
        + aviso_match + aviso_erro,
        title="Resultado",
        border_style="green",
    ))


if __name__ == "__main__":
    main()
