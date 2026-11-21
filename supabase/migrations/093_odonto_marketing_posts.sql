-- 093_odonto_marketing_posts.sql  (idempotente — pode rodar várias vezes)
-- Publicação real de posts do Instagram pelo Estúdio da Mika

-- ============================================================
-- 1. Extensões
-- ============================================================
create extension if not exists "pg_cron" with schema pg_catalog;
create extension if not exists "pg_net" with schema extensions;

-- ============================================================
-- 2. Tabela posts_agendados
-- ============================================================
create table if not exists public.posts_agendados (
  id               uuid        primary key default gen_random_uuid(),
  cliente_id       uuid        not null references auth.users on delete cascade default auth.uid(),
  tipo             text        not null check (tipo in ('story','reel','feed')),
  midia_url        text,
  legenda          text,
  hashtags         text,
  agendado_para    timestamptz not null,
  status           text        not null default 'rascunho'
                               check (status in ('rascunho','aguardando','aprovado','publicando','publicado','erro')),
  ig_container_id  text,
  ig_media_id      text,
  erro             text,
  criado_em        timestamptz not null default now()
);

create index if not exists posts_agendados_cliente_idx
  on public.posts_agendados (cliente_id);

create index if not exists posts_agendados_fila_idx
  on public.posts_agendados (status, agendado_para)
  where status = 'aprovado';

-- ============================================================
-- 3. RLS
-- ============================================================
alter table public.posts_agendados enable row level security;

drop policy if exists "pa_select" on public.posts_agendados;
drop policy if exists "pa_insert" on public.posts_agendados;
drop policy if exists "pa_update" on public.posts_agendados;
drop policy if exists "pa_delete" on public.posts_agendados;

create policy "pa_select" on public.posts_agendados
  for select using (cliente_id = auth.uid());

create policy "pa_insert" on public.posts_agendados
  for insert with check (cliente_id = auth.uid());

create policy "pa_update" on public.posts_agendados
  for update using (cliente_id = auth.uid());

create policy "pa_delete" on public.posts_agendados
  for delete using (cliente_id = auth.uid());

-- ============================================================
-- 4. Storage bucket "marketing" (URL pública — Instagram exige)
-- ============================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'marketing',
  'marketing',
  true,
  104857600,
  array['image/jpeg','image/jpg','image/png','image/webp','video/mp4','video/quicktime','video/mov']
)
on conflict (id) do update set
  public            = true,
  file_size_limit   = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "mkt_upload"        on storage.objects;
drop policy if exists "mkt_read_public"   on storage.objects;
drop policy if exists "mkt_delete_owner"  on storage.objects;

create policy "mkt_upload" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'marketing'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "mkt_read_public" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'marketing');

create policy "mkt_delete_owner" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'marketing'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ============================================================
-- 5. pg_cron: instagram-fila a cada 5 minutos
-- ============================================================
-- ATENÇÃO: substitua COLOQUE_O_CRON_SECRET_ABAIXO pelo valor
-- que você definiu com: supabase secrets set CRON_SECRET=...

select cron.unschedule('instagram-fila-5min')
  from cron.job
 where jobname = 'instagram-fila-5min';

select cron.schedule(
  'instagram-fila-5min',
  '*/5 * * * *',
  $job$
  select
    net.http_post(
      url     := 'https://qxspiaqaigjkmilxxfri.supabase.co/functions/v1/instagram-fila',
      headers := '{"Content-Type":"application/json","x-cron-secret":"COLOQUE_O_CRON_SECRET_ABAIXO"}'::jsonb,
      body    := '{}'::jsonb
    );
  $job$
);
