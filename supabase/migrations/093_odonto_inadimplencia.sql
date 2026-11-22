-- =====================================================================
-- 093 · Ideali Odonto · Inadimplência
-- Dívidas de clientes → acordos parcelados (dono paga 60% à Inove)
--   → recuperação quando cliente paga o dono (dono paga 40% à Inove).
--
-- CONSTANTES (edite aqui para ajustar o negócio):
--   inad_pct_pagar    = 60   (% da dívida que o dono paga à Inove)
--   inad_max_parcelas = 5    (máximo de parcelas por acordo)
-- Ficam em odo_fin_config (por conta), com esses valores como default.
-- =====================================================================

-- ---- Constantes em odo_fin_config (idempotente) -------------------
alter table public.odo_fin_config
  add column if not exists inad_pct_pagar    numeric(5,2) not null default 60;
alter table public.odo_fin_config
  add column if not exists inad_max_parcelas smallint     not null default 5;

-- ---- Tabela 1: dívidas individuais --------------------------------
create table if not exists public.odo_fin_inad_dividas (
  id               uuid        primary key default gen_random_uuid(),
  user_id          uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  mes_id           uuid        references public.odo_fin_meses(id) on delete set null,
  cliente_id       uuid        references public.odo_clientes(id) on delete set null,
  ano              smallint    not null check (ano between 2000 and 2100),
  mes              smallint    not null check (mes between 1 and 12),
  valor_divida     numeric(12,2) not null check (valor_divida >= 0),
  acordo_id        uuid,                              -- FK adicionada após odo_fin_inad_acordos
  status           text        not null default 'aberta' check (status in ('aberta','acordo','recuperada')),
  recuperado_valor numeric(12,2) check (recuperado_valor >= 0),
  recuperado_em    date,
  obs              text        check (char_length(obs) <= 1000),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  unique (user_id, mes_id)                           -- mesmo mês não entra duas vezes
);
create index if not exists odo_fin_inad_div_dono on public.odo_fin_inad_dividas (user_id);
create index if not exists odo_fin_inad_div_mes  on public.odo_fin_inad_dividas (mes_id);
alter table public.odo_fin_inad_dividas enable row level security;
drop policy if exists odo_fin_inad_dividas_dono on public.odo_fin_inad_dividas;
create policy odo_fin_inad_dividas_dono on public.odo_fin_inad_dividas for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.odo_fin_inad_dividas from anon;

