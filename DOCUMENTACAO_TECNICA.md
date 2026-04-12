# 📚 Documentação Técnica — LEGO

> **Gerado em:** 11/04/2026 10:57:44  
> **Projeto:** `C:\Users\djast\LEGO`  
> **Arquivos analisados:** 72 principais + 4 gerados automaticamente

---

> ⚠️ **DIRETRIZ DE INTEGRIDADE DO PROJETO**  
> Nada deve ser removido, acrescido, reescrito ou reordenado sem a completa autorização do autor do projeto.  
> A integridade do que funciona deve ser preservada sempre, a qualquer custo,  
> salvo se existir autorização direta do mesmo.

---

## Índice

0. [Sumário Executivo](#sumário-executivo)
1. [Estrutura de Pastas](#estrutura-de-pastas)
2. [Alertas Arquiteturais](#alertas-arquiteturais)
3. [Modelos Hive](#modelos-hive)
4. [Coleções Firestore](#coleções-firestore)
5. [Catálogo de Arquivos](#catálogo-de-arquivos)
6. [Mapa de Dependências](#mapa-de-dependências)
7. [Mapa de Impacto](#mapa-de-impacto)
8. [Dependências pubspec.yaml](#dependências)
9. [Guia — Onde Mexer](#guia--onde-mexer)

---

## Sumário Executivo

### Estatísticas por camada

| Camada | Qtd | Arquivos |
|--------|:---:|---------|
| 🚀 Entry Points       | 2  | `main.dart`, `main_desktop.dart` |
| 🖥️ Telas              | 21   | `contagem_choice_page.dart`, `analise_patrimonial_screen.dart`, `comparativo_contagens_screen.dart`, `comparativo_inventarios_screen.dart`, `controle_contagem_screen.dart` _+16 mais_ |
| ⚙️ Serviços           | 12| `auth_service.dart`, `comparativo_service.dart`, `connectivity_service.dart`, `consolidation_service.dart`, `estoque_service.dart` _+7 mais_ |
| 🏛️ Repositórios       | 3   | `barras_repository.dart`, `lancamentos_repository.dart`, `produtos_repository.dart` |
| 🗃️ Modelos Hive       | 4 | `app_state.dart`, `barra_local.dart`, `lanc_local.dart`, `produto_local.dart` |
| 📦 Modelos de domínio | 6  | `balanco_financeiro.dart`, `divergencia.dart`, `inventario.dart`, `participante.dart`, `produto_consolidado.dart` _+1 mais_ |
| 🧩 Widgets            | 11 | `alerta_badge_widget.dart`, `balanco_summary_widget.dart`, `divergencia_card_widget.dart`, `filtros_bar_widget.dart`, `produto_detail_dialog.dart` _+6 mais_ |
| **Total**             | **72** | **26,006 linhas** |

### Saúde do projeto

🔴 **6 God File(s)** detectado(s) — ver [Alertas Arquiteturais](#alertas-arquiteturais)
🟠 **5 violação(ões) de camada** — ver [Alertas Arquiteturais](#alertas-arquiteturais)

🟡 5 arquivo(s) com alto acoplamento — atenção ao modificar.

### Núcleo do projeto

> Arquivos mais importados. Qualquer mudança aqui tem alto potencial de impacto.

- `inventario.dart` — importado por **14** arquivo(s)
- `hive_boxes.dart` — importado por **13** arquivo(s)
- `produto_local.dart` — importado por **9** arquivo(s)
- `barra_local.dart` — importado por **9** arquivo(s)
- `inventario_service.dart` — importado por **8** arquivo(s)
- `lanc_local.dart` — importado por **7** arquivo(s)
- `balanco_financeiro.dart` — importado por **7** arquivo(s)
- `produto_consolidado.dart` — importado por **6** arquivo(s)

---

## Estrutura de Pastas

> ⚠️ = arquivo com mais de 800 linhas

```
📁 lib/
  📄 firebase_options.dart  (84 linhas)
  📄 hive_probe_strict.dart  (145 linhas)
  🚀 main.dart  (111 linhas)
  🚀 main_desktop.dart  (260 linhas)
  📄 test_hive.dart  (78 linhas)
  📄 test_hive_seed.dart  (218 linhas)
  📁 config/
    ⚙️ planta_diadema_config.dart  (192 linhas)
  📁 data/
    📁 local/
      🗃️ app_state.dart  (54 linhas)
      🗃️ barra_local.dart  (19 linhas)
      📄 hive_boxes.dart  (48 linhas)
      🗃️ lanc_local.dart  (162 linhas)
      🗃️ produto_local.dart  (22 linhas)
    📁 repositories/
      🏛️ barras_repository.dart  (22 linhas)
      🏛️ lancamentos_repository.dart  (658 linhas)
      🏛️ produtos_repository.dart  (161 linhas)
  📁 models/
    📦 balanco_financeiro.dart  (256 linhas)
    📦 divergencia.dart  (214 linhas)
    📦 inventario.dart  (382 linhas)
    📦 participante.dart  (186 linhas)
    📦 produto_consolidado.dart  (243 linhas)
    📦 user_profile.dart  (51 linhas)
  📁 services/
    📄 admin_guard.dart  (12 linhas)
    ⚙️ auth_service.dart  (175 linhas)
    ⚙️ comparativo_service.dart  (322 linhas)
    ⚙️ connectivity_service.dart  (37 linhas)
    ⚙️ consolidation_service.dart  (519 linhas)
    ⚙️ estoque_service.dart  (466 linhas)
    ⚙️ excel_parser_service.dart  (397 linhas)
    ⚙️ exportar_excel_service.dart  (472 linhas)
    📄 fixed_collections_sync.dart  (141 linhas)
    📄 hive_diagnostics.dart  (129 linhas)
    ⚙️ inventario_service.dart  (704 linhas)
    ⚙️ mobile_sync_service.dart  (494 linhas)
    📄 offline_bootstrap.dart  (44 linhas)
    ⚙️ relatorio_service.dart  (582 linhas)
    📄 seed_bootstrap.dart  (70 linhas)
    📄 seed_importer.dart  (236 linhas)
    📄 sync_diagnostics.dart  (38 linhas)
    ⚙️ sync_service.dart  (92 linhas)
    ⚙️ user_service.dart  (219 linhas)
  📁 ui/
    🖥️ contagem_choice_page.dart  (63 linhas)
    🖥️ diagnostics_page.dart  (107 linhas)
    🖥️ first_sync_screen.dart  (294 linhas)
    🖥️ handover_page.dart  (28 linhas)
    🖥️ home_page.dart  (3585 linhas)  ⚠️
    🖥️ home_page.hive.dart  (99 linhas)
    🖥️ login_page.dart  (518 linhas)
    📁 desktop/
      📁 screens/
        🖥️ analise_patrimonial_screen.dart  (275 linhas)
        🖥️ comparativo_contagens_screen.dart  (385 linhas)
        🖥️ comparativo_inventarios_screen.dart  (764 linhas)
        🖥️ controle_contagem_screen.dart  (989 linhas)  ⚠️
        🖥️ criar_inventario_screen.dart  (987 linhas)  ⚠️
        🖥️ dashboard_desktop_screen.dart  (659 linhas)
        🖥️ dashboard_screen.dart  (407 linhas)
        🖥️ detalhe_inventario_screen.dart  (985 linhas)  ⚠️
        🖥️ historico_screen.dart  (651 linhas)
        🖥️ importar_estoque_screen.dart  (496 linhas)
        🖥️ participantes_screen.dart  (1058 linhas)  ⚠️
        🖥️ relatorio_screen.dart  (1108 linhas)  ⚠️
      📁 widgets/
        🧩 alerta_badge_widget.dart  (160 linhas)
        🧩 balanco_summary_widget.dart  (346 linhas)
        🧩 divergencia_card_widget.dart  (261 linhas)
        🧩 filtros_bar_widget.dart  (200 linhas)
        🧩 produto_detail_dialog.dart  (452 linhas)
        🧩 sidebar_navigation.dart  (259 linhas)
        🧩 tabela_produtos_widget.dart  (269 linhas)
    📁 mobile/
      📁 screens/
        🖥️ modo_operacao_screen.dart  (531 linhas)
        🖥️ plant_map_page.dart  (513 linhas)
      📁 widgets/
        🧩 inventario_ativo_widget.dart  (395 linhas)
    📁 widgets/
      🧩 sync_banner.dart  (20 linhas)
  📁 widgets/
    🧩 planta_navegador_widget.dart  (418 linhas)
📁 test/
  🧩 widget_test.dart  (9 linhas)
```

---

## Alertas Arquiteturais

- 🔴 **God File**: `controle_contagem_screen.dart` tem **989 linhas**. Considere dividir em partes menores.
- 🔴 **God File**: `criar_inventario_screen.dart` tem **987 linhas**. Considere dividir em partes menores.
- 🔴 **God File**: `detalhe_inventario_screen.dart` tem **985 linhas**. Considere dividir em partes menores.
- 🔴 **God File**: `participantes_screen.dart` tem **1058 linhas**. Considere dividir em partes menores.
- 🔴 **God File**: `relatorio_screen.dart` tem **1108 linhas**. Considere dividir em partes menores.
- 🔴 **God File**: `home_page.dart` tem **3585 linhas**. Considere dividir em partes menores.
- 🟠 **Violação de camada**: `controle_contagem_screen.dart` (Tela) acessa Firestore diretamente — coleções: `inventarios`, `participantes`. Mova para um Repositório.
- 🟠 **Violação de camada**: `detalhe_inventario_screen.dart` (Tela) acessa Firestore diretamente — coleções: `inventarios`, `participantes`, `estoque`. Mova para um Repositório.
- 🟠 **Violação de camada**: `historico_screen.dart` (Tela) acessa Firestore diretamente — coleções: `inventarios`. Mova para um Repositório.
- 🟠 **Violação de camada**: `participantes_screen.dart` (Tela) acessa Firestore diretamente — coleções: `inventarios`, `participantes`. Mova para um Repositório.
- 🟠 **Violação de camada**: `home_page.dart` (Tela) acessa Firestore diretamente — coleções: `inventarios`, `participantes`, `lancamentos`. Mova para um Repositório.
- 🟡 **Alto acoplamento**: `barra_local.dart` é importado por **9 arquivos**. Mudanças aqui têm alto impacto.
- 🟡 **Alto acoplamento**: `hive_boxes.dart` é importado por **13 arquivos**. Mudanças aqui têm alto impacto.
- 🟡 **Alto acoplamento**: `produto_local.dart` é importado por **9 arquivos**. Mudanças aqui têm alto impacto.
- 🟡 **Alto acoplamento**: `inventario.dart` é importado por **14 arquivos**. Mudanças aqui têm alto impacto.
- 🟡 **Alto acoplamento**: `inventario_service.dart` é importado por **8 arquivos**. Mudanças aqui têm alto impacto.

---

## Modelos Hive

| typeId | Classe | Arquivo | Campos | Próximo fieldId |
|:------:|--------|---------|:------:|:---------------:|
| 2 | `class AppState` | `app_state.dart` | 10 | **10** |
| 31 | `class ProdutoLocal` | `produto_local.dart` | 5 | **5** |
| 32 | `class BarraLocal` | `barra_local.dart` | 4 | **4** |
| 41 | `class LancLocal` | `lanc_local.dart` | 25 | **25** |

### Campos por modelo

#### `app_state.dart` — typeId `2` — próximo fieldId: `10`

| fieldId | Tipo | Nome |
|:-------:|------|------|
| 0 | `String?` | `lastSyncMateriais` |
| 1 | `String?` | `lastSyncBarras` |
| 2 | `String?` | `lastSyncGases` |
| 3 | `DateTime?` | `lastLogin` |
| 4 | `String?` | `lastSyncProdutos` |
| 5 | `int` | `seedVersion` |
| 6 | `String?` | `cursorBarrasShard` |
| 7 | `String?` | `cursorProdutosShard` |
| 8 | `bool` | `handover` |
| 9 | `int?` | `contagemAtual` |

#### `produto_local.dart` — typeId `31` — próximo fieldId: `5`

| fieldId | Tipo | Nome |
|:-------:|------|------|
| 0 | `String` | `codigo` |
| 1 | `String` | `descricao` |
| 2 | `String` | `unidade` |
| 3 | `String` | `origem` |
| 4 | `DateTime?` | `updatedAt` |

#### `barra_local.dart` — typeId `32` — próximo fieldId: `4`

| fieldId | Tipo | Nome |
|:-------:|------|------|
| 0 | `String` | `tag` |
| 1 | `String` | `codigo` |
| 2 | `String?` | `lote` |
| 3 | `DateTime?` | `updatedAt` |

#### `lanc_local.dart` — typeId `41` — próximo fieldId: `25`

| fieldId | Tipo | Nome |
|:-------:|------|------|
| 0 | `String` | `idLocal` |
| 1 | `String` | `uid` |
| 2 | `String` | `codigo` |
| 3 | `String` | `descricao` |
| 4 | `String` | `unidade` |
| 5 | `double` | `quantidade` |
| 6 | `String` | `prateleira` |
| 7 | `double` | `cheio` |
| 8 | `double` | `vazio` |
| 9 | `String?` | `lote` |
| 10 | `String?` | `tag` |
| 11 | `DateTime` | `createdAtLocal` |
| 12 | `LancStatus` | `status` |
| 13 | `String?` | `errorCode` |
| 14 | `String?` | `remoteId` |
| 15 | `TipoRegistro` | `registro` |
| 16 | `double?` | `volume` |
| 17 | `String?` | `inventarioId` |
| 18 | `String?` | `contagemId` |
| 19 | `String?` | `nickname` |
| 20 | `String?` | `nomeCompleto` |
| 21 | `String?` | `localizacaoId` |
| 22 | `String?` | `localizacaoNome` |
| 23 | `String?` | `comentario` |
| 24 | `String?` | `ordemServico` |

_Possui: `copyWith`, `toJson`/`fromJson`_

### Rastreabilidade — Quem usa cada modelo Hive

> Para cada modelo: quais arquivos o importam (acesso potencial aos dados locais).

- **`app_state.dart`** → `contagem_choice_page.dart`, `fixed_collections_sync.dart`
- **`produto_local.dart`** → `fixed_collections_sync.dart`, `hive_boxes.dart`, `hive_diagnostics.dart`, `hive_probe_strict.dart`, `home_page.hive.dart`, `produtos_repository.dart`, `seed_importer.dart`, `test_hive.dart`, `test_hive_seed.dart`
- **`barra_local.dart`** → `barras_repository.dart`, `fixed_collections_sync.dart`, `hive_boxes.dart`, `hive_diagnostics.dart`, `hive_probe_strict.dart`, `home_page.hive.dart`, `seed_importer.dart`, `test_hive.dart`, `test_hive_seed.dart`
- **`lanc_local.dart`** → `diagnostics_page.dart`, `hive_boxes.dart`, `hive_diagnostics.dart`, `home_page.dart`, `lancamentos_repository.dart`, `sync_diagnostics.dart`, `sync_service.dart`

---

## Coleções Firestore

| Coleção | Operações detectadas | Arquivos que acessam |
|---------|---------------------|---------------------|
| `barras` | leitura | `fixed_collections_sync.dart` |
| `estoque` | escrita, leitura, stream | `comparativo_service.dart`, `consolidation_service.dart`, `detalhe_inventario_screen.dart`, `estoque_service.dart`, `relatorio_service.dart` |
| `inventarios` | delete, escrita, leitura, stream, update | `comparativo_service.dart`, `controle_contagem_screen.dart`, `detalhe_inventario_screen.dart`, `estoque_service.dart`, `historico_screen.dart` _(+5)_ |
| `lancamentos` | delete, escrita, leitura, stream, update | `consolidation_service.dart`, `home_page.dart`, `inventario_service.dart`, `lancamentos_repository.dart`, `mobile_sync_service.dart` _(+3)_ |
| `materiais` | leitura | `consolidation_service.dart`, `estoque_service.dart`, `fixed_collections_sync.dart` |
| `participantes` | delete, escrita, leitura, stream, update | `controle_contagem_screen.dart`, `detalhe_inventario_screen.dart`, `home_page.dart`, `inventario_service.dart`, `mobile_sync_service.dart` _(+1)_ |
| `produtos_manuais` | escrita | `produtos_repository.dart` |
| `sistema` | leitura | `inventario_service.dart` |
| `users` | escrita, leitura, update | `sync_diagnostics.dart`, `user_service.dart` |

### Detalhes por coleção

#### `barras`

| Arquivo | Operações |
|---------|-----------|
| `fixed_collections_sync.dart` | leitura |

#### `estoque`

| Arquivo | Operações |
|---------|-----------|
| `comparativo_service.dart` | leitura |
| `consolidation_service.dart` | leitura |
| `detalhe_inventario_screen.dart` | stream |
| `estoque_service.dart` | escrita, leitura, stream |
| `relatorio_service.dart` | leitura |

#### `inventarios`

| Arquivo | Operações |
|---------|-----------|
| `comparativo_service.dart` | leitura |
| `controle_contagem_screen.dart` | stream |
| `detalhe_inventario_screen.dart` | stream |
| `estoque_service.dart` | leitura, stream |
| `historico_screen.dart` | leitura |
| `home_page.dart` | delete, leitura, stream |
| `inventario_service.dart` | escrita, leitura, stream, update |
| `mobile_sync_service.dart` | escrita, leitura, stream, update |
| `participantes_screen.dart` | stream |
| `relatorio_service.dart` | leitura, update |

#### `lancamentos`

| Arquivo | Operações |
|---------|-----------|
| `consolidation_service.dart` | leitura, stream |
| `home_page.dart` | leitura |
| `inventario_service.dart` | leitura, update |
| `lancamentos_repository.dart` | delete, escrita |
| `mobile_sync_service.dart` | leitura |
| `relatorio_service.dart` | leitura |
| `sync_diagnostics.dart` | leitura |
| `sync_service.dart` | delete |

#### `materiais`

| Arquivo | Operações |
|---------|-----------|
| `consolidation_service.dart` | leitura |
| `estoque_service.dart` | leitura |
| `fixed_collections_sync.dart` | leitura |

#### `participantes`

| Arquivo | Operações |
|---------|-----------|
| `controle_contagem_screen.dart` | stream |
| `detalhe_inventario_screen.dart` | stream |
| `home_page.dart` | delete, leitura, stream |
| `inventario_service.dart` | escrita, leitura, stream, update |
| `mobile_sync_service.dart` | escrita, leitura, stream, update |
| `participantes_screen.dart` | stream |

#### `produtos_manuais`

| Arquivo | Operações |
|---------|-----------|
| `produtos_repository.dart` | escrita |

#### `sistema`

| Arquivo | Operações |
|---------|-----------|
| `inventario_service.dart` | leitura |

#### `users`

| Arquivo | Operações |
|---------|-----------|
| `sync_diagnostics.dart` | leitura |
| `user_service.dart` | escrita, leitura, update |

---

## Catálogo de Arquivos

> Responsabilidade inferida, declarações, métodos e relações de cada arquivo.

### 📁 `lib`

#### `firebase_options.dart` — 📄  Dart

> Configurações de conexão Firebase geradas pelo FlutterFire CLI (não editar manualmente).

- **Linhas:** 84
- **Declarações:** `class DefaultFirebaseOptions`
- **Importado por:** `main.dart`, `main_desktop.dart`

#### `hive_probe_strict.dart` — 📄  Dart

> Sonda estrita de integridade Hive — usada em testes e depuração.

- **Linhas:** 145
- **Declarações:** `class HiveProbeStrict`, `class _HiveProbeStrictState`
- **Métodos públicos:** `main()`, `setState()`
- **Importa (locais):** `hive_boxes.dart`, `produto_local.dart`, `barra_local.dart`
- **Pacotes:** hive_flutter

#### `main.dart` — 🚀  Entry Point

> Entry point mobile — inicializa Firebase, Hive e roteamento.

- **Linhas:** 111
- **Declarações:** `class MyApp`, `class _Bootstrapper`
- **Importa (locais):** `hive_boxes.dart`, `mobile_sync_service.dart`, `home_page.dart`, `login_page.dart`, `first_sync_screen.dart`, `modo_operacao_screen.dart`, `firebase_options.dart`
- **Pacotes:** firebase_core, firebase_auth, hive_flutter, hive
- **Importado por:** `widget_test.dart`
- **Rotas:** `/login`, `/home`, `/modo_operacao`

#### `main_desktop.dart` — 🚀  Entry Point

> Entry point desktop — inicializa Firebase, Hive e roteamento para a versão analista.

- **Linhas:** 260
- **Declarações:** `class LegoDesktopApp`, `class AuthWrapper`, `class LoginDesktopScreen`, `class _LoginDesktopScreenState`
- **Métodos públicos:** `main()`, `runApp()`, `setState()`
- **Recursos:** `copyWith`
- **Importa (locais):** `firebase_options.dart`, `dashboard_desktop_screen.dart`
- **Pacotes:** cloud_firestore, firebase_core, firebase_auth

#### `test_hive.dart` — 📄  Dart

> Arquivo de suporte/infraestrutura.

- **Linhas:** 78
- **Métodos públicos:** `main()`
- **Importa (locais):** `hive_boxes.dart`, `produto_local.dart`, `barra_local.dart`, `seed_importer.dart`
- **Pacotes:** hive_flutter

#### `test_hive_seed.dart` — 📄  Dart

> Arquivo de suporte/infraestrutura.

- **Linhas:** 218
- **Declarações:** `class TestHiveSeedPage`, `class _TestHiveSeedPageState`, `class _Probe`
- **Métodos públicos:** `main()`
- **Importa (locais):** `hive_boxes.dart`, `produto_local.dart`, `barra_local.dart`, `seed_importer.dart`
- **Pacotes:** hive_flutter

### 📁 `lib/config`

#### `planta_diadema_config.dart` — ⚙️  Config

> Configuração da planta de Diadema: áreas, localizações e layout do mapa SVG/JSON.

- **Linhas:** 192
- **Declarações:** `class RectRelativo`, `class AreaMapa`, `class SubArea`, `class PlantaDiademaConfig`
- **Métodos públicos:** `toAbsolute()`, `getArea()`, `getSubArea()`
- **Importado por:** `planta_navegador_widget.dart`

### 📁 `lib/data/local`

#### `app_state.dart` — 🗃️  Modelo Hive

> Modelo Hive (typeId 2) com 10 campos persistidos localmente: lastSyncMateriais, lastSyncBarras, lastSyncGases, lastLogin, lastSyncProdutos.

- **Linhas:** 54
- **Declarações:** `class AppState`
- **Hive:** typeId `2` | 10 campos | próximo fieldId: `10`
- **Campos Hive:** `lastSyncMateriais`:`String?`, `lastSyncBarras`:`String?`, `lastSyncGases`:`String?`, `lastLogin`:`DateTime?`, `lastSyncProdutos`:`String?`, `seedVersion`:`int`, `cursorBarrasShard`:`String?`, `cursorProdutosShard`:`String?`, `handover`:`bool`, `contagemAtual`:`int?`
- **Pacotes:** hive
- **Importado por:** `fixed_collections_sync.dart`, `contagem_choice_page.dart`

#### `barra_local.dart` — 🗃️  Modelo Hive

> Modelo Hive (typeId 32) com 4 campos persistidos localmente: tag, codigo, lote, updatedAt.

- **Linhas:** 19
- **Declarações:** `class BarraLocal`
- **Hive:** typeId `32` | 4 campos | próximo fieldId: `4`
- **Campos Hive:** `tag`:`String`, `codigo`:`String`, `lote`:`String?`, `updatedAt`:`DateTime?`
- **Pacotes:** hive
- **Importado por:** `hive_boxes.dart`, `barras_repository.dart`, `hive_probe_strict.dart`, `fixed_collections_sync.dart`, `hive_diagnostics.dart`, `seed_importer.dart`, `test_hive.dart`, `test_hive_seed.dart` _(+1)_

#### `hive_boxes.dart` — 📄  Dart

> Centraliza a abertura e referência de todas as caixas Hive do projeto.

- **Linhas:** 48
- **Declarações:** `class HiveBoxes`
- **Métodos públicos:** `ensureAdapters()`, `openProdutos()`, `openBarras()`, `openUserLancamentos()`, `lancamentosBox()`, `closeUserLancamentos()`
- **Importa (locais):** `lanc_local.dart`, `produto_local.dart`, `barra_local.dart`
- **Pacotes:** hive
- **Importado por:** `barras_repository.dart`, `produtos_repository.dart`, `hive_probe_strict.dart`, `main.dart`, `auth_service.dart`, `fixed_collections_sync.dart`, `hive_diagnostics.dart`, `offline_bootstrap.dart` _(+5)_

#### `lanc_local.dart` — 🗃️  Modelo Hive

> Modelo Hive (typeId 41) com 25 campos persistidos localmente: idLocal, uid, codigo, descricao, unidade. Suporta `copyWith`. Serialização JSON/Map.

- **Linhas:** 162
- **Declarações:** `enum LancStatus`, `enum TipoRegistro`, `class LancLocal`, `extension LancLocalToJson`
- **Métodos públicos:** `copyWith()`, `toJson()`
- **Hive:** typeId `41` | 25 campos | próximo fieldId: `25`
- **Campos Hive:** `idLocal`:`String`, `uid`:`String`, `codigo`:`String`, `descricao`:`String`, `unidade`:`String`, `quantidade`:`double`, `prateleira`:`String`, `cheio`:`double`, `vazio`:`double`, `lote`:`String?`, `tag`:`String?`, `createdAtLocal`:`DateTime`, `status`:`LancStatus`, `errorCode`:`String?`, `remoteId`:`String?`, `registro`:`TipoRegistro`, `volume`:`double?`, `inventarioId`:`String?`, `contagemId`:`String?`, `nickname`:`String?`, `nomeCompleto`:`String?`, `localizacaoId`:`String?`, `localizacaoNome`:`String?`, `comentario`:`String?`, `ordemServico`:`String?`
- **Recursos:** `copyWith`, `toJson/fromJson`
- **Pacotes:** hive, cloud_firestore
- **Importado por:** `hive_boxes.dart`, `lancamentos_repository.dart`, `hive_diagnostics.dart`, `sync_diagnostics.dart`, `sync_service.dart`, `diagnostics_page.dart`, `home_page.dart`

#### `produto_local.dart` — 🗃️  Modelo Hive

> Modelo Hive (typeId 31) com 5 campos persistidos localmente: codigo, descricao, unidade, origem, updatedAt.

- **Linhas:** 22
- **Declarações:** `class ProdutoLocal`
- **Hive:** typeId `31` | 5 campos | próximo fieldId: `5`
- **Campos Hive:** `codigo`:`String`, `descricao`:`String`, `unidade`:`String`, `origem`:`String`, `updatedAt`:`DateTime?`
- **Pacotes:** hive
- **Importado por:** `hive_boxes.dart`, `produtos_repository.dart`, `hive_probe_strict.dart`, `fixed_collections_sync.dart`, `hive_diagnostics.dart`, `seed_importer.dart`, `test_hive.dart`, `test_hive_seed.dart` _(+1)_

### 📁 `lib/data/repositories`

#### `barras_repository.dart` — 🏛️  Repositório

> Repositório Firestore.

- **Linhas:** 22
- **Declarações:** `class BarrasRepository`
- **Métodos públicos:** `getByTag()`, `logAvailableKeys()`
- **Importa (locais):** `hive_boxes.dart`, `barra_local.dart`
- **Pacotes:** hive
- **Importado por:** `home_page.dart`, `home_page.hive.dart`

#### `lancamentos_repository.dart` — 🏛️  Repositório

> Repositório Firestore — coleções: lancamentos. Operações: escrita, delete. Suporta `copyWith`. Serialização JSON/Map.

- **Linhas:** 658
- **Declarações:** `class LancamentosRepository`, `class UserStats`, `class CleanupStats`, `class CleanupResult`
- **Métodos públicos:** `addPending()`, `getPending()`, `countPending()`, `countErrors()`, `countManual()`, `watchAllSorted()`, `updatePartial()`, `markSynced()`, `delete()`, `markError()`, `hardDeleteLocal()`, `tagJaExiste()`
- **Firestore:** `lancamentos` (delete, escrita)
- **Recursos:** `copyWith`, `toJson/fromJson`
- **Importa (locais):** `user_service.dart`, `lanc_local.dart`
- **Pacotes:** cloud_firestore, hive, uuid, shared_preferences, firebase_auth, path_provider
- **Importado por:** `auth_service.dart`, `sync_service.dart`, `home_page.dart`

#### `produtos_repository.dart` — 🏛️  Repositório

> Repositório Firestore — coleções: produtos_manuais. Operações: escrita.

- **Linhas:** 161
- **Declarações:** `class ProdutosRepository`
- **Métodos públicos:** `getByCodigoPreferGases()`, `addManualProduct()`, `logAvailableKeys()`, `searchCodigosOuDescricoes()`, `removeDiacritics()`
- **Firestore:** `produtos_manuais` (escrita)
- **Importa (locais):** `hive_boxes.dart`, `produto_local.dart`
- **Pacotes:** hive, diacritic, uuid, cloud_firestore
- **Importado por:** `home_page.dart`, `home_page.hive.dart`

### 📁 `lib/models`

#### `balanco_financeiro.dart` — 📦  Modelo

> Modelo de domínio — `BalancoFinanceiro`, `BalancoFinanceiroBuilder`. Suporta `copyWith`.

- **Linhas:** 256
- **Declarações:** `class BalancoFinanceiro`, `class BalancoFinanceiroBuilder`
- **Métodos públicos:** `formatarValor()`, `toString()`, `copyWith()`, `addSobra()`, `addFalta()`, `addItemOk()`, `addItemNaoEncontrado()`, `addItemAguardandoC3()`, `reset()`
- **Recursos:** `copyWith`
- **Importado por:** `consolidation_service.dart`, `relatorio_service.dart`, `analise_patrimonial_screen.dart`, `relatorio_screen.dart`, `balanco_summary_widget.dart`, `produto_detail_dialog.dart`, `tabela_produtos_widget.dart`

#### `divergencia.dart` — 📦  Modelo

> Modelo de domínio — `Divergencia`, `DivergenciaLocal`, `TipoDivergenciaLocal`. Suporta `copyWith`.

- **Linhas:** 214
- **Declarações:** `class Divergencia`, `class DivergenciaLocal`, `enum TipoDivergenciaLocal`, `extension TipoDivergenciaLocalUI`, `class DivergenciaBuilder`
- **Métodos públicos:** `copyWith()`, `toString()`, `fromProdutoConsolidado()`
- **Recursos:** `copyWith`
- **Importado por:** `consolidation_service.dart`, `exportar_excel_service.dart`, `relatorio_service.dart`, `comparativo_contagens_screen.dart`, `relatorio_screen.dart`, `divergencia_card_widget.dart`

#### `inventario.dart` — 📦  Modelo

> Modelo de domínio — `TipoContagem`, `StatusInventario`, `Inventario`. Suporta `copyWith`. Serialização JSON/Map.

- **Linhas:** 382
- **Declarações:** `enum TipoContagem`, `enum StatusInventario`, `class Inventario`, `class ContagemInfo`, `class TiposMaterial`
- **Métodos públicos:** `toFirestore()`, `proximaContagem()`, `copyWith()`, `toMap()`, `label()`, `tipoContagemSugerido()`
- **Recursos:** `copyWith`, `toJson/fromJson`
- **Pacotes:** cloud_firestore
- **Importado por:** `comparativo_service.dart`, `inventario_service.dart`, `mobile_sync_service.dart`, `relatorio_service.dart`, `comparativo_inventarios_screen.dart`, `controle_contagem_screen.dart`, `criar_inventario_screen.dart`, `dashboard_desktop_screen.dart` _(+6)_

#### `participante.dart` — 📦  Modelo

> Modelo de domínio — `Participante`. Suporta `copyWith`.

- **Linhas:** 186
- **Declarações:** `class Participante`
- **Métodos públicos:** `toFirestore()`, `copyWith()`
- **Recursos:** `copyWith`
- **Pacotes:** cloud_firestore, equatable
- **Importado por:** `controle_contagem_screen.dart`, `detalhe_inventario_screen.dart`, `participantes_screen.dart`

#### `produto_consolidado.dart` — 📦  Modelo

> Modelo de domínio — `StatusProduto`, `StatusProdutoUI`, `ProdutoConsolidado`. Suporta `copyWith`.

- **Linhas:** 243
- **Declarações:** `enum StatusProduto`, `extension StatusProdutoUI`, `class ProdutoConsolidado`
- **Métodos públicos:** `copyWith()`, `toString()`
- **Recursos:** `copyWith`
- **Importado por:** `consolidation_service.dart`, `analise_patrimonial_screen.dart`, `comparativo_contagens_screen.dart`, `filtros_bar_widget.dart`, `produto_detail_dialog.dart`, `tabela_produtos_widget.dart`

#### `user_profile.dart` — 📦  Modelo

> Modelo de domínio — `UserProfile`.

- **Linhas:** 51
- **Declarações:** `class UserProfile`
- **Métodos públicos:** `toFirestore()`
- **Pacotes:** cloud_firestore
- **Importado por:** `user_service.dart`

### 📁 `lib/services`

#### `admin_guard.dart` — 📄  Dart

> Guard de rota: bloqueia acesso a telas administrativas para não-admins.

- **Linhas:** 12
- **Declarações:** `class AdminGuard`
- **Métodos públicos:** `setPin()`, `verify()`
- **Pacotes:** flutter_secure_storage

#### `auth_service.dart` — ⚙️  Serviço

> Serviço de negócio — expõe: signInWithEmailAndPassword, registerWithEmail, signInWithGoogle, sendPasswordResetEmail().

- **Linhas:** 175
- **Declarações:** `class AuthService`
- **Métodos públicos:** `signInWithEmailAndPassword()`, `registerWithEmail()`, `signInWithGoogle()`, `sendPasswordResetEmail()`, `signOutWithGuard()`, `signOut()`
- **Importa (locais):** `hive_boxes.dart`, `lancamentos_repository.dart`, `connectivity_service.dart`, `seed_bootstrap.dart`, `user_service.dart`
- **Pacotes:** firebase_auth
- **Importado por:** `login_page.dart`

#### `comparativo_service.dart` — ⚙️  Serviço

> Serviço de negócio — expõe: gerarComparativo, listarInventariosParaComparacao(). ⚠️ Acessa Firestore diretamente (coleções: inventarios, estoque) — considere mover para um repositório.

- **Linhas:** 322
- **Declarações:** `class ResultadoComparativo`, `class ResumoComparativo`, `class ItemComparativo`, `enum TipoAlteracao`, `class ComparativoService`
- **Métodos públicos:** `gerarComparativo()`, `listarInventariosParaComparacao()`
- **Firestore:** `inventarios` (leitura), `estoque` (leitura)
- **Importa (locais):** `inventario.dart`
- **Pacotes:** cloud_firestore, intl
- **Importado por:** `comparativo_inventarios_screen.dart`

#### `connectivity_service.dart` — ⚙️  Serviço

> Serviço de negócio — expõe: start, stop().

- **Linhas:** 37
- **Declarações:** `class ConnectivityService`
- **Métodos públicos:** `start()`, `stop()`
- **Importa (locais):** `sync_service.dart`
- **Pacotes:** connectivity_plus, firebase_auth
- **Importado por:** `auth_service.dart`, `offline_bootstrap.dart`

#### `consolidation_service.dart` — ⚙️  Serviço

> Serviço de negócio — expõe: streamProdutosConsolidados, invalidarCache, calcularBalanco, extrairDivergencias(). Suporta `copyWith`. ⚠️ Acessa Firestore diretamente (coleções: lancamentos, materiais, estoque) — considere mover para um repositório.

- **Linhas:** 519
- **Declarações:** `class ConsolidationService`, `enum OrdenacaoCriterio`, `extension OrdenacaoCriterioLabel`
- **Métodos públicos:** `streamProdutosConsolidados()`, `invalidarCache()`, `calcularBalanco()`, `extrairDivergencias()`, `filtrarPorStatus()`, `filtrarPorBusca()`, `ordenar()`, `gerarRelatorio()`, `getEstatisticasRapidas()`, `produtoPrecisaC3()`
- **Firestore:** `lancamentos` (leitura, stream), `materiais` (leitura), `estoque` (leitura)
- **Recursos:** `copyWith`
- **Importa (locais):** `produto_consolidado.dart`, `balanco_financeiro.dart`, `divergencia.dart`
- **Pacotes:** cloud_firestore
- **Importado por:** `analise_patrimonial_screen.dart`, `comparativo_contagens_screen.dart`, `filtros_bar_widget.dart`

#### `estoque_service.dart` — ⚙️  Serviço

> Serviço de negócio — expõe: importarEstoqueParaInventario, buscarEstoqueInventario, streamEstoqueInventario, buscarItemEstoque(). ⚠️ Acessa Firestore diretamente (coleções: inventarios, estoque, materiais) — considere mover para um repositório.

- **Linhas:** 466
- **Declarações:** `class EstoqueService`
- **Métodos públicos:** `importarEstoqueParaInventario()`, `buscarEstoqueInventario()`, `streamEstoqueInventario()`, `buscarItemEstoque()`, `getEstatisticasEstoque()`, `getProdutoCompleto()`, `importarEstoque()`, `validarArquivoImportacao()`, `listarEstoque()`, `getEstatisticas()`
- **Firestore:** `inventarios` (leitura, stream), `estoque` (escrita, leitura, stream), `materiais` (leitura)
- **Pacotes:** cloud_firestore
- **Importado por:** `criar_inventario_screen.dart`, `importar_estoque_screen.dart`

#### `excel_parser_service.dart` — ⚙️  Serviço

> Serviço de negócio — expõe: toMap, toString, processarBytes, processarArquivo(). Serialização JSON/Map.

- **Linhas:** 397
- **Declarações:** `class ParseResult`, `class ItemEstoque`, `class ExcelParserService`
- **Métodos públicos:** `toMap()`, `toString()`, `processarBytes()`, `processarArquivo()`, `gerarPreview()`, `calcularEstatisticas()`
- **Recursos:** `toJson/fromJson`
- **Pacotes:** excel
- **Importado por:** `criar_inventario_screen.dart`

#### `exportar_excel_service.dart` — ⚙️  Serviço

> Serviço de negócio — expõe: exportarCompleto, exportarDivergencias, exportarFinanceiro().

- **Linhas:** 472
- **Declarações:** `class ExportarExcelService`, `class ExcelColors`
- **Métodos públicos:** `exportarCompleto()`, `exportarDivergencias()`, `exportarFinanceiro()`
- **Importa (locais):** `relatorio_service.dart`, `divergencia.dart`
- **Pacotes:** excel, intl, path_provider
- **Importado por:** `relatorio_screen.dart`

#### `fixed_collections_sync.dart` — 📄  Dart

> Sincroniza coleções fixas (produtos, barras) do Firestore para o Hive.

- **Linhas:** 141
- **Declarações:** `class FixedCollectionsSync`
- **Métodos públicos:** `fullSync()`, `log()`, `ensureIncrementalInBackground()`
- **Firestore:** `materiais` (leitura), `barras` (leitura)
- **Importa (locais):** `app_state.dart`, `barra_local.dart`, `produto_local.dart`, `hive_boxes.dart`
- **Pacotes:** cloud_firestore, hive
- **Importado por:** `offline_bootstrap.dart`

#### `hive_diagnostics.dart` — 📄  Dart

> Diagnóstico do estado interno das caixas Hive (integridade, contagens).

- **Linhas:** 129
- **Declarações:** `class HiveSnapshot`, `class HiveDiagnostics`
- **Métodos públicos:** `captureForCurrentUser()`, `bannerForCurrentUser()`
- **Importa (locais):** `hive_boxes.dart`, `lanc_local.dart`, `produto_local.dart`, `barra_local.dart`
- **Pacotes:** firebase_auth, hive
- **Importado por:** `diagnostics_page.dart`

#### `inventario_service.dart` — ⚙️  Serviço

> Serviço de negócio — expõe: criarInventarioCompleto, criarInventario, buscarInventarioAtivo, buscarInventarioPorId(). ⚠️ Acessa Firestore diretamente (coleções: inventarios, sistema, lancamentos) — considere mover para um repositório.

- **Linhas:** 704
- **Declarações:** `class InventarioService`
- **Métodos públicos:** `criarInventarioCompleto()`, `criarInventario()`, `buscarInventarioAtivo()`, `buscarInventarioPorId()`, `listarInventarios()`, `streamInventarios()`, `streamInventario()`, `iniciarInventario()`, `iniciarContagem()`, `finalizarContagem()`, `finalizarInventario()`, `avancarParaProximaContagem()`
- **Firestore:** `inventarios` (escrita, leitura, stream, update), `sistema` (leitura), `lancamentos` (leitura, update), `participantes` (escrita, leitura, stream, update)
- **Importa (locais):** `inventario.dart`
- **Pacotes:** firebase_auth, cloud_firestore
- **Importado por:** `comparativo_contagens_screen.dart`, `controle_contagem_screen.dart`, `criar_inventario_screen.dart`, `dashboard_desktop_screen.dart`, `dashboard_screen.dart`, `historico_screen.dart`, `participantes_screen.dart`, `home_page.dart`

#### `mobile_sync_service.dart` — ⚙️  Serviço

> Serviço de negócio — expõe: inicializar, setModoAutonomo, setModoControlado, buscarInventarioAtivo(). ⚠️ Acessa Firestore diretamente (coleções: inventarios, participantes, lancamentos) — considere mover para um repositório.

- **Linhas:** 494
- **Declarações:** `enum ModoOperacao`, `enum StatusParticipacao`, `class ResultadoSolicitacao`, `class InfoModoControlado`, `class MobileSyncService`
- **Métodos públicos:** `inicializar()`, `setModoAutonomo()`, `setModoControlado()`, `buscarInventarioAtivo()`, `streamInventarioAtivo()`, `verificarStatusParticipacao()`, `podeRegistrarLancamento()`
- **Firestore:** `inventarios` (escrita, leitura, stream, update), `participantes` (escrita, leitura, stream, update), `lancamentos` (leitura)
- **Importa (locais):** `inventario.dart`
- **Pacotes:** cloud_firestore, firebase_auth, shared_preferences
- **Importado por:** `main.dart`, `modo_operacao_screen.dart`, `inventario_ativo_widget.dart`

#### `offline_bootstrap.dart` — 📄  Dart

> Inicialização offline: carrega dados locais do Hive antes da autenticação.

- **Linhas:** 44
- **Declarações:** `class OfflineBootstrap`
- **Métodos públicos:** `run()`, `log()`
- **Importa (locais):** `hive_boxes.dart`, `seed_importer.dart`, `fixed_collections_sync.dart`, `connectivity_service.dart`
- **Pacotes:** firebase_auth

#### `relatorio_service.dart` — ⚙️  Serviço

> Serviço de negócio — expõe: toMap, gerarRelatorio, getCodigosDivergentes, marcarDivergenciasParaC3(). Serialização JSON/Map. ⚠️ Acessa Firestore diretamente (coleções: inventarios, estoque, lancamentos) — considere mover para um repositório.

- **Linhas:** 582
- **Declarações:** `class ConstantesFinanceiras`, `class ItemApurado`, `enum StatusApuracao`, `class ResultadoRelatorio`, `enum TipoRelatorio`, `class RelatorioService`
- **Métodos públicos:** `toMap()`, `gerarRelatorio()`, `getCodigosDivergentes()`, `marcarDivergenciasParaC3()`
- **Firestore:** `inventarios` (leitura, update), `estoque` (leitura), `lancamentos` (leitura)
- **Recursos:** `toJson/fromJson`
- **Importa (locais):** `balanco_financeiro.dart`, `divergencia.dart`, `inventario.dart`
- **Pacotes:** cloud_firestore
- **Importado por:** `exportar_excel_service.dart`, `detalhe_inventario_screen.dart`, `relatorio_screen.dart`

#### `seed_bootstrap.dart` — 📄  Dart

> Verifica e dispara o seed inicial de dados mestres (produtos, barras).

- **Linhas:** 70
- **Declarações:** `class SeedBootstrap`
- **Métodos públicos:** `ensureSeedOnceWithProgress()`, `ensureSeedOnce()`
- **Importa (locais):** `hive_boxes.dart`, `seed_importer.dart`
- **Pacotes:** hive
- **Importado por:** `auth_service.dart`, `first_sync_screen.dart`

#### `seed_importer.dart` — 📄  Dart

> Importa dados mestres do Firestore para o Hive local na primeira execução.

- **Linhas:** 236
- **Declarações:** `class SyncProgress`, `class SeedImporter`
- **Métodos públicos:** `importFromAssetJsonWithProgress()`, `log()`, `importFromAssetJson()`
- **Importa (locais):** `produto_local.dart`, `barra_local.dart`, `hive_boxes.dart`
- **Pacotes:** hive
- **Importado por:** `offline_bootstrap.dart`, `seed_bootstrap.dart`, `test_hive.dart`, `test_hive_seed.dart`, `first_sync_screen.dart`

#### `sync_diagnostics.dart` — 📄  Dart

> Coleta e expõe métricas de diagnóstico do estado de sincronização.

- **Linhas:** 38
- **Declarações:** `class SyncDiagnostics`
- **Métodos públicos:** `run()`
- **Firestore:** `users` (leitura), `lancamentos` (leitura)
- **Importa (locais):** `lanc_local.dart`
- **Pacotes:** cloud_firestore, hive

#### `sync_service.dart` — ⚙️  Serviço

> Serviço de negócio — expõe: runOnce, schedule, cancel, unawaited(). Serialização JSON/Map. ⚠️ Acessa Firestore diretamente (coleções: lancamentos) — considere mover para um repositório.

- **Linhas:** 92
- **Declarações:** `class SyncService`
- **Métodos públicos:** `runOnce()`, `schedule()`, `cancel()`, `unawaited()`, `syncLancamentos()`
- **Firestore:** `lancamentos` (delete)
- **Recursos:** `toJson/fromJson`
- **Importa (locais):** `lancamentos_repository.dart`, `lanc_local.dart`
- **Pacotes:** cloud_firestore
- **Importado por:** `connectivity_service.dart`, `home_page.dart`

#### `user_service.dart` — ⚙️  Serviço

> Serviço de negócio — expõe: criarPerfil, buscarPerfil, buscarNickname, atualizarPerfil(). ⚠️ Acessa Firestore diretamente (coleções: users) — considere mover para um repositório.

- **Linhas:** 219
- **Declarações:** `class UserService`
- **Métodos públicos:** `criarPerfil()`, `buscarPerfil()`, `buscarNickname()`, `atualizarPerfil()`, `nicknameDisponivel()`, `limparCache()`
- **Firestore:** `users` (escrita, leitura, update)
- **Importa (locais):** `user_profile.dart`
- **Pacotes:** cloud_firestore, shared_preferences
- **Importado por:** `lancamentos_repository.dart`, `auth_service.dart`

### 📁 `lib/ui`

#### `contagem_choice_page.dart` — 🖥️  Tela

> Tela da interface — `ContagemChoicePage`.

- **Linhas:** 63
- **Declarações:** `class ContagemChoicePage`
- **Importa (locais):** `app_state.dart`, `hive_boxes.dart`
- **Pacotes:** hive
- **Rotas:** `/home`

#### `diagnostics_page.dart` — 🖥️  Tela

> Tela da interface — `DiagnosticsPage`, `_DiagnosticsPageState`.

- **Linhas:** 107
- **Declarações:** `class DiagnosticsPage`, `class _DiagnosticsPageState`
- **Métodos públicos:** `setState()`
- **Importa (locais):** `hive_diagnostics.dart`, `lanc_local.dart`
- **Pacotes:** firebase_auth

#### `first_sync_screen.dart` — 🖥️  Tela

> Tela da interface — `FirstSyncScreen`.

- **Linhas:** 294
- **Declarações:** `class FirstSyncScreen`
- **Importa (locais):** `seed_bootstrap.dart`, `seed_importer.dart`, `home_page.dart`
- **Importado por:** `main.dart`, `login_page.dart`

#### `handover_page.dart` — 🖥️  Tela

> Tela da interface — `HandoverPage`.

- **Linhas:** 28
- **Declarações:** `class HandoverPage`

#### `home_page.dart` — 🖥️  Tela ⚠️ God File

> Tela da interface — `_Lancamento`, `_Unset`. Suporta `copyWith`. ⚠️ Acessa Firestore diretamente (coleções: inventarios, participantes, lancamentos) — considere mover para um repositório.

- **Linhas:** 3585
- **Declarações:** `class _Lancamento`, `class _Unset`, `class _LancamentoDoc`, `class _CadastroManualDialog`, `class _CadastroManualDialogState`, `class _ManualCleanupDialog`, `class _ManualCleanupDialogState`, `class _FormPane`, `class _LancamentosPane`, `class _LancamentosListAndTable`
- **Métodos públicos:** `copyWith()`, `setState()`, `setStateLocal()`, `two()`, `showDialog()`
- **Firestore:** `inventarios` (delete, leitura, stream), `participantes` (delete, leitura, stream), `lancamentos` (leitura)
- **Recursos:** `copyWith`
- **Importa (locais):** `inventario_service.dart`, `produtos_repository.dart`, `plant_map_page.dart`, `barras_repository.dart`, `lancamentos_repository.dart`, `lanc_local.dart`, `sync_service.dart`
- **Pacotes:** cloud_firestore, firebase_auth, connectivity_plus, hive
- **Importado por:** `main.dart`, `first_sync_screen.dart`, `login_page.dart`
- **Rotas:** `/login`

#### `home_page.hive.dart` — 🖥️  Tela

> Variante da home page com acesso direto ao Hive (diagnóstico/debug).

- **Linhas:** 99
- **Declarações:** `class HomePageHive`, `class _HomePageHiveState`
- **Métodos públicos:** `setState()`, `log()`
- **Importa (locais):** `produtos_repository.dart`, `barras_repository.dart`, `produto_local.dart`, `barra_local.dart`

#### `login_page.dart` — 🖥️  Tela

> Tela da interface — `LoginPage`, `_LoginPageState`. Suporta `copyWith`.

- **Linhas:** 518
- **Declarações:** `class LoginPage`, `class _LoginPageState`
- **Métodos públicos:** `setState()`
- **Recursos:** `copyWith`
- **Importa (locais):** `auth_service.dart`, `home_page.dart`, `first_sync_screen.dart`
- **Pacotes:** firebase_auth, hive
- **Importado por:** `main.dart`

### 📁 `lib/ui/desktop/screens`

#### `analise_patrimonial_screen.dart` — 🖥️  Tela

> Tela da interface — `AnalisePatrimonialScreen`, `_AnalisePatrimonialScreenState`.

- **Linhas:** 275
- **Declarações:** `class AnalisePatrimonialScreen`, `class _AnalisePatrimonialScreenState`
- **Métodos públicos:** `setState()`
- **Importa (locais):** `produto_consolidado.dart`, `balanco_financeiro.dart`, `consolidation_service.dart`, `balanco_summary_widget.dart`, `filtros_bar_widget.dart`, `tabela_produtos_widget.dart`, `alerta_badge_widget.dart`
- **Importado por:** `dashboard_screen.dart`

#### `comparativo_contagens_screen.dart` — 🖥️  Tela

> Tela da interface — `ComparativoContagensScreen`, `_ComparativoContagensScreenState`. Suporta `copyWith`.

- **Linhas:** 385
- **Declarações:** `class ComparativoContagensScreen`, `class _ComparativoContagensScreenState`
- **Métodos públicos:** `setState()`
- **Recursos:** `copyWith`
- **Importa (locais):** `divergencia.dart`, `produto_consolidado.dart`, `consolidation_service.dart`, `inventario_service.dart`, `divergencia_card_widget.dart`
- **Importado por:** `dashboard_screen.dart`

#### `comparativo_inventarios_screen.dart` — 🖥️  Tela

> Tela da interface — `ComparativoInventariosScreen`, `_ComparativoInventariosScreenState`.

- **Linhas:** 764
- **Declarações:** `class ComparativoInventariosScreen`, `class _ComparativoInventariosScreenState`
- **Métodos públicos:** `setState()`
- **Importa (locais):** `inventario.dart`, `comparativo_service.dart`
- **Pacotes:** intl
- **Importado por:** `dashboard_desktop_screen.dart`

#### `controle_contagem_screen.dart` — 🖥️  Tela ⚠️ God File

> Tela da interface — `ControleContagemScreen`, `_ControleContagemScreenState`. Suporta `copyWith`. ⚠️ Acessa Firestore diretamente (coleções: inventarios, participantes) — considere mover para um repositório.

- **Linhas:** 989
- **Declarações:** `class ControleContagemScreen`, `class _ControleContagemScreenState`
- **Firestore:** `inventarios` (stream), `participantes` (stream)
- **Recursos:** `copyWith`
- **Importa (locais):** `inventario.dart`, `participante.dart`, `inventario_service.dart`
- **Pacotes:** cloud_firestore, intl
- **Importado por:** `dashboard_desktop_screen.dart`

#### `criar_inventario_screen.dart` — 🖥️  Tela ⚠️ God File

> Tela da interface — `CriarInventarioScreen`, `_CriarInventarioScreenState`. Suporta `copyWith`. Serialização JSON/Map.

- **Linhas:** 987
- **Declarações:** `class CriarInventarioScreen`, `class _CriarInventarioScreenState`
- **Métodos públicos:** `setState()`
- **Recursos:** `copyWith`, `toJson/fromJson`
- **Importa (locais):** `inventario.dart`, `excel_parser_service.dart`, `inventario_service.dart`, `estoque_service.dart`
- **Pacotes:** file_picker, firebase_auth, intl
- **Importado por:** `dashboard_desktop_screen.dart`

#### `dashboard_desktop_screen.dart` — 🖥️  Tela

> Tela da interface — `DashboardDesktopScreen`, `_DashboardDesktopScreenState`.

- **Linhas:** 659
- **Declarações:** `class DashboardDesktopScreen`, `class _DashboardDesktopScreenState`
- **Métodos públicos:** `setState()`
- **Importa (locais):** `inventario.dart`, `inventario_service.dart`, `criar_inventario_screen.dart`, `controle_contagem_screen.dart`, `participantes_screen.dart`, `relatorio_screen.dart`, `historico_screen.dart`, `comparativo_inventarios_screen.dart`
- **Pacotes:** firebase_auth, intl
- **Importado por:** `main_desktop.dart`

#### `dashboard_screen.dart` — 🖥️  Tela

> Tela da interface — `DashboardScreen`, `_DashboardScreenState`.

- **Linhas:** 407
- **Declarações:** `class DashboardScreen`, `class _DashboardScreenState`
- **Métodos públicos:** `setState()`
- **Importa (locais):** `participantes_screen.dart`, `inventario.dart`, `inventario_service.dart`, `sidebar_navigation.dart`, `analise_patrimonial_screen.dart`, `comparativo_contagens_screen.dart`, `importar_estoque_screen.dart`
- **Pacotes:** firebase_auth

#### `detalhe_inventario_screen.dart` — 🖥️  Tela ⚠️ God File

> Tela da interface — `DetalheInventarioScreen`, `_DetalheInventarioScreenState`. Suporta `copyWith`. Serialização JSON/Map. ⚠️ Acessa Firestore diretamente (coleções: inventarios, participantes, estoque) — considere mover para um repositório.

- **Linhas:** 985
- **Declarações:** `class DetalheInventarioScreen`, `class _DetalheInventarioScreenState`
- **Firestore:** `inventarios` (stream), `participantes` (stream), `estoque` (stream)
- **Recursos:** `copyWith`, `toJson/fromJson`
- **Importa (locais):** `inventario.dart`, `participante.dart`, `relatorio_service.dart`, `relatorio_screen.dart`
- **Pacotes:** cloud_firestore, intl
- **Importado por:** `historico_screen.dart`

#### `historico_screen.dart` — 🖥️  Tela

> Tela da interface — `HistoricoScreen`, `_HistoricoScreenState`. ⚠️ Acessa Firestore diretamente (coleções: inventarios) — considere mover para um repositório.

- **Linhas:** 651
- **Declarações:** `class HistoricoScreen`, `class _HistoricoScreenState`
- **Métodos públicos:** `setState()`
- **Firestore:** `inventarios` (leitura)
- **Importa (locais):** `inventario.dart`, `inventario_service.dart`, `detalhe_inventario_screen.dart`, `relatorio_screen.dart`
- **Pacotes:** cloud_firestore, intl
- **Importado por:** `dashboard_desktop_screen.dart`

#### `importar_estoque_screen.dart` — 🖥️  Tela

> Tela da interface — `ImportarEstoqueScreen`, `_ImportarEstoqueScreenState`. Suporta `copyWith`.

- **Linhas:** 496
- **Declarações:** `class ImportarEstoqueScreen`, `class _ImportarEstoqueScreenState`
- **Métodos públicos:** `setState()`
- **Recursos:** `copyWith`
- **Importa (locais):** `estoque_service.dart`
- **Pacotes:** file_picker
- **Importado por:** `dashboard_screen.dart`

#### `participantes_screen.dart` — 🖥️  Tela ⚠️ God File

> Tela da interface — `ParticipantesScreen`, `_ParticipantesScreenState`. Suporta `copyWith`. ⚠️ Acessa Firestore diretamente (coleções: inventarios, participantes) — considere mover para um repositório.

- **Linhas:** 1058
- **Declarações:** `class ParticipantesScreen`, `class _ParticipantesScreenState`
- **Métodos públicos:** `setState()`, `showDialog()`
- **Firestore:** `inventarios` (stream), `participantes` (stream)
- **Recursos:** `copyWith`
- **Importa (locais):** `participante.dart`, `inventario.dart`, `inventario_service.dart`
- **Pacotes:** cloud_firestore, intl
- **Importado por:** `dashboard_desktop_screen.dart`, `dashboard_screen.dart`

#### `relatorio_screen.dart` — 🖥️  Tela ⚠️ God File

> Tela da interface — `RelatorioScreen`, `_RelatorioScreenState`. Suporta `copyWith`.

- **Linhas:** 1108
- **Declarações:** `class RelatorioScreen`, `class _RelatorioScreenState`
- **Métodos públicos:** `setState()`
- **Recursos:** `copyWith`
- **Importa (locais):** `balanco_financeiro.dart`, `divergencia.dart`, `relatorio_service.dart`, `exportar_excel_service.dart`
- **Pacotes:** intl
- **Importado por:** `dashboard_desktop_screen.dart`, `detalhe_inventario_screen.dart`, `historico_screen.dart`

### 📁 `lib/ui/desktop/widgets`

#### `alerta_badge_widget.dart` — 🧩  Widget

> Widget reutilizável — `AlertaBadgeWidget`.

- **Linhas:** 160
- **Declarações:** `class AlertaBadgeWidget`, `class _AlertaBadgeWidgetState`, `class SimpleBadge`
- **Importado por:** `analise_patrimonial_screen.dart`

#### `balanco_summary_widget.dart` — 🧩  Widget

> Widget reutilizável — `BalancoSummaryWidget`. Suporta `copyWith`.

- **Linhas:** 346
- **Declarações:** `class BalancoSummaryWidget`, `class _ValorCard`, `class _StatusBadge`, `class _MiniStat`
- **Recursos:** `copyWith`
- **Importa (locais):** `balanco_financeiro.dart`
- **Importado por:** `analise_patrimonial_screen.dart`

#### `divergencia_card_widget.dart` — 🧩  Widget

> Widget reutilizável — `DivergenciaCardWidget`. Suporta `copyWith`.

- **Linhas:** 261
- **Declarações:** `class DivergenciaCardWidget`, `class _DivergenciaCardWidgetState`
- **Recursos:** `copyWith`
- **Importa (locais):** `divergencia.dart`
- **Importado por:** `comparativo_contagens_screen.dart`

#### `filtros_bar_widget.dart` — 🧩  Widget

> Widget reutilizável — `FiltrosBarWidget`.

- **Linhas:** 200
- **Declarações:** `class FiltrosBarWidget`, `class _FiltroChip`
- **Importa (locais):** `produto_consolidado.dart`, `consolidation_service.dart`
- **Importado por:** `analise_patrimonial_screen.dart`

#### `produto_detail_dialog.dart` — 🧩  Widget

> Widget reutilizável — `ProdutoDetailDialog`. Suporta `copyWith`.

- **Linhas:** 452
- **Declarações:** `class ProdutoDetailDialog`
- **Recursos:** `copyWith`
- **Importa (locais):** `produto_consolidado.dart`, `balanco_financeiro.dart`
- **Importado por:** `tabela_produtos_widget.dart`

#### `sidebar_navigation.dart` — 🧩  Widget

> Componente de navegação lateral do layout desktop.

- **Linhas:** 259
- **Declarações:** `class SidebarNavigation`, `class _MenuItem`, `class _Badge`
- **Recursos:** `copyWith`
- **Importado por:** `dashboard_screen.dart`

#### `tabela_produtos_widget.dart` — 🧩  Widget

> Widget reutilizável — `TabelaProdutosWidget`.

- **Linhas:** 269
- **Declarações:** `class TabelaProdutosWidget`, `class _TabelaProdutosWidgetState`
- **Métodos públicos:** `showDialog()`
- **Importa (locais):** `produto_consolidado.dart`, `balanco_financeiro.dart`, `produto_detail_dialog.dart`
- **Importado por:** `analise_patrimonial_screen.dart`

### 📁 `lib/ui/mobile/screens`

#### `modo_operacao_screen.dart` — 🖥️  Tela

> Tela da interface — `ModoOperacaoScreen`, `_ModoOperacaoScreenState`.

- **Linhas:** 531
- **Declarações:** `class ModoOperacaoScreen`, `class _ModoOperacaoScreenState`
- **Métodos públicos:** `setState()`
- **Importa (locais):** `inventario.dart`, `mobile_sync_service.dart`
- **Pacotes:** intl
- **Importado por:** `main.dart`, `inventario_ativo_widget.dart`

#### `plant_map_page.dart` — 🖥️  Tela

> Tela da interface — `PlantArea`, `PlantLayout`. Serialização JSON/Map.

- **Linhas:** 513
- **Declarações:** `class PlantArea`, `class PlantLayout`, `class PlantMapPage`, `class _PlantMapPageState`, `class _AreaOverlayPainter`, `class _SelectedAreaBar`
- **Métodos públicos:** `toRect()`, `contains()`, `setState()`, `paint()`, `shouldRepaint()`
- **Recursos:** `toJson/fromJson`
- **Importado por:** `home_page.dart`

### 📁 `lib/ui/mobile/widgets`

#### `inventario_ativo_widget.dart` — 🧩  Widget

> Widget reutilizável — `InventarioAtivoWidget`.

- **Linhas:** 395
- **Declarações:** `class InventarioAtivoWidget`, `class _InventarioAtivoWidgetState`, `class ModoOperacaoChip`, `class AguardandoAprovacaoBanner`
- **Importa (locais):** `inventario.dart`, `mobile_sync_service.dart`, `modo_operacao_screen.dart`

### 📁 `lib/ui/widgets`

#### `sync_banner.dart` — 🧩  Widget

> Banner de status de sincronização exibido no topo das telas.

- **Linhas:** 20
- **Declarações:** `class SyncBanner`

### 📁 `lib/widgets`

#### `planta_navegador_widget.dart` — 🧩  Widget

> Widget reutilizável — `LocalizacaoSelecionada`.

- **Linhas:** 418
- **Declarações:** `class LocalizacaoSelecionada`, `class PlantaNavegadorWidget`, `class _PlantaNavegadorWidgetState`
- **Métodos públicos:** `setState()`
- **Importa (locais):** `planta_diadema_config.dart`

### 📁 `test`

#### `widget_test.dart` — 🧩  Widget

> Teste de widget padrão gerado pelo Flutter (esqueleto inicial, sem valor real ainda).

- **Linhas:** 9
- **Métodos públicos:** `main()`, `expect()`
- **Importa (locais):** `main.dart`
- **Pacotes:** flutter_test

### ⚙️ Arquivos gerados automaticamente

| Arquivo | Linhas | Pasta |
|---------|:------:|-------|
| `app_state.g.dart` | 69 | `lib/data/local` |
| `barra_local.g.dart` | 51 | `lib/data/local` |
| `lanc_local.g.dart` | 197 | `lib/data/local` |
| `produto_local.g.dart` | 54 | `lib/data/local` |

> Não edite manualmente. Regenere com: `flutter pub run build_runner build --delete-conflicting-outputs`

---

## Mapa de Dependências

> Quanto mais importado, mais central — e mais arriscado de modificar sem testes.

| # | Arquivo | Importado por | Quem importa |
|:-:|---------|:-------------:|--------------|
| 1 | `inventario.dart` 🔴 | 14 | `comparativo_service.dart`, `inventario_service.dart`, `mobile_sync_service.dart`, `relatorio_service.dart`, `comparativo_inventarios_screen.dart` _(+9)_ |
| 2 | `hive_boxes.dart` 🔴 | 13 | `barras_repository.dart`, `produtos_repository.dart`, `hive_probe_strict.dart`, `main.dart`, `auth_service.dart` _(+8)_ |
| 3 | `produto_local.dart` 🔴 | 9 | `hive_boxes.dart`, `produtos_repository.dart`, `hive_probe_strict.dart`, `fixed_collections_sync.dart`, `hive_diagnostics.dart` _(+4)_ |
| 4 | `barra_local.dart` 🔴 | 9 | `hive_boxes.dart`, `barras_repository.dart`, `hive_probe_strict.dart`, `fixed_collections_sync.dart`, `hive_diagnostics.dart` _(+4)_ |
| 5 | `inventario_service.dart` 🔴 | 8 | `comparativo_contagens_screen.dart`, `controle_contagem_screen.dart`, `criar_inventario_screen.dart`, `dashboard_desktop_screen.dart`, `dashboard_screen.dart` _(+3)_ |
| 6 | `lanc_local.dart` | 7 | `hive_boxes.dart`, `lancamentos_repository.dart`, `hive_diagnostics.dart`, `sync_diagnostics.dart`, `sync_service.dart` _(+2)_ |
| 7 | `balanco_financeiro.dart` | 7 | `consolidation_service.dart`, `relatorio_service.dart`, `analise_patrimonial_screen.dart`, `relatorio_screen.dart`, `balanco_summary_widget.dart` _(+2)_ |
| 8 | `produto_consolidado.dart` | 6 | `consolidation_service.dart`, `analise_patrimonial_screen.dart`, `comparativo_contagens_screen.dart`, `filtros_bar_widget.dart`, `produto_detail_dialog.dart` _(+1)_ |
| 9 | `divergencia.dart` | 6 | `consolidation_service.dart`, `exportar_excel_service.dart`, `relatorio_service.dart`, `comparativo_contagens_screen.dart`, `relatorio_screen.dart` _(+1)_ |
| 10 | `seed_importer.dart` | 5 | `offline_bootstrap.dart`, `seed_bootstrap.dart`, `test_hive.dart`, `test_hive_seed.dart`, `first_sync_screen.dart` |
| 11 | `mobile_sync_service.dart` | 3 | `main.dart`, `modo_operacao_screen.dart`, `inventario_ativo_widget.dart` |
| 12 | `home_page.dart` | 3 | `main.dart`, `first_sync_screen.dart`, `login_page.dart` |
| 13 | `lancamentos_repository.dart` | 3 | `auth_service.dart`, `sync_service.dart`, `home_page.dart` |
| 14 | `relatorio_service.dart` | 3 | `exportar_excel_service.dart`, `detalhe_inventario_screen.dart`, `relatorio_screen.dart` |
| 15 | `consolidation_service.dart` | 3 | `analise_patrimonial_screen.dart`, `comparativo_contagens_screen.dart`, `filtros_bar_widget.dart` |
| 16 | `participante.dart` | 3 | `controle_contagem_screen.dart`, `detalhe_inventario_screen.dart`, `participantes_screen.dart` |
| 17 | `relatorio_screen.dart` | 3 | `dashboard_desktop_screen.dart`, `detalhe_inventario_screen.dart`, `historico_screen.dart` |
| 18 | `user_service.dart` | 2 | `lancamentos_repository.dart`, `auth_service.dart` |
| 19 | `first_sync_screen.dart` | 2 | `main.dart`, `login_page.dart` |
| 20 | `modo_operacao_screen.dart` | 2 | `main.dart`, `inventario_ativo_widget.dart` |
| 21 | `firebase_options.dart` | 2 | `main.dart`, `main_desktop.dart` |
| 22 | `connectivity_service.dart` | 2 | `auth_service.dart`, `offline_bootstrap.dart` |
| 23 | `seed_bootstrap.dart` | 2 | `auth_service.dart`, `first_sync_screen.dart` |
| 24 | `sync_service.dart` | 2 | `connectivity_service.dart`, `home_page.dart` |
| 25 | `app_state.dart` | 2 | `fixed_collections_sync.dart`, `contagem_choice_page.dart` |
| 26 | `estoque_service.dart` | 2 | `criar_inventario_screen.dart`, `importar_estoque_screen.dart` |
| 27 | `participantes_screen.dart` | 2 | `dashboard_desktop_screen.dart`, `dashboard_screen.dart` |
| 28 | `produtos_repository.dart` | 2 | `home_page.dart`, `home_page.hive.dart` |
| 29 | `barras_repository.dart` | 2 | `home_page.dart`, `home_page.hive.dart` |
| 30 | `login_page.dart` | 1 | `main.dart` |
| 31 | `dashboard_desktop_screen.dart` | 1 | `main_desktop.dart` |
| 32 | `fixed_collections_sync.dart` | 1 | `offline_bootstrap.dart` |
| 33 | `user_profile.dart` | 1 | `user_service.dart` |
| 34 | `balanco_summary_widget.dart` | 1 | `analise_patrimonial_screen.dart` |
| 35 | `filtros_bar_widget.dart` | 1 | `analise_patrimonial_screen.dart` |
| 36 | `tabela_produtos_widget.dart` | 1 | `analise_patrimonial_screen.dart` |
| 37 | `alerta_badge_widget.dart` | 1 | `analise_patrimonial_screen.dart` |
| 38 | `divergencia_card_widget.dart` | 1 | `comparativo_contagens_screen.dart` |
| 39 | `comparativo_service.dart` | 1 | `comparativo_inventarios_screen.dart` |
| 40 | `excel_parser_service.dart` | 1 | `criar_inventario_screen.dart` |

---

## Mapa de Impacto

> **"Se eu modificar X, o que pode ser afetado?"**

> Lista os arquivos que importam diretamente cada arquivo do projeto.

> Arquivos sem dependentes não constam — mudanças neles são isoladas.

### `inventario.dart` — 🔴 CRÍTICO (14 dependente(s))

- `comparativo_inventarios_screen.dart`
- `comparativo_service.dart`
- `controle_contagem_screen.dart`
- `criar_inventario_screen.dart`
- `dashboard_desktop_screen.dart`
- `dashboard_screen.dart`
- `detalhe_inventario_screen.dart`
- `historico_screen.dart`
- `inventario_ativo_widget.dart`
- `inventario_service.dart`
- `mobile_sync_service.dart`
- `modo_operacao_screen.dart`
- `participantes_screen.dart`
- `relatorio_service.dart`

### `hive_boxes.dart` — 🔴 CRÍTICO (13 dependente(s))

- `auth_service.dart`
- `barras_repository.dart`
- `contagem_choice_page.dart`
- `fixed_collections_sync.dart`
- `hive_diagnostics.dart`
- `hive_probe_strict.dart`
- `main.dart`
- `offline_bootstrap.dart`
- `produtos_repository.dart`
- `seed_bootstrap.dart`
- `seed_importer.dart`
- `test_hive.dart`
- `test_hive_seed.dart`

### `produto_local.dart` — 🔴 CRÍTICO (9 dependente(s))

- `fixed_collections_sync.dart`
- `hive_boxes.dart`
- `hive_diagnostics.dart`
- `hive_probe_strict.dart`
- `home_page.hive.dart`
- `produtos_repository.dart`
- `seed_importer.dart`
- `test_hive.dart`
- `test_hive_seed.dart`

### `barra_local.dart` — 🔴 CRÍTICO (9 dependente(s))

- `barras_repository.dart`
- `fixed_collections_sync.dart`
- `hive_boxes.dart`
- `hive_diagnostics.dart`
- `hive_probe_strict.dart`
- `home_page.hive.dart`
- `seed_importer.dart`
- `test_hive.dart`
- `test_hive_seed.dart`

### `inventario_service.dart` — 🔴 CRÍTICO (8 dependente(s))

- `comparativo_contagens_screen.dart`
- `controle_contagem_screen.dart`
- `criar_inventario_screen.dart`
- `dashboard_desktop_screen.dart`
- `dashboard_screen.dart`
- `historico_screen.dart`
- `home_page.dart`
- `participantes_screen.dart`

### `lanc_local.dart` — 🟠 ALTO (7 dependente(s))

- `diagnostics_page.dart`
- `hive_boxes.dart`
- `hive_diagnostics.dart`
- `home_page.dart`
- `lancamentos_repository.dart`
- `sync_diagnostics.dart`
- `sync_service.dart`

### `balanco_financeiro.dart` — 🟠 ALTO (7 dependente(s))

- `analise_patrimonial_screen.dart`
- `balanco_summary_widget.dart`
- `consolidation_service.dart`
- `produto_detail_dialog.dart`
- `relatorio_screen.dart`
- `relatorio_service.dart`
- `tabela_produtos_widget.dart`

### `produto_consolidado.dart` — 🟠 ALTO (6 dependente(s))

- `analise_patrimonial_screen.dart`
- `comparativo_contagens_screen.dart`
- `consolidation_service.dart`
- `filtros_bar_widget.dart`
- `produto_detail_dialog.dart`
- `tabela_produtos_widget.dart`

### `divergencia.dart` — 🟠 ALTO (6 dependente(s))

- `comparativo_contagens_screen.dart`
- `consolidation_service.dart`
- `divergencia_card_widget.dart`
- `exportar_excel_service.dart`
- `relatorio_screen.dart`
- `relatorio_service.dart`

### `seed_importer.dart` — 🟠 ALTO (5 dependente(s))

- `first_sync_screen.dart`
- `offline_bootstrap.dart`
- `seed_bootstrap.dart`
- `test_hive.dart`
- `test_hive_seed.dart`

### `mobile_sync_service.dart` — 🟡 MÉDIO (3 dependente(s))

- `inventario_ativo_widget.dart`
- `main.dart`
- `modo_operacao_screen.dart`

### `home_page.dart` — 🟡 MÉDIO (3 dependente(s))

- `first_sync_screen.dart`
- `login_page.dart`
- `main.dart`

### `lancamentos_repository.dart` — 🟡 MÉDIO (3 dependente(s))

- `auth_service.dart`
- `home_page.dart`
- `sync_service.dart`

### `relatorio_service.dart` — 🟡 MÉDIO (3 dependente(s))

- `detalhe_inventario_screen.dart`
- `exportar_excel_service.dart`
- `relatorio_screen.dart`

### `consolidation_service.dart` — 🟡 MÉDIO (3 dependente(s))

- `analise_patrimonial_screen.dart`
- `comparativo_contagens_screen.dart`
- `filtros_bar_widget.dart`

### `participante.dart` — 🟡 MÉDIO (3 dependente(s))

- `controle_contagem_screen.dart`
- `detalhe_inventario_screen.dart`
- `participantes_screen.dart`

### `relatorio_screen.dart` — 🟡 MÉDIO (3 dependente(s))

- `dashboard_desktop_screen.dart`
- `detalhe_inventario_screen.dart`
- `historico_screen.dart`

### `user_service.dart` — 🟡 MÉDIO (2 dependente(s))

- `auth_service.dart`
- `lancamentos_repository.dart`

### `first_sync_screen.dart` — 🟡 MÉDIO (2 dependente(s))

- `login_page.dart`
- `main.dart`

### `modo_operacao_screen.dart` — 🟡 MÉDIO (2 dependente(s))

- `inventario_ativo_widget.dart`
- `main.dart`

### `firebase_options.dart` — 🟡 MÉDIO (2 dependente(s))

- `main.dart`
- `main_desktop.dart`

### `connectivity_service.dart` — 🟡 MÉDIO (2 dependente(s))

- `auth_service.dart`
- `offline_bootstrap.dart`

### `seed_bootstrap.dart` — 🟡 MÉDIO (2 dependente(s))

- `auth_service.dart`
- `first_sync_screen.dart`

### `sync_service.dart` — 🟡 MÉDIO (2 dependente(s))

- `connectivity_service.dart`
- `home_page.dart`

### `app_state.dart` — 🟡 MÉDIO (2 dependente(s))

- `contagem_choice_page.dart`
- `fixed_collections_sync.dart`

### `estoque_service.dart` — 🟡 MÉDIO (2 dependente(s))

- `criar_inventario_screen.dart`
- `importar_estoque_screen.dart`

### `participantes_screen.dart` — 🟡 MÉDIO (2 dependente(s))

- `dashboard_desktop_screen.dart`
- `dashboard_screen.dart`

### `produtos_repository.dart` — 🟡 MÉDIO (2 dependente(s))

- `home_page.dart`
- `home_page.hive.dart`

### `barras_repository.dart` — 🟡 MÉDIO (2 dependente(s))

- `home_page.dart`
- `home_page.hive.dart`

### `login_page.dart` — 🟡 MÉDIO (1 dependente(s))

- `main.dart`

### `dashboard_desktop_screen.dart` — 🟡 MÉDIO (1 dependente(s))

- `main_desktop.dart`

### `fixed_collections_sync.dart` — 🟡 MÉDIO (1 dependente(s))

- `offline_bootstrap.dart`

### `user_profile.dart` — 🟡 MÉDIO (1 dependente(s))

- `user_service.dart`

### `balanco_summary_widget.dart` — 🟡 MÉDIO (1 dependente(s))

- `analise_patrimonial_screen.dart`

### `filtros_bar_widget.dart` — 🟡 MÉDIO (1 dependente(s))

- `analise_patrimonial_screen.dart`

### `tabela_produtos_widget.dart` — 🟡 MÉDIO (1 dependente(s))

- `analise_patrimonial_screen.dart`

### `alerta_badge_widget.dart` — 🟡 MÉDIO (1 dependente(s))

- `analise_patrimonial_screen.dart`

### `divergencia_card_widget.dart` — 🟡 MÉDIO (1 dependente(s))

- `comparativo_contagens_screen.dart`

### `comparativo_service.dart` — 🟡 MÉDIO (1 dependente(s))

- `comparativo_inventarios_screen.dart`

### `excel_parser_service.dart` — 🟡 MÉDIO (1 dependente(s))

- `criar_inventario_screen.dart`

### `criar_inventario_screen.dart` — 🟡 MÉDIO (1 dependente(s))

- `dashboard_desktop_screen.dart`

### `controle_contagem_screen.dart` — 🟡 MÉDIO (1 dependente(s))

- `dashboard_desktop_screen.dart`

### `historico_screen.dart` — 🟡 MÉDIO (1 dependente(s))

- `dashboard_desktop_screen.dart`

### `comparativo_inventarios_screen.dart` — 🟡 MÉDIO (1 dependente(s))

- `dashboard_desktop_screen.dart`

### `sidebar_navigation.dart` — 🟡 MÉDIO (1 dependente(s))

- `dashboard_screen.dart`

### `analise_patrimonial_screen.dart` — 🟡 MÉDIO (1 dependente(s))

- `dashboard_screen.dart`

### `comparativo_contagens_screen.dart` — 🟡 MÉDIO (1 dependente(s))

- `dashboard_screen.dart`

### `importar_estoque_screen.dart` — 🟡 MÉDIO (1 dependente(s))

- `dashboard_screen.dart`

### `detalhe_inventario_screen.dart` — 🟡 MÉDIO (1 dependente(s))

- `historico_screen.dart`

### `exportar_excel_service.dart` — 🟡 MÉDIO (1 dependente(s))

- `relatorio_screen.dart`

### `produto_detail_dialog.dart` — 🟡 MÉDIO (1 dependente(s))

- `tabela_produtos_widget.dart`

### `hive_diagnostics.dart` — 🟡 MÉDIO (1 dependente(s))

- `diagnostics_page.dart`

### `plant_map_page.dart` — 🟡 MÉDIO (1 dependente(s))

- `home_page.dart`

### `auth_service.dart` — 🟡 MÉDIO (1 dependente(s))

- `login_page.dart`

### `planta_diadema_config.dart` — 🟡 MÉDIO (1 dependente(s))

- `planta_navegador_widget.dart`

### `main.dart` — 🟡 MÉDIO (1 dependente(s))

- `widget_test.dart`

---

## Dependências

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Firebase (versões atualizadas para melhor compatibilidade)
  firebase_core: ^4.4.0
  firebase_auth: ^6.1.4
  cloud_firestore: ^6.1.2

  # Offline-first
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  connectivity_plus: ^6.0.3
  path_provider: ^2.1.5
  shared_preferences: ^2.2.2

  # Util
  archive: ^3.4.10
  intl: ^0.20.2
  uuid: ^4.5.1
  flutter_secure_storage: ^9.2.2
  diacritic: ^0.1.5

  file_picker: ^8.0.0
  excel: ^4.0.6
  csv: ^6.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

  # Necessários para gerar os adapters Hive
  build_runner: ^2.4.8
  hive_generator: ^2.0.1

```

---

## Guia — Onde Mexer

Referência rápida para qualquer tipo de modificação no projeto.

### 🖥️ Adicionar ou modificar tela/página

_Telas ficam em `lib/ui/`. Para nova tela: crie o arquivo na pasta adequada (desktop ou mobile) e registre a navegação em `home_page.dart` ou no roteador._

**Arquivos relevantes:**

- `lib/ui/desktop/screens/analise_patrimonial_screen.dart` — `class AnalisePatrimonialScreen`, `class _AnalisePatrimonialScreenState`
  > Tela da interface — `AnalisePatrimonialScreen`, `_AnalisePatrimonialScreenState`.
- `lib/ui/desktop/screens/comparativo_contagens_screen.dart` — `class ComparativoContagensScreen`, `class _ComparativoContagensScreenState`
  > Tela da interface — `ComparativoContagensScreen`, `_ComparativoContagensScreenState`. Suporta `copyWith`.
- `lib/ui/desktop/screens/comparativo_inventarios_screen.dart` — `class ComparativoInventariosScreen`, `class _ComparativoInventariosScreenState`
  > Tela da interface — `ComparativoInventariosScreen`, `_ComparativoInventariosScreenState`.
- `lib/ui/contagem_choice_page.dart` — `class ContagemChoicePage`
  > Tela da interface — `ContagemChoicePage`.
- `lib/ui/desktop/screens/controle_contagem_screen.dart` — `class ControleContagemScreen`, `class _ControleContagemScreenState`
  > Tela da interface — `ControleContagemScreen`, `_ControleContagemScreenState`. Suporta `copyWith`. ⚠️ Acessa Firestore diretamente (coleções: inventarios, participantes) — considere mover para um repositório.
- `lib/ui/desktop/screens/criar_inventario_screen.dart` — `class CriarInventarioScreen`, `class _CriarInventarioScreenState`
  > Tela da interface — `CriarInventarioScreen`, `_CriarInventarioScreenState`. Suporta `copyWith`. Serialização JSON/Map.
- `lib/ui/desktop/screens/dashboard_desktop_screen.dart` — `class DashboardDesktopScreen`, `class _DashboardDesktopScreenState`
  > Tela da interface — `DashboardDesktopScreen`, `_DashboardDesktopScreenState`.
- `lib/ui/desktop/screens/dashboard_screen.dart` — `class DashboardScreen`, `class _DashboardScreenState`
  > Tela da interface — `DashboardScreen`, `_DashboardScreenState`.
- `lib/ui/desktop/screens/detalhe_inventario_screen.dart` — `class DetalheInventarioScreen`, `class _DetalheInventarioScreenState`
  > Tela da interface — `DetalheInventarioScreen`, `_DetalheInventarioScreenState`. Suporta `copyWith`. Serialização JSON/Map. ⚠️ Acessa Firestore diretamente (coleções: inventarios, participantes, estoque) — considere mover para um repositório.
- `lib/ui/diagnostics_page.dart` — `class DiagnosticsPage`, `class _DiagnosticsPageState`
  > Tela da interface — `DiagnosticsPage`, `_DiagnosticsPageState`.
- `lib/ui/first_sync_screen.dart` — `class FirstSyncScreen`
  > Tela da interface — `FirstSyncScreen`.
- `lib/ui/handover_page.dart` — `class HandoverPage`
  > Tela da interface — `HandoverPage`.
- `lib/ui/desktop/screens/historico_screen.dart` — `class HistoricoScreen`, `class _HistoricoScreenState`
  > Tela da interface — `HistoricoScreen`, `_HistoricoScreenState`. ⚠️ Acessa Firestore diretamente (coleções: inventarios) — considere mover para um repositório.
- `lib/ui/home_page.dart` — `class _Lancamento`, `class _Unset`, `class _LancamentoDoc`
  > Tela da interface — `_Lancamento`, `_Unset`. Suporta `copyWith`. ⚠️ Acessa Firestore diretamente (coleções: inventarios, participantes, lancamentos) — considere mover para um repositório.
- `lib/ui/home_page.hive.dart` — `class HomePageHive`, `class _HomePageHiveState`
  > Variante da home page com acesso direto ao Hive (diagnóstico/debug).
- `lib/ui/desktop/screens/importar_estoque_screen.dart` — `class ImportarEstoqueScreen`, `class _ImportarEstoqueScreenState`
  > Tela da interface — `ImportarEstoqueScreen`, `_ImportarEstoqueScreenState`. Suporta `copyWith`.
- `lib/ui/login_page.dart` — `class LoginPage`, `class _LoginPageState`
  > Tela da interface — `LoginPage`, `_LoginPageState`. Suporta `copyWith`.
- `lib/ui/mobile/screens/modo_operacao_screen.dart` — `class ModoOperacaoScreen`, `class _ModoOperacaoScreenState`
  > Tela da interface — `ModoOperacaoScreen`, `_ModoOperacaoScreenState`.
- `lib/ui/desktop/screens/participantes_screen.dart` — `class ParticipantesScreen`, `class _ParticipantesScreenState`
  > Tela da interface — `ParticipantesScreen`, `_ParticipantesScreenState`. Suporta `copyWith`. ⚠️ Acessa Firestore diretamente (coleções: inventarios, participantes) — considere mover para um repositório.
- `lib/ui/mobile/screens/plant_map_page.dart` — `class PlantArea`, `class PlantLayout`, `class PlantMapPage`
  > Tela da interface — `PlantArea`, `PlantLayout`. Serialização JSON/Map.
- `lib/ui/desktop/screens/relatorio_screen.dart` — `class RelatorioScreen`, `class _RelatorioScreenState`
  > Tela da interface — `RelatorioScreen`, `_RelatorioScreenState`. Suporta `copyWith`.

### 🗃️ Adicionar ou modificar campo Hive (dado local)

_Para adicionar um campo:_
1. Adicione `@HiveField(PROXIMO_ID)` + declaração no modelo
2. Atualize o construtor e o `copyWith`
3. Rode: `flutter pub run build_runner build --delete-conflicting-outputs`
4. Atualize `toJson`/`fromJson` se existirem
5. Se já houver dados gravados no dispositivo, considere migração de schema

**Arquivos relevantes:**

- `lib/data/local/app_state.dart` — `class AppState`
  > Modelo Hive (typeId 2) com 10 campos persistidos localmente: lastSyncMateriais, lastSyncBarras, lastSyncGases, lastLogin, lastSyncProdutos.
- `lib/data/local/barra_local.dart` — `class BarraLocal`
  > Modelo Hive (typeId 32) com 4 campos persistidos localmente: tag, codigo, lote, updatedAt.
- `lib/data/local/lanc_local.dart` — `enum LancStatus`, `enum TipoRegistro`, `class LancLocal`
  > Modelo Hive (typeId 41) com 25 campos persistidos localmente: idLocal, uid, codigo, descricao, unidade. Suporta `copyWith`. Serialização JSON/Map.
- `lib/data/local/produto_local.dart` — `class ProdutoLocal`
  > Modelo Hive (typeId 31) com 5 campos persistidos localmente: codigo, descricao, unidade, origem, updatedAt.

### ☁️ Adicionar ou modificar dados no Firestore

_Operações Firestore estão nos repositórios. **Nunca** chame `.collection()` diretamente nas telas — use o repositório correspondente._

**Arquivos relevantes:**

- `lib/data/repositories/barras_repository.dart` — `class BarrasRepository`
  > Repositório Firestore.
- `lib/data/repositories/lancamentos_repository.dart` — `class LancamentosRepository`, `class UserStats`, `class CleanupStats`
  > Repositório Firestore — coleções: lancamentos. Operações: escrita, delete. Suporta `copyWith`. Serialização JSON/Map.
- `lib/data/repositories/produtos_repository.dart` — `class ProdutosRepository`
  > Repositório Firestore — coleções: produtos_manuais. Operações: escrita.

### ⚙️ Modificar lógica de negócio

_Serviços encapsulam regras independentes de UI. Lógica que envolve múltiplos repositórios ou cálculos complexos fica aqui._

**Arquivos relevantes:**

- `lib/services/auth_service.dart` — `class AuthService`
  > Serviço de negócio — expõe: signInWithEmailAndPassword, registerWithEmail, signInWithGoogle, sendPasswordResetEmail().
- `lib/services/comparativo_service.dart` — `class ResultadoComparativo`, `class ResumoComparativo`, `class ItemComparativo`
  > Serviço de negócio — expõe: gerarComparativo, listarInventariosParaComparacao(). ⚠️ Acessa Firestore diretamente (coleções: inventarios, estoque) — considere mover para um repositório.
- `lib/services/connectivity_service.dart` — `class ConnectivityService`
  > Serviço de negócio — expõe: start, stop().
- `lib/services/consolidation_service.dart` — `class ConsolidationService`, `enum OrdenacaoCriterio`, `extension OrdenacaoCriterioLabel`
  > Serviço de negócio — expõe: streamProdutosConsolidados, invalidarCache, calcularBalanco, extrairDivergencias(). Suporta `copyWith`. ⚠️ Acessa Firestore diretamente (coleções: lancamentos, materiais, estoque) — considere mover para um repositório.
- `lib/services/estoque_service.dart` — `class EstoqueService`
  > Serviço de negócio — expõe: importarEstoqueParaInventario, buscarEstoqueInventario, streamEstoqueInventario, buscarItemEstoque(). ⚠️ Acessa Firestore diretamente (coleções: inventarios, estoque, materiais) — considere mover para um repositório.
- `lib/services/excel_parser_service.dart` — `class ParseResult`, `class ItemEstoque`, `class ExcelParserService`
  > Serviço de negócio — expõe: toMap, toString, processarBytes, processarArquivo(). Serialização JSON/Map.
- `lib/services/exportar_excel_service.dart` — `class ExportarExcelService`, `class ExcelColors`
  > Serviço de negócio — expõe: exportarCompleto, exportarDivergencias, exportarFinanceiro().
- `lib/services/inventario_service.dart` — `class InventarioService`
  > Serviço de negócio — expõe: criarInventarioCompleto, criarInventario, buscarInventarioAtivo, buscarInventarioPorId(). ⚠️ Acessa Firestore diretamente (coleções: inventarios, sistema, lancamentos) — considere mover para um repositório.
- `lib/services/mobile_sync_service.dart` — `enum ModoOperacao`, `enum StatusParticipacao`, `class ResultadoSolicitacao`
  > Serviço de negócio — expõe: inicializar, setModoAutonomo, setModoControlado, buscarInventarioAtivo(). ⚠️ Acessa Firestore diretamente (coleções: inventarios, participantes, lancamentos) — considere mover para um repositório.
- `lib/services/relatorio_service.dart` — `class ConstantesFinanceiras`, `class ItemApurado`, `enum StatusApuracao`
  > Serviço de negócio — expõe: toMap, gerarRelatorio, getCodigosDivergentes, marcarDivergenciasParaC3(). Serialização JSON/Map. ⚠️ Acessa Firestore diretamente (coleções: inventarios, estoque, lancamentos) — considere mover para um repositório.
- `lib/services/sync_service.dart` — `class SyncService`
  > Serviço de negócio — expõe: runOnce, schedule, cancel, unawaited(). Serialização JSON/Map. ⚠️ Acessa Firestore diretamente (coleções: lancamentos) — considere mover para um repositório.
- `lib/services/user_service.dart` — `class UserService`
  > Serviço de negócio — expõe: criarPerfil, buscarPerfil, buscarNickname, atualizarPerfil(). ⚠️ Acessa Firestore diretamente (coleções: users) — considere mover para um repositório.

### 📦 Modificar modelo de dados (sem Hive)

_Modelos de domínio usados para trafegar dados entre camadas. Alterações aqui podem exigir atualização de serialização e telas que exibem esses dados._

**Arquivos relevantes:**

- `lib/models/balanco_financeiro.dart` — `class BalancoFinanceiro`, `class BalancoFinanceiroBuilder`
  > Modelo de domínio — `BalancoFinanceiro`, `BalancoFinanceiroBuilder`. Suporta `copyWith`.
- `lib/models/divergencia.dart` — `class Divergencia`, `class DivergenciaLocal`, `enum TipoDivergenciaLocal`
  > Modelo de domínio — `Divergencia`, `DivergenciaLocal`, `TipoDivergenciaLocal`. Suporta `copyWith`.
- `lib/models/inventario.dart` — `enum TipoContagem`, `enum StatusInventario`, `class Inventario`
  > Modelo de domínio — `TipoContagem`, `StatusInventario`, `Inventario`. Suporta `copyWith`. Serialização JSON/Map.
- `lib/models/participante.dart` — `class Participante`
  > Modelo de domínio — `Participante`. Suporta `copyWith`.
- `lib/models/produto_consolidado.dart` — `enum StatusProduto`, `extension StatusProdutoUI`, `class ProdutoConsolidado`
  > Modelo de domínio — `StatusProduto`, `StatusProdutoUI`, `ProdutoConsolidado`. Suporta `copyWith`.
- `lib/models/user_profile.dart` — `class UserProfile`
  > Modelo de domínio — `UserProfile`.

### 🧩 Criar ou modificar componente visual reutilizável

_Widgets reutilizáveis ficam em `lib/ui/widgets/` (globais) ou `lib/ui/desktop/widgets/` / `lib/ui/mobile/widgets/` (específicos de plataforma)._

**Arquivos relevantes:**

- `lib/ui/desktop/widgets/alerta_badge_widget.dart` — `class AlertaBadgeWidget`, `class _AlertaBadgeWidgetState`, `class SimpleBadge`
  > Widget reutilizável — `AlertaBadgeWidget`.
- `lib/ui/desktop/widgets/balanco_summary_widget.dart` — `class BalancoSummaryWidget`, `class _ValorCard`, `class _StatusBadge`
  > Widget reutilizável — `BalancoSummaryWidget`. Suporta `copyWith`.
- `lib/ui/desktop/widgets/divergencia_card_widget.dart` — `class DivergenciaCardWidget`, `class _DivergenciaCardWidgetState`
  > Widget reutilizável — `DivergenciaCardWidget`. Suporta `copyWith`.
- `lib/ui/desktop/widgets/filtros_bar_widget.dart` — `class FiltrosBarWidget`, `class _FiltroChip`
  > Widget reutilizável — `FiltrosBarWidget`.
- `lib/ui/mobile/widgets/inventario_ativo_widget.dart` — `class InventarioAtivoWidget`, `class _InventarioAtivoWidgetState`, `class ModoOperacaoChip`
  > Widget reutilizável — `InventarioAtivoWidget`.
- `lib/widgets/planta_navegador_widget.dart` — `class LocalizacaoSelecionada`, `class PlantaNavegadorWidget`, `class _PlantaNavegadorWidgetState`
  > Widget reutilizável — `LocalizacaoSelecionada`.
- `lib/ui/desktop/widgets/produto_detail_dialog.dart` — `class ProdutoDetailDialog`
  > Widget reutilizável — `ProdutoDetailDialog`. Suporta `copyWith`.
- `lib/ui/desktop/widgets/sidebar_navigation.dart` — `class SidebarNavigation`, `class _MenuItem`, `class _Badge`
  > Componente de navegação lateral do layout desktop.
- `lib/ui/widgets/sync_banner.dart` — `class SyncBanner`
  > Banner de status de sincronização exibido no topo das telas.
- `lib/ui/desktop/widgets/tabela_produtos_widget.dart` — `class TabelaProdutosWidget`, `class _TabelaProdutosWidgetState`
  > Widget reutilizável — `TabelaProdutosWidget`.
- `test/widget_test.dart`
  > Teste de widget padrão gerado pelo Flutter (esqueleto inicial, sem valor real ainda).

### 🔄 Modificar sincronização / comportamento offline

_Lógica de sync entre Hive (local) e Firestore (nuvem). Alterações aqui afetam a confiabilidade offline — teste bem antes de subir._

**Arquivos relevantes:**

- `lib/ui/first_sync_screen.dart` — `class FirstSyncScreen`
  > Tela da interface — `FirstSyncScreen`.
- `lib/services/fixed_collections_sync.dart` — `class FixedCollectionsSync`
  > Sincroniza coleções fixas (produtos, barras) do Firestore para o Hive.
- `lib/services/mobile_sync_service.dart` — `enum ModoOperacao`, `enum StatusParticipacao`, `class ResultadoSolicitacao`
  > Serviço de negócio — expõe: inicializar, setModoAutonomo, setModoControlado, buscarInventarioAtivo(). ⚠️ Acessa Firestore diretamente (coleções: inventarios, participantes, lancamentos) — considere mover para um repositório.
- `lib/services/offline_bootstrap.dart` — `class OfflineBootstrap`
  > Inicialização offline: carrega dados locais do Hive antes da autenticação.
- `lib/ui/widgets/sync_banner.dart` — `class SyncBanner`
  > Banner de status de sincronização exibido no topo das telas.
- `lib/services/sync_diagnostics.dart` — `class SyncDiagnostics`
  > Coleta e expõe métricas de diagnóstico do estado de sincronização.
- `lib/services/sync_service.dart` — `class SyncService`
  > Serviço de negócio — expõe: runOnce, schedule, cancel, unawaited(). Serialização JSON/Map. ⚠️ Acessa Firestore diretamente (coleções: lancamentos) — considere mover para um repositório.

---

_Documentação gerada por `gerar_documentacao.py` v4.0 — 11/04/2026 10:57:44_