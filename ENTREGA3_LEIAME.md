# Entrega 3 (teste acelerado): Monitor mínimo + C3 distribuída e offline

Base: `LEGO_HANDOFF_CLAUDE_ACELERACAO_MONITOR_C3.md` (08/10/2026). Só no LEGO TESTE
(`lego-teste`). Provisório; antes de produção, revisão e endurecimento.
Inclui as Entregas 1 e 2 e o B60.

## O que mudou desde a Entrega 2
| Item do handoff | Onde |
| --- | --- |
| §10–12 Monitor mínimo (dentro do app de teste; regras nos serviços) | `monitor_screen.dart`, `monitor_service.dart` |
| §4–7 C3: "aguardando participantes" → "Estou pronto" → Iniciar C3 congela participantes e distribui | `c3_service.dart`; tela de escolha |
| §6 Distribuição justa (máx − mín ≤ 1, aleatória) | `c3.dart` `distribuirTarefas` |
| §8 Tarefa por linha: responsável, versão, status, atribuída/sincronizada em, resultado | campos `c3_*` em `inventarios/{id}/comparativo/{linha}` |
| §9 Redistribuir só pendentes, versão += 1, recusa de resultado antigo | `redistribuirPendentes`, `motivoRecusaSync` |
| §3, §17 C3 offline: baixar tarefas, concluir sem rede, sincronizar depois; encerrar só com 100% sincronizado | `c3_service.dart`, `c3_screen.dart` (Minhas tarefas C3) |
| §13 / A2 Não encerrar C1/C2 com pendentes locais; segundo nível "Encerrar mesmo assim?" | `MonitorService.encerrarRodada` |
| A1 Divergência original × pendência atual (`pendenteAtual`, `resolvida`); selo "C3 ✓" | `comparativo.dart`, `comparativo_screen.dart` |
| A3 Mesma TAG cheio e vazio na mesma rodada = CONFLITO → força C3 | `comparativo.dart` |
| §15 C3 cega | `c3_screen.dart` (não mostra C1/C2) |
| §16 "NÃO encontrado" conclui a tarefa; final 0; C1/C2 preservados | `TotaisRodada.naoEncontrado`, `origemFinal` |
| §18 Só o responsável, com a versão certa, sincroniza | `motivoRecusaSync` dentro da transação |

## Estados da C3 (`contagens.contagem_3.status`)
`pendente` (comparativo com divergências) → `aguardando_participantes` →
`em_andamento` (participantes congelados em `usuarios`, `c3_versao`) → `encerrada`.
Sem divergências: `nao_necessaria`.

## Firestore (publicar `firestore.rules` só no lego-teste)
- `inventarios/{id}/comparativo/{linha}`: linhas + tarefa C3.
- `inventarios/{id}/c3_participantes/{uid}`: "estou pronto" e progresso do aparelho
  (cada um grava só o seu).

## Arquivos
NOVOS: `lib/services/c3.dart`, `c3_service.dart`, `monitor_service.dart`,
`lib/ui/mobile/screens/monitor_screen.dart`, `test/c3_test.dart` (19 testes).
ALTERADOS: `comparativo.dart`, `comparativo_rodadas_service.dart` (C3 online removida),
`comparativo_screen.dart`, `c3_screen.dart` (reescrita), `modo_operacao_screen.dart`,
`models/inventario.dart` (`StatusRodada.aguardandoParticipantes`),
`test/comparativo_test.dart` (31 testes), `firestore.rules`.
Mantidos da Entrega 2: `home_page.dart` (B60).

## Limites conhecidos (provisório)
- `pendentes_locais` só é conhecido quando o coletor informa (ex.: ao finalizar).
- Distribuição grava as tarefas em lotes depois de marcar a C3 em andamento; se
  falhar no meio, "Redistribuir pendentes" corrige.
- Regras amplas (R14 pendente).

## rev2 (08/10/2026): correções da revisão do ChatGPT

