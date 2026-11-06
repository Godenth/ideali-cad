-- =====================================================================
-- 043 · Ideali Odonto · Pedidos e produção (etapa 2).
-- As antigas "Ordens CAM" viram pedidos do tipo CAD: ficam roxos em "Desenho CAD a fazer"
-- e, quando o desenho é feito e enviado à Inove, passam para "Em produção".
-- Cada linha tem dono (user_id). RLS: só o dono lê e grava.
-- =====================================================================
create table if not exists public.odo_cadistas (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  reg        integer,                                   -- número no sistema antigo
  nome       text not null check (char_length(nome) between 1 and 80),
  email      text check (char_length(email) <= 120),
  tel        text check (char_length(tel) <= 30),
  cnpj       text check (char_length(cnpj) <= 20),
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (user_id, reg)
);
alter table public.odo_cadistas enable row level security;
drop policy if exists odo_cadistas_dono on public.odo_cadistas;
create policy odo_cadistas_dono on public.odo_cadistas for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.odo_cadistas from anon;

create table if not exists public.odo_pedidos (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users(id) on delete cascade,
  numero         integer,
  cliente_id     uuid references public.odo_clientes(id) on delete set null,
  cliente_reg    integer,
  cliente_nome   text check (char_length(cliente_nome) <= 120),
  paciente       text check (char_length(paciente) <= 120),
  tipo           text not null default 'cad' check (tipo in ('cad','analogico')),
  trabalho       text check (char_length(trabalho) <= 120),
  descricao      text check (char_length(descricao) <= 4000),
  dentes         smallint[] check (cardinality(dentes) <= 32),
  qtd            smallint check (qtd between 0 and 99),
  cor            text check (char_length(cor) <= 20),
  material       text check (char_length(material) <= 60),
  sobre_implante boolean not null default false,
  componente     text check (char_length(componente) <= 120),
  valor          numeric(10,2) check (valor >= 0),
  prazo          date,
  urgente        boolean not null default false,
  status         text not null default 'desenho' check (status in ('orcamento','desenho','producao','finalizado','entregue','cancelado')),
  desenho_feito  boolean not null default false,
  enviado_inove  boolean not null default false,
  cadista_id     uuid references public.odo_cadistas(id) on delete set null,
  cadista_nome   text check (char_length(cadista_nome) <= 80),
  origem         text check (origem in ('whatsapp','email','portal','manual')),
  obs            text check (char_length(obs) <= 1000),
  arquivado      boolean not null default false,
  apagado        boolean not null default false,
  legado         text check (char_length(legado) <= 60),  -- id no sistema antigo (p: pedido, o: ordem CAM)
  finalizado_em  timestamptz,
  entregue_em    timestamptz,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (user_id, legado)
);
create index if not exists odo_pedidos_dono on public.odo_pedidos (user_id, numero desc);
create index if not exists odo_pedidos_status on public.odo_pedidos (user_id, status) where not arquivado and not apagado;
alter table public.odo_pedidos enable row level security;
drop policy if exists odo_pedidos_dono on public.odo_pedidos;
create policy odo_pedidos_dono on public.odo_pedidos for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.odo_pedidos from anon;

-- o dono nunca muda; data de atualização sempre do servidor (função da 042)
drop trigger if exists odo_cadistas_dono on public.odo_cadistas;
create trigger odo_cadistas_dono before update on public.odo_cadistas for each row execute function public.odo_dono_fixo();
drop trigger if exists odo_pedidos_dono on public.odo_pedidos;
create trigger odo_pedidos_dono before update on public.odo_pedidos for each row execute function public.odo_dono_fixo();

-- o cliente e o cadista de um pedido têm que ser do mesmo dono do pedido
create or replace function public.odo_pedidos_confere() returns trigger language plpgsql as $$
begin
  if new.cliente_id is not null and not exists (select 1 from public.odo_clientes c where c.id = new.cliente_id and c.user_id = new.user_id) then
    raise exception 'cliente inválido'; end if;
  if new.cadista_id is not null and not exists (select 1 from public.odo_cadistas c where c.id = new.cadista_id and c.user_id = new.user_id) then
    raise exception 'cadista inválido'; end if;
  return new; end $$;
drop trigger if exists odo_pedidos_confere on public.odo_pedidos;
create trigger odo_pedidos_confere before insert or update on public.odo_pedidos for each row execute function public.odo_pedidos_confere();
