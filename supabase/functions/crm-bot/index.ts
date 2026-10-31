// Network CRM · bot Telegram (Supabase Edge Function, fa ciò che facevano i workflow n8n)
//   POST /crm-bot                    aggiornamenti da Telegram (vocali, messaggi, pulsanti, /collega)
//   GET  /crm-bot?setup=1            registra questo indirizzo come webhook del bot
//   POST /crm-bot?promemoria=1       invia i promemoria in scadenza (lo chiama pg_cron ogni 15 minuti)
//   POST /crm-bot?interpreta=1       dall'app: frase → azioni proposte (con il login dell'utente)
//   POST /crm-bot?notifica=1         avvisa subito su Telegram chi riceve un promemoria assegnato da un collega (lo chiama un trigger del database)
//   POST /crm-bot?invita=1           dall'app: un amministratore aggiunge un utente
// Segreti da impostare (Edge Functions → Secrets): TELEGRAM_BOT_TOKEN, ANTHROPIC_API_KEY e, per i vocali,
// GROQ_API_KEY (gratuito) oppure OPENAI_API_KEY.
// CRM_CRON_SECRET è lo stesso valore che pg_cron manda nell'header x-crm-cron.
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY li fornisce Supabase.

// trim: un token incollato con uno spazio o un a capo in più non funzionerebbe
const TG = (Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "").trim().replace(/^bot/i, "");
const ANTHROPIC = (Deno.env.get("ANTHROPIC_API_KEY") ?? "").trim();
const OPENAI = (Deno.env.get("OPENAI_API_KEY") ?? "").trim();
// Se c'è la chiave Groq la trascrizione usa Groq (piano gratuito), altrimenti OpenAI
const GROQ = (Deno.env.get("GROQ_API_KEY") ?? "").trim();
const TRASCRIZIONE = GROQ
  ? { url: "https://api.groq.com/openai/v1/audio/transcriptions", chiave: GROQ, modello: "whisper-large-v3-turbo", nome: "Groq" }
  : { url: "https://api.openai.com/v1/audio/transcriptions", chiave: OPENAI, modello: "whisper-1", nome: "OpenAI" };
const SB_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SB_ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type", "Access-Control-Allow-Methods": "POST, GET, OPTIONS" };
const json = (body: unknown, status = 200) => Response.json(body, { status, headers: CORS });
const MODELLO = Deno.env.get("CRM_MODELLO") ?? "claude-opus-5-5";
const EFFORT = Deno.env.get("CRM_EFFORT") ?? "low";

async function sha(s: string) {
  const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 48);
}
// Segreti derivati: Telegram e pg_cron li mandano in un header, così nessun altro può chiamare la funzione
const segretoWebhook = () => sha(`webhook:${TG}`);
const segretoCron = async () => Deno.env.get("CRM_CRON_SECRET") || crypto.randomUUID();

async function rpc(fn: string, body: unknown) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const t = await r.text();
  const j = t ? JSON.parse(t) : null;
  if (!r.ok) throw new Error(j?.message ?? `rpc ${fn} ${r.status}`);
  return j;
}

// Chiamate al database con il login dell'utente dell'app: valgono i suoi permessi (RLS)
async function comeUtente(token: string, percorso: string, init: RequestInit = {}) {
  const r = await fetch(`${SB_URL}${percorso}`, { ...init, headers: { apikey: SB_ANON, Authorization: `Bearer ${token}`, "Content-Type": "application/json", ...(init.headers ?? {}) } });
  const t = await r.text();
  const j = t ? JSON.parse(t) : null;
  if (!r.ok) throw new Error(j?.message ?? j?.msg ?? `${r.status}`);
  return j;
}

