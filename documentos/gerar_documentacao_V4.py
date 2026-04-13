"""
gerar_documentacao.py  v4.0
─────────────────────────────────────────────────────────────────────────────
Documentação técnica de excelência para projetos Flutter.
Objetivo: guia cirúrgico para humanos e IAs realizarem manutenção e evolução
sem achismo, sem danificar o que já funciona.

SEÇÕES GERADAS:
  0. Sumário Executivo          — saúde geral, alertas críticos, estatísticas
  1. Estrutura de Pastas        — hierarquia com ícones por tipo
  2. Alertas Arquiteturais      — God Files, acoplamento, violações de camada
  3. Modelos Hive               — campos, typeIds, próximo fieldId, rastreabilidade
  4. Coleções Firestore         — operações por coleção (leitura/escrita/stream)
  5. Catálogo de Arquivos       — por pasta: descrição inferida, declarações,
                                  métodos, imports/exports, quem importa
  6. Mapa de Dependências       — ranking de centralidade
  7. Mapa de Impacto            — "se eu mudar X, o que é afetado?"
  8. Dependências pubspec.yaml
  9. Guia — Onde Mexer          — referência rápida por tipo de tarefa

CORREÇÕES EM RELAÇÃO À V1:
  - Regex de imports aceita aspas simples e duplas (fix do mapa incompleto)
  - Rastreabilidade Hive e Firestore com tipo de operação
  - Descrição inferida por heurística (offline, zero custo)
  - Alertas arquiteturais consolidados
  - Mapa de impacto por arquivo
  - Sumário executivo com saúde do projeto

Uso:
    python gerar_documentacao_V4.py
    python gerar_documentacao_V4.py --projeto "C:\\outro\\projeto"
    python gerar_documentacao_V4.py --saida "C:\\docs\\lego.md"
─────────────────────────────────────────────────────────────────────────────
"""

import os
import re
import sys
import argparse
from pathlib import Path
from datetime import datetime
from collections import defaultdict

# Força UTF-8 no terminal Windows (evita UnicodeEncodeError com emojis)
import sys
if sys.stdout.encoding != 'utf-8':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

# ─── Caminho padrão ───────────────────────────────────────────────────────────
PROJETO_DEFAULT = Path(r"C:\Users\djast\LEGO")

# ─── Configuração ─────────────────────────────────────────────────────────────
PASTAS_IGNORADAS = {
    '.dart_tool', '.idea', '.vscode', 'build', '.git',
    '.gradle', '.plugin_symlinks', 'ephemeral', 'node_modules',
    '__pycache__', '.flutter-plugins', '.flutter-plugins-dependencies',
    'windows', 'linux', 'macos', 'ios', 'android', 'web',
}

EXTENSOES_DART = {'.dart'}

ARQUIVOS_GERADOS = {
    'generated_plugin_registrant.dart',
    'app_localizations.dart',
}
SUFIXOS_GERADOS = {'.g.dart', '.freezed.dart', '.gr.dart', '.config.dart'}

LIMITE_GOD_FILE    = 800   # linhas
LIMITE_ACOPLAMENTO = 8     # importado por N+ arquivos


# ─── Regex ────────────────────────────────────────────────────────────────────
# FIX v4: aceita aspas simples E duplas
RE_IMPORT  = re.compile(r"""^import\s+['"]([^'"]+)['"]\s*;""", re.MULTILINE)
RE_EXPORT  = re.compile(r"""^export\s+['"]([^'"]+)['"]\s*;""", re.MULTILINE)

RE_CLASS   = re.compile(
    r'^\s*(?:abstract\s+|sealed\s+|base\s+|final\s+|interface\s+)*'
    r'(class|enum|mixin|extension)\s+(\w+)',
    re.MULTILINE
)

RE_METHOD_PUBLIC = re.compile(
    r'^\s{2,}(?:static\s+|async\s+)*'
    r'(?:Future|Stream|void|String|int|double|bool|List|Map|Set|Widget|'
    r'dynamic|Object|Iterable|BuildContext|Color|IconData|[\w<>?,\s]+?)\s+'
    r'([a-z][a-zA-Z0-9_]*)\s*\(',
    re.MULTILINE
)

RE_HIVE_TYPE  = re.compile(r'@HiveType\s*\(\s*typeId\s*:\s*(\d+)\s*\)', re.DOTALL)
RE_HIVE_FIELD = re.compile(
    r'@HiveField\s*\(\s*(\d+)\s*\)'
    r'\s*(?:\/\/[^\n]*)?\s*'
    r'(?:late\s+)?(?:final\s+)?(?:static\s+)?'
    r'([\w<>?,\s\[\]]+?)\s+'
    r'(\w+)\s*[;=]',
    re.DOTALL
)

RE_FIRESTORE_COL = re.compile(r"""\.collection\(\s*['"](\w+)['"]\s*\)""")

RE_PROVIDER   = re.compile(
    r'\b(Provider|ChangeNotifierProvider|StreamProvider|FutureProvider|'
    r'StateNotifierProvider|ConsumerWidget|ConsumerStatefulWidget|'
    r'ProviderScope|ref\.watch|ref\.read)\b'
)
RE_ROUTE      = re.compile(r"""['"](/[\w/\-_]+)['"]""")
RE_GETX_ROUTE = re.compile(r"""GetPage\s*\(\s*name\s*:\s*['"]([^'"]+)['"]""")
RE_COPY_WITH  = re.compile(r'\bcopyWith\s*\(')
RE_JSON       = re.compile(r'\b(toJson|fromJson|toMap|fromMap)\s*[({]')


