-- Prova dei permessi: crea un'organizzazione con admin, collaboratore e sola lettura e controlla cosa vede e può fare ciascuno.
\set ON_ERROR_STOP 1
grant usage on schema public to authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;
insert into auth.users values ('00000000-0000-0000-0000-00000000000a','admin@x'),('00000000-0000-0000-0000-00000000000b','paolo@x'),('00000000-0000-0000-0000-00000000000c','sara@x');
insert into organizzazioni(id,nome) values ('10000000-0000-0000-0000-000000000000','Org');
insert into membri values ('10000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-00000000000a','Admin','admin',true),
 ('10000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-00000000000b','Paolo','collaboratore',true),
 ('10000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-00000000000c','Sara','lettura',true);
insert into settori(id,org_id,nome) values ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000000','Nautica'),('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000000','Immobiliare');
insert into membri_settori values ('10000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-00000000000b','20000000-0000-0000-0000-000000000002'),('10000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-00000000000c','20000000-0000-0000-0000-000000000001');
insert into canali_utente values ('10000000-0000-0000-0000-000000000000','00000000-0000-0000-0000-00000000000b','telegram','555');
-- admin crea dati
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
insert into persone(id,org_id,nome,visibilita) values ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000000','Marco Rossi','tutti'),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000000','Anna Verdi','settore'),
 ('30000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000000','Giorgio Galli','settore'),
 ('30000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000000','Davide Costa','privato');
insert into persone_settori values ('30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002'),('30000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001');
insert into relazioni(org_id,da,a,tipo) values ('10000000-0000-0000-0000-000000000000','30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002','collaborazione'),
 ('10000000-0000-0000-0000-000000000000','30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000003','amicizia'),
 ('10000000-0000-0000-0000-000000000000','30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000004','amicizia');
select 'admin vede', count(*) from persone; select 'admin rel', count(*) from relazioni;
-- paolo (collaboratore immobiliare)
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select 'paolo vede', string_agg(nome, ', ' order by nome) from persone; select 'paolo rel', count(*) from relazioni;
select 'paolo voce', public.applica_azioni_vocali('10000000-0000-0000-0000-000000000000','test','[{"tipo":"crea_persona","nome":"Franco Moretti","settori":["Immobiliare"]},{"tipo":"crea_relazione","da":"Marco Rossi","a":"Franco Moretti","relazione":"presentazione"},{"tipo":"crea_relazione","da":"Marco Rossi","a":"Giorgio Galli"},{"tipo":"registra_contatto","persona":"Anna","canale":"chiamata","testo":"ok"},{"tipo":"crea_attivita","persona":"Anna Verdi","attivita":"chiamata","data":"2030-01-01","ora":"10:00","testo":"Richiamare"},{"tipo":"crea_trattativa","titolo":"Villa","persona":"Marco Rossi","settore":"Nautica","importo":1000}]'::jsonb)->'esito';
select 'anna ultimo', ultimo_contatto = current_date from persone where nome='Anna Verdi';
select 'tratt settore', s.nome from trattative t join settori s on s.id=t.settore_id;
-- sara (sola lettura)
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
select 'sara vede', string_agg(nome, ', ' order by nome) from persone;
do $$ begin insert into persone(org_id,nome) values ('10000000-0000-0000-0000-000000000000','X'); raise notice 'ERRORE: sara ha scritto'; exception when insufficient_privilege then raise notice 'ok: sara bloccata'; end $$;
do $$ begin perform public.applica_azioni_vocali('10000000-0000-0000-0000-000000000000','t','[]'); raise notice 'ERRORE'; exception when insufficient_privilege then raise notice 'ok: sara bloccata a voce'; end $$;
do $$ begin perform public.contesto_vocale('telegram','555'); raise notice 'ERRORE contesto'; exception when insufficient_privilege then raise notice 'ok: contesto riservato a n8n'; end $$;
reset role;
set role service_role;
select 'n8n contesto', jsonb_array_length(public.contesto_vocale('telegram','555')->'persone');
select public.proponi_comando_vocale('telegram','555','x','[{"tipo":"aggiungi_nota","persona":"Davide Costa","testo":"spia"},{"tipo":"aggiungi_nota","persona":"Anna Verdi","testo":"nota ok"}]','') ->>'id' as id \gset
do $$ begin perform public.decidi_comando_vocale((select id from comandi_vocali where canale='telegram'),'telegram','999',true); raise notice 'ERRORE altro chat'; exception when insufficient_privilege then raise notice 'ok: altra chat rifiutata'; end $$;
select 'n8n conferma', public.decidi_comando_vocale(:'id','telegram','555',true)->'esito';
select 'n8n ripete', public.decidi_comando_vocale(:'id','telegram','555',true)->>'stato';
select 'promemoria', count(*) from public.promemoria_da_inviare();
select 'registro', via, tabella, operazione, count(*) from registro group by 1,2,3,4 order by 2,3,4;
-- primo avvio con gli utenti reali e collegamento Telegram
reset role;
delete from organizzazioni;
insert into auth.users values ('00000000-0000-0000-0000-0000000000a1','loris4386@gmail.com'),('00000000-0000-0000-0000-0000000000a2','Enrico.Berte@gmail.com');
\ir ../primo_avvio.sql
\ir ../primo_avvio.sql
select 'telegram loris', public.collega_telegram('loris4386@gmail.com', '111');
select 'collega da sconosciuto', public.collega_telegram_da_admin('999', 'enrico.berte@gmail.com', '777')->>'ok';
select 'collega email errata', public.collega_telegram_da_admin('111', 'nessuno@x.it', '777')->>'errore';
select 'collega da admin', public.collega_telegram_da_admin('111', 'ENRICO.berte@gmail.com', ' 777 ')->>'messaggio';
select 'enrico contesto', public.contesto_vocale('telegram','777')->>'nome';