| # | Defeito | Correção |
| --- | --- | --- |
| B61 | Sincronização regravava uma "fotografia" antiga da lista local por cima de tarefas concluídas durante o envio; vários syncs simultâneos | Fila única para toda leitura-modificação-gravação local (`_exclusivo`); sync **single-flight**; cada resposta do servidor é aplicada sobre a lista MAIS RECENTE, só se a tarefa ainda for a mesma conclusão (versão + hora). Sem sync automático a cada tarefa: só pelo botão ou ao abrir a tela. Tela bloqueada durante o envio. Primeira falha de rede encerra a tentativa (sem esperar 15 s por tarefa) |
| B62 | C3 ia para `em_andamento` antes de gravar as tarefas; redistribuição podia reatribuir tarefa recém-sincronizada | Estados de trava `distribuindo` / `redistribuindo`. Iniciar: trava → congela → grava TODAS as tarefas → `em_andamento`. Redistribuir: trava (versão += 1) → **relê** depois da trava só as não sincronizadas → reatribui → `em_andamento`. Durante a trava: não baixa tarefas, e o sync recebe "aguardar" (fica no aparelho, não é recusado). "Retomar distribuição" no monitor se ela parar no meio |
| B63 | Mesma TAG com códigos diferentes podia dar consenso | `TotaisRodada.codigos`; mesma TAG com códigos diferentes entre rodadas ou dentro da rodada → CONFLITO → C3 |
| menor | Participante congelado com zero tarefas sumia do monitor | Monitor lista todos os congelados |

Testes: `c3_test.dart` 21, `comparativo_test.dart` 35.

## Revisão da rev2 (ChatGPT, 08/10/2026)
B61, B62 fechados; B63 fechado quanto à detecção. Aprovado para o primeiro teste integrado.
**B64 (aberto):** o servidor não sabe de tarefa concluída offline e ainda não sincronizada;
"Redistribuir pendentes" pode passá-la a outro operador e o trabalho original será recusado.
**Regra operacional até corrigir:** não usar "Redistribuir pendentes" enquanto algum operador
puder ter tarefas concluídas offline sem sincronizar. Um analista só comanda distribuição.
Não trocar de conta no aparelho durante uma sincronização da C3.

## rev3 (08/10/2026) — B65
O `lib/services/comparativo_service.dart` da Entrega 1 sobrescreveu um arquivo de mesmo nome
que já existia (usado por `ui/desktop/screens/comparativo_inventarios_screen.dart`), gerando
erros no `flutter analyze`. O APK Android não era afetado (tela desktop fora do alvo).
Correção: o serviço novo passa a ser `comparativo_rodadas_service.dart` / `ComparativoRodadasService`;
o `comparativo_service.dart` original deve ser restaurado do git. Sem mudança de comportamento.

## rev4 (08/10/2026) — B66
Logout na tela "Tipo de contagem" não saía (causa exata a confirmar). O botão Sair
(tela de escolha e HomePage) agora isola cada etapa: falha em limparSessao ou no
AuthService.signOut não impede o FirebaseAuth.signOut nem a ida ao /login
(pushNamedAndRemoveUntil). Na tela de escolha, se alguma etapa falhar, um aviso
"Logout com aviso (B66)" mostra o erro real para diagnóstico.

## rev7 (09/10/2026) — L3: três consolidados + C3 por consolidado (substitui rev5/rev6)
Orientação "LEGO_ORIENTACAO_CLAUDE_3_CONSOLIDADOS" + decisão do Djalma (C3 de UM consolidado).

| Consolidado | Origem | Chave | Métrica |
|---|---|---|---|
| MATERIAL | coleção `materiais` | código + lote + local + prateleira | quantidade |
| GÁS | coleção `gases` | código + lote + local | só cheios |
| CILINDRO | coleção `gases` | produto (descrição do gás) + local | cheios + vazios |

