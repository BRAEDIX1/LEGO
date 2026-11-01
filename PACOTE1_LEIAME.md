# LEGO TESTE — Pacote 1 (rev4): fila offline + registro de erros do Desktop

**Data:** 01/11/2026
**Base:** branch `teste-c3`, commit `b8794ee`
**Ambiente:** só o LEGO TESTE e o `lego-teste`. A produção não é alterada: APK, Firebase `murilo`, regras de produção e dados históricos ficam como estão.


## Revisão rev4 (01/11/2026)

| # | Pedido | O que mudou |
|---|---|---|
| 1 | Entrega confirmada ≠ escrita que excedeu o tempo | `FirestoreCanalStatusSync.gravar` devolve `EntregaInforme.confirmada` **só** quando o servidor respondeu dentro do prazo. Se o tempo esgota, devolve `semConfirmacao`, porque a escrita pode continuar na fila do SDK. `StatusSyncAparelho.publicar` devolve `ResultadoPublicacao`: `confirmado`, `semConfirmacao`, `semConexao`, `semMudanca` ou `falhou`. Sem confirmação, nada é registrado como entregue e a próxima execução informa de novo, com base nova. Teste: T-SYNC-018 "gravação sem resposta do servidor não conta como entrega" |
| 2 | Teste integrado mais rígido e encerramento real | `encerramento_recusa_firestore_test.dart` agora **exige** a cópia em `lancamentos_recuperacao` no servidor (`get` do servidor, com `inventarioId`, `operacao` e `motivo_codigo`). `permission-denied` reprova. Também passou a encerrar pelo **serviço real do Desktop** (`MonitorService.encerrarRodada`): (a) o aparelho publica o informe com entrega confirmada; (b) o encerramento normal é **recusado** por pendência conhecida (`PendentesLocaisException`); (c) o encerramento excepcional, com motivo, encerra a C1 e grava a **auditoria**, conferida no servidor: `eventos` com `tipo = rodada_encerrada`, `forcado = true`, o motivo e a lista de pendências. **Pré-requisito:** regras do Pacote 1 publicadas **só no `lego-teste`** e conta analista |
| 3 | Limpeza documentada | Ver a seção abaixo. As regras não foram flexibilizadas |

### Limpeza dos registros dos testes (só no `lego-teste`)

Os testes integrados apagam o que as regras do app permitem: o inventário de teste, os lançamentos dele, o participante e o lançamento do teste de tempo esgotado. **Ficam no `lego-teste`, de propósito:**

| Coleção / documento | Por que fica | Como identificar |
|---|---|---|
| `lancamentos_recuperacao/{uid}_ITC_<hora>` | A regra impede apagar pelo app (evidência) | `inventarioId` começa com `IT_PACOTE1_`; `codigo = IT-TESTE` |
| `inventarios/IT_PACOTE1_<hora>/eventos/*` | A auditoria só aceita inclusão. A subcoleção continua existindo depois que o documento do inventário é apagado | Caminho com `IT_PACOTE1_` |
| `sync_status/{uid}` e `relogio_servidor/{uid}` da conta de teste | São o estado atual da conta e serão sobrescritos no próximo uso | Id = uid da conta de teste |

**Como limpar**, quando quiser, sem mexer nas regras:
1. Use o **console do Firebase, projeto `lego-teste`**: Firestore → localizar pelos ids acima → excluir o documento (ou a coleção `eventos` do inventário `IT_PACOTE1_...`). O console age como administrador e não passa pelas regras do app.
2. Alternativa pela linha de comando, com o login do próprio usuário (sem JSON de conta de serviço) e **sempre com o projeto explícito**:
   `firebase firestore:delete "inventarios/IT_PACOTE1_<hora>" --recursive --project lego-teste`
3. **Nunca no `murilo-21h52m` (produção).** Os testes integrados abortam se o projeto não for `lego-teste`.

Arquivos alterados na rev4: `status_sync_aparelho.dart`, `integration_test/encerramento_recusa_firestore_test.dart`, `test/sincronizacao_test.dart` e este LEIAME.

## Revisão rev3 (01/11/2026)

