-- 083 · Tarefas com o Pedro (estagiário): quadro A fazer / Fazendo / Aguardando / Feito.
-- Cada conta vê SÓ as próprias tarefas (RLS por user_id). Pode rodar mais de uma vez.
create table if not exists public.odo_tarefas (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  titulo     text not null check (char_length(titulo) between 1 and 300),
  tipo       text not null default 'Outro' check (tipo in ('Pedido','Cliente','Prazo','Financeiro','Agenda','Outro')),
  coluna     text not null default 'fazer' check (coluna in ('fazer','fazendo','aguardando','feito')),
  vence      date,
  hora       time,
  obs        text check (char_length(obs) <= 1000),
  ordem      double precision not null default 0,
  feito_em   timestamptz,
  criado_em  timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists odo_tarefas_user on public.odo_tarefas(user_id, coluna, ordem);
alter table public.odo_tarefas enable row level security;
drop policy if exists odo_tarefas_dono on public.odo_tarefas;
create policy odo_tarefas_dono on public.odo_tarefas for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.odo_tarefas from anon;
grant select, insert, update, delete on public.odo_tarefas to authenticated;
create or replace function public.odo_tarefas_toca() returns trigger language plpgsql set search_path = '' as $$
begin new.atualizado_em := now(); new.user_id := old.user_id;
  if new.coluna = 'feito' and old.coluna <> 'feito' then new.feito_em := now(); end if;
  if new.coluna <> 'feito' then new.feito_em := null; end if;
  return new; end $$;
drop trigger if exists odo_tarefas_toca on public.odo_tarefas;
create trigger odo_tarefas_toca before update on public.odo_tarefas for each row execute function public.odo_tarefas_toca();
