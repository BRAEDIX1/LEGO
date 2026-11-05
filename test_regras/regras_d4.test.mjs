// test_regras/regras_d4.test.mjs
//
// D4 revisto (05/11/2026): a mesma pessoa pode contar C1 e C2, nunca ao
// mesmo tempo. Testa o ../firestore.rules REAL no emulador local.
//
// Projeto "demo-lego-regras": o emulador roda offline e NÃO acessa o
// lego-teste nem a produção. Nada é publicado.
//
// Rodar (nesta pasta):  npm install   e depois   npm test
//
// As escritas imitam o que o app grava em InventarioService.entrarNaRodada
// (participante com merge + update do inventário, no mesmo lote) e em
// lançamentos de Contagem Completa.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  arrayUnion,
  collection,
  doc,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

const INV = 'INV_D4';
const C1 = 'contagem_1';
const C2 = 'contagem_2';
const ANALISTA = 'analista@teste.com';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-lego-regras',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
});

// ---------- cenário ----------

/** Grava o estado inicial sem regras (como o analista/app teriam deixado). */
async function cenario({ c1, c2, participantes = {} }) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'sistema/app_config'), { analistas: [ANALISTA] });
    await setDoc(doc(db, `inventarios/${INV}`), {
      fluxo_versao: 2,
      status: 'em_andamento',
      natureza_contagem: 'material',
      contagens: {
        contagem_1: c1,
        contagem_2: c2,
        contagem_3: { status: 'pendente', usuarios: [] },
      },
    });
    for (const [uid, dados] of Object.entries(participantes)) {
      await setDoc(doc(db, `inventarios/${INV}/participantes/${uid}`), {
        uid,
        displayName: uid,
        ...dados,
      });
    }
  });
}

const operador = (uid) =>
  env.authenticatedContext(uid, { email: `${uid}@teste.com` }).firestore();

/**
 * O que o app grava ao entrar numa rodada (entrarNaRodada): participante
 * (merge) + inventário + evento de auditoria, no mesmo lote. Primeira
 * entrada na rodada.
 */
function entrar(db, uid, rodada, { abrir = false, gravarBase = false } = {}) {
  const sufixo = rodada === C1 ? 'c1' : 'c2';
  const lote = writeBatch(db);
  const participante = {
    uid,
    displayName: uid,
    ultimo_acesso: serverTimestamp(),
    [`status_${sufixo}`]: 'em_andamento',
    [`iniciou_${sufixo}_em`]: serverTimestamp(),
    [`total_lancamentos_${sufixo}`]: 0,
  };
  if (gravarBase) participante.rodada_base = rodada;
  lote.set(doc(db, `inventarios/${INV}/participantes/${uid}`), participante, {
    merge: true,
  });
  const inv = { [`contagens.${rodada}.usuarios`]: arrayUnion(uid) };
  if (abrir) {
    inv[`contagens.${rodada}.status`] = 'em_andamento';
    inv[`contagens.${rodada}.iniciada_em`] = serverTimestamp();
  }
  lote.update(doc(db, `inventarios/${INV}`), inv);
  // Trilha de auditoria, como no app (AuditEventService).
  lote.set(doc(collection(db, `inventarios/${INV}/eventos`)), {
    tipo: 'participante_entrou',
    ts: serverTimestamp(),
    uid,
    rodada,
    dados: {},
  });
  return lote.commit();
}

/** Só a inclusão na lista `usuarios` (sem mexer no status). */
const incluirNaLista = (db, uid, rodada) =>
  updateDoc(doc(db, `inventarios/${INV}`), {
    [`contagens.${rodada}.usuarios`]: arrayUnion(uid),
  });

const lancar = (db, uid, rodada, id) =>
  setDoc(doc(db, `lancamentos/${id}`), {
    uid,
    inventarioId: INV,
    contagemId: rodada,
    codigo: 'MAT-100',
    quantidade: 1,
  });

// Estados das rodadas usados nos cenários.
const aberta = (usuarios = []) => ({ status: 'em_andamento', usuarios });
const disponivel = () => ({ status: 'disponivel', usuarios: [] });
const encerrada = (usuarios = []) => ({ status: 'encerrada', usuarios });

// ---------- 1. C2 antes do encerramento da C1 ----------

describe('1. entrada na C2 antes do encerramento da C1', () => {
  test('C1 em andamento, C2 disponível: recusada', async () => {
    await cenario({
      c1: aberta(['uA']),
      c2: disponivel(),
      participantes: { uA: { rodada_base: C1, status_c1: 'em_andamento' } },
    });
    await assertFails(entrar(operador('uA'), 'uA', C2, { abrir: true }));
  });

  test('C1 e C2 em andamento: recusada', async () => {
    await cenario({
      c1: aberta(['uA']),
      c2: aberta(['uB']),
      participantes: { uA: { rodada_base: C1, status_c1: 'em_andamento' } },
    });
    await assertFails(entrar(operador('uA'), 'uA', C2));
  });

  test('entrar nas duas de uma vez (ninguém estava): recusada', async () => {
    await cenario({ c1: aberta(), c2: aberta() });
    const db = operador('uB');
    await assertFails(
      updateDoc(doc(db, `inventarios/${INV}`), {
        'contagens.contagem_1.usuarios': arrayUnion('uB'),
        'contagens.contagem_2.usuarios': arrayUnion('uB'),
      }),
    );
  });
});

// ---------- 2. C2 depois do encerramento da C1 ----------