| # | Pedido | O que mudou |
|---|---|---|
| 1 | Emissão inicial do painel | `observarPendencias` emite o retrato **assim que alguém escuta**, sem depender de mudança no Hive, e depois segue observando. Erro de leitura sai como erro do stream e a escuta continua. A tela trata o erro: para de carregar e mostra a falha. Teste novo **T-SYNC-017**: abrir com pendências antigas sem nenhuma alteração posterior, e erro de leitura seguido de recuperação |
| 2 | Atualidade dos informes | **Problema:** um `sync_status` enfileirado offline chega depois com `atualizado_em` recente. **Solução:** antes de montar o informe, o aparelho faz um **pulso** no servidor (`relogio_servidor/{uid}` com `serverTimestamp`, relido do servidor) e grava essa hora em `base_servidor`. O conteúdo é sempre produzido **depois** da base. **Sem pulso (offline), o aparelho não informa**: nada fica na fila para chegar velho. O Desktop mede a idade como hora do servidor agora (por um pulso do próprio Desktop) menos `base_servidor`. O relógio do aparelho e o do computador não entram na decisão. Informe sem `base_servidor` (formato antigo) conta como **antigo**. Informe que chegou mais de 2 min depois da base conta como **atrasado**: o aparelho ficou offline depois de conferir. Nos dois casos a pendência fica desconhecida e o encerramento normal continua protegido. Testes novos em **T-SYNC-018**: informe de 40 min entregue agora, reconexão com 4,5 min de atraso, relógio do aparelho errado, sem base, e `publicar` sem rede (não grava) e com rede (grava com a base, com conteúdo lido depois dela) |
| 3 | Validação do cenário completo | Novo `integration_test/encerramento_recusa_firestore_test.dart`, contra o `lego-teste`, num **inventário de teste criado e apagado pelo próprio teste** (`IT_PACOTE1_<hora>`). Não usa inventários existentes nem `sistema/contadores`. Roteiro: (1) lançamento enviado; (2) escrita que excede o tempo e chega ao servidor; (3) encerramento da C1 pelo analista; (4) a regravação recusada é reconhecida como já sincronizada; (5) lançamento depois do encerramento é recusado em definitivo e fica no aparelho, vai à Recuperação, e o reenvio manual **não** grava na coleção oficial; (6) limpeza. **Exige:** conta **analista** do `lego-teste` e, para a Recuperação, as regras do Pacote 1 publicadas no `lego-teste`. Sem regras, o teste registra a recusa da Recuperação em vez de falhar. Rodar com o Desktop fechado: o inventário de teste existe por alguns segundos |

**Regra nova (só acréscimo):** `relogio_servidor/{uid}`. Cada usuário grava só o próprio documento, e apenas `em == request.time`.

**Limites documentados:**
- **Testes integrados:** precisam de rede, de conta do `lego-teste` (analista, no teste de encerramento) e rodam no Windows. Não fazem parte do `flutter test` comum.
- **Desktop:** sem pulso (offline), não avalia pendências e, portanto, não encerra pelo caminho normal.
- **Cópia na Recuperação:** fica no `lego-teste`, porque a regra impede apagar.

**Comandos dos testes integrados** (Windows):
```
flutter test integration_test/sync_timeout_firestore_test.dart -d windows --dart-define=LEGO_TESTE_EMAIL=<email> --dart-define=LEGO_TESTE_SENHA=<senha>
flutter test integration_test/encerramento_recusa_firestore_test.dart -d windows --dart-define=LEGO_TESTE_EMAIL=<email-analista> --dart-define=LEGO_TESTE_SENHA=<senha>
```

Arquivos novos na rev3: `integration_test/encerramento_recusa_firestore_test.dart`.
Arquivos alterados na rev3: `observador_pendencias.dart`, `pendencias_sync_screen.dart`, `status_sync_aparelho.dart`, `acompanhamento_sync_service.dart`, `monitor_service.dart`, `painel_analista.dart`, `firestore.rules` e `test/sincronizacao_test.dart`.

**Validação da rev3: NÃO EXECUTADA neste ambiente** (não há Flutter aqui). `flutter analyze`, `flutter test test/sincronizacao_test.dart`, `flutter test` e os dois testes integrados precisam rodar na máquina do Djalma antes de pedir a liberação. Não publicar regras em produção e não gerar APK de distribuição.

## Revisão rev2 (01/11/2026): pendências da revisão da rev1

