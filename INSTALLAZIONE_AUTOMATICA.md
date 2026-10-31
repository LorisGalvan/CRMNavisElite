# Installazione automatica · istruzioni per Claude

Questo file serve a una nuova sessione di Claude Code per installare il Network CRM
al posto di Loris, usando i segreti salvati nelle impostazioni dell'ambiente cloud.
I segreti NON vanno mai scritti in chat, nei commit o nei log.

## Segreti e credenziali
Le chiavi sono **network secret** dell'ambiente: il proxy le aggiunge alle richieste e Claude non le vede.
| Segreto | Sito consentito | Header |
|---|---|---|
| Supabase | `api.supabase.com` | `Authorization`, prefisso `Bearer`, personal access token |
| n8n | host dell'istanza n8n di Loris | `X-N8N-API-KEY`, nessun prefisso |

Telegram, Anthropic e OpenAI non passano dal proxy: il token Telegram sta nell'URL e
`api.anthropic.com` non riceve mai segreti. Loris crea quindi direttamente in n8n tre credenziali
con questi nomi: **Telegram CRM** (Telegram API), **Anthropic CRM** (Header Auth, `x-api-key`),
**OpenAI CRM** (OpenAI). Claude le cerca per nome e le assegna ai nodi.

## Passi
1. Provare `curl https://api.supabase.com/v1/projects` e `curl $N8N/api/v1/workflows`: se rispondono 200 i segreti funzionano.
2. Supabase (Management API `https://api.supabase.com/v1`):
   - prendere l'organizzazione di Loris, creare il progetto `network-crm` in `eu-central-1`
     con una password generata (da comunicare a Loris come da conservare, non in chiaro nei log);
   - attendere lo stato `ACTIVE_HEALTHY`;
   - eseguire `supabase/schema.sql` con `POST /projects/{ref}/database/query`;
   - creare gli utenti `loris4386@gmail.com` ed `enrico.berte@gmail.com` (Auth admin API con la
     chiave service_role, `email_confirm: true`, password temporanee da far cambiare);
   - eseguire `supabase/primo_avvio.sql` e controllare che restituisca i due amministratori.
3. n8n (API pubblica, header `X-N8N-API-KEY`):
   - creare la credenziale `supabaseApi` (host + service_role del nuovo progetto, senza stamparla);
     trovare per nome le credenziali Telegram CRM, Anthropic CRM e OpenAI CRM create da Loris;
   - importare i due JSON di `n8n/workflows/`, inserendo nei nodi gli id delle credenziali
     e l'URL Supabase nel nodo IMPOSTAZIONI;
   - attivare i due workflow.
4. Chiedere a Loris di scrivere `/start` al bot e di comunicare il codice (non è un segreto),
   poi eseguire `select collega_telegram('loris4386@gmail.com', 'CODICE');`.
5. Provare con un messaggio di testo e controllare l'esecuzione in n8n.
6. Dire a Loris cosa è stato fatto, cosa non è riuscito e come collegare Enrico (`/collega`).

## Stato (26 ottobre 2026): installazione completata
- Supabase `wblulveycweghgbmxvqy` (Francoforte, ora italiana): schema, Loris (loris4386@gmail.com) ed
  Enrico Bertelli (enrico.berte@gmail.com) amministratori, pg_cron dei promemoria.
- Funzione `crm-bot`: bot @NAVISELITEBOT (trascrizione Groq, Claude), endpoint per l'app.
  Secret: TELEGRAM_BOT_TOKEN, ANTHROPIC_API_KEY, GROQ_API_KEY, OPENAI_API_KEY, CRM_CRON_SECRET.
- Telegram di Loris collegato. Enrico da collegare con `/collega`.
- App online con GitHub Pages dal ramo `main` del repository CRMNavisElite: https://lorisgalvan.github.io/CRMNavisElite/

## 31 ottobre 2026
- Promemoria tra colleghi con avviso immediato su Telegram (migrazione `supabase/migrazioni/2026-10-31_promemoria_condivisi.sql`, funzione `crm-bot` v17).
- Telegram di Enrico collegato.
- Progetto spostato dal repository `n8n` al repository `CRMNavisElite`.
- n8n non è usato: i workflow in `n8n/` restano come alternativa.
