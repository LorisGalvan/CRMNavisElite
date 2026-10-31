// IMPOSTAZIONI · modifica solo questi valori
return [{
  json: {
    // URL del progetto Supabase (Project Settings → API), senza / finale
    supabase_url: 'https://IL-TUO-PROGETTO.supabase.co',
    // Modello Claude che interpreta i comandi vocali
    modello: 'claude-opus-5-5',
    // Livello di ragionamento: 'low' risponde in pochi secondi
    effort: 'low',
    // Modello OpenAI che trascrive i messaggi vocali di Telegram
    modello_trascrizione: 'whisper-1',
  },
}];