-- ---- Tabela 2: acordos de parcelamento ----------------------------
create table if not exists public.odo_fin_inad_acordos (
  id            uuid        primary key default gen_random_uuid(),
  user_id       uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  valor_dividas numeric(12,2) not null check (valor_dividas >= 0),
  pct_pagar     numeric(5,2) not null default 60 check (pct_pagar between 0 and 100),
  valor_acordo  numeric(12,2) not null check (valor_acordo >= 0),
  n_parcelas    smallint    not null check (n_parcelas between 1 and 24),  -- app limita pelo inad_max_parcelas
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists odo_fin_inad_ac_dono on public.odo_fin_inad_acordos (user_id);
alter table public.odo_fin_inad_acordos enable row level security;
drop policy if exists odo_fin_inad_acordos_dono on public.odo_fin_inad_acordos;
create policy odo_fin_inad_acordos_dono on public.odo_fin_inad_acordos for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.odo_fin_inad_acordos from anon;

-- FK circular: dividas → acordos (idempotente)
do $$begin
  alter table public.odo_fin_inad_dividas
    add constraint odo_fin_inad_dividas_acordo_fk
    foreign key (acordo_id) references public.odo_fin_inad_acordos(id) on delete set null;
exception when duplicate_object then null; end$$;

-- ---- Tabela 3: parcelas (pagamento do dono ou recuperação) --------
-- tipo='parcela'     → acordo_id não-nulo, divida_id nulo  (dono paga à Inove)
-- tipo='recuperacao' → divida_id não-nulo, acordo_id nulo  (cliente pagou o dono; dono deve 40% à Inove)
create table if not exists public.odo_fin_inad_parcelas (
  id               uuid        primary key default gen_random_uuid(),
  user_id          uuid        not null default auth.uid() references auth.users(id) on delete cascade,
  acordo_id        uuid        references public.odo_fin_inad_acordos(id) on delete cascade,
  divida_id        uuid        references public.odo_fin_inad_dividas(id) on delete cascade,
  tipo             text        not null check (tipo in ('parcela','recuperacao')),
  numero           smallint    not null check (numero >= 1),
  vencimento       date,
  valor            numeric(12,2) not null check (valor >= 0),
  pago_em          date,
  comprovante_path text        check (char_length(comprovante_path) <= 300),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  constraint inad_parc_tipo_ref check (
    (tipo = 'parcela'     and acordo_id is not null and divida_id is null) or
    (tipo = 'recuperacao' and divida_id is not null and acordo_id is null)
  )
);
create index if not exists odo_fin_inad_par_dono   on public.odo_fin_inad_parcelas (user_id);
create index if not exists odo_fin_inad_par_acordo on public.odo_fin_inad_parcelas (acordo_id);
create index if not exists odo_fin_inad_par_divida on public.odo_fin_inad_parcelas (divida_id);
alter table public.odo_fin_inad_parcelas enable row level security;
drop policy if exists odo_fin_inad_parcelas_dono on public.odo_fin_inad_parcelas;
create policy odo_fin_inad_parcelas_dono on public.odo_fin_inad_parcelas for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.odo_fin_inad_parcelas from anon;

-- ---- Triggers: dono fixo (mesmo padrão da 044) --------------------
do $t$ declare t text; begin
  foreach t in array array['odo_fin_inad_dividas','odo_fin_inad_acordos','odo_fin_inad_parcelas'] loop
    execute format('drop trigger if exists %I on public.%I', t||'_dono', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.odo_dono_fixo()', t||'_dono', t);
  end loop;
end $t$;

-- ---- Trigger: mesmo dono (mes_id e divida_id têm que ser do dono) -
create or replace function public.odo_fin_inad_confere() returns trigger language plpgsql as $$
begin
  if tg_table_name = 'odo_fin_inad_dividas' then
    if new.mes_id is not null and not exists (
      select 1 from public.odo_fin_meses m where m.id = new.mes_id and m.user_id = new.user_id
    ) then raise exception 'mês inválido'; end if;
    if new.cliente_id is not null and not exists (
      select 1 from public.odo_clientes c where c.id = new.cliente_id and c.user_id = new.user_id
    ) then raise exception 'cliente inválido'; end if;
  elsif tg_table_name = 'odo_fin_inad_parcelas' then
    if new.acordo_id is not null and not exists (
      select 1 from public.odo_fin_inad_acordos a where a.id = new.acordo_id and a.user_id = new.user_id
    ) then raise exception 'acordo inválido'; end if;
    if new.divida_id is not null and not exists (
      select 1 from public.odo_fin_inad_dividas d where d.id = new.divida_id and d.user_id = new.user_id
    ) then raise exception 'dívida inválida'; end if;
  end if;
  return new;
end $$;
drop trigger if exists odo_fin_inad_dividas_confere on public.odo_fin_inad_dividas;
create trigger odo_fin_inad_dividas_confere before insert or update on public.odo_fin_inad_dividas
  for each row execute function public.odo_fin_inad_confere();
drop trigger if exists odo_fin_inad_parcelas_confere on public.odo_fin_inad_parcelas;
create trigger odo_fin_inad_parcelas_confere before insert or update on public.odo_fin_inad_parcelas
  for each row execute function public.odo_fin_inad_confere();

-- ---- Leitura para o parceiro (escopo Inove — mesmo padrão da 046) -
do $t$ declare t text; begin
  foreach t in array array['odo_fin_inad_dividas','odo_fin_inad_acordos','odo_fin_inad_parcelas'] loop
    execute format('drop policy if exists %I on public.%I', t||'_espelho', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.odo_parceiro_de(user_id))', t||'_espelho', t);
  end loop;
end $t$;

-- ---- Storage: sem política nova -----------------------------------
-- Bucket 'odonto-fin' já existe (migration 044) e as políticas
-- (storage.foldername(name))[1] = auth.uid()::text cobrem qualquer
-- subpasta, inclusive odonto-fin/<user_id>/inadimplencia/<id>.<ext>.
-- A política de leitura do parceiro (odonto_fin_espelho, migration 046)
-- também cobre automaticamente.

select 'ok: 093 pronta' as resultado;