- Um lançamento de gás alimenta GÁS e CILINDRO. Ex.: 8+5 × 7+6 → cilindro 13×13 consenso;
  gás 8×7 divergente.
- Natureza pelo cadastro do aparelho (`ProdutosRepository.getByCodigoPreferGases` → origem).
  Sem cadastro: com cheio/vazio = gás; senão material.
- Cilindro (decisão de 09/10): por produto, com a descrição do gás. Não se agrupa
  produtos diferentes numa família física comum. `ClassificadorCilindro` fica como
  ponto de extensão; a regra de produção devolve null (sem correspondência inventada).
- C3: no monitor, o analista escolhe UM consolidado (gás, cilindro ou material) antes de
  "Chamar participantes". Só as divergências dele viram tarefas; as demais recebem
  `c3_fora: true` → resultado "sem C3 (não selecionado)", sem valor final.
  `contagens.contagem_3.natureza` guarda a escolha. Não dá para trocar depois.
- Tela da C3: um campo só — material: quantidade (mostra local e prateleira);
  cilindro: total físico; gás: só cheios. Continua cega e soberana.
- Comparativo: filtro por consolidado; CSV com natureza, local, item, prateleira e métrica.
- Saem as regras por TAG (A3, B63, LOCAL): no modelo por lote/consolidado não se aplicam;
  TAG com código diferente cai em linhas diferentes e diverge naturalmente.
- comparativo_test.dart: 30 testes, todos com a regra de PRODUÇÃO (sem classificador injetado).
- Mantidos: B61, B62, C3 cega, participantes explícitos, distribuição justa, offline,
  versão de atribuição, C3 soberana, não encontrado preserva evidência. B64 segue aberto.
Comparativo gerado antes: "Refazer" no monitor (antes de chamar a C3).

## rev8 (09/10/2026) — revisão da rev7 (ChatGPT) + decisões do Djalma
- B67 retirado: C3 de UM consolidado é decisão de negócio.
- B68 retirado: cilindro = descrição do gás por enquanto. Saiu o aviso "não classificado".
- **B69 corrigido:** encerrar C3 zera `reconciliacao.em_analise` (pendências da C3 escolhida),
  mas grava `reconciliacao.c3_natureza`, `reconciliacao.sem_c3` e
  `reconciliacao.por_natureza.{material|cilindro|gas}` = {divergencias, recontadas,
  resolvidas, sem_c3, selecionada}. Os não escolhidos nunca aparecem como recontados.
- Resultado (tela): "C3 selecionada: GASES" + uma linha por consolidado
  ("Gases: 5 divergência(s) · 5 recontada(s) · 5 resolvida(s)" /
  "Cilindros: 2 divergência(s) · C3 não selecionada").
- CSV: coluna `c3_selecionada`; linhas fora da C3 com origem "sem C3 (não selecionado)"
  e situação `sem_c3`.
- Testes de produção para o cilindro (7, 8, 9 reescritos) + 4 testes de B69.

## rev9 (09/10/2026) — L4: tipo da Contagem Completa escolhido na abertura
Decisão do Djalma: o tipo é definido ANTES da contagem, não no fim.
- Sem inventário ativo, quem toca em C1/C2 escolhe **Materiais, Cilindros ou Gases**
  (diálogo logo após a tela Simples/Completa). Grava `natureza_contagem` no inventário
  ('material' | 'cilindro' | 'gas'). Quem entra depois herda o tipo; o card mostra "Tipo: X".
  Corrida (dois abrindo ao mesmo tempo): vale o do primeiro, e o segundo é avisado.
- Lançamento: Materiais só aceita produtos da coleção `materiais`; Cilindros e Gases só
  `gases` (bloqueio em `_confirmar` e no "vazio por código lido"). A sessão guarda o tipo
  (`SessaoContagem.natureza`), então vale offline. Cadastro manual de produto sem
  cadastro: não bloqueado nesta versão.
