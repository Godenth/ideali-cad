-- 096_mkt_temas_drive.sql  (idempotente)
-- Estúdio da Mika · ETAPA 1: temas do Drive, geração de imagens, carrossel

-- ============================================================
-- 1. Perfil da marca: campos visuais
-- ============================================================
alter table public.mkt_perfil_marca
  add column if not exists logo_url        text,
  add column if not exists cor_principal   text default '#2F6FD6',
  add column if not exists cor_secundaria  text default '#1A1A2E',
  add column if not exists fonte           text default 'Inter';

-- ============================================================
-- 2. Temas (subpastas do Google Drive)
-- ============================================================
create table if not exists public.mkt_temas (
  id               uuid        primary key default gen_random_uuid(),
  cliente_id       uuid        not null references auth.users on delete cascade default auth.uid(),
  nome             text        not null,
  drive_folder_id  text,
  texto_base       text,
  ativo            boolean     not null default true,
  sincronizado_em  timestamptz,
  criado_em        timestamptz not null default now()
);
create index if not exists mkt_temas_cliente on public.mkt_temas (cliente_id);
alter table public.mkt_temas enable row level security;
drop policy if exists "mt_all"    on public.mkt_temas;
create policy "mt_all" on public.mkt_temas for all to authenticated
  using (cliente_id = auth.uid()) with check (cliente_id = auth.uid());

-- ============================================================
-- 3. Mídias de cada tema (imagens, vídeos, docs do Drive)
-- ============================================================
create table if not exists public.mkt_tema_midias (
  id               uuid        primary key default gen_random_uuid(),
  tema_id          uuid        not null references public.mkt_temas on delete cascade,
  drive_file_id    text        not null,
  modified_time    timestamptz,
  arquivo_url      text,
  tipo             text        not null check (tipo in ('imagem','video','texto')),
  descricao        text,        -- gerada pela Mika (visão)
  ativo            boolean     not null default true,
  criado_em        timestamptz not null default now(),
  unique (tema_id, drive_file_id)
);
create index if not exists mkt_tema_midias_tema on public.mkt_tema_midias (tema_id);
-- RLS via JOIN no tema (cliente_id)
alter table public.mkt_tema_midias enable row level security;
drop policy if exists "mtm_all" on public.mkt_tema_midias;
create policy "mtm_all" on public.mkt_tema_midias for all to authenticated
  using (exists (select 1 from public.mkt_temas t where t.id = tema_id and t.cliente_id = auth.uid()))
  with check (exists (select 1 from public.mkt_temas t where t.id = tema_id and t.cliente_id = auth.uid()));

-- ============================================================
-- 4. posts_agendados: carrossel + slides + tema + horário
-- ============================================================
-- Adicionar 'carrossel' ao tipo
alter table public.posts_agendados
  drop constraint if exists posts_agendados_tipo_check;
alter table public.posts_agendados
  add constraint posts_agendados_tipo_check
  check (tipo in ('story','reel','feed','carrossel'));

alter table public.posts_agendados
  add column if not exists slides          jsonb,          -- [{layout, titulo, texto, print_id, png_path}]
  add column if not exists tema_id         uuid references public.mkt_temas on delete set null,
  add column if not exists horario_sugerido timestamptz,
  add column if not exists gerado_por_mika boolean not null default false;

-- ============================================================
-- 5. Controle de uso diário da Mika (máx 20 peças/dia/cliente)
-- ============================================================
create table if not exists public.mkt_mika_uso (
  id          uuid        primary key default gen_random_uuid(),
  cliente_id  uuid        not null references auth.users on delete cascade,
  dia         date        not null default current_date,
  pecas       integer     not null default 0,
  unique (cliente_id, dia)
);
alter table public.mkt_mika_uso enable row level security;
drop policy if exists "mmu_sel" on public.mkt_mika_uso;
create policy "mmu_sel" on public.mkt_mika_uso for select to authenticated
  using (cliente_id = auth.uid());
-- inserção/atualização só via service role (edge function)

-- ============================================================
-- 6. cron: drive-sincronizar a cada hora
-- ============================================================
select cron.unschedule('drive-sincronizar-1h')
  from cron.job
 where jobname = 'drive-sincronizar-1h';

select cron.schedule(
  'drive-sincronizar-1h',
  '0 * * * *',
  $job$
  select
    net.http_post(
      url     := 'https://qxspiaqaigjkmilxxfri.supabase.co/functions/v1/drive-sincronizar',
      headers := '{"Content-Type":"application/json","x-cron-secret":"COLOQUE_O_CRON_SECRET_ABAIXO"}'::jsonb,
      body    := '{}'::jsonb
    );
  $job$
);

select 'ok: 096 pronta' as resultado;
