// Risposta al comando /collega email codice.
const t = $('Tipo di messaggio').first().json;
if (t.errore) return [{ json: { chat_id: t.chat_id, testo: t.errore } }];
const r = $json;
if (r.ok) return [{ json: { chat_id: t.chat_id, testo: `✅ ${r.messaggio}. Da ora può mandarmi vocali e messaggi.` } }];
return [{ json: { chat_id: t.chat_id, testo: `⚠️ ${r.errore || 'Non sono riuscito a collegare questo utente.'}` } }];