- Comparativo: só o consolidado do tipo. C3 automática: o monitor mostra
  "Inventário de X: N divergência(s)" e "Chamar participantes", sem escolha.
- Inventário antigo (sem tipo): continua como na rev8 (três consolidados + escolha no fim).
- Arquivos novos no pacote: inventario_service.dart, mobile_sync_service.dart,
  sessao_contagem.dart. comparativo_test.dart: 35 testes (5 de L4).
- **Para testar: cancele/encerre o inventário de teste atual** e abra um novo, escolhendo o tipo.

## rev10 (09/10/2026) — revisão da rev9 (ChatGPT) + ressalva do Djalma
- **L5:** Gases e Cilindros têm a mesma coleta (cheios + vazios) e geram OS DOIS
  comparativos. O tipo escolhido na abertura define só o que vai para a C3:
  Gases → C3 de Gases (Cilindros fica informativo); Cilindros → C3 de Cilindros
  (Gases informativo). Materiais continua só Materiais. (`consolidadosDoTipo`)
- C3 necessária só se houver divergência do consolidado do tipo; `reconciliacao.em_analise`
  conta só essas, e `reconciliacao.divergencias_informativas` guarda as do outro.
- B70 retirado como bloqueio de interface (o Vazio continua). Defensivo no comparador:
  lançamento só de vazios não cria linha de gás com zero.
- **B71:** cadastro manual bloqueado na Contagem Completa com tipo (Simples continua).
- **B72:** cabeçalho "Inventário 002 | Gases | C1 | Em andamento".
- comparativo_test.dart: 40 testes.

## rev11 (09/10/2026) — revisão da rev10 (ChatGPT)
- **B73:** inventário com tipo → as divergências do outro consolidado já são gravadas com
  `c3_fora: true` no `gerarComparativo` (`marcarForaDaC3`). Valem como "sem C3 /
  informativo" mesmo se a C3 for não necessária; nunca "pendente na C3".
  `chamarParticipantes` continua regravando de forma idempotente.
- **B74:** mensagem do monitor: "N para a C3 · M informativa(s)".
- **B75:** `chamarParticipantes` recusa natureza diferente do tipo do inventário.
- Tela: linha informativa mostra "C3: fora (informativo)".
- comparativo_test.dart: 44 testes (4 de B73).

## rev12 (09/10/2026) — item 4 (falha grave apontada pelo Djalma)
- As tarefas C3 guardadas no aparelho ficavam para sempre no login ("Minhas tarefas C3").
  Agora, depois de cada leitura do servidor na tela de escolha, elas são descartadas
  se o inventário delas não for mais o ativo (encerrado/cancelado/substituído) ou se a
  C3 dele não estiver mais aberta (encerrada / não necessária).
  Offline nada é apagado. Regra pura `tarefasLocaisAindaValidas` (c3.dart).

## rev13 (09/10/2026) — pontos do Djalma após o 1º teste integrado
Substitui o rev12 (que só tinha o item 4).
1. **Painel do analista redesenhado:** etapas (C1 e C2 → Comparativo → C3 → Final); cada
   bloco com estado, QUEM está nele e uma ação principal. Sem botão atualizar (streams +
   contagem de lançamentos renovada a cada 20 s). "Redistribuir pendentes" virou exceção
   (botão vermelho com aviso B64). Cancelar inventário no menu ⋮.
2. **Relatório .xlsx no formato do modelo** (relatorio_lego.xlsx): abas C1 Lançamentos,
   C1 Consolidado, C2 Lançamentos, C2 Consolidado, C3, Final (Gases/Cilindros: uma aba
   de consolidado e uma Final por consolidado). A tela "Relatório" mostra as MESMAS abas
   (mesmo montador), com exportar .xlsx.
   - Materiais: Código, Descrição, Quantidade, Prateleira (chave código + prateleira).
   - Gases: Código, Descrição, Lote, Cilindros cheios, Volume contado, Localização
     (chave código + lote + localização; volume = cheios × volume unitário do cadastro).
   - Cilindros: Código, Descrição, Cheios, Vazios, Localização (código + localização).
   - Final = fechadas (C1 = C2) + resolvidas na C3. Informativas só na aba C3.
