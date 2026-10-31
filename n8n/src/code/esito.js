// Trasforma l'esito del database in un messaggio per Telegram.
const p = $('Tipo di messaggio').first().json;
const r = $json;
if (r.stato === 'scartato') return [{ json: { chat_id: p.chat_id, testo: 'Va bene, non ho salvato niente.' } }];
if (r.stato !== 'confermato' || !Array.isArray(r.esito)) {
  return [{ json: { chat_id: p.chat_id, testo: (r.message || r.error) ? 'Questo comando non è più valido.' : 'Comando già gestito.' } }];
}
const ok = r.esito.filter((e) => e.ok).length;
const ko = r.esito.filter((e) => !e.ok);
let testo = `✅ Salvate ${ok} modifiche.`;
if (ko.length) testo += `\n⚠️ ${ko.length} non salvate: ${ko.map((e) => e.errore).join('; ')}.`;
return [{ json: { chat_id: p.chat_id, testo } }];
