// Un messaggio Telegram per ogni promemoria in scadenza.
return $input.all()
  .filter((i) => i.json.attivita_id && i.json.identificativo)
  .map((i) => {
    const a = i.json;
    const quando = a.ora ? `alle ${String(a.ora).slice(0, 5)}` : 'oggi';
    const chi = a.persona ? `\n👤 ${a.persona}${a.telefono ? ` · ${a.telefono}` : ''}` : '';
    return { json: { attivita_id: a.attivita_id, chat_id: a.identificativo, testo: `⏰ Promemoria ${quando}: ${a.testo}${chi}` } };
  });