3. **C3:** a lista de itens fica; tocar abre a TELA PADRÃO de lançamento (_FormPane) com
   código, descrição, lote, prateleira e localização preenchidos e travados. Editáveis:
   Cheio e Vazio (Gases/Cilindros) ou Quantidade (Materiais). O Enter grava e encerra o
   item. Só na C3 vale 0 e 0 (= não encontrado, com confirmação).
4. **C3 não fica no login:** tarefas descartadas quando a C3/inventário acabou (rev12) e
   ao "Finalizar minha C3".
5. Painel mostra, em C1, C2 e C3, cada pessoa: em andamento ou finalizou.
6. **Sincronização automática / finalizar com 100%:**
   - C1/C2: "Finalizar minha contagem" desabilitado com "Sincronizando · faltam N";
     lançamento com erro bloqueia e avisa.
   - C3: sincroniza ao gravar cada item, quando a rede volta e a cada 20 s. "Finalizar
     minha C3" só habilita com todos os itens sincronizados; marca o participante como
     finalizado no servidor e limpa o aparelho. Tarefas são baixadas sozinhas quando a
     C3 começa; a tela de escolha se atualiza sozinha enquanto a C3 espera o analista.
- Item 8 (painel só para o analista no mobile) fica para depois dos testes.
- Testes: comparativo_test 49, c3_test 24, relatorio_test 10 (novo).

## rev14 (09/10/2026) — revisão da rev13 (ChatGPT)
- **B76:** ao voltar da lista da C3, a tela de escolha relê tudo (inclusive "finalizei?")
  e `baixarMinhasTarefas` recusa quem já finalizou a própria C3.
- **B77:** participante congelado que recebeu 0 itens vê "Você não recebeu itens nesta C3"
  e "Finalizar minha C3". O servidor confirma (C3 em andamento, eu participante, nenhuma
  linha atribuída a mim) antes de marcar finalizado (`podeFinalizarSemTarefas`).
- **B78:** ignorado por decisão do Djalma — "não encontrado" na C3 entra no Final como zero.
- **B79:** "Redistribuir pendentes" não entrega tarefas a quem já finalizou.
- Fechamento global da C3 segue exigindo 100% das tarefas sincronizadas (não exige que
  todos toquem em "Finalizar minha C3").
- c3_test.dart: 28 testes (4 de B77).

## rev15 (09/10/2026) — B80
- `HiveBoxes.closeUserLancamentos` buscava a caixa sem o tipo (`Hive.box(name)`), e o Hive
  recusava ("already open and of type Box<LancLocal>"). O logout seguia (B66), mas a caixa
  ficava aberta. Agora `Hive.box<LancLocal>(name).close()`. Só `lib/data/local/hive_boxes.dart`.

## Desktop D16 (09/10/2026) — LEGO TESTE no Windows
- O Windows não usa `--flavor`. O ambiente é fixado pelo ponto de entrada (D16-1,
  revisão ChatGPT): `lib/main_desktop.dart` = produção (comando de sempre);
  `lib/main_desktop_teste.dart` = teste. Nenhum parâmetro de build decide.
- Os dois passam pelos mesmos portões do celular antes do login: opções conferidas
  (projeto + appId do app Windows), Firebase iniciado, projeto/appId conferidos de novo.
  Divergência → tela "Build desktop inconsistente", sem login.
- No teste: faixa laranja fixa no topo ("LEGO TESTE · ambiente de teste"), tema laranja.
- Sessão salva de outro projeto (prod e teste no mesmo PC) é descartada na abertura.
- `firebase_options_teste.dart` ganhou `windows` (app Web "LEGO Desktop Teste" do
  lego-teste, appId `1:155608278634:web:6ebbd7c38e1e0a7ae5cc13`); `ambiente.dart` ganhou `appIdEsperadoDesktop` e o
  parâmetro `appIdExigido` nos portões.