| # | Pedido | O que mudou |
|---|---|---|
| 1 | Zero confirmado ≠ informação ausente | O `sync_status` passa a ter `formato: 2` e `escopos_verificados`: os escopos que o aparelho conferiu (tem lançamento dele, a sessão ativa do Completo, ou exclusão classificada nele), **inclusive com zero pendências**. `avaliarPendenciasEncerramento` só aceita "sem pendência" para quem está em andamento quando o informe é recente **e** lista o inventário + rodada em `escopos_verificados`. Informe recente sem esse escopo, ou em formato antigo, vira `escopoNaoConfirmado` e bloqueia, como pendência desconhecida |
| 2 | Exclusões antigas sem escopo | O motor tenta identificar o escopo lendo o documento oficial antes de apagar (guarda em `sync_meta`). Identificado: a exclusão conta no escopo dela. Não identificado: vai para o escopo `nao_classificado`, **sem presumir a rodada atual**. No encerramento, pendência não classificada aparece como **"NÃO CLASSIFICADA — decisão do analista"** e bloqueia, inclusive para quem já finalizou (a finalização só conferiu o escopo da rodada). Seguir exige o encerramento excepcional, com motivo e auditoria |
| 3 | `delete_pending` atualiza o painel | Quem grava a lista (o repositório no caminho legado e o motor) avisa o painel com `avisarMudancaExclusoesLegadas`. Como rede de segurança, o painel confere a lista a cada 5 s |
| 4 | LEIAME e testes | O nome do zip foi corrigido. Testes novos: **T-SYNC-011** (informe sem o escopo, formato antigo, não classificada mesmo finalizado); **T-SYNC-014** (escopo da exclusão identificado, e não classificada sem leitura); **T-SYNC-015** (painel atualiza com mudança em SharedPreferences, com e sem aviso); **T-SYNC-016** (escrita que excedeu o tempo, mas chegou) |
| — | Achado ao analisar o timeout | O tempo esgotado da Future **não cancela** a escrita já enfileirada pelo SDK. Se ela chega ao servidor e a rodada é encerrada depois, a regravação seguinte seria recusada (update de rodada encerrada) e o registro ficaria marcado como "rejeitado" sem ter sido. **Correção:** numa recusa definitiva, o motor lê o documento oficial. Se é igual ao do aparelho, o registro já estava lá e fica sincronizado, sem ir à Recuperação. Na exclusão, se o documento não existe mais, a exclusão está feita (as regras recusam apagar documento inexistente) |
| — | Teste integrado com o Firestore real | `integration_test/sync_timeout_firestore_test.dart`, que roda no Windows contra o `lego-teste`: desliga a rede do SDK, o motor desiste por tempo esgotado, liga a rede, confirma no **servidor** que a escrita chegou, e o motor reconcilia sem duplicar. Aborta se o projeto não for `lego-teste` e apaga o próprio registro no fim. Precisa de uma conta de teste (ver abaixo) |

**Comando do teste integrado** (Windows, conta de teste do `lego-teste`):
```
flutter test integration_test/sync_timeout_firestore_test.dart -d windows --dart-define=LEGO_TESTE_EMAIL=<email> --dart-define=LEGO_TESTE_SENHA=<senha>
```

Arquivos novos na rev2: `integration_test/sync_timeout_firestore_test.dart`.
Arquivos alterados na rev2: `pubspec.yaml` (`integration_test` como dependência de desenvolvimento), `registro_sync.dart`, `pendencias_sync.dart`, `observador_pendencias.dart`, `motor_sincronizacao.dart`, `status_sync_aparelho.dart`, `acompanhamento_sync_service.dart`, `lancamentos_repository.dart` e `test/sincronizacao_test.dart`.

**Validação da rev2: NÃO EXECUTADA neste ambiente** (não há Flutter aqui). `flutter analyze`, o conjunto completo, `test/sincronizacao_test.dart` e o teste integrado precisam rodar na máquina do Djalma. Não publicar regras e não gerar APK de distribuição antes disso.

## Revisão rev1 (01/11/2026): ajustes pedidos na revisão

