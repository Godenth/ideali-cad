-- =====================================================================
-- 045 · Ideali Odonto · Resumo diário por e-mail (todo dia às 7h de Brasília).
-- O banco chama a função "odo-resumo" uma vez por dia com um segredo aleatório
-- guardado no Vault (cofre do Supabase). Ninguém precisa copiar esse segredo.
-- Rode DEPOIS de criar a função odo-resumo no painel (Edge Functions).
-- =====================================================================
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- segredo aleatório (só é criado uma vez)
do $s$ begin
  if not exists (select 1 from vault.secrets where name = 'odo_resumo_segredo') then
    perform vault.create_secret(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'odo_resumo_segredo', 'Chamada diária do resumo do Ideali Odonto');
  end if; end $s$;

-- a função confere o segredo sem nunca expor o valor
create or replace function public.odo_resumo_confere(p text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from vault.decrypted_secrets where name = 'odo_resumo_segredo' and decrypted_secret = p);
$$;
revoke all on function public.odo_resumo_confere(text) from public, anon, authenticated;
grant execute on function public.odo_resumo_confere(text) to service_role;

-- agenda: 10:00 UTC = 7:00 em Brasília
select cron.unschedule('odo-resumo-diario') where exists (select 1 from cron.job where jobname = 'odo-resumo-diario');
select cron.schedule('odo-resumo-diario', '0 10 * * *', $c$
  select net.http_post(
    url := 'https://qxspiaqaigjkmilxxfri.supabase.co/functions/v1/odo-resumo',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-resumo', (select decrypted_secret from vault.decrypted_secrets where name = 'odo_resumo_segredo')),
    body := '{}'::jsonb);
$c$);
select jobname, schedule, active from cron.job where jobname = 'odo-resumo-diario';
