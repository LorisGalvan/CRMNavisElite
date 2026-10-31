-- Promemoria condivisi tra colleghi con avviso immediato su Telegram

CREATE OR REPLACE FUNCTION private.esegui_azioni(p_org uuid, p_user uuid, p_azioni jsonb, p_via text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a jsonb; creati jsonb := '{}'; esito jsonb := '[]';
  v_id uuid; v_ass uuid; v_da uuid; v_a uuid; v_set uuid; v_tr trattative%rowtype;
  k text; v text;

begin
  if not private.puo_scrivere(p_org, p_user) then
    raise exception 'L''utente non può modificare il CRM' using errcode = '42501';
  end if;
  perform set_config('crm.via', p_via, true);
  perform set_config('crm.utente', p_user::text, true);

  for a in select * from jsonb_array_elements(p_azioni) loop
    begin
      case a->>'tipo'
      when 'crea_persona' then
        insert into persone (org_id, tipo, nome, ruolo, azienda, telefono, email, citta, visibilita, creato_da)
        values (p_org, coalesce(nullif(a->>'tipoScheda',''),'persona')::tipo_scheda, a->>'nome',
                coalesce(a->>'ruolo',''), coalesce(a->>'azienda',''), coalesce(a->>'telefono',''),
                coalesce(a->>'email',''), coalesce(a->>'citta',''),
                case when jsonb_array_length(coalesce(a->'settori','[]')) > 0 and not private.is_admin(p_org, p_user)
                     then 'settore' else 'privato' end::visibilita, p_user)
        returning id into v_id;
        insert into persone_settori (persona_id, settore_id)
          select v_id, s.id from settori s
          where s.org_id = p_org
            and (s.id::text in (select jsonb_array_elements_text(coalesce(a->'settori','[]')))
                 or lower(s.nome) in (select lower(jsonb_array_elements_text(coalesce(a->'settori','[]')))))
            and (private.is_admin(p_org, p_user) or private.ha_settore(s.id, p_user));
        creati := creati || jsonb_build_object(lower(a->>'nome'), v_id);
        esito := esito || jsonb_build_object('tipo', a->>'tipo', 'ok', true, 'id', v_id);

      when 'aggiorna_persona' then
        v_id := private.risolvi_persona(p_org, p_user, a->>'persona', creati);
        if v_id is null or not private.modifica_persona(v_id, p_user) then raise exception 'persona non modificabile'; end if;
        for k, v in select * from jsonb_each_text(coalesce(a->'campi','{}')) loop
          if k in ('telefono','email','citta','ruolo','azienda') then
            execute format('update persone set %I = $1 where id = $2', k) using v, v_id;
          end if;
        end loop;
        esito := esito || jsonb_build_object('tipo', a->>'tipo', 'ok', true, 'id', v_id);

      when 'crea_relazione' then
        v_da := private.risolvi_persona(p_org, p_user, a->>'da', creati);
        v_a  := private.risolvi_persona(p_org, p_user, a->>'a', creati);
        if v_da is null or v_a is null or v_da = v_a then raise exception 'persone non trovate'; end if;
        insert into relazioni (org_id, da, a, tipo, nota, creato_da)
        values (p_org, v_da, v_a, coalesce(nullif(a->>'relazione',''),'conoscenza')::tipo_relazione, coalesce(a->>'nota',''), p_user)
        returning id into v_id;
        esito := esito || jsonb_build_object('tipo', a->>'tipo', 'ok', true, 'id', v_id);

      when 'registra_contatto', 'aggiungi_nota' then
        v_id := private.risolvi_persona(p_org, p_user, a->>'persona', creati);
        if v_id is null then raise exception 'persona non trovata'; end if;
        insert into attivita (org_id, tipo, persona_id, data, ora, testo, fatto, assegnato_a, creato_da)
        values (p_org, case when a->>'tipo' = 'aggiungi_nota' then 'nota' else coalesce(nullif(a->>'canale',''),'chiamata') end::tipo_attivita,
                v_id, current_date, case when a->>'tipo' = 'aggiungi_nota' then null else localtime(0) end,
                coalesce(a->>'testo',''), true, p_user, p_user)
        returning id into v_id;
        esito := esito || jsonb_build_object('tipo', a->>'tipo', 'ok', true, 'id', v_id);

      when 'crea_attivita' then
        v_id := private.risolvi_persona(p_org, p_user, a->>'persona', creati);
        if nullif(a->>'persona','') is not null and v_id is null then raise exception 'persona non trovata'; end if;
        -- "ricorda a Enrico di…": l'attività può essere assegnata a un collega attivo dell'organizzazione
        v_ass := p_user;
        if nullif(a->>'assegnato_a','') is not null then
          select m.user_id into v_ass from membri m
          where m.org_id = p_org and m.attivo
            and (m.user_id::text = a->>'assegnato_a' or lower(m.nome) = lower(a->>'assegnato_a')
                 or lower(split_part(m.nome, ' ', 1)) = lower(a->>'assegnato_a'))
          order by (m.user_id::text = a->>'assegnato_a') desc limit 1;
          if v_ass is null then raise exception 'collega non trovato: %', a->>'assegnato_a'; end if;
        end if;
        insert into attivita (org_id, tipo, persona_id, data, ora, testo, assegnato_a, creato_da)
        values (p_org, coalesce(nullif(a->>'attivita',''),'promemoria')::tipo_attivita, v_id,
                coalesce(nullif(a->>'data','')::date, current_date + 1), nullif(a->>'ora','')::time,
                coalesce(a->>'testo',''), v_ass, p_user)
        returning id into v_id;
        esito := esito || jsonb_build_object('tipo', a->>'tipo', 'ok', true, 'id', v_id);

      when 'crea_trattativa' then
        v_id := private.risolvi_persona(p_org, p_user, a->>'persona', creati);
        select id into v_set from settori s where s.org_id = p_org
          and (s.id::text = a->>'settore' or lower(s.nome) = lower(a->>'settore'))
          and (private.is_admin(p_org, p_user) or private.ha_settore(s.id, p_user));
        if v_set is null then
          select ms.settore_id into v_set from membri_settori ms where ms.user_id = p_user and ms.org_id = p_org limit 1;
        end if;
        if v_set is null then raise exception 'nessun settore autorizzato'; end if;
        insert into trattative (org_id, titolo, persona_id, settore_id, fase, importo, responsabile, scadenza, creato_da)
        values (p_org, a->>'titolo', v_id, v_set, coalesce(nullif(a->>'fase',''),'Contatto')::fase_trattativa,
                coalesce(nullif(a->>'importo','')::numeric, 0), p_user, nullif(a->>'scadenza','')::date, p_user)
        returning id into v_id;
        esito := esito || jsonb_build_object('tipo', a->>'tipo', 'ok', true, 'id', v_id);

      when 'aggiorna_trattativa' then
        select * into v_tr from trattative t where t.org_id = p_org
          and (t.id::text = a->>'trattativa' or lower(t.titolo) = lower(a->>'trattativa')) limit 1;
        if v_tr.id is null or not private.vede_trattativa(v_tr, p_user) then raise exception 'trattativa non trovata'; end if;
        update trattative set fase = coalesce(nullif(a->>'fase','')::fase_trattativa, fase),
                              importo = coalesce(nullif(a->>'importo','')::numeric, importo)
        where id = v_tr.id;
        esito := esito || jsonb_build_object('tipo', a->>'tipo', 'ok', true, 'id', v_tr.id);

      else
        raise exception 'azione sconosciuta: %', a->>'tipo';
      end case;
    exception when others then
      esito := esito || jsonb_build_object('tipo', a->>'tipo', 'ok', false, 'errore', sqlerrm);
    end;
  end loop;
  return esito;
end $function$

;

CREATE OR REPLACE FUNCTION private.contesto(p_org uuid, p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m membri%rowtype;
begin
  select * into m from membri where org_id = p_org and user_id = p_user and attivo;
  if m.user_id is null then return jsonb_build_object('collegato', false); end if;
  return jsonb_build_object(
    'collegato', true, 'org_id', p_org, 'user_id', p_user, 'nome', m.nome, 'ruolo', m.ruolo,
    'puo_scrivere', private.puo_scrivere(p_org, p_user),
    'oggi', current_date,
    'utenti', (select coalesce(jsonb_agg(jsonb_build_object('id', u.user_id, 'nome', u.nome)), '[]') from membri u where u.org_id = p_org and u.attivo and u.user_id <> p_user),
    'settori', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome)), '[]') from settori s where s.org_id = p_org),
    'persone', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nome', p.nome, 'tipo', p.tipo, 'ruolo', p.ruolo, 'citta', p.citta, 'ultimoContatto', p.ultimo_contatto)), '[]')
                from persone p where p.org_id = p_org and private.vede_persona(p.id, p_user)),
    'relazioni', (select coalesce(jsonb_agg(jsonb_build_object('da', r.da, 'a', r.a, 'tipo', r.tipo)), '[]')
                  from relazioni r where r.org_id = p_org and private.vede_relazione(r, p_user)),
    'trattative', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'titolo', t.titolo, 'persona', t.persona_id, 'fase', t.fase, 'importo', t.importo, 'scadenza', t.scadenza)), '[]')
                   from trattative t where t.org_id = p_org and private.vede_trattativa(t, p_user)),
    'attivita', (select coalesce(jsonb_agg(jsonb_build_object('persona', a.persona_id, 'tipo', a.tipo, 'data', a.data, 'ora', a.ora, 'testo', a.testo, 'fatto', a.fatto)), '[]')
                 from attivita a where a.org_id = p_org and a.data >= current_date - 30 and private.vede_attivita(a, p_user))
  );