// deno-lint-ignore no-explicit-any
async function interpretaApp(req: Request): Promise<any> {
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { testo, org } = await req.json();
  const ctx = await comeUtente(token, "/rest/v1/rpc/contesto_app", { method: "POST", body: JSON.stringify({ p_org: org }) });
  if (!ctx?.collegato) return { errore: "utente non autorizzato" };
  const out = await chiediClaude(istruzioni(ctx, String(testo ?? "")));
  if (!out) return { errore: "interpretazione non riuscita" };
  // deno-lint-ignore no-explicit-any
  return { azioni: (Array.isArray(out.azioni) ? out.azioni : []).filter((a: any) => a && TIPI.includes(a.tipo)), risposta: String(out.risposta ?? "") };
}

async function invita(req: Request) {
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const io = await comeUtente(token, "/auth/v1/user");
  const { org, email, nome, ruolo, settori } = await req.json();
  const mio = await comeUtente(token, `/rest/v1/membri?org_id=eq.${org}&user_id=eq.${io.id}&select=ruolo`);
  if (mio?.[0]?.ruolo !== "admin") return { errore: "Solo un amministratore può aggiungere utenti." };
  const password = `Crm-${crypto.randomUUID().slice(0, 8)}`;
  const srv = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json" };
  const nuovo = await (await fetch(`${SB_URL}/auth/v1/admin/users`, { method: "POST", headers: srv, body: JSON.stringify({ email: String(email).toLowerCase().trim(), password, email_confirm: true }) })).json();
  if (!nuovo?.id) return { errore: nuovo?.msg ?? nuovo?.message ?? "Utente non creato (email già registrata?)." };
  await fetch(`${SB_URL}/rest/v1/membri`, { method: "POST", headers: srv, body: JSON.stringify({ org_id: org, user_id: nuovo.id, nome, ruolo }) });
  if (Array.isArray(settori) && settori.length) {
    await fetch(`${SB_URL}/rest/v1/membri_settori`, { method: "POST", headers: srv, body: JSON.stringify(settori.map((s: string) => ({ org_id: org, user_id: nuovo.id, settore_id: s }))) });
  }
  return { ok: true, password };
}

async function tg(metodo: string, body: unknown) {
  const r = await fetch(`https://api.telegram.org/bot${TG}/${metodo}`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
  });
  return r.json();
}
const scrivi = (chat_id: string, text: string, extra: Record<string, unknown> = {}) => tg("sendMessage", { chat_id, text, ...extra });

async function trascrivi(file_id: string) {
  const f = await tg("getFile", { file_id });
  const audio = await (await fetch(`https://api.telegram.org/file/bot${TG}/${f.result.file_path}`)).blob();
  const form = new FormData();
  form.append("file", audio, "vocale.ogg");
  form.append("model", TRASCRIZIONE.modello);
  form.append("language", "it");
  const r = await fetch(TRASCRIZIONE.url, { method: "POST", headers: { Authorization: `Bearer ${TRASCRIZIONE.chiave}` }, body: form });
  const j = await r.json();
  if (!r.ok) throw new Error(j?.error?.message ?? "trascrizione non riuscita");
  return String(j.text ?? "").trim();
}

