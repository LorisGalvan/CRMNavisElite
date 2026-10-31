# CRM Navis Elite: la lavagna del detective per i tuoi contatti

App online: **https://lorisgalvan.github.io/CRMNavisElite/**

Network CRM è un CRM condiviso in cui ogni persona è una scheda appuntata su una lavagna e i rapporti sono fili rossi. Oltre a rubrica, trattative, agenda e permessi, adesso si aggiorna **anche a voce**: dici cosa è successo, lui propone le modifiche e salva solo dopo la tua conferma.

```
  App web (PC e telefono)                       Telegram (vocali)
  ── microfono o tastiera ──┐            ┌── vocale o messaggio
                            ▼            ▼
                 interprete (Claude) → modifiche proposte → «Salva?»
                            │            │
                            ▼            ▼
              Supabase: i permessi vengono ricontrollati dal database
                            │
                            └──▶ promemoria su Telegram (pg_cron + crm-bot)
```

## Cosa c'è nel repository

| Percorso | Contenuto |
|---|---|
| `index.html` | **L'app vera (v1.2)**: login, dati su Supabase, mappa, voce con Claude. Online su https://lorisgalvan.github.io/CRMNavisElite/ |
| `prototipo.html` | Il prototipo con dati inventati, che funziona senza internet |
| `supabase/functions/crm-bot` | Bot Telegram, promemoria, interpretazione della voce per l'app, creazione utenti |
| `supabase/schema.sql` | Il database cloud con i permessi a livello di riga e l'esecutore dei comandi vocali |
| `supabase/migrazioni/` | Modifiche al database applicate dopo `schema.sql`, in ordine di data |
| `supabase/primo_avvio.sql` | Crea l'organizzazione, i settori e gli utenti (Loris ed Enrico, amministratori) |
| `supabase/test/` | Prove dei permessi su un PostgreSQL locale (`bash supabase/test/esegui.sh`) |
| `n8n/workflows/` | 2 workflow da importare in n8n: assistente vocale Telegram e promemoria |
| `n8n/src/` | Il sorgente dei workflow e i test (`npm test` dentro `n8n/`) |

## Le funzioni della v1.1

| Funzione | Stato |
|---|---|
| Mappa investigativa: schede trascinabili, fili rossi, filtri per settore, ricerca, «Collega due persone» | ✅ nel prototipo |
| Rubrica con ricerca, settori, ultimo contatto (verde, arancione, rosso) | ✅ |
| Scheda contatto con collegamenti, trattative e cronologia | ✅ |
| Trattative per fase (Contatto → Proposta → Trattativa → Vinta/Persa) | ✅ |
| Agenda: scadute, oggi, domani, prossimi giorni | ✅ |
| Utenti e permessi ibridi: admin, responsabile, collaboratore, sola lettura | ✅ simulati nell'app, **reali** nel database |
| Aggiunta, ridenominazione, colore ed eliminazione dei settori | ✅ scheda Permessi (solo amministratore) |
| Tema chiaro, scuro o automatico | ✅ in alto a destra |
| Registro di tutte le modifiche, con l'indicazione di quelle fatte a voce | ✅ |
| **Aggiornamento vocale nell'app** (tasto rosso col microfono) | ✅ |
| **Aggiornamento vocale da Telegram**, con conferma a pulsanti | ✅ workflow n8n |
| **Promemoria su Telegram** | ✅ workflow n8n |
| Esportazione e importazione dei dati in JSON | ✅ |
| WhatsApp e Alexa | 🔜 prossimo passo (vedi in fondo) |

## Come funziona la voce

Si può parlare in modo naturale, anche con più cose nella stessa frase:

| Dici | Il CRM prepara |
|---|---|
| «Ho chiamato Giorgio Galli, vuole vedere il Riva sabato. Richiamalo tra 3 giorni» | Chiamata registrata (aggiorna «ultimo contatto») e promemoria fra 3 giorni |
| «Aggiungi contatto Franco Moretti, broker, settore nautica, telefono 333 9876543» | Nuova scheda nel settore Nautica |
| «Marco Rossi mi ha presentato Franco Moretti» | Nuova scheda e filo «ha presentato» |
| «Collega Anna Verdi con Lucia Bianchi, sono amiche» | Filo «amicizia» |
| «Appuntamento con Chiara Fontana venerdì alle 11» | Appuntamento in agenda |
| «Nuova trattativa per la villa di Cernobbio con Marco Rossi da 1,2 milioni» | Trattativa da 1.200.000 € |
| «La trattativa Vendita Riva 68 è vinta» | Trattativa spostata in «Vinta» |
| «Il telefono di Paolo Neri è 347 1112223» | Scheda aggiornata |
| «Chi non sento da 3 mesi?» · «Chi conosce Marco Rossi nel settore nautica?» · «Cosa devo fare domani?» | Risposta, senza modifiche |

**Niente viene salvato senza conferma.** Ogni modifica compare come una casella spuntata e puoi togliere quelle sbagliate prima di premere «Conferma e salva».

**Chi interpreta le frasi:**
- Se apri il prototipo da claude.ai, le frasi le interpreta **Claude**, che capisce anche le frasi più libere e gli errori di trascrizione. Alla prima richiesta chiede il permesso.
- Se apri il file `index.html` dal computer, usa un **interprete locale** che funziona senza internet e riconosce le frasi come quelle della tabella.
- Con il ruolo «Sola lettura» si possono fare domande ma non modifiche, né a voce né a mano.

