-- =====================================================================
-- Network CRM · primo avvio (da eseguire UNA volta, dopo schema.sql)
--
-- Prima di eseguirlo: Authentication → Users → "Invite user" per
--   loris4386@gmail.com ed enrico.berte@gmail.com
-- (ognuno riceve una mail per scegliere la password).
-- Gli account non ancora creati vengono saltati: si può rieseguire
-- in seguito senza creare doppioni.
-- =====================================================================

-- organizzazione
insert into organizzazioni (nome)
select 'Network CRM' where not exists (select 1 from organizzazioni);

-- settori (se ne aggiungono altri in qualsiasi momento con una riga in più)
insert into settori (org_id, nome, colore)
select o.id, s.nome, s.colore
from organizzazioni o,
     (values ('Nautica', '#1f5f99'), ('Immobiliare', '#7a4a9e'), ('Fornitori', '#2f7d5b'), ('Personale', '#a06a12')) s(nome, colore)
on conflict (org_id, nome) do nothing;

-- utenti: Loris ed Enrico, entrambi amministratori
insert into membri (org_id, user_id, nome, ruolo)
select o.id, u.id, v.nome, v.ruolo::ruolo_utente
from organizzazioni o
cross join (values
  ('loris4386@gmail.com',    'Loris',           'admin'),
  ('enrico.berte@gmail.com', 'Enrico Bertelli', 'admin')
) v(email, nome, ruolo)
join auth.users u on lower(u.email) = v.email
on conflict (org_id, user_id) do nothing;

-- settori: gli amministratori li hanno tutti (un collaboratore futuro avrà solo i suoi)
insert into membri_settori (org_id, user_id, settore_id)
select m.org_id, m.user_id, s.id
from membri m
join auth.users u on u.id = m.user_id
join settori s on s.org_id = m.org_id
where m.ruolo = 'admin'
on conflict do nothing;

-- controllo
select u.email, m.nome, m.ruolo, string_agg(s.nome, ', ' order by s.nome) as settori
from membri m join auth.users u on u.id = m.user_id
left join membri_settori ms on ms.user_id = m.user_id
left join settori s on s.id = ms.settore_id
group by 1, 2, 3 order by 3, 2;

-- ---------------------------------------------------------------------
-- Telegram: scrivi /start al bot, che risponde con il tuo codice, ed esegui
-- QUESTA SOLA RIGA (è l'unica volta che serve l'editor SQL):
--
--   select collega_telegram('loris4386@gmail.com', 'IL_TUO_CODICE');
--
-- Gli altri li colleghi direttamente da Telegram: fanno /start, ti mandano il
-- loro codice e tu scrivi al bot:  /collega enrico.berte@gmail.com CODICE
--
-- Un nuovo settore, in futuro:
--   insert into settori (org_id, nome, colore) select id, 'Charter', '#0f7c86' from organizzazioni;
--   insert into membri_settori (org_id, user_id, settore_id)
--     select m.org_id, m.user_id, s.id from membri m join settori s on s.org_id = m.org_id
--     where m.ruolo = 'admin' and s.nome = 'Charter';
-- ---------------------------------------------------------------------