// ---------------------------------------------------------------- Claude
// deno-lint-ignore no-explicit-any
function istruzioni(ctx: any, testo: string) {
  const dati = { oggi: ctx.oggi, utente: { nome: ctx.nome, ruolo: ctx.ruolo, puo_scrivere: ctx.puo_scrivere }, settori: ctx.settori, colleghi: ctx.utenti ?? [], persone: ctx.persone, relazioni: ctx.relazioni, trattative: ctx.trattative, attivita: ctx.attivita };
  return `Sei l'assistente di un CRM italiano basato sulle relazioni tra persone. L'utente ha dettato un messaggio: può contenere errori di trascrizione nei nomi. Trasformalo in azioni sul CRM oppure rispondi alle domande usando SOLO i dati forniti.

DATI (JSON): ${JSON.stringify(dati)}

MESSAGGIO DELL'UTENTE: """${testo}"""

Rispondi SOLO con un oggetto JSON, senza testo prima o dopo, con questa forma:
{"azioni":[...], "risposta":"testo per l'utente, vuoto se ci sono solo azioni"}
Azioni ammesse (per "persona", "da", "a" usa l'id esistente; per una persona nuova creata nello stesso messaggio usa il suo nome esatto):
{"tipo":"crea_persona","nome":"","tipoScheda":"persona|azienda","ruolo":"","azienda":"","settori":["id settore"],"telefono":"","email":"","citta":""}
{"tipo":"aggiorna_persona","persona":"id","campi":{"telefono|email|citta|ruolo|azienda":"valore"}}
{"tipo":"crea_relazione","da":"id o nome","a":"id o nome","relazione":"conoscenza|amicizia|parentela|collaborazione|presentazione|socio|cliente|fornitore","nota":""}  (per "presentazione": "da" è chi ha presentato)
{"tipo":"registra_contatto","persona":"id","canale":"chiamata|appuntamento|messaggio","testo":"riassunto di cosa ci si è detti"}
{"tipo":"crea_attivita","persona":"id o null","attivita":"chiamata|appuntamento|promemoria","data":"AAAA-MM-GG","ora":"HH:MM o vuoto","testo":"cosa fare, breve","assegnato_a":"id di un collega o null"}  (assegnato_a solo se l'attività è per un collega, es. "ricorda a Enrico di…": usa l'id da "colleghi"; altrimenti null = per chi parla)
{"tipo":"aggiungi_nota","persona":"id","testo":""}
{"tipo":"crea_trattativa","titolo":"","persona":"id o null","settore":"id","importo":0,"fase":"Contatto|Proposta|Trattativa|Vinta|Persa","scadenza":"AAAA-MM-GG o null"}
{"tipo":"aggiorna_trattativa","trattativa":"id","fase":"Contatto|Proposta|Trattativa|Vinta|Persa","importo":null}
Regole: calcola le date relative partendo da oggi. Non inventare dati che l'utente non ha detto. Se un nome non corrisponde a nessuna persona e non è chiaro che vada creato, non creare azioni e chiedi chiarimenti nella risposta. Se l'utente non può scrivere, non proporre azioni. Le risposte alle domande devono essere brevi, in italiano, con un elenco puntato se servono più nomi.`;
}

async function chiediClaude(prompt: string) {
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": ANTHROPIC, "anthropic-version": "2023-06-01", "anthropic-beta": "server-side-fallback-2026-07-01", "content-type": "application/json" },
    body: JSON.stringify({ model: MODELLO, max_tokens: 8000, output_config: { effort: EFFORT }, fallbacks: "default", messages: [{ role: "user", content: prompt }] }),
  });
  const j = await r.json();
  if (!r.ok || j.stop_reason === "refusal") return null;
  // deno-lint-ignore no-explicit-any
  const testo = (j.content ?? []).filter((b: any) => b.type === "text").map((b: any) => b.text).join("");
  try { return JSON.parse(testo.slice(testo.indexOf("{"), testo.lastIndexOf("}") + 1)); } catch { return null; }
}

const TIPI = ["crea_persona", "aggiorna_persona", "crea_relazione", "registra_contatto", "crea_attivita", "aggiungi_nota", "crea_trattativa", "aggiorna_trattativa"];
const REL: Record<string, string> = { conoscenza: "si conoscono", amicizia: "amicizia", parentela: "parentela", collaborazione: "lavorano insieme", presentazione: "ha presentato", socio: "soci", cliente: "cliente di", fornitore: "fornitore di" };
const data = (d?: string) => (d ? new Date(`${d}T12:00:00`).toLocaleDateString("it-IT", { weekday: "short", day: "numeric", month: "short" }) : "");
const eur = (n: unknown) => (Number(n) || 0).toLocaleString("it-IT", { style: "currency", currency: "EUR", maximumFractionDigits: 0 });

