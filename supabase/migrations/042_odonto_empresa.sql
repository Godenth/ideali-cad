-- =====================================================================
-- 042 · Ideali Odonto · Empresa de verdade (etapa 1): negócio, clientes e tabela de preços no banco.
-- Cada empresa tem um dono (user_id). RLS: só o dono lê e grava. Nada disso aparece para outras contas.
-- =====================================================================
create table if not exists public.odo_empresas (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  tipo       text not null check (tipo in ('clinica','lab','centro','auto','dental','escola')),
  nome       text not null check (char_length(nome) between 2 and 80),
  uf         text check (uf ~ '^[A-Z]{2}$'),
  cidade     text check (char_length(cidade) <= 60),
  papel      text check (papel in ('faz','gestao')),
  rt         text check (char_length(rt) <= 80),
  dados      jsonb not null default '{}'::jsonb check (pg_column_size(dados) < 60000),  -- equipe, vagas e ajustes da tela
  criado_em  timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (user_id)
);
alter table public.odo_empresas enable row level security;
drop policy if exists odo_empresas_dono on public.odo_empresas;
create policy odo_empresas_dono on public.odo_empresas for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.odo_empresas from anon;

create table if not exists public.odo_clientes (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  reg        integer,                                   -- número do cliente no sistema antigo
  nome       text not null check (char_length(nome) between 1 and 120),
  documento  text check (char_length(documento) <= 20),  -- CPF ou CNPJ
  cro        text check (char_length(cro) <= 30),
  endereco   text check (char_length(endereco) <= 160),
  bairro     text check (char_length(bairro) <= 80),
  cidade     text check (char_length(cidade) <= 80),
  uf         text check (char_length(uf) <= 2),
  cep        text check (char_length(cep) <= 10),
  telefone   text check (char_length(telefone) <= 30),
  whatsapp   text check (char_length(whatsapp) <= 30),
  email      text check (char_length(email) <= 120),
  obs        text check (char_length(obs) <= 1000),
  regra      text check (char_length(regra) <= 1000),   -- regra padrão do cliente (ex.: não cimentar componente)
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (user_id, reg)
);
create index if not exists odo_clientes_dono on public.odo_clientes (user_id, nome);
alter table public.odo_clientes enable row level security;
drop policy if exists odo_clientes_dono on public.odo_clientes;
create policy odo_clientes_dono on public.odo_clientes for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.odo_clientes from anon;

create table if not exists public.odo_precos (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nome       text not null check (char_length(nome) between 1 and 120),
  grupo      text check (char_length(grupo) <= 40),
  valor      numeric(10,2) check (valor >= 0),
  prazo      smallint check (prazo between 0 and 90),
  obs        text check (char_length(obs) <= 200),
  ordem      integer not null default 0,
  criado_em  timestamptz not null default now(),
  unique (user_id, nome)
);
alter table public.odo_precos enable row level security;
drop policy if exists odo_precos_dono on public.odo_precos;
create policy odo_precos_dono on public.odo_precos for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.odo_precos from anon;

-- o dono nunca muda e a data de atualização é sempre a do servidor
create or replace function public.odo_dono_fixo() returns trigger language plpgsql as $$
begin if tg_op = 'UPDATE' then new.user_id := old.user_id; end if;
  if tg_table_name <> 'odo_precos' then new.atualizado_em := now(); end if; return new; end $$;
drop trigger if exists odo_empresas_dono on public.odo_empresas;
create trigger odo_empresas_dono before update on public.odo_empresas for each row execute function public.odo_dono_fixo();
drop trigger if exists odo_clientes_dono on public.odo_clientes;
create trigger odo_clientes_dono before update on public.odo_clientes for each row execute function public.odo_dono_fixo();
drop trigger if exists odo_precos_dono on public.odo_precos;
create trigger odo_precos_dono before update on public.odo_precos for each row execute function public.odo_dono_fixo();
