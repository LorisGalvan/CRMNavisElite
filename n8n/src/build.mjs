// Genera i workflow n8n del Network CRM a partire dal codice in src/code.
// Uso: node n8n/src/build.mjs
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const SRC = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(SRC, '..', 'workflows');
const leggi = (file) => fs.readFileSync(path.join(SRC, 'code', file), 'utf8');
const uuid = (seed) => {
  const h = crypto.createHash('sha1').update(seed).digest('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-a${h.slice(17, 20)}-${h.slice(20, 32)}`;
};
const CFG = (k) => `$('IMPOSTAZIONI').first().json.${k}`;

class Workflow {
  constructor(nome) {
    this.nome = nome;
    this.nodes = [];
    this.connections = {};
  }

  add(name, type, typeVersion, parameters, position, extra = {}) {
    this.nodes.push({ parameters, id: uuid(`${this.nome}/${name}`), name, type, typeVersion, position, ...extra });
    return name;
  }

  link(da, a, uscita = 0) {
    const c = (this.connections[da] ??= { main: [] });
    while (c.main.length <= uscita) c.main.push([]);
    c.main[uscita].push({ node: a, type: 'main', index: 0 });
  }

  catena(...nomi) {
    for (let i = 0; i < nomi.length - 1; i++) this.link(nomi[i], nomi[i + 1]);
  }

  nota(testo, pos, altezza = 300) {
    return this.add('Nota', 'n8n-nodes-base.stickyNote', 1, { content: testo, height: altezza, width: 420 }, pos);
  }

  impostazioni(pos) {
    return this.add('IMPOSTAZIONI', 'n8n-nodes-base.code', 2, { jsCode: leggi('impostazioni.js') }, pos, {
      notes: 'Modifica qui i tuoi dati',
      notesInFlow: true,
      color: 6,
    });
  }

  codice(name, file, pos) {
    return this.add(name, 'n8n-nodes-base.code', 2, { jsCode: leggi(file) }, pos);
  }

  smista(name, uscite, pos) {
    return this.add(name, 'n8n-nodes-base.switch', 3.2, {
      mode: 'expression',
      numberOutputs: uscite.length,
      output: `={{ ${JSON.stringify(uscite)}.indexOf($json._dest) }}`,
      options: {},
    }, pos);
  }

  // Chiamata a una funzione del database (Supabase RPC) con la chiave service_role
  rpc(name, funzione, corpo, pos) {
    return this.add(name, 'n8n-nodes-base.httpRequest', 4.2, {
      method: 'POST',
      url: `={{ ${CFG('supabase_url')} }}/rest/v1/rpc/${funzione}`,
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'supabaseApi',
      sendBody: true,
      specifyBody: 'json',
      jsonBody: `={{ JSON.stringify(${corpo}) }}`,
      options: { timeout: 30000 },
    }, pos, { onError: 'continueRegularOutput', retryOnFail: true, maxTries: 2, waitBetweenTries: 2000 });
  }

  telegram(name, parameters, pos, extra = {}) {
    return this.add(name, 'n8n-nodes-base.telegram', 1.2, parameters, pos, extra);
  }

  messaggio(name, pos) {
    return this.telegram(name, {
      chatId: '={{ $json.chat_id }}',
      text: '={{ $json.testo }}',
      additionalFields: { appendAttribution: false },
    }, pos, { onError: 'continueRegularOutput' });
  }

  json() {
    return {
      name: this.nome,
      nodes: this.nodes,
      connections: this.connections,
      active: false,
      settings: { executionOrder: 'v1', timezone: 'Europe/Rome' },
      pinData: {},
      meta: { templateCredsSetupCompleted: false },
      tags: [],
    };
  }
}

const X = (i) => i * 220;

// ---------------------------------------------------------------- 01
function assistente() {
  const w = new Workflow('CRM - 01 Assistente vocale (Telegram)');
  w.nota(
    '## Assistente vocale del CRM\nMandi al bot Telegram un **vocale** o un **messaggio**. Whisper lo trascrive, Claude lo trasforma in modifiche al CRM e il bot ti chiede conferma con due pulsanti. Le modifiche vengono salvate con i **tuoi** permessi: il database ricontrolla tutto.\n\nCredenziali: Telegram API, Supabase API (chiave service_role), OpenAI (solo per i vocali), Header Auth Anthropic (`x-api-key`).',
    [X(-1), -420], 260,
  );
  w.add('Telegram', 'n8n-nodes-base.telegramTrigger', 1.2, { updates: ['message', 'callback_query'], additionalFields: {} }, [X(0), 0]);
  w.impostazioni([X(1), 0]);
  w.codice('Tipo di messaggio', 'tipo_messaggio.js', [X(2), 0]);
  w.smista('Vocale, testo o pulsante?', ['vocale', 'testo', 'pulsante', 'collega'], [X(3), 0]);

  // vocale → testo
  w.telegram('Scarica vocale', { resource: 'file', fileId: '={{ $json.file_id }}', download: true, additionalFields: {} }, [X(4), -200]);
  w.add('Trascrivi (Whisper)', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST',
    url: 'https://api.openai.com/v1/audio/transcriptions',
    authentication: 'predefinedCredentialType',
    nodeCredentialType: 'openAiApi',
    sendBody: true,
    contentType: 'multipart-form-data',
    bodyParameters: {
      parameters: [
        { parameterType: 'formBinaryData', name: 'file', inputDataFieldName: 'data' },
        { name: 'model', value: `={{ ${CFG('modello_trascrizione')} }}` },
        { name: 'language', value: 'it' },
      ],
    },
    options: { timeout: 120000 },
  }, [X(5), -200], { onError: 'continueRegularOutput' });
  w.codice('Unisci testo', 'unisci_testo.js', [X(6), 0]);

  // contesto e Claude
  w.rpc('Contesto utente (Supabase)', 'contesto_vocale', "{ p_canale: 'telegram', p_identificativo: $json.chat_id }", [X(7), 0]);
  w.codice('Prepara richiesta Claude', 'prepara_richiesta.js', [X(8), 0]);
  w.smista('Utente collegato?', ['claude', 'rispondi'], [X(9), 0]);
  w.add('Claude: interpreta', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST',
    url: 'https://api.anthropic.com/v1/messages',
    authentication: 'genericCredentialType',
    genericAuthType: 'httpHeaderAuth',
    sendHeaders: true,
    headerParameters: {
      parameters: [
        { name: 'anthropic-version', value: '2023-06-01' },
        { name: 'anthropic-beta', value: 'server-side-fallback-2026-07-01' },
      ],
    },
    sendBody: true,
    specifyBody: 'json',
    jsonBody: '={{ JSON.stringify($json.richiesta_claude) }}',
    options: { timeout: 120000 },
  }, [X(10), -100], { onError: 'continueRegularOutput', retryOnFail: true, maxTries: 2, waitBetweenTries: 3000 });
  w.codice('Leggi azioni', 'leggi_azioni.js', [X(11), -100]);
  w.smista('Da confermare?', ['proponi', 'rispondi'], [X(12), -100]);
  w.rpc('Salva proposta (Supabase)', 'proponi_comando_vocale',
    "{ p_canale: 'telegram', p_identificativo: $json.chat_id, p_testo: $json.testo_utente, p_azioni: $json.azioni, p_risposta: $json.risposta }",
    [X(13), -200]);
  w.telegram('Chiedi conferma', {
    chatId: "={{ $('Leggi azioni').item.json.chat_id }}",
    text: "={{ $('Leggi azioni').item.json.testo }}",
    replyMarkup: 'inlineKeyboard',
    inlineKeyboard: {
      rows: [{
        row: {
          buttons: [
            { text: '✅ Salva', additionalFields: { callback_data: '=ok:{{ $json.id }}' } },
            { text: '✖️ Annulla', additionalFields: { callback_data: '=no:{{ $json.id }}' } },
          ],
        },
      }],
    },
    additionalFields: { appendAttribution: false },
  }, [X(14), -200], { onError: 'continueRegularOutput' });
  w.messaggio('Rispondi', [X(14), 100]);

  // pulsante premuto
  w.telegram('Chiudi pulsante', {
    resource: 'callback',
    operation: 'answerQuery',
    queryId: '={{ $json.query_id }}',
    additionalFields: { text: 'Ricevuto' },
  }, [X(4), 250], { onError: 'continueRegularOutput' });
  w.rpc('Conferma o annulla (Supabase)', 'decidi_comando_vocale',
    "{ p_comando: $('Tipo di messaggio').first().json.comando_id, p_canale: 'telegram', p_identificativo: $('Tipo di messaggio').first().json.chat_id, p_conferma: $('Tipo di messaggio').first().json.conferma }",
    [X(5), 250]);
  w.codice('Esito', 'esito.js', [X(6), 250]);

  // /collega email codice (solo amministratori già collegati)
  w.rpc('Collega utente (Supabase)', 'collega_telegram_da_admin',
    "{ p_chat_admin: $json.chat_id, p_email: $json.email || '', p_chat_id: $json.codice || '' }", [X(5), 450]);
  w.codice('Esito collegamento', 'esito_collega.js', [X(6), 450]);

  w.catena('Telegram', 'IMPOSTAZIONI', 'Tipo di messaggio', 'Vocale, testo o pulsante?');
  w.link('Vocale, testo o pulsante?', 'Scarica vocale', 0);
  w.link('Vocale, testo o pulsante?', 'Unisci testo', 1);
  w.link('Vocale, testo o pulsante?', 'Chiudi pulsante', 2);
  w.catena('Scarica vocale', 'Trascrivi (Whisper)', 'Unisci testo', 'Contesto utente (Supabase)', 'Prepara richiesta Claude', 'Utente collegato?');
  w.link('Utente collegato?', 'Claude: interpreta', 0);
  w.link('Utente collegato?', 'Rispondi', 1);
  w.catena('Claude: interpreta', 'Leggi azioni', 'Da confermare?');
  w.link('Da confermare?', 'Salva proposta (Supabase)', 0);
  w.link('Da confermare?', 'Rispondi', 1);
  w.link('Salva proposta (Supabase)', 'Chiedi conferma');
  w.catena('Chiudi pulsante', 'Conferma o annulla (Supabase)', 'Esito', 'Rispondi');
  w.link('Vocale, testo o pulsante?', 'Collega utente (Supabase)', 3);
  w.catena('Collega utente (Supabase)', 'Esito collegamento', 'Rispondi');
  return w;
}