// deno-lint-ignore no-explicit-any
function riepilogo(azioni: any[], ctx: any) {
  const colleghi = Object.fromEntries((ctx.utenti ?? []).map((u: { id: string; nome: string }) => [u.id, u.nome]));
  const persone = Object.fromEntries((ctx.persone ?? []).map((p: { id: string; nome: string }) => [p.id, p.nome]));
  const trattative = Object.fromEntries((ctx.trattative ?? []).map((t: { id: string; titolo: string }) => [t.id, t.titolo]));
  const nuovi = new Set(azioni.filter((a) => a.tipo === "crea_persona").map((a) => String(a.nome).toLowerCase()));
  const nome = (r: string) => persone[r] ?? (r && nuovi.has(String(r).toLowerCase()) ? `${r} (nuovo)` : r || "—");
  return azioni.map((a) => {
    switch (a.tipo) {
      case "crea_persona": return `➕ Nuovo contatto: ${a.nome}${a.ruolo ? `, ${a.ruolo}` : ""}${a.citta ? `, ${a.citta}` : ""}${a.telefono ? `, ${a.telefono}` : ""}`;
      case "aggiorna_persona": return `✏️ ${nome(a.persona)}: ${Object.entries(a.campi ?? {}).map(([k, v]) => `${k} → ${v}`).join(", ")}`;
      case "crea_relazione": return `🔗 ${nome(a.da)} — ${REL[a.relazione] ?? a.relazione} — ${nome(a.a)}`;
      case "registra_contatto": return `📞 Contatto con ${nome(a.persona)}: ${a.testo}`;
      case "crea_attivita": return `⏰ ${a.testo}${a.persona ? ` (${nome(a.persona)})` : ""} · ${data(a.data)}${a.ora ? ` alle ${a.ora}` : ""}${a.assegnato_a ? ` → per ${colleghi[a.assegnato_a] ?? a.assegnato_a}` : ""}`;
      case "aggiungi_nota": return `📝 Nota su ${nome(a.persona)}: ${a.testo}`;
      case "crea_trattativa": return `💼 Nuova trattativa: ${a.titolo}${a.persona ? ` (${nome(a.persona)})` : ""} · ${eur(a.importo)}${a.scadenza ? ` · entro ${data(a.scadenza)}` : ""}`;
      case "aggiorna_trattativa": return `💼 ${trattative[a.trattativa] ?? a.trattativa}${a.fase ? ` → ${a.fase}` : ""}${a.importo ? ` · ${eur(a.importo)}` : ""}`;
    }
    return "";
  }).join("\n");
}