| # | Pedido | O que mudou |
|---|---|---|
| 1 | Recusa definitiva não pode voltar à coleção oficial | No `MotorSincronizacao`, um registro recusado em definitivo **nunca** é reenviado a `lancamentos` pelo aparelho, nem no envio automático, nem no reenvio manual, nem se a rodada for reaberta. O reenvio devolve `rejeitadoNaoReenviado`. **Reenvio** (falhas de rede e passageiras, que vão à coleção oficial) e **Recuperação administrativa** (`SyncService.recuperar`, que só garante a cópia em `lancamentos_recuperacao`) agora são ações separadas, com botões separados no painel. Erro antigo cujo texto é de recusa de permissão vira recusa definitiva, sem reenvio. Exclusão recusada também não é tentada de novo e vai à Recuperação como `operacao: exclusao` |
| 2 | Encerramento usando `sync_status` e a idade do informe | `MonitorService.encerrarRodada` passa a ler também `sync_status` (no servidor) e usa `avaliarPendenciasEncerramento`. **Pendência conhecida** em qualquer fonte bloqueia, valendo a maior quantidade entre o aparelho e o participante. **Em andamento sem informe**, ou com informe de mais de 15 min, é "pendência desconhecida" e também bloqueia: não conta como zero. Quem finalizou já provou zero pendência. O diálogo mostra cada caso com a idade da informação, e a auditoria grava a lista. Sem pendências, o encerramento segue como antes. O coletor renova o informe a cada 5 min, ou na hora quando algo muda |
| 3 | Painel atualiza quando só o `sync_meta` muda | Fonte nova `observarPendencias` (`observador_pendencias.dart`), que escuta a caixa dos lançamentos **e** a caixa `sync_meta_<uid>`. Motivo, tentativas, última e próxima tentativa e Recuperação aparecem com a tela aberta |
| 4 | `delete_pending` antigo (SharedPreferences) | **Verificado:** `LancamentosRepository.delete` (caminho legado) gravava as exclusões remotas que falhavam em `delete_pending`, e **nada processava essa lista**, nem o `SyncService` antigo. O novo `SyncService` não eliminou nenhum procedimento existente: passa a concluir as exclusões do usuário logado com as mesmas regras de falha. As de outros usuários continuam na lista até eles entrarem no aparelho. Exclusão recusada fica na lista, visível, e vai à Recuperação com o documento oficial anexado. O painel, o CSV e o informe ao Desktop mostram essas exclusões |
| 5 | Testes | **T-SYNC-010:** reenvio manual depois de recusa definitiva e reabertura (nenhuma escrita oficial), e erro antigo de permissão. **T-SYNC-011:** encerramento com pendência conhecida, sem informe, informe antigo, finalizado e outro escopo. **T-SYNC-012:** painel atualiza com falha registrada só no metadado. **T-SYNC-013:** exclusões antigas concluídas, sem rede, recusadas e de outro usuário. T-SYNC-002 e T-SYNC-005 foram ajustados à regra do item 1 |
| 6 | Validação | **Não executada neste ambiente:** não há Flutter aqui. `flutter analyze`, o conjunto completo e `test/sincronizacao_test.dart` precisam rodar na máquina do Djalma. **Não publicar as regras e não gerar o APK definitivo de teste.** |

Arquivos novos na rev1: `lib/services/sincronizacao/observador_pendencias.dart`.
Arquivos alterados na rev1: `motor_sincronizacao.dart`, `pendencias_sync.dart`, `status_sync_aparelho.dart`, `registro_sync.dart`, `sync_service.dart`, `pendencias_sync_screen.dart`, `acompanhamento_sync_service.dart`, `monitor_service.dart`, `painel_analista.dart` e `test/sincronizacao_test.dart`.

## 1. Causa do incidente (provada no código antigo)

1. **Registro com erro ficava preso para sempre.** Uma falha no envio, como oscilação de rede ou cota esgotada, marcava o lançamento como `error`. O `SyncService` só reenviava `pending`, e o botão de status do registro com erro ficava desabilitado.
2. **O operador não conseguia sair do impasse.** O botão "Finalizar minha contagem" desabilitava com qualquer erro e mostrava "N com erro: corrija". Mas era justamente a finalização que devolvia os erros para a fila, então o registro nunca voltava. Também não havia tela que dissesse quais registros estavam presos nem por quê.
3. **A fila podia travar.** Um envio sem resposta prendia a trava da fila até o app ser reiniciado, e os demais registros não saíam.
4. **Encerramento forçado bloqueia a sincronização para sempre (resposta à investigação).** As regras B82/B86 exigem a rodada `em_andamento` e a participação aberta para criar, alterar ou apagar o lançamento. Depois do encerramento, o servidor recusa definitivamente (`permission-denied`) qualquer lançamento daquela rodada que ainda estiver no aparelho. Isso protege a evidência congelada e não foi alterado. Antes deste pacote, esses registros ficavam no aparelho como erro, sem caminho de recuperação. Agora vão para a Recuperação (seção 2).

## 2. O que muda

### Coletor