**Il microfono:** in Chrome (PC e Android) aprendo `index.html` la dettatura parte dal tasto rosso. Dove il browser non la consente (per esempio dentro la pagina di claude.ai) tocca il microfono della tastiera del telefono dentro il riquadro e poi premi «Interpreta».

## Provare il prototipo

1. Apri `app/index.html` con Chrome.
2. Cambia utente in alto a destra («Stai usando il CRM come…»). Per provare i permessi, nella scheda Permessi aggiungi un collaboratore di prova con un solo settore e guarda come si riduce la mappa.
3. Premi il tasto rosso e prova le frasi della tabella.

I dati sono **inventati** e restano solo nel browser. Nel prototipo i permessi sono una simulazione: la riservatezza vera arriva con Supabase.

## Passare alla versione cloud (multiutente)

### 1. Database Supabase
1. Crea un progetto su supabase.com (regione UE, per esempio Francoforte).
2. **SQL Editor** → incolla `supabase/schema.sql` → **Run**.
3. **Authentication → Users → Invite user**: invita `loris4386@gmail.com` ed `enrico.berte@gmail.com`. Ognuno riceve una mail per scegliere la password.
4. **SQL Editor** → incolla `supabase/primo_avvio.sql` → **Run**. Crea i 4 settori e vi registra entrambi come amministratori. Si può rieseguire senza creare doppioni, per esempio se Enrico accetta l'invito più tardi.
5. Per un settore nuovo, o per un collaboratore in più, in fondo a `primo_avvio.sql` ci sono le righe pronte da copiare.

Cosa garantisce il database, anche se qualcuno aggira l'app:
- l'amministratore vede tutto;
- gli altri vedono le schede «tutti», quelle dei propri settori e quelle condivise con loro;
- un filo compare solo se si vedono **entrambe** le persone, e i fili privati solo a chi li ha creati;
- le trattative si vedono per settore o se si è responsabili;
- «Sola lettura» non può scrivere;
- ogni modifica finisce nel `registro` con autore, valori prima e dopo, e canale (`app`, `voce`, `voce:telegram`);
- i comandi vocali vengono eseguiti **con i permessi di chi ha parlato**: un collaboratore non può collegare o annotare una persona che non vede.

### 2. Assistente vocale su Telegram (Supabase Edge Function, senza n8n)
Il bot è la funzione `supabase/functions/crm-bot`, che gira dentro lo stesso progetto Supabase:
riceve vocali e messaggi, li fa trascrivere (Whisper) e interpretare (Claude), chiede conferma
con i pulsanti e manda i promemoria ogni 15 minuti dalle 7 alle 21 (pg_cron, `promemoria_cron.sql`).

1. Crea il bot con @BotFather (`/newbot`) e copia il token.
2. Su Supabase apri **Edge Functions → Secrets** e aggiungi:
   `TELEGRAM_BOT_TOKEN`, `ANTHROPIC_API_KEY` (`sk-ant-…`) e, per i vocali, `GROQ_API_KEY` (`gsk_…`, gratuito su console.groq.com) oppure `OPENAI_API_KEY` (`sk-…`).
3. Apri una volta `https://PROGETTO.supabase.co/functions/v1/crm-bot?setup=1`: registra il webhook del bot.
4. Scrivi `/start` al bot e collega il codice che ti dà:
   `select collega_telegram('loris4386@gmail.com', 'IL_TUO_CODICE');`
5. Enrico scrive `/start` e ti manda il suo codice; tu scrivi al bot `/collega enrico.berte@gmail.com CODICE`.

### Promemoria tra colleghi
Se un'attività (promemoria, chiamata, appuntamento) viene assegnata a un collega, dall'app con «Assegnata a» oppure a voce («ricorda a Enrico di…»), il collega riceve **subito** un messaggio sul suo Telegram e poi il promemoria all'orario previsto.
Funziona con il trigger `attivita_avvisa_assegnazione` che chiama `crm-bot?notifica=1` (migrazione `supabase/migrazioni/2026-10-31_promemoria_condivisi.sql`).

Il modello si cambia con i secret facoltativi `CRM_MODELLO` (predefinito `claude-opus-5-5`) e `CRM_EFFORT` (`low`).

I workflow n8n in `n8n/` fanno la stessa cosa e restano come alternativa per chi preferisce n8n.

## L'app online
L'app è una pagina statica pubblicata con GitHub Pages: **Settings → Pages → Deploy from a branch**, ramo `main`, cartella `/ (root)`. Indirizzo: https://lorisgalvan.github.io/CRMNavisElite/

Il vecchio indirizzo `https://lorisgalvan.github.io/n8n/network-crm/app/` rimanda automaticamente a quello nuovo.

Il codice è pubblico, i dati no: senza login il database non restituisce niente. Ogni lettura e scrittura passa dai permessi del database. La voce dell'app usa Claude tramite la funzione `crm-bot`, con i permessi di chi è collegato.

## Prossimi passi

1. **Collegare l'app a Supabase**: login, lettura e scrittura reali, mappa sincronizzata tra PC e telefono. Il pulsante vocale chiamerà la funzione `applica_azioni_vocali`, già pronta nel database.
2. **WhatsApp**: stesso workflow dell'assistente con il trigger WhatsApp Business al posto di Telegram. La tabella `canali_utente` prevede già il canale `whatsapp`.
3. **Alexa**: una skill personalizzata che inoltra la frase al workflow n8n tramite webhook (canale `alexa`, già previsto).
4. Sincronizzazione dell'agenda con Google Calendar.
5. Backup automatici e tempi di conservazione dei dati secondo il GDPR.