// ---------------------------------------------------------------- gestione messaggi
// deno-lint-ignore no-explicit-any
async function gestisci(u: any) {
  if (u.callback_query) {
    const q = u.callback_query, chat = String(q.message.chat.id);
    const [scelta, id] = String(q.data ?? "").split(":");
    await tg("answerCallbackQuery", { callback_query_id: q.id, text: "Ricevuto" });
    await tg("editMessageReplyMarkup", { chat_id: chat, message_id: q.message.message_id, reply_markup: { inline_keyboard: [] } });
    try {
      const r = await rpc("decidi_comando_vocale", { p_comando: id, p_canale: "telegram", p_identificativo: chat, p_conferma: scelta === "ok" });
      if (r.stato === "scartato") return scrivi(chat, "Va bene, non ho salvato niente.");
      if (r.stato !== "confermato" || !Array.isArray(r.esito)) return scrivi(chat, "Comando già gestito.");
      // deno-lint-ignore no-explicit-any
      const ko = r.esito.filter((e: any) => !e.ok);
      const n = r.esito.length - ko.length;
      return scrivi(chat, `✅ ${n === 1 ? "Salvata 1 modifica" : `Salvate ${n} modifiche`}.${ko.length ? `\n⚠️ ${ko.length} non salvate: ${ko.map((e: { errore: string }) => e.errore).join("; ")}.` : ""}`);
    } catch {
      return scrivi(chat, "Questo comando non è più valido.");
    }
  }

  const m = u.message;
  if (!m) return;
  const chat = String(m.chat.id);
  const testoGrezzo = String(m.text ?? "").trim();

  if (/^\/collega\b/i.test(testoGrezzo)) {
    const c = testoGrezzo.match(/^\/collega(?:@\w+)?\s+(\S+@\S+)\s+(-?\d+)\s*$/i);
    if (!c) return scrivi(chat, "Scrivi così: /collega email codice\nEsempio: /collega enrico.berte@gmail.com 123456789");
    const r = await rpc("collega_telegram_da_admin", { p_chat_admin: chat, p_email: c[1].toLowerCase(), p_chat_id: c[2] });
    return scrivi(chat, r.ok ? `✅ ${r.messaggio}. Da ora può mandarmi vocali e messaggi.` : `⚠️ ${r.errore}`);
  }

  const ctx = await rpc("contesto_vocale", { p_canale: "telegram", p_identificativo: chat });
  if (!ctx?.collegato) {
    return scrivi(chat, `Questo account Telegram non è ancora collegato al CRM.\nIl tuo codice è: ${chat}\nMandalo all'amministratore, che lo collega alla tua email.`);
  }

  let testo = testoGrezzo;
  const vocale = m.voice ?? m.audio;
  if (vocale) {
    await tg("sendChatAction", { chat_id: chat, action: "typing" });
    try { testo = await trascrivi(vocale.file_id); } catch (e) {
      console.error("trascrizione", e);
      return scrivi(chat, `Non riesco a trascrivere il vocale (${String((e as Error).message).slice(0, 160)}). Intanto puoi scrivermi il messaggio.`);
    }
    if (testo) await scrivi(chat, `🎙 «${testo}»`);
  }
  if (!testo || testo.startsWith("/start")) {
    return scrivi(chat, `Ciao ${ctx.nome}. Mandami un vocale o un messaggio, per esempio:\n• «Ho chiamato Marco Rossi, richiamalo tra 15 giorni»\n• «Collega Anna Verdi con Lucia Bianchi, sono amiche»\n• «Chi non sento da tre mesi?»\nPrima di salvare ti chiedo sempre conferma.` +
      (ctx.ruolo === "admin" ? "\n\nPer collegare un'altra persona: chiedile di scrivermi /start e poi scrivi /collega email codice" : ""));
  }

  await tg("sendChatAction", { chat_id: chat, action: "typing" });
  const out = await chiediClaude(istruzioni(ctx, testo));
  if (!out) return scrivi(chat, "Non sono riuscito a interpretare il messaggio. Riprova tra poco o riformulalo.");
  // deno-lint-ignore no-explicit-any
  const azioni = (Array.isArray(out.azioni) ? out.azioni : []).filter((a: any) => a && TIPI.includes(a.tipo));
  const risposta = String(out.risposta ?? "").trim();
  if (!azioni.length || !ctx.puo_scrivere) {
    return scrivi(chat, (risposta || "Non ho trovato modifiche da fare.") + (azioni.length ? "\n\nCon il tuo ruolo puoi solo consultare il CRM." : ""));
  }
  const p = await rpc("proponi_comando_vocale", { p_canale: "telegram", p_identificativo: chat, p_testo: testo, p_azioni: azioni, p_risposta: risposta });
  return scrivi(chat, `${risposta ? `${risposta}\n\n` : ""}Ho capito queste modifiche:\n${riepilogo(azioni, ctx)}\n\nLe salvo?`, {
    reply_markup: { inline_keyboard: [[{ text: "✅ Salva", callback_data: `ok:${p.id}` }, { text: "✖️ Annulla", callback_data: `no:${p.id}` }]] },
  });
}

async function promemoria() {
  const lista = await rpc("promemoria_da_inviare", {});
  for (const a of lista ?? []) {
    const quando = a.ora ? `alle ${String(a.ora).slice(0, 5)}` : "oggi";
    const chi = a.persona ? `\n👤 ${a.persona}${a.telefono ? ` · ${a.telefono}` : ""}` : "";
    const r = await scrivi(a.identificativo, `⏰ Promemoria ${quando}: ${a.testo}${chi}`);
    if (r?.ok) await rpc("segna_promemoria_inviato", { p_attivita: a.attivita_id });
  }
  return (lista ?? []).length;
}