| Item do pedido | Como ficou |
|---|---|
| 2. Reenvio automático sem duplicar | O documento remoto continua `lancamentos/{uid}_{idLocal}` (gravação com `set` + `merge`), então não há duplicidade. **Falha de rede** (`unavailable`, `deadline-exceeded`, `unauthenticated`, tempo esgotado, sem conexão): o registro continua pendente e o aparelho tenta sozinho, sem limite, esperando de 30 s a 10 min. Quando a conexão volta, tenta na hora. **Falha passageira** (`resource-exhausted`, `aborted`, `internal`...): até 8 tentativas automáticas, esperando de 1 a 60 min; depois disso, só por reenvio manual. **Erro antigo sem motivo** (registros de antes deste pacote): volta para a fila uma vez, sozinho |
| Erro definitivo | `permission-denied`, `invalid-argument` e similares: o registro sai da fila automática, **fica no aparelho** com o motivo e uma cópia vai para a Recuperação |
| Envio sem resposta | Cada operação tem limite de 20 s. Se o tempo esgota, a rodada de envio para (o resto fica para a próxima) e a trava é liberada |
| 1 e 4. Painel de diagnóstico | Tela nova **"Pendências de envio"**, aberta pelo ícone de nuvem na barra (com contador) ou pelo botão de finalizar quando há pendência. Lê só o Hive, então **funciona sem internet**. Para cada registro mostra situação, produto, código, lote, TAG, área, quantidades, data, hora, id local, contagem, tentativas, próxima tentativa e motivo. Segurando o item, abre o histórico de tentativas |
| 3. Reenvio manual | Por registro, pelos selecionados ou de todos, com o resultado de cada um (enviado, sem conexão, passageira, rejeitado) |
| 4. Exportação | CSV (separador `;`, abre no Excel) salvo no aparelho |
| 6. Motivo de cada falha | Situação atual na caixa Hive `sync_meta_<uid>` e histórico de tentativas na caixa `sync_log_<uid>` (até 3.000 eventos). O `LancLocal` não muda de formato |
| 8. Recuperação | Recusa definitiva → cópia em `lancamentos_recuperacao/{uid}_{idLocal}`, enviada uma única vez (o app confere no servidor antes). Leva os dados do lançamento, o id local, o motivo e a hora da recusa. **Não entra no resultado do inventário.** O registro local nunca é apagado |
| Finalizar participação (Completo) | Passa a reenviar **tudo** do escopo, inclusive os registros com erro, pelo motor, que registra o motivo de cada falha. A regra de finalizar continua a mesma: só com zero não sincronizados |

### Desktop

| Item | Como ficou |
|---|---|
| Registro persistente de erros (P0-06) | O app passa a ter tratadores globais (`FlutterError.onError`, `PlatformDispatcher.onError` e zona protegida) gravando em `<pasta de suporte do app>\logs\lego_erros.log`, com troca de arquivo ao passar de 2 MB. Na faixa laranja do teste, o link "Log de erros" abre a pasta |
| 5. Indicadores por operador | O coletor transmite um resumo em `sync_status/{uid}`: contagens por situação e por contagem, até 50 itens detalhados, último sucesso, última falha e hora do informe. **Painel do Completo:** cada pessoa da C1/C2 mostra "aparelho: N pendente(s), N com erro, N rejeitado(s) (informado HH:MM)". **Contagem Simples:** faixa com quem ainda tem lançamentos não enviados. O Desktop mostra **só o que o aparelho transmitiu**; o que está apenas no Hive de um aparelho offline não aparece |
| 7. Encerramento forçado | Continua possível, mas exige **motivo**, com no mínimo 10 caracteres. A auditoria (`eventos`) registra o motivo e, para cada operador, a quantidade de pendências informadas. O diálogo explica que nada é apagado dos aparelhos. Quem pode encerrar e quando não mudou |
| 8. Recuperação | Cartão novo **"Recuperação"** no painel do Completo, com os recusados que chegaram (fora do resultado) e exportação para .xlsx |

### Regras (`firestore.rules`) — **publicar só no `lego-teste`**

Só **acréscimos**, sem mexer nas regras existentes:
- `sync_status/{uid}`: cada operador grava o próprio documento; o analista lê.
- `lancamentos_recuperacao/{docId}`:
  - o operador cria a própria cópia (id `<uid>_<idLocal>`) e pode conferir se ela existe;
  - ninguém apaga;
  - o analista lê e só altera os campos `analise_*`.

## 3. Arquivos

**Novos**
- `lib/services/sincronizacao/falha_sync.dart`: classificação das falhas e espera entre tentativas.
- `lib/services/sincronizacao/motor_sincronizacao.dart`: motor de envio e Recuperação.
- `lib/services/sincronizacao/pendencias_sync.dart`: visão das pendências e CSV.
- `lib/services/sincronizacao/status_sync_aparelho.dart`: informe ao Desktop.
- `lib/data/local/registro_sync.dart`: estado e histórico no Hive.
- `lib/ui/mobile/screens/pendencias_sync_screen.dart`: painel do coletor.
- `lib/services/acompanhamento_sync_service.dart`: leitura no Desktop.
- `lib/services/registro_erros.dart`: log de erros do Desktop.
- `test/sincronizacao_test.dart`: testes T-SYNC-001 a 009.
- `PACOTE1_LEIAME.md`: este arquivo.

