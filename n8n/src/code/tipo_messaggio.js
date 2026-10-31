// Capisce cosa è arrivato da Telegram: vocale, testo o pulsante premuto.
const u = $('Telegram').first().json;
if (u.callback_query) {
  const q = u.callback_query;
  const [scelta, id] = String(q.data || '').split(':');
  return [{ json: { _dest: 'pulsante', chat_id: String(q.message.chat.id), query_id: q.id, comando_id: id, conferma: scelta === 'ok' } }];
}
const m = u.message;
if (!m) return [];
const chat_id = String(m.chat.id);
const vocale = m.voice || m.audio;
if (vocale) return [{ json: { _dest: 'vocale', chat_id, file_id: vocale.file_id } }];
if (m.text) {
  const collega = m.text.trim().match(/^\/collega(?:@\w+)?\s+(\S+@\S+)\s+(-?\d+)\s*$/i);
  if (collega) return [{ json: { _dest: 'collega', chat_id, email: collega[1].toLowerCase(), codice: collega[2] } }];
  if (/^\/collega\b/i.test(m.text.trim())) {
    return [{ json: { _dest: 'collega', chat_id, errore: 'Scrivi così: /collega email codice\nEsempio: /collega enrico.berte@gmail.com 123456789' } }];
  }
  if (m.text.startsWith('/start')) {
    return [{ json: { _dest: 'testo', chat_id, testo_utente: '', saluto: true } }];
  }
  return [{ json: { _dest: 'testo', chat_id, testo_utente: m.text.trim() } }];
}
return [];