// ---------------------------------------------------------------- 02
function promemoria() {
  const w = new Workflow('CRM - 02 Promemoria (Telegram)');
  w.nota(
    '## Promemoria\nOgni 15 minuti, dalle 7 alle 21, manda su Telegram le attività scadute o in scadenza nella prossima mezz\'ora a chi è assegnata. Ogni attività viene notificata una sola volta.',
    [X(-1), -380], 200,
  );
  w.add('Ogni 15 minuti 7-21', 'n8n-nodes-base.scheduleTrigger', 1.2, { rule: { interval: [{ field: 'cronExpression', expression: '*/15 7-21 * * *' }] } }, [X(0), 0]);
  w.impostazioni([X(1), 0]);
  w.rpc('Promemoria da inviare (Supabase)', 'promemoria_da_inviare', '{}', [X(2), 0]);
  w.codice('Componi promemoria', 'componi_promemoria.js', [X(3), 0]);
  w.messaggio('Invia promemoria', [X(4), 0]);
  w.rpc('Segna come inviato (Supabase)', 'segna_promemoria_inviato', "{ p_attivita: $('Componi promemoria').item.json.attivita_id }", [X(5), 0]);
  w.catena('Ogni 15 minuti 7-21', 'IMPOSTAZIONI', 'Promemoria da inviare (Supabase)', 'Componi promemoria', 'Invia promemoria', 'Segna come inviato (Supabase)');
  return w;
}

fs.mkdirSync(OUT, { recursive: true });
for (const w of [assistente(), promemoria()]) {
  const file = path.join(OUT, `${w.nome.replace(/^CRM - /, '').replace(/[()]/g, '').trim()}.json`);
  fs.writeFileSync(file, `${JSON.stringify(w.json(), null, 2)}\n`);
  console.log('scritto', path.relative(process.cwd(), file));
}
