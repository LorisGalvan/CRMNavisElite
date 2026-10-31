// Legge la risposta di Claude e prepara il riepilogo da confermare.
const req = $('Prepara richiesta Claude').first().json;
const r = $json;
const chat_id = req.chat_id;

const TIPI = ['crea_persona', 'aggiorna_persona', 'crea_relazione', 'registra_contatto', 'crea_attivita', 'aggiungi_nota', 'crea_trattativa', 'aggiorna_trattativa'];
const REL = { conoscenza: 'si conoscono', amicizia: 'amicizia', parentela: 'parentela', collaborazione: 'lavorano insieme', presentazione: 'ha presentato', socio: 'soci', cliente: 'cliente di', fornitore: 'fornitore di' };

if (r.error || r.stop_reason === 'refusal') {
  return [{ json: { _dest: 'rispondi', chat_id, testo: 'Non sono riuscito a interpretare il messaggio. Riprova tra poco o riformulalo.' } }];
}
const testo = (r.content || []).filter((b) => b.type === 'text').map((b) => b.text).join('');
let out;
try {
  const inizio = testo.indexOf('{'), fine = testo.lastIndexOf('}');
  out = JSON.parse(testo.slice(inizio, fine + 1));
} catch (e) {
  return [{ json: { _dest: 'rispondi', chat_id, testo: 'Non ho capito. Puoi ripetere con altre parole?' } }];
}

const azioni = (Array.isArray(out.azioni) ? out.azioni : []).filter((a) => a && TIPI.includes(a.tipo));
const nuovi = new Set(azioni.filter((a) => a.tipo === 'crea_persona').map((a) => String(a.nome).toLowerCase()));
const nome = (ref) => req.persone[ref] || (ref && nuovi.has(String(ref).toLowerCase()) ? `${ref} (nuovo)` : ref || '—');
const data = (d) => (d ? new Date(`${d}T12:00:00`).toLocaleDateString('it-IT', { weekday: 'short', day: 'numeric', month: 'short' }) : '');
const eur = (n) => (Number(n) || 0).toLocaleString('it-IT', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 });

const riga = (a) => {
  switch (a.tipo) {
    case 'crea_persona': return `➕ Nuovo contatto: ${a.nome}${a.ruolo ? `, ${a.ruolo}` : ''}${a.citta ? `, ${a.citta}` : ''}${a.telefono ? `, ${a.telefono}` : ''}`;
    case 'aggiorna_persona': return `✏️ ${nome(a.persona)}: ${Object.entries(a.campi || {}).map(([k, v]) => `${k} → ${v}`).join(', ')}`;
    case 'crea_relazione': return `🔗 ${nome(a.da)} — ${REL[a.relazione] || a.relazione} — ${nome(a.a)}`;
    case 'registra_contatto': return `📞 Contatto con ${nome(a.persona)}: ${a.testo}`;
    case 'crea_attivita': return `⏰ ${a.testo}${a.persona ? ` (${nome(a.persona)})` : ''} · ${data(a.data)}${a.ora ? ` alle ${a.ora}` : ''}`;
    case 'aggiungi_nota': return `📝 Nota su ${nome(a.persona)}: ${a.testo}`;
    case 'crea_trattativa': return `💼 Nuova trattativa: ${a.titolo}${a.persona ? ` (${nome(a.persona)})` : ''} · ${eur(a.importo)}`;
    case 'aggiorna_trattativa': return `💼 ${req.trattative[a.trattativa] || a.trattativa}${a.fase ? ` → ${a.fase}` : ''}${a.importo ? ` · ${eur(a.importo)}` : ''}`;
  }
  return '';
};

const risposta = String(out.risposta || '').trim();
if (!azioni.length || !req.puo_scrivere) {
  const extra = azioni.length && !req.puo_scrivere ? '\n\nCon il tuo ruolo puoi solo consultare il CRM.' : '';
  return [{ json: { _dest: 'rispondi', chat_id, testo: (risposta || 'Non ho trovato modifiche da fare.') + extra } }];
}
const elenco = azioni.map(riga).join('\n');
return [{
  json: {
    _dest: 'proponi',
    chat_id,
    testo_utente: req.testo_utente,
    azioni,
    risposta,
    testo: `${risposta ? `${risposta}\n\n` : ''}Ho capito queste modifiche:\n${elenco}\n\nLe salvo?`,
  },
}];