- lego-teste: `sistema/app_config.versao_minima_desktop = "1.3.7"`.
- ambiente_test.dart: +10 testes (D16, estado configurado: provas positivas e negativas).

## D17 (09/10/2026) — painel do analista no desktop
- Nova seção **Inventário Completo** no topo da barra lateral do desktop (abre direto
  nela). Esquerda: etapas e ações (C1, C2, Comparativo, C3, Final, com quem está em
  andamento/finalizou). Direita: relatório em abas (igual ao .xlsx), recarregado
  sozinho quando a etapa muda e a cada item da C3 sincronizado; botão de recarga
  manual e "Exportar .xlsx" com janela "Salvar como". Topo: seletor (ativo + Completos
  recentes) e "Cancelar inventário (teste)" no menu ⋮.
- UM código para celular e desktop: `lib/ui/analista/painel_analista.dart` (antes no
  MonitorScreen) e `lib/ui/analista/relatorio_view.dart` (antes no ComparativoScreen).
  As telas do celular viraram cascas finas; comportamento igual.
- Telas legadas do desktop (Painel, Controle, Participantes, Relatórios, Histórico,
  Comparativo) intactas; na seção Completo somem o chip legado e "Novo Inventário".
- `InventarioService.listarCompletosRecentes` (orderBy data_inicio, filtro local).
- `RelatorioInventarioService.gerar` (bytes) separado de `exportar` (arquivo no celular).
- rev1: tabelas do relatório com barras de rolagem sempre visíveis, arrasto com o mouse
  e colunas esticando até a largura da área; botão "Relatório em tela cheia" no desktop
  (esconde as etapas; "Mostrar etapas" volta).

## Operacional — parte 1 (09/10/2026, noite)
- **Encerrar inventário:** botão no card "Resultado final" (desktop e celular) quando a
  C3 terminou (ou não foi necessária). Status vira Encerrado e a trava do Completo é
  liberada para o próximo. Usa `encerrarInventarioCompleto` (pendências conferidas).
- **Item 8:** `sistema/app_config.analistas` (lista de e-mails) define o analista.
  Celular: botão "Abrir monitor do analista" só para quem está na lista. Desktop: seção
  Inventário Completo mostra "Acesso exclusivo do analista" para os demais.
  Lista ausente/vazia = ninguém (falha fechada). `lib/services/analista.dart` (regra pura,
  test/analista_test.dart) e `analista_service.dart`.
- **Gates de teste removidos:** a C3 do operador e o painel deixam de depender de
  `ambienteAtual == teste`. A tela já só existe com o fluxo 2 ligado (em produção exige
  `LEGO_FLUXO2` e `LEGO_FLUXO2_PRODUCAO`). Caixa da C3 com título neutro; some quando o
  operador não tem nada da C3 a fazer.
- "Cancelar inventário (teste)" → "Cancelar inventário" (ação do analista, aviso de que
  o normal é "Encerrar inventário").
- **Antes de testar:** no lego-teste, `sistema/app_config` → campo `analistas` (array)
  com `d6gz41@linde.com`.

## Operacional — parte 2 (09/10/2026, noite): regras do Firestore
- `analista()` = e-mail do token em `sistema/app_config.analistas` (minúsculas).
- **Inventário do fluxo 2** (`fluxo_versao >= 2`):
  - update: analista; o operador só pode se incluir em `contagens.contagem_1|2.usuarios`
    e passar a rodada de `disponivel` → `em_andamento` (entrada na C1/C2);
  - delete: só analista;
  - create: qualquer autenticado (o operador abre o Completo).