end $function$

;

-- segreto condiviso con la funzione crm-bot (stesso valore di CRM_CRON_SECRET, già usato da pg_cron)
select vault.create_secret((select substring(command from 'x-crm-cron'', ''([0-9a-f]+)''') from cron.job where jobname = 'crm-promemoria'), 'crm_cron_secret', 'header x-crm-cron per crm-bot')
where not exists (select 1 from vault.secrets where name = 'crm_cron_secret');

-- dettagli per il messaggio Telegram (solo la funzione, con la service role)
create or replace function public.dettaglio_assegnazione(p_attivita uuid, p_da uuid)
returns table(identificativo text, tipo text, testo text, data date, ora time, persona text, telefono text, autore text)
language sql stable security definer set search_path to 'public' as $$
  select cu.identificativo, a.tipo::text, a.testo, a.data, a.ora, p.nome, p.telefono,
         (select m.nome from membri m where m.org_id = a.org_id and m.user_id = coalesce(p_da, a.creato_da))
  from attivita a
  join canali_utente cu on cu.user_id = a.assegnato_a and cu.org_id = a.org_id and cu.canale = 'telegram'
  left join persone p on p.id = a.persona_id
  where a.id = p_attivita and not a.fatto
$$;
revoke all on function public.dettaglio_assegnazione(uuid, uuid) from public, anon, authenticated;
grant execute on function public.dettaglio_assegnazione(uuid, uuid) to service_role;

