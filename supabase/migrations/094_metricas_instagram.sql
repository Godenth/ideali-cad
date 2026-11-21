-- 094_metricas_instagram.sql  (idempotente)

-- ============================================================
-- 1. Métricas diárias da conta
-- ============================================================
create table if not exists public.conta_metricas_diarias (
  id                uuid        primary key default gen_random_uuid(),
  cliente_id        uuid        not null references auth.users on delete cascade,
  data              date        not null,
  seguidores        int,
  media_count       int,
  alcance           int,
  visualizacoes     int,
  visitas_perfil    int,
  interacoes        int,
  curtidas          int,
  comentarios       int,
  compartilhamentos int,
  salvamentos       int,
  seguidores_ganhos int,
  coletado_em       timestamptz not null default now(),
  constraint conta_metricas_diarias_uniq unique (cliente_id, data)
);

alter table public.conta_metricas_diarias enable row level security;
drop policy if exists "cmd_select" on public.conta_metricas_diarias;
drop policy if exists "cmd_insert" on public.conta_metricas_diarias;
drop policy if exists "cmd_update" on public.conta_metricas_diarias;
create policy "cmd_select" on public.conta_metricas_diarias for select using (cliente_id = auth.uid());
create policy "cmd_insert" on public.conta_metricas_diarias for insert with check (cliente_id = auth.uid());
create policy "cmd_update" on public.conta_metricas_diarias for update using (cliente_id = auth.uid());

-- ============================================================
-- 2. Métricas por post/reel/story
-- ============================================================
create table if not exists public.post_metricas (
  id                uuid        primary key default gen_random_uuid(),
  cliente_id        uuid        not null references auth.users on delete cascade,
  ig_media_id       text        not null,
  tipo              text        not null check (tipo in ('story','reel','feed')),
  legenda           text,
  permalink         text,
  thumbnail_url     text,
  publicado_em      timestamptz,
  coletado_em       timestamptz not null default now(),
  visualizacoes     int,
  alcance           int,
  curtidas          int,
  comentarios       int,
  compartilhamentos int,
  salvamentos       int,
  interacoes        int,
  tempo_medio_reel  numeric(10,2),
  respostas_story   int,
  saidas_story      int,
  constraint post_metricas_uniq unique (cliente_id, ig_media_id)
);

create index if not exists post_metricas_tipo_idx
  on public.post_metricas (cliente_id, tipo, publicado_em desc);

alter table public.post_metricas enable row level security;
drop policy if exists "pm_select" on public.post_metricas;
drop policy if exists "pm_insert" on public.post_metricas;
drop policy if exists "pm_update" on public.post_metricas;
create policy "pm_select" on public.post_metricas for select using (cliente_id = auth.uid());
create policy "pm_insert" on public.post_metricas for insert with check (cliente_id = auth.uid());
create policy "pm_update" on public.post_metricas for update using (cliente_id = auth.uid());