- **comparativo:** create/delete só analista; update = analista, ou o operador gravando
  o resultado da tarefa da C3 que é DELE (só os campos `c3*` do resultado, status
  `sincronizada`).
- **participantes (fluxo 2):** cada um o próprio; o analista, qualquer um.
- **sistema/contadores:** liberar a trava (encerrar/cancelar) só analista; criar o
  próximo Completo continua com qualquer autenticado.
- **Legado (fluxo 1): regras de antes, sem mudança.**
- Publicar primeiro no **lego-teste**. Em produção, só depois do teste.
- OP1 rev1 (tempo real no desktop): a lista de inventários escuta a trava
  (`sistema/contadores`) — Completo aberto no celular aparece e é selecionado sozinho;
  encerrado/cancelado atualiza a lista.
- Lançamentos por pessoa (painel, celular e desktop) e abas de lançamentos do relatório
  em TEMPO REAL por escuta do Firestore (antes: releitura total a cada 20 s). Custo: a
  carga inicial e 1 leitura por lançamento novo. O relatório relê do cache local (custo
  zero), agrupando o que chega em 5 s.
- **Contagem Simples no desktop** (seção nova, 2ª da barra lateral, só analista):
  período (padrão: hoje) e operador; abas Lançamentos (formato do modelo) + Consolidado
  Materiais / Gases / Cilindros (as que tiverem linhas, mesmas chaves do Completo);
  tempo real; Exportar .xlsx ("Salvar como"). Consulta: `lancamentos` com
  `inventarioId == ''` no período → **índice composto: lancamentos (inventarioId ↑,
  createdAt ↓)** no lego-teste e no murilo (o erro na tela traz o link para criar).

## Revisão OP1+OP2 (ChatGPT, 10/10) — OP3
- **B81:** `_RelatorioAoLadoState` sem `initState` (LateInitializationError ao abrir o
  Inventário Completo no desktop). Corrigido.
- **B81-A:** "é analista" em cache por no máximo 2 min.
- Contagem Simples: filtro de operador por **uid** (nome só como rótulo; nomes repetidos
  ganham o início do uid).
- **B82 (regras):** lançamento do fluxo 2 só é criado/alterado/apagado com o inventário
  ativo e a rodada dele em andamento; `uid`, `inventarioId` e `contagemId` imutáveis no
  update. Simples e legado como antes. Efeito: lançamento feito offline e sincronizado
  depois do encerramento da rodada é recusado (fica com erro no aparelho) — coerente com
  o aviso A2 de pendentes ao encerrar.
- **B83:** resultado da C3 só com a C3 em andamento.
- **B84:** entrada na C1/C2 não remove ninguém de `usuarios`, não põe o mesmo uid nas
  duas rodadas, `iniciada_em` só na abertura; `rodada_base` do participante imutável;
  participante do fluxo 2 só é apagado pelo analista.
- **B85:** a trava do Completo só é ocupada se estiver livre ou órfã (inventário
  apontado inexistente ou não ativo).
- **OP3 rev1 — B86 (revisão OP3):** lançamento do fluxo 2 exige também que o uid esteja
  em `contagens.<rodada>.usuarios`, que o participante tenha `rodada_base` = a rodada e
  `status_c1|c2 = em_andamento` (quem finalizou a própria contagem não lança mais).
- B87 (trava + inventário com getAfter), B88 (versão da tarefa C3 nas regras) e allowlist
  de campos do participante: registrados para depois do piloto (ver resposta à revisão).

## C3 — TAG e OS (10/10, noite)
- Tela de lançamento da C3 (gás/cilindro) com duas abas, como na C1/C2:
  - **TAG:** leitura sequencial; cada TAG válida = 1 cilindro cheio, acumulando
    ("N TAGs lidas"). Descartadas com o alerta sonoro: TAG de outro produto, TAG de
    outro lote (só na divergência de gás, que é por lote), TAG não encontrada e TAG já
    lida no item. "Desfazer a última TAG".
  - **Código:** cheio/vazio digitados (vazios e contagem à mão).
  - Resultado: cheios = TAGs + cheios digitados; vazios = digitados.
