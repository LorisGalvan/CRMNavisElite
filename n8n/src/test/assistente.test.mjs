// Prova la logica dei nodi Code senza n8n. Uso: npm test (dentro n8n/)
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'workflows');
const carica = (inizio) => JSON.parse(fs.readFileSync(path.join(DIR, fs.readdirSync(DIR).find((f) => f.startsWith(inizio))), 'utf8'));
const WF = carica('01');
const PROM = carica('02');

// Esegue un nodo Code con $json/$input e gli output di altri nodi
async function esegui(wf, nodo, { input = [], dati = {} } = {}) {
  const n = wf.nodes.find((x) => x.name === nodo);
  assert.ok(n, `nodo ${nodo}`);
  const items = input.map((json) => ({ json }));
  const $ = (nome) => {
    const v = (dati[nome] || []).map((json) => ({ json }));
    return { first: () => v[0], all: () => v, item: v[0] };
  };
  const $input = { all: () => items, first: () => items[0] };
  const fn = new Function('$', '$input', '$json', `return (async () => {\n${n.parameters.jsCode}\n})();`);
  return (await fn($, $input, items[0]?.json)).map((i) => i.json);
}

const CFG = { supabase_url: 'https://x.supabase.co', modello: 'claude-opus-5-5', effort: 'low', modello_trascrizione: 'whisper-1' };
const CTX = {
  collegato: true, nome: 'Paolo', ruolo: 'collaboratore', puo_scrivere: true, oggi: '2026-10-26',
  settori: [{ id: 's1', nome: 'Immobiliare' }],
  persone: [{ id: 'p1', nome: 'Marco Rossi' }, { id: 'p2', nome: 'Anna Verdi' }],
  relazioni: [], trattative: [{ id: 't1', titolo: 'Villa Lesmo' }], attivita: [],
};

test('riconosce vocale, testo e pulsante', async () => {
  const voce = await esegui(WF, 'Tipo di messaggio', { dati: { Telegram: [{ message: { chat: { id: 42 }, voice: { file_id: 'F1' } } }] } });
  assert.deepEqual(voce, [{ _dest: 'vocale', chat_id: '42', file_id: 'F1' }]);
  const testo = await esegui(WF, 'Tipo di messaggio', { dati: { Telegram: [{ message: { chat: { id: 42 }, text: ' Chi non sento da 3 mesi? ' } }] } });
  assert.equal(testo[0].testo_utente, 'Chi non sento da 3 mesi?');
  const btn = await esegui(WF, 'Tipo di messaggio', { dati: { Telegram: [{ callback_query: { id: 'q', data: 'ok:abc', message: { chat: { id: 42 } } } }] } });
  assert.deepEqual(btn[0], { _dest: 'pulsante', chat_id: '42', query_id: 'q', comando_id: 'abc', conferma: true });
  assert.deepEqual(await esegui(WF, 'Tipo di messaggio', { dati: { Telegram: [{ edited_message: {} }] } }), []);
});

test('/collega: comando valido, sbagliato ed esito', async () => {
  const tg = (text) => ({ Telegram: [{ message: { chat: { id: 1 }, text } }] });
  const ok = await esegui(WF, 'Tipo di messaggio', { dati: tg('/collega Enrico.Berte@gmail.com 777') });
  assert.deepEqual(ok[0], { _dest: 'collega', chat_id: '1', email: 'enrico.berte@gmail.com', codice: '777' });
  const ko = await esegui(WF, 'Tipo di messaggio', { dati: tg('/collega enrico') });
  assert.match(ko[0].errore, /\/collega email codice/);
  const r1 = await esegui(WF, 'Esito collegamento', { input: [{ ok: true, messaggio: 'Telegram collegato a Enrico Bertelli' }], dati: { 'Tipo di messaggio': [ok[0]] } });
  assert.match(r1[0].testo, /Enrico Bertelli/);
  const r2 = await esegui(WF, 'Esito collegamento', { input: [{}], dati: { 'Tipo di messaggio': [ko[0]] } });
  assert.match(r2[0].testo, /Scrivi così/);
});

test('unisce il testo trascritto o scritto', async () => {
  const v = await esegui(WF, 'Unisci testo', { input: [{ text: ' ciao ' }], dati: { 'Tipo di messaggio': [{ _dest: 'vocale', chat_id: '42' }] } });
  assert.equal(v[0].testo_utente, 'ciao');
  const t = await esegui(WF, 'Unisci testo', { input: [{}], dati: { 'Tipo di messaggio': [{ _dest: 'testo', chat_id: '42', testo_utente: 'x' }] } });
  assert.equal(t[0].testo_utente, 'x');
});

test('utente non collegato riceve il suo codice', async () => {
  const r = await esegui(WF, 'Prepara richiesta Claude', { input: [{ collegato: false }], dati: { IMPOSTAZIONI: [CFG], 'Unisci testo': [{ chat_id: '42', testo_utente: 'x' }] } });
  assert.equal(r[0]._dest, 'rispondi');
  assert.match(r[0].testo, /42/);
});

