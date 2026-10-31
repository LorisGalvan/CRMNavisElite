// Prepara la richiesta a Claude con i soli dati che l'utente può vedere.
const CFG = $('IMPOSTAZIONI').first().json;
const ingresso = $('Unisci testo').first().json;
const ctx = $json;
const chat_id = ingresso.chat_id;

if (!ctx.collegato) {
  return [{ json: { _dest: 'rispondi', chat_id, testo:
    `Questo account Telegram non è ancora collegato al CRM.\nIl tuo codice è: ${chat_id}\nMandalo all'amministratore, che lo collega alla tua email.` } }];
}
if (ingresso.saluto || !ingresso.testo_utente) {
  return [{ json: { _dest: 'rispondi', chat_id, testo:
    `Ciao ${ctx.nome}. Mandami un vocale o un messaggio, per esempio:\n` +
    '• «Ho chiamato Marco Rossi, richiamalo tra 15 giorni»\n' +
    '• «Collega Anna Verdi con Lucia Bianchi, sono amiche»\n' +
    '• «Chi non sento da tre mesi?»\n' +
    'Prima di salvare ti chiedo sempre conferma.' +
    (ctx.ruolo === 'admin' ? '\n\nPer collegare un\'altra persona: chiedile di scrivermi /start e poi scrivi /collega email codice' : '') } }];
}

const dati = {
  oggi: ctx.oggi,
  utente: { nome: ctx.nome, ruolo: ctx.ruolo, puo_scrivere: ctx.puo_scrivere },
  settori: ctx.settori,
  persone: ctx.persone,
  relazioni: ctx.relazioni,
  trattative: ctx.trattative,
  attivita: ctx.attivita,
};

const istruzioni = `Sei l'assistente di un CRM italiano basato sulle relazioni tra persone. L'utente ha dettato un messaggio: può contenere errori di trascrizione nei nomi. Trasformalo in azioni sul CRM oppure rispondi alle domande usando SOLO i dati forniti.

DATI (JSON): ${JSON.stringify(dati)}

MESSAGGIO DELL'UTENTE: """${ingresso.testo_utente}"""

Rispondi SOLO con un oggetto JSON, senza testo prima o dopo, con questa forma:
{"azioni":[...], "risposta":"testo per l'utente, vuoto se ci sono solo azioni"}
Azioni ammesse (per "persona", "da", "a" usa l'id esistente; per una persona nuova creata nello stesso messaggio usa il suo nome esatto):
{"tipo":"crea_persona","nome":"","tipoScheda":"persona|azienda","ruolo":"","azienda":"","settori":["id settore"],"telefono":"","email":"","citta":""}
{"tipo":"aggiorna_persona","persona":"id","campi":{"telefono|email|citta|ruolo|azienda":"valore"}}
{"tipo":"crea_relazione","da":"id o nome","a":"id o nome","relazione":"conoscenza|amicizia|parentela|collaborazione|presentazione|socio|cliente|fornitore","nota":""}  (per "presentazione": "da" è chi ha presentato)
{"tipo":"registra_contatto","persona":"id","canale":"chiamata|appuntamento|messaggio","testo":"riassunto di cosa ci si è detti"}
{"tipo":"crea_attivita","persona":"id o null","attivita":"chiamata|appuntamento|promemoria","data":"AAAA-MM-GG","ora":"HH:MM o vuoto","testo":"cosa fare, breve"}
{"tipo":"aggiungi_nota","persona":"id","testo":""}
{"tipo":"crea_trattativa","titolo":"","persona":"id o null","settore":"id","importo":0,"fase":"Contatto|Proposta|Trattativa|Vinta|Persa","scadenza":"AAAA-MM-GG o null"}
{"tipo":"aggiorna_trattativa","trattativa":"id","fase":"Contatto|Proposta|Trattativa|Vinta|Persa","importo":null}
Regole: calcola le date relative partendo da oggi. Non inventare dati che l'utente non ha detto. Se un nome non corrisponde a nessuna persona e non è chiaro che vada creato, non creare azioni e chiedi chiarimenti nella risposta. Se l'utente non può scrivere, non proporre azioni. Le risposte alle domande devono essere brevi, in italiano, con un elenco puntato se servono più nomi.`;

return [{
  json: {
    _dest: 'claude',
    chat_id,
    testo_utente: ingresso.testo_utente,
    persone: Object.fromEntries((ctx.persone || []).map((p) => [p.id, p.nome])),
    trattative: Object.fromEntries((ctx.trattative || []).map((t) => [t.id, t.titolo])),
    puo_scrivere: !!ctx.puo_scrivere,
    richiesta_claude: {
      model: CFG.modello,
      max_tokens: 8000,
      output_config: { effort: CFG.effort },
      fallbacks: 'default',
      messages: [{ role: 'user', content: istruzioni }],
    },
  },
}];