# ─── Descrições heurísticas (offline, zero custo) ─────────────────────────────
DESCRICOES_CONHECIDAS = {
    'main.dart':                   'Entry point mobile — inicializa Firebase, Hive e roteamento.',
    'main_desktop.dart':           'Entry point desktop — inicializa Firebase, Hive e roteamento para a versão analista.',
    'firebase_options.dart':       'Configurações de conexão Firebase geradas pelo FlutterFire CLI (não editar manualmente).',
    'hive_boxes.dart':             'Centraliza a abertura e referência de todas as caixas Hive do projeto.',
    'offline_bootstrap.dart':      'Inicialização offline: carrega dados locais do Hive antes da autenticação.',
    'seed_bootstrap.dart':         'Verifica e dispara o seed inicial de dados mestres (produtos, barras).',
    'seed_importer.dart':          'Importa dados mestres do Firestore para o Hive local na primeira execução.',
    'fixed_collections_sync.dart': 'Sincroniza coleções fixas (produtos, barras) do Firestore para o Hive.',
    'sync_diagnostics.dart':       'Coleta e expõe métricas de diagnóstico do estado de sincronização.',
    'hive_diagnostics.dart':       'Diagnóstico do estado interno das caixas Hive (integridade, contagens).',
    'hive_probe_strict.dart':      'Sonda estrita de integridade Hive — usada em testes e depuração.',
    'admin_guard.dart':            'Guard de rota: bloqueia acesso a telas administrativas para não-admins.',
    'sidebar_navigation.dart':     'Componente de navegação lateral do layout desktop.',
    'sync_banner.dart':            'Banner de status de sincronização exibido no topo das telas.',
    'widget_test.dart':            'Teste de widget padrão gerado pelo Flutter (esqueleto inicial, sem valor real ainda).',
    'planta_diadema_config.dart':  'Configuração da planta de Diadema: áreas, localizações e layout do mapa SVG/JSON.',
    'home_page.hive.dart':         'Variante da home page com acesso direto ao Hive (diagnóstico/debug).',
}


def inferir_descricao(a) -> str:
    """Descrição legível sem API — heurística por nome, classes e conteúdo."""
    if a.nome in DESCRICOES_CONHECIDAS:
        return DESCRICOES_CONHECIDAS[a.nome]

    partes = []

    if a.eh_modelo_hive:
        campos = [f[2] for f in a.hive_fields[:5]]
        partes.append(
            f"Modelo Hive (typeId {a.hive_type}) com {len(a.hive_fields)} campos persistidos localmente"
            + (f": {', '.join(campos)}" if campos else "") + "."
        )
    elif a.eh_repositorio:
        cols = a.firestore[:3]
        partes.append(
            "Repositório Firestore"
            + (f" — coleções: {', '.join(cols)}" if cols else "") + "."
        )
        ops = []
        if any('escrita' in (a.fs_ops.get(c, set())) for c in a.firestore):  ops.append("escrita")
        if any('update'  in (a.fs_ops.get(c, set())) for c in a.firestore):  ops.append("update")
        if any('delete'  in (a.fs_ops.get(c, set())) for c in a.firestore):  ops.append("delete")
        if any(('leitura' in (a.fs_ops.get(c, set())) or
                'stream'  in (a.fs_ops.get(c, set()))) for c in a.firestore): ops.append("leitura/stream")
        if ops:
            partes.append(f"Operações: {', '.join(ops)}.")
    elif a.eh_servico:
        partes.append(
            "Serviço de negócio"
            + ("." if not a.metodos
               else f" — expõe: {', '.join(a.metodos[:4])}().")
        )
    elif a.eh_tela:
        cls = [c.split()[-1] for c in a.classes[:2]] if a.classes else []
        partes.append(
            "Tela da interface"
            + (f" — `{'`, `'.join(cls)}`." if cls else ".")
        )
    elif a.eh_widget:
        cls = a.classes[0].split()[-1] if a.classes else ''
        partes.append(
            "Widget reutilizável"
            + (f" — `{cls}`." if cls else ".")
        )
    elif a.eh_model:
        cls = [c.split()[-1] for c in a.classes[:3]] if a.classes else []
        partes.append(
            "Modelo de domínio"
            + (f" — `{'`, `'.join(cls)}`." if cls else ".")
        )

    if a.tem_copywith:  partes.append("Suporta `copyWith`.")
    if a.tem_json:      partes.append("Serialização JSON/Map.")
    if a.tem_provider:  partes.append("Usa Provider/Riverpod.")
    if a.firestore and not a.eh_repositorio:
        partes.append(
            f"⚠️ Acessa Firestore diretamente (coleções: {', '.join(a.firestore[:3])}) — "
            f"considere mover para um repositório."
        )

    return ' '.join(partes) if partes else "Arquivo de suporte/infraestrutura."


