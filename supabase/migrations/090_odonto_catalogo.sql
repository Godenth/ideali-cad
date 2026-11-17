-- 090 · Catálogo de componentes (bases de titânio, scanbodies, pilares) com o código do fabricante.
-- Cada conta alimenta o seu; só a própria conta (dono ou equipe) vê e mexe. Pode rodar mais de uma vez.
create table if not exists public.odo_catalogo (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null default public.odo_conta() references auth.users(id) on delete cascade,
  marca     text not null default '' check (char_length(marca) <= 60),
  linha     text not null check (char_length(linha) between 1 and 40),
  peca      text not null check (char_length(peca) between 1 and 60),
  detalhe   text not null default '' check (char_length(detalhe) <= 120),
  diametro  numeric(4,2),
  altura    numeric(4,2),
  codigo    text not null check (char_length(codigo) between 1 and 40),
  criado_em timestamptz not null default now()
);
create index if not exists odo_catalogo_conta on public.odo_catalogo(user_id, linha, diametro, altura);
alter table public.odo_catalogo enable row level security;
drop policy if exists odo_catalogo_dono on public.odo_catalogo;
create policy odo_catalogo_dono on public.odo_catalogo for all to authenticated
  using (user_id = (select public.odo_conta())) with check (user_id = (select public.odo_conta()));
revoke all on public.odo_catalogo from anon;
grant select, insert, update, delete on public.odo_catalogo to authenticated;