describe('2. entrada na C2 após o encerramento da C1', () => {
  test('C1 encerrada, C2 disponível: permitida (abre a C2)', async () => {
    await cenario({
      c1: encerrada(['uA']),
      c2: disponivel(),
      participantes: { uA: { rodada_base: C1, status_c1: 'finalizado' } },
    });
    await assertSucceeds(entrar(operador('uA'), 'uA', C2, { abrir: true }));
  });

  test('C1 encerrada, C2 em andamento: permitida, lança na C2 e não na C1',
    async () => {
      await cenario({
        c1: encerrada(['uA']),
        c2: aberta(['uB']),
        participantes: { uA: { rodada_base: C1, status_c1: 'finalizado' } },
      });
      const db = operador('uA');
      await assertSucceeds(entrar(db, 'uA', C2));
      await assertSucceeds(lancar(db, 'uA', C2, 'L_C2'));
      await assertFails(lancar(db, 'uA', C1, 'L_C1')); // C1 congelada
    });

  test('simétrico: C2 encerrada libera a C1', async () => {
    await cenario({
      c1: aberta(['uB']),
      c2: encerrada(['uA']),
      participantes: { uA: { rodada_base: C2, status_c2: 'finalizado' } },
    });
    await assertSucceeds(entrar(operador('uA'), 'uA', C1));
  });

  test('retomada: já nas duas (C1 encerrada) volta para a C2', async () => {
    await cenario({
      c1: encerrada(['uA']),
      c2: aberta(['uA']),
      participantes: {
        uA: { rodada_base: C1, status_c1: 'finalizado', status_c2: 'em_andamento' },
      },
    });
    const db = operador('uA');
    await assertSucceeds(incluirNaLista(db, 'uA', C2));
    await assertSucceeds(lancar(db, 'uA', C2, 'L_RET'));
  });

  test('lançar na C2 exige a C1 (rodada_base) encerrada', async () => {
    // Estado que o operador não consegue criar sozinho (lista da C2 montada
    // sem regras): mesmo assim, com a C1 aberta, o lançamento é recusado.
    await cenario({
      c1: aberta(['uA']),
      c2: aberta(['uA']),
      participantes: {
        uA: { rodada_base: C1, status_c1: 'em_andamento', status_c2: 'em_andamento' },
      },
    });
    await assertFails(lancar(operador('uA'), 'uA', C2, 'L_X'));
  });
});

// ---------- 3. inclusão direta numa rodada encerrada ----------

describe('3. inclusão direta de usuário numa rodada encerrada', () => {
  test('usuário novo se inclui na C1 encerrada: recusada', async () => {
    await cenario({ c1: encerrada(['uA']), c2: aberta(['uC']) });
    await assertFails(incluirNaLista(operador('uB'), 'uB', C1));
  });

  test('usuário novo se inclui na C2 encerrada: recusada', async () => {
    await cenario({ c1: aberta(['uA']), c2: encerrada(['uC']) });
    await assertFails(incluirNaLista(operador('uB'), 'uB', C2));
  });

  test('quem está na C1 encerrada se inclui na C2 também encerrada: recusada',
    async () => {
      await cenario({
        c1: encerrada(['uA']),
        c2: encerrada(['uC']),
        participantes: { uA: { rodada_base: C1, status_c1: 'finalizado' } },
      });
      await assertFails(incluirNaLista(operador('uA'), 'uA', C2));
    });

  // Sem regressão: entrada e retomada em rodadas abertas.
  test('usuário novo entra na C1 em andamento: permitida', async () => {
    await cenario({ c1: aberta(['uA']), c2: disponivel() });
    await assertSucceeds(
      entrar(operador('uB'), 'uB', C1, { gravarBase: true }),
    );
  });

  test('primeiro a entrar na C2 disponível (abre a rodada): permitida',
    async () => {
      await cenario({ c1: aberta(['uA']), c2: disponivel() });
      await assertSucceeds(
        entrar(operador('uB'), 'uB', C2, { abrir: true, gravarBase: true }),
      );
    });

  test('retomada na C1 em andamento (já na lista): permitida', async () => {
    await cenario({
      c1: aberta(['uA']),
      c2: disponivel(),
      participantes: { uA: { rodada_base: C1, status_c1: 'em_andamento' } },
    });
    await assertSucceeds(incluirNaLista(operador('uA'), 'uA', C1));
  });

  test('não inclui outra pessoa na lista: recusada', async () => {
    await cenario({ c1: aberta(['uA']), c2: disponivel() });
    await assertFails(incluirNaLista(operador('uA'), 'uZ', C1));
  });
});

// ---------- 5. finalização individual sem encerramento global ----------

describe('5. finalizar a própria C1 sem encerramento global', () => {
  test('participação da C1 finalizada, C1 em andamento: C2 bloqueada',
    async () => {
      await cenario({
        c1: aberta(['uA', 'uB']),
        c2: aberta(['uC']),
        participantes: {
          uA: {
            rodada_base: C1,
            status_c1: 'finalizado',
            finalizado_por_c1: 'usuario',
          },
        },
      });
      const db = operador('uA');
      await assertFails(entrar(db, 'uA', C2));
      await assertFails(lancar(db, 'uA', C2, 'L_F'));
    });

  test('C2 disponível também continua bloqueada', async () => {
    await cenario({
      c1: aberta(['uA']),
      c2: disponivel(),
      participantes: { uA: { rodada_base: C1, status_c1: 'finalizado' } },
    });
    await assertFails(entrar(operador('uA'), 'uA', C2, { abrir: true }));
  });
});