# ─── Modelo de dados ──────────────────────────────────────────────────────────
class ArquivoDart:
    def __init__(self, caminho: Path, raiz: Path):
        self.caminho      = caminho
        self.relativo     = caminho.relative_to(raiz)
        self.nome         = caminho.name
        self.conteudo     = ''
        self.imports      = []
        self.exports      = []
        self.classes      = []
        self.metodos      = []
        self.hive_type    = None
        self.hive_fields  = []
        self.firestore    = []
        self.fs_ops       = {}   # {colecao: set(ops)}
        self.tem_provider = False
        self.tem_copywith = False
        self.tem_json     = False
        self.rotas        = []
        self.linhas       = 0
        self.eh_gerado    = False
        self.erro         = None

    def analisar(self):
        if (self.nome in ARQUIVOS_GERADOS or
                any(self.nome.endswith(s) for s in SUFIXOS_GERADOS)):
            self.eh_gerado = True

        try:
            raw = self.caminho.read_bytes()
            try:
                self.conteudo = raw.decode('utf-8')
            except UnicodeDecodeError:
                self.conteudo = raw.decode('latin-1', errors='replace')

            self.linhas  = self.conteudo.count('\n') + 1
            self.imports = RE_IMPORT.findall(self.conteudo)
            self.exports = RE_EXPORT.findall(self.conteudo)

            self.classes = list(dict.fromkeys(
                f"{m.group(1)} {m.group(2)}"
                for m in RE_CLASS.finditer(self.conteudo)
            ))

            ignorar = {'build', 'initState', 'dispose', 'didChangeDependencies',
                       'didUpdateWidget', 'createState', 'debugFillProperties',
                       'if', 'for', 'return', 'switch', 'while', 'debugPrint', 'print'}
            self.metodos = list(dict.fromkeys(
                m for m in RE_METHOD_PUBLIC.findall(self.conteudo)
                if m not in ignorar
            ))[:25]

            ht = RE_HIVE_TYPE.search(self.conteudo)
            if ht:
                self.hive_type = int(ht.group(1))
                self._extrair_hive_fields()

            self.firestore = list(dict.fromkeys(RE_FIRESTORE_COL.findall(self.conteudo)))
            self._mapear_ops_firestore()
            self.tem_provider = bool(RE_PROVIDER.search(self.conteudo))
            self.tem_copywith = bool(RE_COPY_WITH.search(self.conteudo))
            self.tem_json     = bool(RE_JSON.search(self.conteudo))

            rotas_raw  = RE_ROUTE.findall(self.conteudo) + RE_GETX_ROUTE.findall(self.conteudo)
            self.rotas = list(dict.fromkeys(rotas_raw))[:10]

        except Exception as e:
            self.erro = str(e)

    def _mapear_ops_firestore(self):
        """Detecta tipo de operação Firestore por coleção."""
        for col in self.firestore:
            ops = set()
            padrao = re.compile(
                r'\.collection\(\s*[\'"]' + re.escape(col) + r'[\'"]'
                r'\s*\)((?:[^\n]|\n(?!\n)){0,300})',
                re.DOTALL
            )
            for m in padrao.finditer(self.conteudo):
                ctx = m.group(1).lower()
                if '.add('       in ctx or '.set('       in ctx: ops.add('escrita')
                if '.update('    in ctx:                          ops.add('update')
                if '.delete('    in ctx:                          ops.add('delete')
                if '.snapshots(' in ctx or '.stream'     in ctx:  ops.add('stream')
                if '.get('       in ctx or '.where('     in ctx:  ops.add('leitura')
            self.fs_ops[col] = ops

    def _extrair_hive_fields(self):
        campos = []

        for m in RE_HIVE_FIELD.finditer(self.conteudo):
            try:
                fid   = int(m.group(1))
                ftype = m.group(2).strip()
                fname = m.group(3).strip()
                if fname and len(fname) < 60 and ftype and len(ftype) < 80:
                    campos.append((fid, ftype, fname))
            except Exception:
                pass

        if not campos:
            linhas = self.conteudo.splitlines()
            for i, linha in enumerate(linhas):
                mf = re.search(r'@HiveField\s*\(\s*(\d+)\s*\)', linha)
                if mf:
                    fid = int(mf.group(1))
                    for j in range(i + 1, min(i + 5, len(linhas))):
                        prox = linhas[j].strip()
                        if not prox or prox.startswith('//') or prox.startswith('@'):
                            continue
                        prox = re.sub(r'^(late|final|static|const)\s+', '', prox)
                        prox = re.sub(r'^(late|final|static|const)\s+', '', prox)
                        md = re.match(r'^([\w<>?,\s\[\]]+?)\s+(\w+)\s*[;=]', prox)
                        if md:
                            ftype, fname = md.group(1).strip(), md.group(2).strip()
                            if fname and ftype:
                                campos.append((fid, ftype, fname))
                            break

        seen, result = set(), []
        for fid, ftype, fname in campos:
            if fid not in seen:
                seen.add(fid)
                result.append((fid, ftype, fname))
        self.hive_fields = sorted(result, key=lambda x: x[0])

    # ── Properties ────────────────────────────────────────────────────────────
    @property
    def pasta(self) -> str:
        return str(self.relativo.parent)

    @property
    def imports_locais(self) -> list:
        # Inclui imports relativos E imports package:lego/ (padrão do projeto)
        return [i for i in self.imports
                if not i.startswith('dart:') and
                (not i.startswith('package:') or i.startswith('package:lego/'))]

    @property
    def imports_pacotes(self) -> list:
        return [i for i in self.imports
                if i.startswith('package:')
                and not i.startswith('package:flutter/')
                and not i.startswith('package:lego/')]

    @property
    def eh_modelo_hive(self) -> bool:
        return self.hive_type is not None

    @property
    def proximo_hive_field_id(self) -> int:
        return (max(f[0] for f in self.hive_fields) + 1) if self.hive_fields else 0

    @property
    def eh_tela(self) -> bool:
        n = self.nome.lower()
        return any(x in n for x in ['screen', 'page', 'view', 'tela']) and not self.eh_widget

    @property
    def eh_repositorio(self) -> bool:
        return 'repository' in self.nome.lower() or 'repositorio' in self.nome.lower()

    @property
    def eh_servico(self) -> bool:
        return 'service' in self.nome.lower() or 'servico' in self.nome.lower()

    @property
    def eh_widget(self) -> bool:
        n = self.nome.lower()
        return (
            ('widget' in n or 'dialog' in n or 'card' in n or
             'banner' in n or 'badge' in n or 'sidebar' in n)
            and 'screen' not in n and 'page' not in n
        )

    @property
    def eh_model(self) -> bool:
        n = self.nome.lower()
        return 'model' in n or 'local' in n or n in {
            'inventario.dart', 'participante.dart', 'divergencia.dart',
            'balanco_financeiro.dart', 'produto_consolidado.dart', 'user_profile.dart',
        }

    @property
    def categoria(self) -> str:
        if self.eh_gerado:       return '⚙️  Gerado'
        if self.eh_modelo_hive:  return '🗃️  Modelo Hive'
        if self.eh_model:        return '📦  Modelo'
        if self.eh_repositorio:  return '🏛️  Repositório'
        if self.eh_servico:      return '⚙️  Serviço'
        if self.eh_tela:         return '🖥️  Tela'
        if self.eh_widget:       return '🧩  Widget'
        if 'provider'  in self.nome.lower() or 'notifier' in self.nome.lower():
            return '🔄  Provider/State'
        if 'router'    in self.nome.lower() or 'route'    in self.nome.lower():
            return '🗺️  Rotas'
        if 'theme'     in self.nome.lower() or 'style'    in self.nome.lower():
            return '🎨  Tema/Estilo'
        if 'util'      in self.nome.lower() or 'helper'   in self.nome.lower():
            return '🔧  Utilitário'
        if 'constant'  in self.nome.lower() or 'config'   in self.nome.lower():
            return '⚙️  Config'
        if 'main'      in self.nome.lower():
            return '🚀  Entry Point'
        return '📄  Dart'


