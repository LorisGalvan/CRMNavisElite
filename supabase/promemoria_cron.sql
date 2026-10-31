-- Promemoria ogni 15 minuti (7-21, ora italiana) tramite la Edge Function crm-bot.
-- Sostituisci PROGETTO con il riferimento del progetto e SEGRETO con il valore
-- del secret CRM_CRON_SECRET delle Edge Functions.
alter database postgres set timezone to 'Europe/Rome';
create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.unschedule(jobid) from cron.job where jobname = 'crm-promemoria';
select cron.schedule('crm-promemoria', '*/15 * * * *', $$
  select net.http_post(
    url := 'https://PROGETTO.supabase.co/functions/v1/crm-bot?promemoria=1',
    headers := jsonb_build_object('x-crm-cron', 'SEGRETO', 'Content-Type', 'application/json'),
    body := '{}'::jsonb)
  where extract(hour from now() at time zone 'Europe/Rome') between 7 and 21
$$);