- **Concluir item** fecha e grava (Enter no último campo também). Zero pede confirmação.
- **OS travada** na C3 (novo `osEnabled` no formulário; nas outras contagens nada muda).
- Sair do item com TAGs lidas sem concluir pede confirmação.
- Material: sem aba TAG, só a quantidade.
- **Mapa com alfinete (C3):** no quadro "Divergência em (fixada)", "Ver no mapa" (ou
  tocar no quadro) abre a planta já com zoom na área da divergência e um **alfinete
  vermelho** no centro dela, só para visualizar (sem seleção). Botão de alfinete na barra
  re-centraliza. A área é achada pelo `id` no JSON das áreas: áreas novas inseridas no
  JSON passam a ter alfinete sozinhas; área sem desenho no mapa mostra aviso na barra.
  `PlantMapPage(destaqueAreaId: ...)`; sem o parâmetro, a seleção de área é a de sempre.

## C3 TAG rev1 (10/10) — revisão do ChatGPT

- B89: leitura automática aos 9 dígitos (150 ms), mesma regra da C1/C2; Enter é gatilho extra.
- B90: Gás compara sempre lote da TAG == lote da divergência, inclusive a linha sem lote. Cilindro não restringe lote.
- B91: duplicidade pela forma canônica (sem zeros à esquerda) da chave que resolveu na base. "033661401" e "33661401" contam uma vez.
- B92: leituras em fila (uma por vez, nenhuma se perde; o campo é liberado na hora). "Concluir item" e "Desfazer" ficam bloqueados enquanto há TAG em leitura ("Lendo TAG…"). TAG incompleta no campo também impede concluir.
- Aba Código da C3: `soCodigo: true` (sem o campo Tag duplicado).
- Sair durante a gravação: bloqueado.
- Mapa: `mounted` conferido após carregar o JSON.

## C3 rev2 (10/10) — B93: C3 travada após "distribuição mudou"

- Causa: redistribuição (versão 1 → 2) com o item ainda do mesmo operador. O resultado da versão 1 foi recusado, o aparelho tratou "recusado" como concluído e liberou "Finalizar minha C3" com 0 de 1 sincronizado. Finalizado não baixa mais tarefas (B76) nem recebe na redistribuição (B79) → C3 sem saída.
- Correção 1: depois de uma recusa, o aparelho rebaixa a lista. Item que continua dele volta para "a contar" na versão nova; item que foi para outro operador segue recusado.
- Correção 2: "Finalizar minha C3" confere no servidor; com item dele ainda sem resultado, não finaliza.

## C3 rev3 (10/10) — B96

- B96: sem deslizar entre abas em nenhuma contagem (C1/C2 e C3). Troca de aba só tocando na aba.
- Lógica da TAG na C3 mantida (rev1): só TAG do produto e do lote procurados; outro lote/produto e TAG repetida no item são descartados com sino; cada TAG = 1 cheio, somada na conclusão.

## Mapa rev4 (10-11/10) — áreas em círculo e giradas

- JSON de áreas aceita `"forma": "circulo"` (x/y/w/h = quadrado que envolve o círculo). Sem o campo = retângulo, como antes.
- O mapa desenha o círculo e o toque só seleciona dentro dele.
- Toque sobre áreas sobrepostas: ganha a menor (uma área dentro de outra continua selecionável).
- JSON aceita `"rot"` (graus, sentido horário, em torno do centro) para retângulos girados; x/y/w/h são o retângulo antes de girar. O mapa desenha, seleciona e enquadra a área girada; o nome acompanha o giro.
- O JSON é gerado pelo "Editor de Áreas da Planta" (artifact). O LEGO original ainda não lê `forma` nem `rot`: lá um círculo aparece como quadrado e uma área girada aparece reta.