# ─── Varredura ────────────────────────────────────────────────────────────────
def varrer_projeto(raiz: Path):
    principais, gerados = [], []
    for dirpath, dirs, files in os.walk(raiz):
        dirs[:] = sorted([
            d for d in dirs
            if d not in PASTAS_IGNORADAS and not d.startswith('.')
        ])
        for arquivo in sorted(files):
            caminho = Path(dirpath) / arquivo
            if caminho.suffix not in EXTENSOES_DART:
                continue
            if caminho.name in ARQUIVOS_GERADOS:
                continue
            a = ArquivoDart(caminho, raiz)
            a.analisar()
            (gerados if a.eh_gerado else principais).append(a)
    principais.sort(key=lambda a: str(a.relativo).lower())
    gerados.sort(   key=lambda a: str(a.relativo).lower())
    return principais, gerados


def ler_pubspec(raiz: Path) -> str:
    p = raiz / 'pubspec.yaml'
    return p.read_text(encoding='utf-8', errors='replace') if p.exists() else ''


# ─── Análises ─────────────────────────────────────────────────────────────────
def mapear_dependencias(arquivos: list) -> dict:
    """Retorna {nome_arquivo: [quem_importa_ele]}."""
    nomes       = {a.nome: a for a in arquivos}
    dependentes = defaultdict(list)
    for a in arquivos:
        for imp in a.imports_locais:
            nome_imp = Path(imp).name
            if nome_imp in nomes and nome_imp != a.nome:
                dependentes[nome_imp].append(a.nome)
    return dependentes


def coletar_firestore(arquivos: list) -> dict:
    """Retorna {colecao: {arquivo: set(ops)}}."""
    col_map = defaultdict(dict)
    for a in arquivos:
        for col in a.firestore:
            col_map[col][a.nome] = a.fs_ops.get(col, set())
    return col_map


def detectar_alertas(arquivos: list, dep_map: dict) -> list:
    alertas = []
    for a in arquivos:
        if a.linhas >= LIMITE_GOD_FILE:
            alertas.append(('🔴', f"**God File**: `{a.nome}` tem **{a.linhas} linhas**. "
                            "Considere dividir em partes menores."))
        if a.eh_tela and a.firestore:
            alertas.append(('🟠', f"**Violação de camada**: `{a.nome}` (Tela) acessa Firestore "
                            f"diretamente — coleções: {', '.join(f'`{c}`' for c in a.firestore)}. "
                            "Mova para um Repositório."))
        qtd = len(dep_map.get(a.nome, []))
        if qtd >= LIMITE_ACOPLAMENTO:
            alertas.append(('🟡', f"**Alto acoplamento**: `{a.nome}` é importado por "
                            f"**{qtd} arquivos**. Mudanças aqui têm alto impacto."))
    return sorted(alertas, key=lambda x: ('🔴', '🟠', '🟡').index(x[0]))


def gerar_arvore(arquivos: list) -> list:
    por_pasta = defaultdict(list)
    for a in arquivos:
        por_pasta[str(a.relativo.parent).replace('\\', '/')].append(a)

    todas_pastas        = sorted(por_pasta.keys())
    linhas, exibidas    = [], set()

    for pasta in todas_pastas:
        partes = [] if pasta == '.' else pasta.split('/')
        for i in range(len(partes)):
            sub = '/'.join(partes[:i+1])
            if sub not in exibidas:
                exibidas.add(sub)
                linhas.append(f"{'  ' * i}📁 {partes[i]}/")

        if pasta == '.' and '.' not in exibidas:
            exibidas.add('.')
            linhas.append('📁 lib/')

        prof_arq   = len(partes)
        indent_arq = '  ' * prof_arq
        for a in sorted(por_pasta[pasta], key=lambda x: x.nome):
            icon    = a.categoria.split()[0]
            alerta  = '  ⚠️' if a.linhas >= LIMITE_GOD_FILE else ''
            linhas.append(f"{indent_arq}{icon} {a.nome}  ({a.linhas} linhas){alerta}")

    return linhas