test('prepara la richiesta a Claude con i soli dati visibili', async () => {
  const r = await esegui(WF, 'Prepara richiesta Claude', { input: [CTX], dati: { IMPOSTAZIONI: [CFG], 'Unisci testo': [{ chat_id: '42', testo_utente: 'Ho chiamato Marco' }] } });
  const q = r[0].richiesta_claude;
  assert.equal(r[0]._dest, 'claude');
  assert.equal(q.model, 'claude-opus-5-5');
  assert.equal(q.fallbacks, 'default');
  assert.deepEqual(q.output_config, { effort: 'low' });
  assert.match(q.messages[0].content, /Marco Rossi/);
  assert.match(q.messages[0].content, /Ho chiamato Marco/);
});

const claude = (obj, extra = {}) => ({ content: [{ type: 'thinking', thinking: '' }, { type: 'text', text: JSON.stringify(obj) }], stop_reason: 'end_turn', ...extra });
const richiesta = { chat_id: '42', testo_utente: 'x', persone: { p1: 'Marco Rossi', p2: 'Anna Verdi' }, trattative: { t1: 'Villa Lesmo' }, puo_scrivere: true };

test('propone le azioni con un riepilogo leggibile', async () => {
  const r = await esegui(WF, 'Leggi azioni', {
    input: [claude({ azioni: [
      { tipo: 'registra_contatto', persona: 'p1', canale: 'chiamata', testo: 'interessato' },
      { tipo: 'crea_persona', nome: 'Franco Moretti' },
      { tipo: 'crea_relazione', da: 'p1', a: 'Franco Moretti', relazione: 'presentazione' },
      { tipo: 'cancella_tutto' },
    ], risposta: '' })],
    dati: { 'Prepara richiesta Claude': [richiesta] },
  });
  assert.equal(r[0]._dest, 'proponi');
  assert.equal(r[0].azioni.length, 3, 'le azioni sconosciute vengono scartate');
  assert.match(r[0].testo, /Marco Rossi — ha presentato — Franco Moretti \(nuovo\)/);
});

test('domande, sola lettura, errori e rifiuti diventano una risposta', async () => {
  const dom = await esegui(WF, 'Leggi azioni', { input: [claude({ azioni: [], risposta: 'Non senti Anna da 110 giorni.' })], dati: { 'Prepara richiesta Claude': [richiesta] } });
  assert.deepEqual([dom[0]._dest, dom[0].testo], ['rispondi', 'Non senti Anna da 110 giorni.']);
  const ro = await esegui(WF, 'Leggi azioni', { input: [claude({ azioni: [{ tipo: 'aggiungi_nota', persona: 'p1', testo: 'x' }], risposta: '' })], dati: { 'Prepara richiesta Claude': [{ ...richiesta, puo_scrivere: false }] } });
  assert.match(ro[0].testo, /solo consultare/);
  const rif = await esegui(WF, 'Leggi azioni', { input: [claude({}, { stop_reason: 'refusal' })], dati: { 'Prepara richiesta Claude': [richiesta] } });
  assert.equal(rif[0]._dest, 'rispondi');
  const rotto = await esegui(WF, 'Leggi azioni', { input: [{ content: [{ type: 'text', text: 'boh' }] }], dati: { 'Prepara richiesta Claude': [richiesta] } });
  assert.match(rotto[0].testo, /Non ho capito/);
});

test('esito della conferma', async () => {
  const d = { 'Tipo di messaggio': [{ chat_id: '42' }] };
  const ok = await esegui(WF, 'Esito', { input: [{ stato: 'confermato', esito: [{ ok: true }, { ok: false, errore: 'persona non trovata' }] }], dati: d });
  assert.match(ok[0].testo, /Salvate 1 modifiche[\s\S]*persona non trovata/);
  const no = await esegui(WF, 'Esito', { input: [{ stato: 'scartato' }], dati: d });
  assert.match(no[0].testo, /non ho salvato/);
  const err = await esegui(WF, 'Esito', { input: [{ code: '42501', message: 'comando inesistente' }], dati: d });
  assert.match(err[0].testo, /non è più valido/);
});

test('promemoria: un messaggio per attività, niente se la lista è vuota', async () => {
  const r = await esegui(PROM, 'Componi promemoria', { input: [
    { attivita_id: 'a1', identificativo: '42', testo: 'Richiamare Marco', persona: 'Marco Rossi', telefono: '333', ora: '10:30:00' },
    {},
  ] });
  assert.equal(r.length, 1);
  assert.match(r[0].testo, /alle 10:30: Richiamare Marco/);
});

test('i collegamenti puntano a nodi esistenti', () => {
  for (const wf of [WF, PROM]) {
    const nomi = new Set(wf.nodes.map((n) => n.name));
    for (const [da, c] of Object.entries(wf.connections)) {
      assert.ok(nomi.has(da), da);
      for (const uscita of c.main) for (const l of uscita) assert.ok(nomi.has(l.node), l.node);
    }
  }
});