// Avviso immediato: un collega ti ha assegnato un promemoria (chiamato dal trigger su attivita)
async function notificaAssegnazione(attivita: string, da: string | null) {
  const righe = await rpc("dettaglio_assegnazione", { p_attivita: attivita, p_da: da });
  const a = righe?.[0];
  if (!a?.identificativo) return false;
  const tipo = ({ chiamata: "📞 Chiamata", appuntamento: "🤝 Appuntamento", promemoria: "📌 Promemoria" } as Record<string, string>)[a.tipo] ?? "📌 Promemoria";
  const quando = `${data(a.data)}${a.ora ? ` alle ${String(a.ora).slice(0, 5)}` : ""}`;
  const chi = a.persona ? `\n👤 ${a.persona}${a.telefono ? ` · ${a.telefono}` : ""}` : "";
  const r = await scrivi(a.identificativo, `${tipo} da ${a.autore ?? "un collega"}\n${a.testo}\n🗓 ${quando}${chi}\n\nTe lo ricordo di nuovo all'orario previsto.`);
  return !!r?.ok;
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    if (url.searchParams.has("interpreta")) return json(await interpretaApp(req));
    if (url.searchParams.has("invita")) return json(await invita(req));
    if (url.searchParams.has("setup")) {
      const self = `${SB_URL}/functions/v1/crm-bot`;
      const r = await tg("setWebhook", { url: self, secret_token: await segretoWebhook(), allowed_updates: ["message", "callback_query"] });
      const me = await tg("getMe", {});
      // Controlli di forma, senza mai mostrare i valori
      const forma = {
        telegram: /^\d{6,}:[\w-]{30,}$/.test(TG) ? "ok" : `formato non valido (lunghezza ${TG.length})`,
        anthropic: ANTHROPIC.startsWith("sk-ant-") ? "ok" : "non inizia con sk-ant-",
        groq: GROQ ? (GROQ.startsWith("gsk_") ? "ok" : "non inizia con gsk_") : "assente",
      };
      // Prova reale delle chiavi AI (risposta del servizio, mai la chiave)
      const oa = await fetch(TRASCRIZIONE.url.replace("audio/transcriptions", "models"), { headers: { Authorization: `Bearer ${TRASCRIZIONE.chiave}` } });
      const an = await fetch("https://api.anthropic.com/v1/models", { headers: { "x-api-key": ANTHROPIC, "anthropic-version": "2023-06-01" } });
      const errore = async (r: Response) => r.ok ? "ok" : `${r.status} ${(await r.json().catch(() => ({})))?.error?.message ?? ""}`.slice(0, 200);
      return Response.json({ trascrizione: TRASCRIZIONE.nome, trascrizione_prova: await errore(oa), anthropic_prova: await errore(an), webhook: r.ok, descrizione: r.description, bot: me?.result?.username, chiavi: forma });
    }
    if (url.searchParams.has("notifica")) {
      if (req.headers.get("x-crm-cron") !== await segretoCron()) return new Response("no", { status: 401 });
      const { attivita, da } = await req.json();
      return Response.json({ inviata: await notificaAssegnazione(String(attivita), da ?? null) });
    }
    if (url.searchParams.has("promemoria")) {
      if (req.headers.get("x-crm-cron") !== await segretoCron()) return new Response("no", { status: 401 });
      return Response.json({ inviati: await promemoria() });
    }
    if (req.headers.get("x-telegram-bot-api-secret-token") !== await segretoWebhook()) return new Response("no", { status: 401 });
    await gestisci(await req.json());
  } catch (e) {
    console.error(e);
    if (url.searchParams.has("interpreta") || url.searchParams.has("invita")) return json({ errore: String((e as Error).message) }, 400);
  }
  // Sempre 200 a Telegram, altrimenti ripete lo stesso messaggio
  return new Response("ok");
});