# ─── Markdown ─────────────────────────────────────────────────────────────────
def gerar_markdown(raiz: Path, arquivos: list, gerados: list, pubspec: str) -> str:
    dep_map   = mapear_dependencias(arquivos)
    fire_map  = coletar_firestore(arquivos)
    hive_mods = sorted([a for a in arquivos if a.eh_modelo_hive], key=lambda a: a.hive_type or 0)
    alertas   = detectar_alertas(arquivos, dep_map)

    telas    = [a for a in arquivos if a.eh_tela]
    servicos = [a for a in arquivos if a.eh_servico]
    repos    = [a for a in arquivos if a.eh_repositorio]
    modelos  = [a for a in arquivos if a.eh_modelo_hive]
    models   = [a for a in arquivos if a.eh_model and not a.eh_modelo_hive]
    widgets  = [a for a in arquivos if a.eh_widget]
    sync_f   = [a for a in arquivos if 'sync' in a.nome.lower() or 'offline' in a.nome.lower()]
    entries  = [a for a in arquivos if 'main' in a.nome.lower() and not a.eh_gerado]

    out = []
    w   = out.append

    # ── Cabeçalho ──────────────────────────────────────────────────────────────
    w(f"# 📚 Documentação Técnica — {raiz.name}\n")
    w(f"> **Gerado em:** {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}  ")
    w(f"> **Projeto:** `{raiz}`  ")
    w(f"> **Arquivos analisados:** {len(arquivos)} principais + {len(gerados)} gerados automaticamente\n")
    w("---\n")

    # ── Diretriz de integridade ───────────────────────────────────────────────
    w("> ⚠️ **DIRETRIZ DE INTEGRIDADE DO PROJETO**  ")
    w("> Nada deve ser removido, acrescido, reescrito ou reordenado sem a completa autorização do autor do projeto.  ")
    w("> A integridade do que funciona deve ser preservada sempre, a qualquer custo,  ")
    w("> salvo se existir autorização direta do mesmo.\n")
    w("---\n")

    # ── Índice ─────────────────────────────────────────────────────────────────
    w("## Índice\n")
    w("0. [Sumário Executivo](#sumário-executivo)")
    w("1. [Estrutura de Pastas](#estrutura-de-pastas)")
    w("2. [Alertas Arquiteturais](#alertas-arquiteturais)")
    w("3. [Modelos Hive](#modelos-hive)")
    w("4. [Coleções Firestore](#coleções-firestore)")
    w("5. [Catálogo de Arquivos](#catálogo-de-arquivos)")
    w("6. [Mapa de Dependências](#mapa-de-dependências)")
    w("7. [Mapa de Impacto](#mapa-de-impacto)")
    w("8. [Dependências pubspec.yaml](#dependências)")
    w("9. [Guia — Onde Mexer](#guia--onde-mexer)\n")
    w("---\n")

    # ── 0. Sumário Executivo ───────────────────────────────────────────────────
    w("## Sumário Executivo\n")
    w("### Estatísticas por camada\n")
    total_linhas = sum(a.linhas for a in arquivos)

    def _fmt_lista(lista, limite=5):
        nomes = ', '.join(f'`{a.nome}`' for a in lista[:limite])
        return nomes + (f' _+{len(lista)-limite} mais_' if len(lista) > limite else '')

    w("| Camada | Qtd | Arquivos |")
    w("|--------|:---:|---------|")
    w(f"| 🚀 Entry Points       | {len(entries)}  | {_fmt_lista(entries)} |")
    w(f"| 🖥️ Telas              | {len(telas)}   | {_fmt_lista(telas)} |")
    w(f"| ⚙️ Serviços           | {len(servicos)}| {_fmt_lista(servicos)} |")
    w(f"| 🏛️ Repositórios       | {len(repos)}   | {_fmt_lista(repos)} |")
    w(f"| 🗃️ Modelos Hive       | {len(modelos)} | {_fmt_lista(modelos)} |")
    w(f"| 📦 Modelos de domínio | {len(models)}  | {_fmt_lista(models)} |")
    w(f"| 🧩 Widgets            | {len(widgets)} | {_fmt_lista(widgets)} |")
    w(f"| **Total**             | **{len(arquivos)}** | **{total_linhas:,} linhas** |")
    w("")

    w("### Saúde do projeto\n")
    n_crit  = sum(1 for s, _ in alertas if s == '🔴')
    n_medio = sum(1 for s, _ in alertas if s == '🟠')
    n_info  = sum(1 for s, _ in alertas if s == '🟡')

    if n_crit == 0 and n_medio == 0:
        w("✅ **Sem problemas críticos ou violações de camada detectados.**\n")
    else:
        if n_crit:
            w(f"🔴 **{n_crit} God File(s)** detectado(s) — ver [Alertas Arquiteturais](#alertas-arquiteturais)")
        if n_medio:
            w(f"🟠 **{n_medio} violação(ões) de camada** — ver [Alertas Arquiteturais](#alertas-arquiteturais)")
        w("")
    if n_info:
        w(f"🟡 {n_info} arquivo(s) com alto acoplamento — atenção ao modificar.\n")

    w("### Núcleo do projeto\n")
    w("> Arquivos mais importados. Qualquer mudança aqui tem alto potencial de impacto.\n")
    for nome, importadores in sorted(dep_map.items(), key=lambda x: len(x[1]), reverse=True)[:8]:
        w(f"- `{nome}` — importado por **{len(importadores)}** arquivo(s)")
    w("")
    w("---\n")

    # ── 1. Estrutura de Pastas ─────────────────────────────────────────────────
    w("## Estrutura de Pastas\n")
    w("> ⚠️ = arquivo com mais de 800 linhas\n")
    w("```")
    for linha in gerar_arvore(arquivos):
        w(linha)
    w("```\n")
    w("---\n")

    # ── 2. Alertas Arquiteturais ───────────────────────────────────────────────
    w("## Alertas Arquiteturais\n")
    if alertas:
        for sev, msg in alertas:
            w(f"- {sev} {msg}")
        w("")
    else:
        w("✅ Nenhum problema arquitetural detectado.\n")
    w("---\n")

    # ── 3. Modelos Hive ────────────────────────────────────────────────────────
    w("## Modelos Hive\n")
    if hive_mods:
        w("| typeId | Classe | Arquivo | Campos | Próximo fieldId |")
        w("|:------:|--------|---------|:------:|:---------------:|")
        for a in hive_mods:
            classe = next((c for c in a.classes if c.startswith('class')),
                          a.classes[0] if a.classes else '—')
            w(f"| {a.hive_type} | `{classe}` | `{a.nome}` | {len(a.hive_fields)} | **{a.proximo_hive_field_id}** |")
        w("")

        w("### Campos por modelo\n")
        for a in hive_mods:
            w(f"#### `{a.nome}` — typeId `{a.hive_type}` — próximo fieldId: `{a.proximo_hive_field_id}`\n")
            if a.hive_fields:
                w("| fieldId | Tipo | Nome |")
                w("|:-------:|------|------|")
                for fid, ftype, fname in a.hive_fields:
                    w(f"| {fid} | `{ftype}` | `{fname}` |")
            else:
                w("_⚠️ Campos não detectados — verifique o arquivo._")
            extras = []
            if a.tem_copywith: extras.append("`copyWith`")
            if a.tem_json:     extras.append("`toJson`/`fromJson`")
            if extras:
                w(f"\n_Possui: {', '.join(extras)}_")
            w("")

        w("### Rastreabilidade — Quem usa cada modelo Hive\n")
        w("> Para cada modelo: quais arquivos o importam (acesso potencial aos dados locais).\n")
        for a in hive_mods:
            importadores = sorted(dep_map.get(a.nome, []))
            if importadores:
                w(f"- **`{a.nome}`** → {', '.join(f'`{i}`' for i in importadores)}")
            else:
                w(f"- **`{a.nome}`** → _não importado diretamente por outros arquivos_")
        w("")
    else:
        w("_Nenhum modelo Hive encontrado._\n")
    w("---\n")

    # ── 4. Coleções Firestore ──────────────────────────────────────────────────
    w("## Coleções Firestore\n")
    if fire_map:
        w("| Coleção | Operações detectadas | Arquivos que acessam |")
        w("|---------|---------------------|---------------------|")
        for col in sorted(fire_map.keys()):
            usos      = fire_map[col]
            todas_ops = set()
            for ops in usos.values():
                todas_ops |= ops
            ops_str  = ', '.join(sorted(todas_ops)) if todas_ops else '—'
            arqs_str = ', '.join(f"`{u}`" for u in sorted(usos.keys())[:5])
            if len(usos) > 5:
                arqs_str += f" _(+{len(usos)-5})_"
            w(f"| `{col}` | {ops_str} | {arqs_str} |")
        w("")

        w("### Detalhes por coleção\n")
        for col in sorted(fire_map.keys()):
            usos = fire_map[col]
            w(f"#### `{col}`\n")
            w("| Arquivo | Operações |")
            w("|---------|-----------|")
            for arq, ops in sorted(usos.items()):
                ops_str = ', '.join(sorted(ops)) if ops else '—'
                w(f"| `{arq}` | {ops_str} |")
            w("")
    else:
        w("_Nenhuma coleção Firestore detectada._\n")
    w("---\n")

    # ── 5. Catálogo de Arquivos ────────────────────────────────────────────────
    w("## Catálogo de Arquivos\n")
    w("> Responsabilidade inferida, declarações, métodos e relações de cada arquivo.\n")

    por_pasta = defaultdict(list)
    for a in arquivos:
        por_pasta[a.pasta].append(a)

    for pasta in sorted(por_pasta.keys(), key=str.lower):
        pasta_d = str(pasta).replace('\\', '/')
        w(f"### 📁 `{pasta_d}`\n")
        for a in sorted(por_pasta[pasta], key=lambda x: x.nome):
            alerta_god = " ⚠️ God File" if a.linhas >= LIMITE_GOD_FILE else ""
            w(f"#### `{a.nome}` — {a.categoria}{alerta_god}\n")

            w(f"> {inferir_descricao(a)}\n")

            w(f"- **Linhas:** {a.linhas}")
            if a.classes:
                w(f"- **Declarações:** {', '.join(f'`{c}`' for c in a.classes[:10])}")
            if a.metodos:
                w(f"- **Métodos públicos:** {', '.join(f'`{m}()`' for m in a.metodos[:12])}")

            if a.firestore:
                ops_resumo = []
                for col in a.firestore:
                    ops = a.fs_ops.get(col, set())
                    s   = f"`{col}`" + (f" ({', '.join(sorted(ops))})" if ops else "")
                    ops_resumo.append(s)
                w(f"- **Firestore:** {', '.join(ops_resumo)}")

            if a.eh_modelo_hive:
                w(f"- **Hive:** typeId `{a.hive_type}` | {len(a.hive_fields)} campos | "
                  f"próximo fieldId: `{a.proximo_hive_field_id}`")
                if a.hive_fields:
                    campos_inline = ', '.join(f"`{f[2]}`:`{f[1]}`" for f in a.hive_fields)
                    w(f"- **Campos Hive:** {campos_inline}")

            features = []
            if a.tem_copywith: features.append("`copyWith`")
            if a.tem_json:     features.append("`toJson/fromJson`")
            if a.tem_provider: features.append("Provider/Riverpod")
            if features:
                w(f"- **Recursos:** {', '.join(features)}")

            if a.imports_locais:
                nomes_imp = [Path(i).name for i in a.imports_locais[:10]]
                w(f"- **Importa (locais):** {', '.join(f'`{n}`' for n in nomes_imp)}")
            if a.imports_pacotes:
                pkgs = list(dict.fromkeys(
                    i.split('/')[0].replace('package:', '') for i in a.imports_pacotes
                ))[:8]
                w(f"- **Pacotes:** {', '.join(pkgs)}")

            usados_por = dep_map.get(a.nome, [])
            if usados_por:
                quem = ', '.join(f"`{u}`" for u in usados_por[:8])
                if len(usados_por) > 8:
                    quem += f" _(+{len(usados_por)-8})_"
                w(f"- **Importado por:** {quem}")

            if a.rotas:
                w(f"- **Rotas:** {', '.join(f'`{r}`' for r in a.rotas[:6])}")
            if a.erro:
                w(f"- ⚠️ **Erro na análise:** `{a.erro}`")
            w("")

    if gerados:
        w("### ⚙️ Arquivos gerados automaticamente\n")
        w("| Arquivo | Linhas | Pasta |")
        w("|---------|:------:|-------|")
        for a in gerados:
            pasta_d = str(a.relativo.parent).replace('\\', '/')
            w(f"| `{a.nome}` | {a.linhas} | `{pasta_d}` |")
        w("\n> Não edite manualmente. Regenere com: "
          "`flutter pub run build_runner build --delete-conflicting-outputs`\n")
    w("---\n")

    # ── 6. Mapa de Dependências ────────────────────────────────────────────────
    w("## Mapa de Dependências\n")
    w("> Quanto mais importado, mais central — e mais arriscado de modificar sem testes.\n")
    dep_contagem = sorted(dep_map.items(), key=lambda x: len(x[1]), reverse=True)
    if dep_contagem:
        w("| # | Arquivo | Importado por | Quem importa |")
        w("|:-:|---------|:-------------:|--------------|")
        for i, (nome, importadores) in enumerate(dep_contagem[:40], 1):
            quem = ', '.join(f"`{u}`" for u in importadores[:5])
            if len(importadores) > 5:
                quem += f" _(+{len(importadores)-5})_"
            alerta = " 🔴" if len(importadores) >= LIMITE_ACOPLAMENTO else ""
            w(f"| {i} | `{nome}`{alerta} | {len(importadores)} | {quem} |")
        w("")
    else:
        w("_Nenhuma dependência local mapeada._\n")
    w("---\n")

    # ── 7. Mapa de Impacto ─────────────────────────────────────────────────────
    w("## Mapa de Impacto\n")
    w('> **"Se eu modificar X, o que pode ser afetado?"**\n')
    w('> Lista os arquivos que importam diretamente cada arquivo do projeto.\n')
    w('> Arquivos sem dependentes não constam — mudanças neles são isoladas.\n')

    com_impacto = [(n, i) for n, i in dep_contagem if i]
    if com_impacto:
        for nome, importadores in com_impacto:
            nivel = ("🔴 CRÍTICO" if len(importadores) >= LIMITE_ACOPLAMENTO
                     else "🟠 ALTO"  if len(importadores) >= 4
                     else "🟡 MÉDIO")
            w(f"### `{nome}` — {nivel} ({len(importadores)} dependente(s))\n")
            for imp in sorted(importadores):
                w(f"- `{imp}`")
            w("")
    else:
        w("_Nenhuma relação de impacto detectada._\n")
    w("---\n")

    # ── 8. Dependências pubspec.yaml ───────────────────────────────────────────
    w("## Dependências\n")
    if pubspec:
        linhas_pub  = pubspec.splitlines()
        secoes_alvo = {'dependencies:', 'dev_dependencies:'}
        em_secao, col = False, []
        for linha in linhas_pub:
            stripped = linha.strip()
            if stripped in secoes_alvo:
                em_secao = True
                col.append(linha)
                continue
            if em_secao:
                if (stripped and not linha[0].isspace()
                        and stripped not in secoes_alvo
                        and not stripped.startswith('#')):
                    em_secao = False
                    continue
                col.append(linha)
        w("```yaml")
        for l in col:
            w(l)
        w("```\n")
    else:
        w("_pubspec.yaml não encontrado._\n")
    w("---\n")

    # ── 9. Guia — Onde Mexer ──────────────────────────────────────────────────
    w("## Guia — Onde Mexer\n")
    w("Referência rápida para qualquer tipo de modificação no projeto.\n")

    def lista_arqs_guia(lista):
        for a in sorted(lista, key=lambda x: x.nome):
            caminho_d = str(a.relativo).replace('\\', '/')
            classes_s = ', '.join(f"`{c}`" for c in a.classes[:3]) if a.classes else ''
            w(f"- `{caminho_d}`{(' — ' + classes_s) if classes_s else ''}")
            w(f"  > {inferir_descricao(a)}")

    secoes = [
        ("🖥️ Adicionar ou modificar tela/página", telas,
         "Telas ficam em `lib/ui/`. Para nova tela: crie o arquivo na pasta adequada "
         "(desktop ou mobile) e registre a navegação em `home_page.dart` ou no roteador."),

        ("🗃️ Adicionar ou modificar campo Hive (dado local)", modelos,
         "Para adicionar um campo:\n"
         "1. Adicione `@HiveField(PROXIMO_ID)` + declaração no modelo\n"
         "2. Atualize o construtor e o `copyWith`\n"
         "3. Rode: `flutter pub run build_runner build --delete-conflicting-outputs`\n"
         "4. Atualize `toJson`/`fromJson` se existirem\n"
         "5. Se já houver dados gravados no dispositivo, considere migração de schema"),

        ("☁️ Adicionar ou modificar dados no Firestore", repos,
         "Operações Firestore estão nos repositórios. "
         "**Nunca** chame `.collection()` diretamente nas telas — use o repositório correspondente."),

        ("⚙️ Modificar lógica de negócio", servicos,
         "Serviços encapsulam regras independentes de UI. "
         "Lógica que envolve múltiplos repositórios ou cálculos complexos fica aqui."),

        ("📦 Modificar modelo de dados (sem Hive)", models,
         "Modelos de domínio usados para trafegar dados entre camadas. "
         "Alterações aqui podem exigir atualização de serialização e telas que exibem esses dados."),

        ("🧩 Criar ou modificar componente visual reutilizável", widgets,
         "Widgets reutilizáveis ficam em `lib/ui/widgets/` (globais) ou "
         "`lib/ui/desktop/widgets/` / `lib/ui/mobile/widgets/` (específicos de plataforma)."),

        ("🔄 Modificar sincronização / comportamento offline", sync_f,
         "Lógica de sync entre Hive (local) e Firestore (nuvem). "
         "Alterações aqui afetam a confiabilidade offline — teste bem antes de subir."),
    ]

    for titulo, lista, dica in secoes:
        w(f"### {titulo}\n")
        for linha_dica in dica.split('\n'):
            if linha_dica.strip():
                prefixo = '_' if not linha_dica[0].isdigit() else ''
                sufixo  = '_' if prefixo else ''
                w(f"{prefixo}{linha_dica}{sufixo}")
        w("")
        if lista:
            w("**Arquivos relevantes:**\n")
            lista_arqs_guia(lista)
        else:
            w("_Nenhum arquivo identificado automaticamente para esta categoria._")
        w("")

    w("---\n")
    w(f"_Documentação gerada por `gerar_documentacao.py` v4.0 — "
      f"{datetime.now().strftime('%d/%m/%Y %H:%M:%S')}_")

    return '\n'.join(out)