**Alterados**
- `lib/services/sync_service.dart`: passa a delegar ao motor e ganha `reenviar` e `reenviarEscopo`.
- `lib/services/connectivity_service.dart`: quando a conexão volta, tenta na hora.
- `lib/services/mobile_sync_service.dart`: a finalização reenvia o escopo pelo motor, e a mensagem aponta para o painel.
- `lib/data/repositories/lancamentos_repository.dart`: novos `listarTodos`, `obter`, `definirStatus` e `mudancas`.
- `lib/ui/home_page.dart`: ícone "Pendências de envio" e botão de finalizar que abre o painel.
- `lib/main_desktop.dart`: zona protegida, tratadores de erro e link do log.
- `lib/services/monitor_service.dart`: motivo obrigatório no encerramento forçado e detalhe na auditoria.
- `lib/ui/analista/painel_analista.dart`: informe do aparelho por pessoa, diálogo do encerramento forçado e cartão Recuperação.
- `lib/ui/desktop/screens/contagem_simples_screen.dart`: faixa de pendências informadas.
- `firestore.rules`: acréscimos da seção 2.

## 4. Testes (`test/sincronizacao_test.dart`)

- **T-SYNC-001:** classificação (rede, passageira, definitiva) e espera entre tentativas.
- **T-SYNC-002, incidente ponta a ponta:**
  1. lançamento local;
  2. falha de rede (continua pendente, com motivo e próxima tentativa);
  3. identificação individual no painel;
  4. sem insistir antes da hora;
  5. registro em erro no esquema antigo;
  6. reconexão, que reenvia tudo **sem duplicar**;
  7. encerramento excepcional (servidor recusa → rejeitado, registro local mantido);
  8. cópia na Recuperação uma vez só;
  9. sem insistência automática;
  10. reenvio manual posterior com resultado por registro;
  11. histórico com motivo.
- **T-SYNC-003:** falha passageira esgota as tentativas automáticas, e o reenvio manual envia.
- **T-SYNC-004:** tempo esgotado não prende a fila nem a trava.
- **T-SYNC-005:** exclusão recusada continua exclusão e não ressuscita.
- **T-SYNC-006:** Recuperação sem rede fica registrada e sai depois.
- **T-SYNC-007:** uma execução por vez; a manual espera a vez.
- **T-SYNC-008:** CSV e informe ao Desktop.
- **T-SYNC-009:** na Contagem Simples, erro antigo volta sozinho para a fila.

## 5. Como aplicar e testar (PowerShell, `C:\LEGO_TESTE`)

As saídas vão para `Desktop\pacote1`, fora do repositório.

**5.1 Conferir e marcar o ponto de retorno**
```
cd C:\LEGO_TESTE
git branch --show-current      # tem de ser: teste-c3
git rev-parse --short HEAD     # tem de ser: b8794ee
git status --short             # só as alterações de assets/ já conhecidas
git tag pre-pacote1 b8794ee
New-Item -ItemType Directory -Force "$env:USERPROFILE\Desktop\pacote1" | Out-Null
```
Se a branch ou o commit forem outros, pare.

**5.2 Aplicar**
```
Expand-Archive -Path "$env:USERPROFILE\Downloads\LEGO_PACOTE1_rev4_FILA_OFFLINE.zip" -DestinationPath "C:\LEGO_TESTE" -Force
git status --short             # os 24 arquivos do pacote + assets/
flutter pub get
```

**5.3 Análise e testes de unidade**
```
$o = "$env:USERPROFILE\Desktop\pacote1"
flutter analyze                                   *> "$o\1_analyze.txt"
flutter test test/sincronizacao_test.dart -r expanded *> "$o\2_test_sync.txt"
flutter test                                      *> "$o\3_test_todos.txt"
```
Esperado: `No issues found!` e `All tests passed!` nos dois testes. Se algo falhar, envie os três arquivos. Não corrija à mão.