-- trigger: quando un'attività viene assegnata a un collega (nuova o riassegnata), avvisalo subito su Telegram
create or replace function private.avvisa_assegnazione() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare v_da uuid := coalesce(auth.uid(), nullif(current_setting('crm.utente', true), '')::uuid, new.creato_da);
begin
  if new.assegnato_a is null or new.fatto or new.tipo::text = 'nota' or new.assegnato_a = v_da then return new; end if;
  if tg_op = 'UPDATE' and old.assegnato_a is not distinct from new.assegnato_a then return new; end if;
  if not exists (select 1 from canali_utente cu where cu.user_id = new.assegnato_a and cu.org_id = new.org_id and cu.canale = 'telegram') then return new; end if;
  begin
    perform net.http_post(
      url := 'https://wblulveycweghgbmxvqy.supabase.co/functions/v1/crm-bot?notifica=1',
      headers := jsonb_build_object('Content-Type', 'application/json',
                   'x-crm-cron', (select decrypted_secret from vault.decrypted_secrets where name = 'crm_cron_secret')),
      body := jsonb_build_object('attivita', new.id, 'da', v_da));
  exception when others then
    raise warning 'avviso assegnazione non inviato: %', sqlerrm;  -- mai bloccare il salvataggio
  end;
  return new;
end $$;
drop trigger if exists attivita_avvisa_assegnazione on public.attivita;
create trigger attivita_avvisa_assegnazione after insert or update of assegnato_a on public.attivita
  for each row execute function private.avvisa_assegnazione();
