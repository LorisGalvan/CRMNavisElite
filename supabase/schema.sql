-- =====================================================================
-- Network CRM · schema Supabase (PostgreSQL 15+) · v1.1
-- CRM condiviso con visibilità ibrida per autorizzazione:
--   * l'amministratore vede tutto;
--   * gli altri vedono le schede condivise con tutti, quelle dei propri
--     settori e quelle condivise con loro personalmente;
--   * un collegamento è visibile solo se si vedono entrambe le persone;
--   * tutti i controlli sono nel database (Row Level Security), non
--     nell'interfaccia.
-- Si esegue una volta sola dall'editor SQL di Supabase.
-- =====================================================================

create extension if not exists pgcrypto;
create schema if not exists private;

-- ---------------------------------------------------------------- tipi
do $$ begin
  create type ruolo_utente   as enum ('admin','responsabile','collaboratore','lettura');
  create type visibilita     as enum ('privato','settore','tutti');
  create type tipo_scheda    as enum ('persona','azienda');
  create type tipo_relazione as enum ('conoscenza','amicizia','parentela','collaborazione','presentazione','socio','cliente','fornitore');
  create type fase_trattativa as enum ('Contatto','Proposta','Trattativa','Vinta','Persa');
  create type tipo_attivita  as enum ('chiamata','appuntamento','promemoria','nota','messaggio');
  create type stato_comando  as enum ('proposto','confermato','scartato','errore');
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------- tabelle
create table if not exists organizzazioni (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  created_at timestamptz not null default now()
);