**5.4 Commit só do pacote** (nunca `git add -A`)
```
git add PACOTE1_LEIAME.md firestore.rules pubspec.yaml integration_test test/sincronizacao_test.dart lib/data/local/registro_sync.dart lib/data/repositories/lancamentos_repository.dart lib/main_desktop.dart lib/services/acompanhamento_sync_service.dart lib/services/connectivity_service.dart lib/services/mobile_sync_service.dart lib/services/monitor_service.dart lib/services/registro_erros.dart lib/services/sincronizacao lib/services/sync_service.dart lib/ui/analista/painel_analista.dart lib/ui/desktop/screens/contagem_simples_screen.dart lib/ui/home_page.dart lib/ui/mobile/screens/pendencias_sync_screen.dart
git status --short             # assets/ continua fora do commit
git commit -m "Pacote 1 rev4: fila offline, pendencias e Recuperacao"
git rev-parse --short HEAD     # anote: é o <commit do Pacote 1> da seção 7
```
Se `flutter pub get` alterou o `pubspec.lock`, inclua também o `pubspec.lock`.

**5.5 Publicar as regras, só no `lego-teste`** (Console do Firebase)
1. Abra o Console e confira **duas vezes**: o nome do projeto no topo é `lego-teste` e o endereço contém `/project/lego-teste/`. Se aparecer `murilo-21h52m`, pare.
2. Abra Firestore Database → Regras. Copie as regras publicadas para `Desktop\pacote1\regras_antes.txt`. Essa é a cópia de reversão.
3. Compare com a versão de antes do pacote: `git show pre-pacote1:firestore.rules > "$o\regras_repo_antes.txt"` e depois `fc.exe "$o\regras_antes.txt" "$o\regras_repo_antes.txt"`.
   - **Iguais:** cole o `firestore.rules` inteiro do repositório.
   - **Diferentes:** não cole o arquivo inteiro. Cole só o bloco `// ===== Pacote 1 ... FIM Pacote 1 =====` antes das duas `}` finais e me envie a diferença.
4. Clique em Publicar e anote a data e a hora.

**5.6 Testes integrados (Windows, Firestore real do `lego-teste`)**
Antes de rodar: o Desktop LEGO fechado e uma conta **analista** do `lego-teste`. A senha é lida sem ficar no histórico.
```
$env:LT_EMAIL = Read-Host "email"
$env:LT_SENHA = Read-Host "senha"
flutter test integration_test/sync_timeout_firestore_test.dart -d windows --dart-define=LEGO_TESTE_EMAIL=$env:LT_EMAIL --dart-define=LEGO_TESTE_SENHA=$env:LT_SENHA *> "$o\4_it_timeout.txt"
flutter test integration_test/encerramento_recusa_firestore_test.dart -d windows --dart-define=LEGO_TESTE_EMAIL=$env:LT_EMAIL --dart-define=LEGO_TESTE_SENHA=$env:LT_SENHA *> "$o\5_it_encerramento.txt"
Remove-Item Env:LT_SENHA
```
Os dois testes abortam se o projeto não for `lego-teste`. Se aparecer `permission-denied`, o teste reprova: as regras da 5.5 não estão publicadas.

**5.7 Builds de teste**
```
flutter build apk --flavor homolog --dart-define=LEGO_FLUXO2=true
flutter build windows -t lib/main_desktop_teste.dart
```
**Sem `--flavor homolog` o APK sai de PRODUÇÃO.** Instale o APK só no seu aparelho de teste e não o publique em release do GitHub.

## 6. Validação prática, com duas contas

Use a **conta A**, de operador, no Android (APK homolog) e a **conta B**, de analista, no Desktop teste. As duas são do `lego-teste`. Faça print de cada passo marcado com 📷.

