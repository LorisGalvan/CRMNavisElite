// Testo del messaggio: trascritto dal vocale oppure scritto.
const t = $('Tipo di messaggio').first().json;
const testo = t._dest === 'vocale' ? String($json.text || '').trim() : t.testo_utente;
return [{ json: { chat_id: t.chat_id, testo_utente: testo, saluto: !!t.saluto } }];