# ─── Main ─────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description='Gera documentação técnica de excelência para projetos Flutter (v4.0).'
    )
    parser.add_argument('--projeto', '-p', default=str(PROJETO_DEFAULT),
                        help=f'Caminho raiz do projeto Flutter (padrão: {PROJETO_DEFAULT})')
    parser.add_argument('--saida', '-o', default=None,
                        help='Arquivo de saída (padrão: DOCUMENTACAO_TECNICA.md na raiz do projeto)')
    args = parser.parse_args()

    raiz = Path(args.projeto).resolve()
    if not raiz.exists():
        print(f"❌ Projeto não encontrado: {raiz}")
        sys.exit(1)

    saida = Path(args.saida) if args.saida else raiz / 'DOCUMENTACAO_TECNICA.md'

    print(f"🔍 Varrendo: {raiz}")
    arquivos, gerados = varrer_projeto(raiz)
    print(f"✅ {len(arquivos)} arquivos principais + {len(gerados)} gerados")

    pubspec  = ler_pubspec(raiz)
    print("📝 Gerando documentação v4.0...")
    markdown = gerar_markdown(raiz, arquivos, gerados, pubspec)

    saida.write_text(markdown, encoding='utf-8')
    kb = len(markdown.encode('utf-8')) / 1024
    print(f"✅ Salvo em: {saida}")
    print(f"   Tamanho: {kb:.1f} KB | {markdown.count(chr(10))+1:,} linhas")

    hive = [a for a in arquivos if a.eh_modelo_hive]
    if hive:
        print("\n📦 Modelos Hive detectados:")
        for a in sorted(hive, key=lambda x: x.hive_type or 0):
            print(f"   typeId {a.hive_type:>3} | {a.nome:<40} | "
                  f"{len(a.hive_fields)} campos | próximo fieldId: {a.proximo_hive_field_id}")

    god       = [a for a in arquivos if a.linhas >= LIMITE_GOD_FILE]
    violacoes = [a for a in arquivos if a.eh_tela and a.firestore]
    if god or violacoes:
        print("\n⚠️  Alertas arquiteturais:")
        for a in god:
            print(f"   🔴 God File: {a.nome} ({a.linhas} linhas)")
        for a in violacoes:
            print(f"   🟠 Violação de camada: {a.nome} acessa Firestore diretamente")


if __name__ == '__main__':
    main()