| # | Onde | Ação | Esperado |
|---|---|---|---|
| 1 | A | Contagem Simples com rede: lance 3 itens | Nuvem com ✓. "Pendências de envio" vazio |
| 2 | B | Contagem Simples | Os 3 itens aparecem e não há faixa de pendência 📷 |
| 3 | A | Modo avião: lance 2 itens | Contador 2. O painel lista produto, código, lote, área, quantidade, data, hora e id local 📷. Exporte o CSV |
| 4 | B | Contagem Simples | Mostra o último informe de A, sem os 2 itens: o Desktop só vê o que o aparelho transmitiu |
| 5 | A | Rede de volta | Os 2 itens saem sozinhos em até ~30 s e o contador zera |
| 6 | B | Crie um inventário de TESTE (C1) com A na rodada | — |
| 7 | A | Lance 1 item na C1 com rede, depois 2 em modo avião | Painel: 2 pendentes na C1 |
| 8 | B | **Espere 16 min** com A em modo avião e encerre a C1 normalmente | **Recusado**: A aparece com "informe antigo" 📷 |
| 9 | B | Encerre à força | O motivo é exigido (mín. 10 caracteres). Encerra. O evento `rodada_encerrada` tem `forcado`, `motivo` e `pendencias` 📷 |
| 10 | B | Anote os totais da C1 | Resultado oficial **R** |
| 11 | A | Rede de volta | Os 2 itens ficam "Rejeitado pelo servidor", continuam no aparelho e mostram "Cópia na Recuperação (data hora)", enviada automaticamente 📷 |
| 12 | A | Toque em "Reenviar" num rejeitado | Não regrava na coleção oficial. Mostra o resultado da tentativa |
| 13 | A | "Enviar rejeitados à Recuperação" | A cópia não duplica: o histórico registra "já estava na Recuperação". Se no passo 11 aparecer "Recuperação: <erro>", este passo a envia 📷 |
| 14 | B | Cartão "Recuperação" do inventário | Os 2 itens aparecem com o motivo. Exporte o xlsx 📷 |
| 15 | B | Totais da C1 | **Iguais a R**: a Recuperação não entra no resultado oficial |
| 16 | A | Histórico de um item | Cada tentativa aparece com a hora e o código do erro |
| 17 | B | "Log de erros" na faixa laranja | A pasta abre com `lego_erros.log` |

**Por que esperar 16 min no passo 8:** o aparelho offline não consegue mandar informe. Até o último informe ficar antigo (15 min), o Desktop só conhece o "zero pendente" que A mandou com rede e não tem como saber dos 2 itens que estão só no Hive. Encerrar antes disso pode ser aceito. É o limite já previsto: o Desktop só vê o que o aparelho transmitiu.

Os passos 7 a 15 reproduzem o incidente: a participação individual fica bloqueada depois do encerramento. Se o resultado de algum passo for diferente do esperado, anote o número do passo e o que apareceu.

Limpeza: veja a seção "Limpeza dos registros dos testes". Faça sempre no `lego-teste`.

## 7. Desfazer

O pacote é aditivo. Desfaça na ordem: primeiro as regras, depois o código.

**Regras (`lego-teste`).** No Console, com o projeto `lego-teste` conferido, há dois caminhos:
- republicar o conteúdo de `Desktop\pacote1\regras_antes.txt`, que é a cópia da 5.5;
- ou remover do editor os **três** `match` do bloco "Pacote 1":
  1. `match /sync_status/{uid}`;
  2. `match /lancamentos_recuperacao/{docId}`;
  3. `match /relogio_servidor/{uid}`.

Depois, publique. As demais regras não mudam. Os documentos já gravados nessas três coleções continuam no banco: sem as regras, o app não os lê nem grava. Para apagá-los, veja a seção "Limpeza dos registros dos testes".

**Código.** `git revert <commit do Pacote 1>`, usando o hash anotado na 5.4. Esse comando cria um commit que desfaz o pacote, mantém o histórico e não toca nas alterações de `assets/`. `git reset --hard pre-pacote1` também volta ao ponto de partida, mas descarta tudo o que não estiver commitado. Use-o só com a árvore limpa. As caixas Hive `sync_meta_*` e `sync_log_*` podem ficar no aparelho, porque o código antigo as ignora.

## 8. O que não foi validado aqui

- **Não compilei nem rodei testes:** neste ambiente não há Flutter. Fiz a revisão manual do código e conferi as APIs dos pacotes nas versões travadas no `pubspec.lock` (`excel` 4.0.6, `file_picker` 8.3.7). A validação é o `flutter analyze` e o `flutter test` na máquina do Djalma.
- O comportamento real do Firestore offline no Android (fila interna do SDK) só se confirma em campo, no roteiro da seção 6.
- Medições de desempenho (Fase 4) ainda não foram feitas. Este pacote só instala o log.

## 9. Relatório de execução (preencher)

| Etapa | Resultado | Evidência |
|---|---|---|
| 5.1 branch/commit/tag | | |
| 5.3 `flutter analyze` | | `1_analyze.txt` |
| 5.3 `test/sincronizacao_test.dart` | __ passou / __ falhou | `2_test_sync.txt` |
| 5.3 `flutter test` (todos) | __ passou / __ falhou | `3_test_todos.txt` |
| 5.4 commit do pacote | hash: | |
| 5.5 regras no lego-teste | data/hora: | `regras_antes.txt` |
| 5.6 IT timeout | | `4_it_timeout.txt` |
| 5.6 IT encerramento | | `5_it_encerramento.txt` |
| 6 passos 1–17 | divergências: | prints |

O Pacote 1 só é homologado com todas as linhas preenchidas e sem divergência.
