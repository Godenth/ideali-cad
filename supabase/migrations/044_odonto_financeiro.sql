-- =====================================================================
-- 044 · Ideali Odonto · Financeiro (etapa 3).
-- Controle por cliente e por mês (valor do mês, pagamentos, comprovantes, extrato),
-- comissão e ajustes (chave Pix, e-mail do resumo).
-- Cada linha tem dono (user_id). RLS: só o dono lê e grava.
-- Arquivos (comprovantes e extratos) ficam no bucket PRIVADO "odonto-fin",
-- na pasta do próprio usuário (<user_id>/...), abertos só por URL assinada.
-- =====================================================================
create table if not exists public.odo_fin_config (
  user_id       uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  chave_pix     text check (char_length(chave_pix) <= 140),
  email_resumo  text check (char_length(email_resumo) <= 120),
  resumo_ativo  boolean not null default false,
  comissao_pct  numeric(5,2) not null default 10 check (comissao_pct between 0 and 100),
  msg_cobranca  text check (char_length(msg_cobranca) <= 1500),
  atualizado_em timestamptz not null default now()
);
alter table public.odo_fin_config enable row level security;
drop policy if exists odo_fin_config_dono on public.odo_fin_config;
create policy odo_fin_config_dono on public.odo_fin_config for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.odo_fin_config from anon;

create table if not exists public.odo_fin_meses (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users(id) on delete cascade,
  cliente_id       uuid references public.odo_clientes(id) on delete set null,
  cliente_reg      integer,
  ano              smallint not null check (ano between 2000 and 2100),
  mes              smallint not null check (mes between 1 and 12),
  valor_mes        numeric(12,2) not null default 0 check (valor_mes >= 0),
  valor_componente numeric(12,2) not null default 0 check (valor_componente >= 0),
  extrato_recebido boolean not null default false,
  enviado          boolean not null default false,   -- extrato/cobrança enviado ao cliente
  quitado          boolean not null default false,
  abater_credito   boolean,                          -- crédito do mês anterior: null = decidir, true = abater, false = não abater
  comissionado     numeric(12,2) not null default 0, -- quanto do pago já entrou em saque de comissão
  confirmado_inove boolean not null default true,
  obs              text check (char_length(obs) <= 1000),
  extrato_path     text check (char_length(extrato_path) <= 300),
  arquivo_legado   text check (char_length(arquivo_legado) <= 300), -- caminho do extrato no sistema antigo
  legado           text check (char_length(legado) <= 60),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  unique (user_id, cliente_id, ano, mes),
  unique (user_id, legado)
);
create index if not exists odo_fin_meses_dono on public.odo_fin_meses (user_id, ano, mes);
alter table public.odo_fin_meses enable row level security;
drop policy if exists odo_fin_meses_dono on public.odo_fin_meses;
create policy odo_fin_meses_dono on public.odo_fin_meses for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.odo_fin_meses from anon;

create table if not exists public.odo_fin_pagamentos (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users(id) on delete cascade,
  mes_id           uuid not null references public.odo_fin_meses(id) on delete cascade,
  valor            numeric(12,2) not null check (valor > 0),
  data             date,
  comprovante_path text check (char_length(comprovante_path) <= 300),
  arquivo_legado   text check (char_length(arquivo_legado) <= 300),
  obs              text check (char_length(obs) <= 500),
  conferencia      text check (conferencia in ('ok','diverge','sem_leitura')),
  anulado_em       timestamptz,
  anulado_motivo   text check (char_length(anulado_motivo) <= 300),
  legado           text check (char_length(legado) <= 60),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  unique (user_id, legado)
);
create index if not exists odo_fin_pag_mes on public.odo_fin_pagamentos (mes_id);
alter table public.odo_fin_pagamentos enable row level security;
drop policy if exists odo_fin_pag_dono on public.odo_fin_pagamentos;
create policy odo_fin_pag_dono on public.odo_fin_pagamentos for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.odo_fin_pagamentos from anon;

create table if not exists public.odo_fin_comissoes (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users(id) on delete cascade,
  ano             smallint,
  mes             smallint,
  valor_total     numeric(12,2) not null check (valor_total >= 0),
  valor_calculado numeric(12,2),
  detalhes        jsonb not null default '[]'::jsonb check (pg_column_size(detalhes) < 60000),
  data            timestamptz not null default now(),
  legado          text check (char_length(legado) <= 60),
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  unique (user_id, legado)
);
alter table public.odo_fin_comissoes enable row level security;
drop policy if exists odo_fin_com_dono on public.odo_fin_comissoes;
create policy odo_fin_com_dono on public.odo_fin_comissoes for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.odo_fin_comissoes from anon;

-- dono fixo + data de atualização do servidor (função da 042)
do $t$ declare t text; begin
  foreach t in array array['odo_fin_config','odo_fin_meses','odo_fin_pagamentos','odo_fin_comissoes'] loop
    execute format('drop trigger if exists %I on public.%I', t||'_dono', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.odo_dono_fixo()', t||'_dono', t);
  end loop; end $t$;

-- cliente e mês têm que ser do mesmo dono
create or replace function public.odo_fin_confere() returns trigger language plpgsql as $$
begin
  if tg_table_name = 'odo_fin_meses' then
    if new.cliente_id is not null and not exists (select 1 from public.odo_clientes c where c.id = new.cliente_id and c.user_id = new.user_id) then
      raise exception 'cliente inválido'; end if;
  elsif tg_table_name = 'odo_fin_pagamentos' then
    if not exists (select 1 from public.odo_fin_meses m where m.id = new.mes_id and m.user_id = new.user_id) then
      raise exception 'mês inválido'; end if;
  end if;
  return new; end $$;
drop trigger if exists odo_fin_meses_confere on public.odo_fin_meses;
create trigger odo_fin_meses_confere before insert or update on public.odo_fin_meses for each row execute function public.odo_fin_confere();
drop trigger if exists odo_fin_pag_confere on public.odo_fin_pagamentos;
create trigger odo_fin_pag_confere before insert or update on public.odo_fin_pagamentos for each row execute function public.odo_fin_confere();

-- bucket privado para comprovantes e extratos (até 10 MB, só PDF e imagem)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('odonto-fin', 'odonto-fin', false, 10485760, array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists odonto_fin_ler on storage.objects;
create policy odonto_fin_ler on storage.objects for select to authenticated
  using (bucket_id = 'odonto-fin' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists odonto_fin_gravar on storage.objects;
create policy odonto_fin_gravar on storage.objects for insert to authenticated
  with check (bucket_id = 'odonto-fin' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists odonto_fin_trocar on storage.objects;
create policy odonto_fin_trocar on storage.objects for update to authenticated
  using (bucket_id = 'odonto-fin' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'odonto-fin' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists odonto_fin_apagar on storage.objects;
create policy odonto_fin_apagar on storage.objects for delete to authenticated
  using (bucket_id = 'odonto-fin' and (storage.foldername(name))[1] = (select auth.uid())::text);
