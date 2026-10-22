-- Guia de componentes: anotações e favoritos de cada cadista (o catálogo em si é fixo, em app/componentes.js)
create table if not exists public.comp_notas(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  comp_id text not null check (length(comp_id) between 1 and 60),
  texto text check (texto is null or length(texto)<=600),
  fav boolean not null default false,
  atualizado_em timestamptz not null default now(),
  unique(user_id,comp_id)
);
alter table public.comp_notas enable row level security;
create policy comp_notas_sel on public.comp_notas for select to authenticated using (user_id=(select auth.uid()));
create policy comp_notas_ins on public.comp_notas for insert to authenticated with check (user_id=(select auth.uid()));
create policy comp_notas_upd on public.comp_notas for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy comp_notas_del on public.comp_notas for delete to authenticated using (user_id=(select auth.uid()));
revoke all on public.comp_notas from anon;
grant select,insert,update,delete on public.comp_notas to authenticated;