create table if not exists membri (
  org_id uuid not null references organizzazioni(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  nome text not null,
  ruolo ruolo_utente not null default 'collaboratore',
  attivo boolean not null default true,
  primary key (org_id, user_id)
);

create table if not exists settori (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizzazioni(id) on delete cascade,
  nome text not null,
  colore text not null default '#1f5f99',
  unique (org_id, nome)
);

create table if not exists membri_settori (
  org_id uuid not null,
  user_id uuid not null,
  settore_id uuid not null references settori(id) on delete cascade,
  primary key (user_id, settore_id),
  foreign key (org_id, user_id) references membri(org_id, user_id) on delete cascade
);

create table if not exists persone (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizzazioni(id) on delete cascade,
  tipo tipo_scheda not null default 'persona',
  nome text not null,
  ruolo text not null default '',
  azienda text not null default '',
  telefono text not null default '',
  email text not null default '',
  citta text not null default '',
  tag text[] not null default '{}',
  visibilita visibilita not null default 'privato',
  ultimo_contatto date,
  pos_x real, pos_y real,                         -- posizione sulla lavagna
  creato_da uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists persone_org_nome on persone (org_id, lower(nome));

create table if not exists persone_settori (
  persona_id uuid not null references persone(id) on delete cascade,
  settore_id uuid not null references settori(id) on delete cascade,
  primary key (persona_id, settore_id)
);

-- condivisione puntuale di una scheda con un utente
create table if not exists persone_condivisioni (
  persona_id uuid not null references persone(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  puo_modificare boolean not null default false,
  primary key (persona_id, user_id)
);

create table if not exists relazioni (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizzazioni(id) on delete cascade,
  da uuid not null references persone(id) on delete cascade,
  a uuid not null references persone(id) on delete cascade,
  tipo tipo_relazione not null default 'conoscenza',
  nota text not null default '',
  privata boolean not null default false,          -- visibile solo a chi l'ha creata e all'admin
  creato_da uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  check (da <> a)
);
create index if not exists relazioni_da on relazioni (da);
create index if not exists relazioni_a on relazioni (a);

create table if not exists trattative (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizzazioni(id) on delete cascade,
  titolo text not null,
  persona_id uuid references persone(id) on delete set null,
  settore_id uuid not null references settori(id),
  fase fase_trattativa not null default 'Contatto',
  importo numeric(14,2) not null default 0,
  responsabile uuid references auth.users(id),
  scadenza date,
  creato_da uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists attivita (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizzazioni(id) on delete cascade,
  tipo tipo_attivita not null default 'promemoria',
  persona_id uuid references persone(id) on delete cascade,
  trattativa_id uuid references trattative(id) on delete set null,
  data date not null default current_date,
  ora time,
  testo text not null,
  fatto boolean not null default false,
  condivisa boolean not null default true,
  assegnato_a uuid not null default auth.uid() references auth.users(id),
  promemoria_inviato_at timestamptz,               -- lo compila il workflow n8n dei promemoria
  creato_da uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists attivita_scadenze on attivita (org_id, data) where not fatto;

-- canali esterni collegati a un utente (Telegram, WhatsApp, Alexa)
create table if not exists canali_utente (
  org_id uuid not null,
  user_id uuid not null,
  canale text not null check (canale in ('telegram','whatsapp','alexa')),
  identificativo text not null,                    -- chat_id Telegram, numero WhatsApp, userId Alexa
  primary key (canale, identificativo),
  foreign key (org_id, user_id) references membri(org_id, user_id) on delete cascade
);

-- ogni comando vocale: testo trascritto, azioni proposte, esito
create table if not exists comandi_vocali (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizzazioni(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  canale text not null default 'app',
  testo text not null,
  azioni jsonb not null default '[]',
  risposta text not null default '',
  stato stato_comando not null default 'proposto',
  esito jsonb,
  created_at timestamptz not null default now(),
  confermato_at timestamptz
);

-- registro delle modifiche (scritto solo dai trigger)
create table if not exists registro (
  id bigint generated always as identity primary key,
  org_id uuid not null,
  user_id uuid,
  tabella text not null,
  record_id uuid,
  operazione text not null,
  prima jsonb,
  dopo jsonb,
  via text not null default 'app',
  quando timestamptz not null default now()
);

-- ------------------------------------------- funzioni di autorizzazione
-- Tutte ricevono l'utente come parametro (default: chi è collegato), così
-- le usa sia la RLS sia l'esecutore dei comandi vocali chiamato da n8n.

create or replace function private.ruolo(p_org uuid, p_user uuid default auth.uid())
returns ruolo_utente language sql stable security definer set search_path = public as $$
  select ruolo from membri where org_id = p_org and user_id = p_user and attivo
$$;

create or replace function private.is_membro(p_org uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from membri where org_id = p_org and user_id = p_user and attivo)
$$;

create or replace function private.is_admin(p_org uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(private.ruolo(p_org, p_user) = 'admin', false)
$$;

create or replace function private.puo_scrivere(p_org uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(private.ruolo(p_org, p_user) <> 'lettura', false)
$$;

create or replace function private.ha_settore(p_settore uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from membri_settori where settore_id = p_settore and user_id = p_user)
$$;

create or replace function private.vede_persona(p_persona uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from persone p
    where p.id = p_persona
      and private.is_membro(p.org_id, p_user)
      and (
        private.is_admin(p.org_id, p_user)
        or p.creato_da = p_user
        or p.visibilita = 'tutti'
        or exists (select 1 from persone_condivisioni c where c.persona_id = p.id and c.user_id = p_user)
        or (p.visibilita = 'settore' and exists (
              select 1 from persone_settori ps join membri_settori ms on ms.settore_id = ps.settore_id
              where ps.persona_id = p.id and ms.user_id = p_user))
      )
  )
$$;

create or replace function private.modifica_persona(p_persona uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from persone p
    where p.id = p_persona
      and private.puo_scrivere(p.org_id, p_user)
      and private.vede_persona(p.id, p_user)
      and (
        private.is_admin(p.org_id, p_user)
        or p.creato_da = p_user
        or exists (select 1 from persone_condivisioni c where c.persona_id = p.id and c.user_id = p_user and c.puo_modificare)
        -- il responsabile modifica le schede dei suoi settori
        or (private.ruolo(p.org_id, p_user) = 'responsabile' and exists (
              select 1 from persone_settori ps join membri_settori ms on ms.settore_id = ps.settore_id
              where ps.persona_id = p.id and ms.user_id = p_user))
      )
  )
$$;

create or replace function private.vede_relazione(r relazioni, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select private.vede_persona(r.da, p_user) and private.vede_persona(r.a, p_user)
     and (not r.privata or r.creato_da = p_user or private.is_admin(r.org_id, p_user))
$$;

create or replace function private.vede_trattativa(t trattative, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select private.is_membro(t.org_id, p_user)
     and (private.is_admin(t.org_id, p_user) or t.responsabile = p_user or t.creato_da = p_user or private.ha_settore(t.settore_id, p_user))
     and (t.persona_id is null or private.vede_persona(t.persona_id, p_user))
$$;

create or replace function private.vede_attivita(a attivita, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select private.is_membro(a.org_id, p_user)
     and (private.is_admin(a.org_id, p_user) or a.assegnato_a = p_user or a.creato_da = p_user
          or (a.condivisa and (a.persona_id is null or private.vede_persona(a.persona_id, p_user))))
$$;

-- ------------------------------------------------------------------ RLS
alter table organizzazioni       enable row level security;
alter table membri               enable row level security;
alter table settori              enable row level security;
alter table membri_settori       enable row level security;
alter table persone              enable row level security;
alter table persone_settori      enable row level security;
alter table persone_condivisioni enable row level security;
alter table relazioni            enable row level security;
alter table trattative           enable row level security;
alter table attivita             enable row level security;
alter table canali_utente        enable row level security;
alter table comandi_vocali       enable row level security;
alter table registro             enable row level security;

drop policy if exists org_sel on organizzazioni;
create policy org_sel on organizzazioni for select using (private.is_membro(id));

drop policy if exists membri_sel on membri;
create policy membri_sel on membri for select using (private.is_membro(org_id));
drop policy if exists membri_adm on membri;
create policy membri_adm on membri for all using (private.is_admin(org_id)) with check (private.is_admin(org_id));

drop policy if exists settori_sel on settori;
create policy settori_sel on settori for select using (private.is_membro(org_id));
drop policy if exists settori_adm on settori;
create policy settori_adm on settori for all using (private.is_admin(org_id)) with check (private.is_admin(org_id));

drop policy if exists ms_sel on membri_settori;
create policy ms_sel on membri_settori for select using (private.is_membro(org_id));
drop policy if exists ms_adm on membri_settori;
create policy ms_adm on membri_settori for all using (private.is_admin(org_id)) with check (private.is_admin(org_id));

-- persone
drop policy if exists persone_sel on persone;
create policy persone_sel on persone for select using (private.vede_persona(id));
drop policy if exists persone_ins on persone;
create policy persone_ins on persone for insert
  with check (private.puo_scrivere(org_id) and creato_da = auth.uid());
drop policy if exists persone_upd on persone;
create policy persone_upd on persone for update
  using (private.modifica_persona(id)) with check (private.puo_scrivere(org_id));
drop policy if exists persone_del on persone;
create policy persone_del on persone for delete
  using (private.is_admin(org_id) or (creato_da = auth.uid() and private.puo_scrivere(org_id)));

drop policy if exists ps_sel on persone_settori;
create policy ps_sel on persone_settori for select using (private.vede_persona(persona_id));
drop policy if exists ps_mod on persone_settori;
create policy ps_mod on persone_settori for all
  using (private.modifica_persona(persona_id))
  with check (private.modifica_persona(persona_id)
              and exists (select 1 from persone p join settori s on s.org_id = p.org_id
                          where p.id = persona_id and s.id = settore_id
                            and (private.is_admin(p.org_id) or private.ha_settore(s.id))));

drop policy if exists pc_sel on persone_condivisioni;
create policy pc_sel on persone_condivisioni for select using (user_id = auth.uid() or private.modifica_persona(persona_id));
drop policy if exists pc_mod on persone_condivisioni;
create policy pc_mod on persone_condivisioni for all
  using (exists (select 1 from persone p where p.id = persona_id and (private.is_admin(p.org_id) or p.creato_da = auth.uid())))
  with check (exists (select 1 from persone p where p.id = persona_id and (private.is_admin(p.org_id) or p.creato_da = auth.uid())
                      and private.is_membro(p.org_id, user_id)));

-- relazioni
drop policy if exists rel_sel on relazioni;
create policy rel_sel on relazioni for select using (private.vede_relazione(relazioni));
drop policy if exists rel_ins on relazioni;
create policy rel_ins on relazioni for insert
  with check (private.puo_scrivere(org_id) and creato_da = auth.uid()
              and private.vede_persona(da) and private.vede_persona(a));
drop policy if exists rel_upd on relazioni;
create policy rel_upd on relazioni for update
  using (private.vede_relazione(relazioni) and private.puo_scrivere(org_id))
  with check (private.vede_persona(da) and private.vede_persona(a));
drop policy if exists rel_del on relazioni;
create policy rel_del on relazioni for delete
  using (private.is_admin(org_id) or (creato_da = auth.uid() and private.puo_scrivere(org_id)));

-- trattative
drop policy if exists tr_sel on trattative;
create policy tr_sel on trattative for select using (private.vede_trattativa(trattative));
drop policy if exists tr_ins on trattative;
create policy tr_ins on trattative for insert
  with check (private.puo_scrivere(org_id) and (private.is_admin(org_id) or private.ha_settore(settore_id))
              and (persona_id is null or private.vede_persona(persona_id)));
drop policy if exists tr_upd on trattative;
create policy tr_upd on trattative for update
  using (private.vede_trattativa(trattative) and private.puo_scrivere(org_id))
  with check (private.is_admin(org_id) or private.ha_settore(settore_id) or responsabile = auth.uid());
drop policy if exists tr_del on trattative;
create policy tr_del on trattative for delete
  using (private.is_admin(org_id) or (private.ruolo(org_id) = 'responsabile' and private.ha_settore(settore_id)));

-- attività
drop policy if exists att_sel on attivita;
create policy att_sel on attivita for select using (private.vede_attivita(attivita));
drop policy if exists att_ins on attivita;
create policy att_ins on attivita for insert
  with check (private.puo_scrivere(org_id) and creato_da = auth.uid()
              and private.is_membro(org_id, assegnato_a)
              and (persona_id is null or private.vede_persona(persona_id)));
drop policy if exists att_upd on attivita;
create policy att_upd on attivita for update
  using (private.vede_attivita(attivita) and private.puo_scrivere(org_id))
  with check (persona_id is null or private.vede_persona(persona_id));
drop policy if exists att_del on attivita;
create policy att_del on attivita for delete
  using (private.is_admin(org_id) or creato_da = auth.uid());

-- canali, comandi vocali, registro
drop policy if exists can_sel on canali_utente;
create policy can_sel on canali_utente for select using (user_id = auth.uid() or private.is_admin(org_id));
drop policy if exists can_adm on canali_utente;
create policy can_adm on canali_utente for all using (private.is_admin(org_id)) with check (private.is_admin(org_id));

drop policy if exists cv_sel on comandi_vocali;
create policy cv_sel on comandi_vocali for select using (user_id = auth.uid() or private.is_admin(org_id));
drop policy if exists cv_ins on comandi_vocali;
create policy cv_ins on comandi_vocali for insert with check (user_id = auth.uid() and private.is_membro(org_id));

drop policy if exists reg_sel on registro;
create policy reg_sel on registro for select using (private.is_admin(org_id) or user_id = auth.uid());

-- ------------------------------------------------------------- trigger
create or replace function private.touch() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists persone_touch on persone;
create trigger persone_touch before update on persone for each row execute function private.touch();
drop trigger if exists trattative_touch on trattative;
create trigger trattative_touch before update on trattative for each row execute function private.touch();

-- registro automatico: chi, cosa, prima e dopo. "via" arriva dalla
-- variabile di sessione crm.via (impostata dall'esecutore dei comandi vocali).
create or replace function private.registra() returns trigger language plpgsql security definer set search_path = public as $$
declare r jsonb; begin
  r := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  insert into registro (org_id, user_id, tabella, record_id, operazione, prima, dopo, via)
  values ((r->>'org_id')::uuid,
          coalesce(auth.uid(), nullif(current_setting('crm.utente', true), '')::uuid),
          tg_table_name, (r->>'id')::uuid, tg_op,
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end,
          coalesce(nullif(current_setting('crm.via', true), ''), 'app'));
  return null;
end $$;

do $$ declare t text; begin
  foreach t in array array['persone','relazioni','trattative','attivita'] loop
    execute format('drop trigger if exists %I_registro on %I', t, t);
    execute format('create trigger %I_registro after insert or update or delete on %I for each row execute function private.registra()', t, t);
  end loop;
end $$;

-- un contatto avvenuto aggiorna "ultimo contatto" della persona
create or replace function private.aggiorna_ultimo_contatto() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.fatto and new.persona_id is not null and new.tipo in ('chiamata','appuntamento','messaggio') then
    update persone set ultimo_contatto = greatest(coalesce(ultimo_contatto, new.data), new.data) where id = new.persona_id;
  end if;
  return null;
end $$;
drop trigger if exists attivita_ultimo_contatto on attivita;
create trigger attivita_ultimo_contatto after insert or update of fatto on attivita
  for each row execute function private.aggiorna_ultimo_contatto();

-- ============================ comandi vocali ============================
-- Esegue la lista di azioni prodotta dall'interprete (app o n8n) PER CONTO
-- di un utente, ricontrollando ogni permesso con le stesse funzioni della RLS.
-- Riferimenti alle persone: uuid esistente oppure nome di una persona creata
-- nello stesso comando.
create or replace function private.esegui_azioni(p_org uuid, p_user uuid, p_azioni jsonb, p_via text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  a jsonb; creati jsonb := '{}'; esito jsonb := '[]';
  v_id uuid; v_da uuid; v_a uuid; v_set uuid; v_tr trattative%rowtype;
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
        insert into attivita (org_id, tipo, persona_id, data, ora, testo, assegnato_a, creato_da)
        values (p_org, coalesce(nullif(a->>'attivita',''),'promemoria')::tipo_attivita, v_id,
                coalesce(nullif(a->>'data','')::date, current_date + 1), nullif(a->>'ora','')::time,
                coalesce(a->>'testo',''), p_user, p_user)
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
end $$;

create or replace function private.risolvi_persona(p_org uuid, p_user uuid, p_ref text, p_creati jsonb)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare v uuid;
begin
  if nullif(p_ref, '') is null then return null; end if;
  if p_creati ? lower(p_ref) then return (p_creati->>lower(p_ref))::uuid; end if;
  if p_ref ~* '^[0-9a-f-]{36}$' then
    select id into v from persone where id = p_ref::uuid and org_id = p_org;
  else
    -- nome esatto, poi nome contenuto (solo se univoco)
    select id into v from persone where org_id = p_org and lower(nome) = lower(p_ref) and private.vede_persona(id, p_user) limit 1;
    if v is null then
      select min(id::text)::uuid into v from persone
      where org_id = p_org and lower(nome) like '%' || lower(p_ref) || '%' and private.vede_persona(id, p_user)
      having count(*) = 1;
    end if;
  end if;
  if v is not null and private.vede_persona(v, p_user) then return v; end if;
  return null;
end $$;

-- Dall'app: esegue le azioni confermate dall'utente collegato.
create or replace function public.applica_azioni_vocali(p_org uuid, p_testo text, p_azioni jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_esito jsonb; v_id uuid;
begin
  if auth.uid() is null or not private.is_membro(p_org) then raise exception 'non autorizzato' using errcode = '42501'; end if;
  v_esito := private.esegui_azioni(p_org, auth.uid(), p_azioni, 'voce');
  insert into comandi_vocali (org_id, user_id, canale, testo, azioni, stato, esito, confermato_at)
  values (p_org, auth.uid(), 'app', p_testo, p_azioni, 'confermato', v_esito, now()) returning id into v_id;
  return jsonb_build_object('comando', v_id, 'esito', v_esito);
end $$;

-- Da n8n (chiave service_role): conferma o scarta un comando arrivato da
-- Telegram/WhatsApp. Si accetta solo dal canale dell'utente che ha parlato e
-- le azioni vengono eseguite con i suoi permessi.
create or replace function public.decidi_comando_vocale(p_comando uuid, p_canale text, p_identificativo text, p_conferma boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c comandi_vocali%rowtype; v_esito jsonb;
begin
  select * into c from comandi_vocali where id = p_comando for update;
  if c.id is null or not exists (select 1 from canali_utente cu where cu.canale = p_canale and cu.identificativo = p_identificativo
                                 and cu.user_id = c.user_id and cu.org_id = c.org_id) then
    raise exception 'comando inesistente' using errcode = '42501';
  end if;
  if c.stato <> 'proposto' then return jsonb_build_object('comando', c.id, 'stato', c.stato, 'esito', c.esito); end if;
  if not p_conferma then
    update comandi_vocali set stato = 'scartato' where id = c.id;
    return jsonb_build_object('comando', c.id, 'stato', 'scartato');
  end if;
  v_esito := private.esegui_azioni(c.org_id, c.user_id, c.azioni, 'voce:' || c.canale);
  update comandi_vocali set stato = 'confermato', esito = v_esito, confermato_at = now() where id = c.id;
  return jsonb_build_object('comando', c.id, 'stato', 'confermato', 'esito', v_esito);
end $$;

-- Da n8n: registra le azioni proposte in attesa di conferma.
create or replace function public.proponi_comando_vocale(p_canale text, p_identificativo text, p_testo text, p_azioni jsonb, p_risposta text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cu canali_utente%rowtype; v_id uuid;
begin
  select * into cu from canali_utente where canale = p_canale and identificativo = p_identificativo;
  if cu.user_id is null then raise exception 'canale non collegato' using errcode = '42501'; end if;
  insert into comandi_vocali (org_id, user_id, canale, testo, azioni, risposta)
  values (cu.org_id, cu.user_id, p_canale, p_testo, coalesce(p_azioni, '[]'), coalesce(p_risposta, ''))
  returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;

-- Da n8n: contesto per l'interprete AI, cioè solo ciò che quell'utente può vedere.
-- Contesto per l'interprete AI: solo ciò che quell'utente può vedere.
create or replace function private.contesto(p_org uuid, p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare m membri%rowtype;
begin
  select * into m from membri where org_id = p_org and user_id = p_user and attivo;
  if m.user_id is null then return jsonb_build_object('collegato', false); end if;
  return jsonb_build_object(
    'collegato', true, 'org_id', p_org, 'user_id', p_user, 'nome', m.nome, 'ruolo', m.ruolo,
    'puo_scrivere', private.puo_scrivere(p_org, p_user),
    'oggi', current_date,
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
end $$;

-- Da Telegram (bot, chiave service_role): contesto di chi scrive da quella chat.
create or replace function public.contesto_vocale(p_canale text, p_identificativo text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare cu canali_utente%rowtype;
begin
  select * into cu from canali_utente where canale = p_canale and identificativo = p_identificativo;
  if cu.user_id is null then return jsonb_build_object('collegato', false); end if;
  return private.contesto(cu.org_id, cu.user_id);
end $$;

-- Dall'app: contesto dell'utente collegato.
create or replace function public.contesto_app(p_org uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select private.contesto(p_org, auth.uid())
$$;

-- Dall'app: email dei membri della propria organizzazione (auth.users non è leggibile dal browser).
create or replace function public.membri_email(p_org uuid)
returns table (user_id uuid, email text) language sql stable security definer set search_path = public as $$
  select m.user_id, u.email::text from membri m join auth.users u on u.id = m.user_id
  where m.org_id = p_org and private.is_membro(p_org)
$$;

-- Dall'editor SQL (amministratore): collega una chat Telegram a un utente.
-- Il codice chat lo manda il bot quando l'utente gli scrive /start.
create or replace function public.collega_telegram(p_email text, p_chat_id text)
returns text language plpgsql security definer set search_path = public as $$
declare m membri%rowtype;
begin
  select mb.* into m from membri mb join auth.users u on u.id = mb.user_id
  where lower(u.email) = lower(trim(p_email)) and mb.attivo limit 1;
  if m.user_id is null then raise exception 'Nessun membro attivo con email %', p_email; end if;
  insert into canali_utente (org_id, user_id, canale, identificativo)
  values (m.org_id, m.user_id, 'telegram', trim(p_chat_id))
  on conflict (canale, identificativo) do update set org_id = excluded.org_id, user_id = excluded.user_id;
  return 'Telegram collegato a ' || m.nome;
end $$;

-- Da n8n: un amministratore già collegato collega un altro utente scrivendo
-- al bot "/collega email codice".
create or replace function public.collega_telegram_da_admin(p_chat_admin text, p_email text, p_chat_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cu canali_utente%rowtype; v_nome text;
begin
  select * into cu from canali_utente where canale = 'telegram' and identificativo = p_chat_admin;
  if cu.user_id is null or not private.is_admin(cu.org_id, cu.user_id) then
    return jsonb_build_object('ok', false, 'errore', 'Solo un amministratore collegato può usare /collega.');
  end if;
  if not exists (select 1 from membri mb join auth.users u on u.id = mb.user_id
                 where mb.org_id = cu.org_id and mb.attivo and lower(u.email) = lower(trim(p_email))) then
    return jsonb_build_object('ok', false, 'errore', 'Nessun utente del CRM con email ' || p_email || '.');
  end if;
  v_nome := public.collega_telegram(p_email, p_chat_id);
  return jsonb_build_object('ok', true, 'messaggio', v_nome);
end $$;

-- Da n8n: promemoria da inviare (scadono oggi o sono scaduti, non ancora notificati).
create or replace function public.promemoria_da_inviare()
returns table (attivita_id uuid, user_id uuid, canale text, identificativo text, testo text, persona text, telefono text, data date, ora time)
language sql stable security definer set search_path = public as $$
  select a.id, a.assegnato_a, cu.canale, cu.identificativo, a.testo, p.nome, p.telefono, a.data, a.ora
  from attivita a
  join canali_utente cu on cu.user_id = a.assegnato_a and cu.org_id = a.org_id and cu.canale = 'telegram'
  left join persone p on p.id = a.persona_id
  where not a.fatto and a.tipo <> 'nota' and a.promemoria_inviato_at is null
    and (a.data < current_date or (a.data = current_date and (a.ora is null or a.ora <= localtime + interval '30 minutes')))
$$;

create or replace function public.segna_promemoria_inviato(p_attivita uuid)
returns void language sql security definer set search_path = public as $$
  update attivita set promemoria_inviato_at = now() where id = p_attivita
$$;

-- --------------------------------------------------------------- grant
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;
revoke execute on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated, service_role;

revoke execute on function public.applica_azioni_vocali(uuid, text, jsonb) from public, anon;
grant  execute on function public.applica_azioni_vocali(uuid, text, jsonb) to authenticated;
revoke execute on function public.decidi_comando_vocale(uuid, text, text, boolean) from public, anon, authenticated;
grant  execute on function public.decidi_comando_vocale(uuid, text, text, boolean) to service_role;
revoke execute on function public.proponi_comando_vocale(text, text, text, jsonb, text) from public, anon, authenticated;
grant  execute on function public.proponi_comando_vocale(text, text, text, jsonb, text) to service_role;
revoke execute on function public.contesto_vocale(text, text) from public, anon, authenticated;
revoke execute on function public.contesto_app(uuid) from public, anon;
grant  execute on function public.contesto_app(uuid) to authenticated;
revoke execute on function public.membri_email(uuid) from public, anon;
grant  execute on function public.membri_email(uuid) to authenticated;
grant  execute on function public.contesto_vocale(text, text) to service_role;
revoke execute on function public.collega_telegram(text, text) from public, anon, authenticated;
revoke execute on function public.collega_telegram_da_admin(text, text, text) from public, anon, authenticated;
grant  execute on function public.collega_telegram_da_admin(text, text, text) to service_role;
revoke execute on function public.promemoria_da_inviare() from public, anon, authenticated;
grant  execute on function public.promemoria_da_inviare() to service_role;
revoke execute on function public.segna_promemoria_inviato(uuid) from public, anon, authenticated;
grant  execute on function public.segna_promemoria_inviato(uuid) to service_role;

-- ============================ primo avvio ===============================
-- Dopo questo file esegui primo_avvio.sql (organizzazione, utenti, settori).
