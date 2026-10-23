-- Ideali CAD · Migração 032 · Prospecção Ideali com equipe
-- A lista de prospecção sai das preferências do administrador e vai para uma tabela própria.
-- O administrador (dono) cadastra o e-mail de quem vai disparar. Essa pessoa cria a própria senha
-- pelo cadastro normal e, depois de confirmar o e-mail, enxerga e atualiza SÓ esta lista.

-- Quem pode disparar (e-mails autorizados pelo dono)
create table if not exists public.prospec_equipe(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade, -- dono da lista
  email text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and length(email) <= 120),
  nome text check (nome is null or length(nome) <= 60),
  ativo boolean not null default true,
  limite_dia int not null default 40 check (limite_dia between 1 and 200),
  criado_em timestamptz not null default now()
);
create unique index if not exists prospec_equipe_email_uq on public.prospec_equipe(user_id, lower(email));
alter table public.prospec_equipe enable row level security;

-- Dono da lista da qual o usuário logado faz parte (null se não faz parte de nenhuma).
-- Só vale para e-mail confirmado, para ninguém se passar pela pessoa autorizada.
create or replace function public.prospec_dono()
returns uuid language sql stable security definer set search_path = public, auth as $$
  select e.user_id
    from public.prospec_equipe e
    join auth.users u on u.id = auth.uid()
   where e.ativo
     and lower(e.email) = lower(u.email)
     and u.email_confirmed_at is not null
   order by e.criado_em
   limit 1;
$$;
revoke all on function public.prospec_dono() from public, anon;
grant execute on function public.prospec_dono() to authenticated;

-- Dados do próprio acesso (nome e limite diário) para a pessoa da equipe
create or replace function public.prospec_meu_acesso()
returns table(dono uuid, nome text, limite_dia int) language sql stable security definer set search_path = public, auth as $$
  select e.user_id, e.nome, e.limite_dia
    from public.prospec_equipe e
    join auth.users u on u.id = auth.uid()
   where e.ativo and lower(e.email) = lower(u.email) and u.email_confirmed_at is not null
   order by e.criado_em limit 1;
$$;
revoke all on function public.prospec_meu_acesso() from public, anon;
grant execute on function public.prospec_meu_acesso() to authenticated;

create policy prospec_equipe_dono on public.prospec_equipe for all to authenticated
  using (user_id = (select auth.uid()) and public.sou_admin())
  with check (user_id = (select auth.uid()) and public.sou_admin());
revoke all on public.prospec_equipe from anon;
grant select, insert, update, delete on public.prospec_equipe to authenticated;

-- Contatos da prospecção (um por telefone, por dono)
create table if not exists public.prospec_contatos(
  id text primary key check (length(id) between 1 and 64),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade, -- dono
  tel text not null check (tel ~ '^\d{10,11}$'),
  st text not null default 'seq' check (st in ('seq','resp','cli','fim','nao')),
  dados jsonb not null default '{}'::jsonb check (pg_column_size(dados) <= 20000),
  atualizado_por uuid,
  atualizado_em timestamptz not null default now(),
  criado_em timestamptz not null default now(),
  unique(user_id, tel)
);
alter table public.prospec_contatos enable row level security;

create policy prospec_ct_sel on public.prospec_contatos for select to authenticated
  using (user_id = (select auth.uid()) or user_id = public.prospec_dono());
create policy prospec_ct_ins on public.prospec_contatos for insert to authenticated
  with check (user_id = (select auth.uid()) and public.sou_admin());
create policy prospec_ct_upd on public.prospec_contatos for update to authenticated
  using (user_id = (select auth.uid()) or user_id = public.prospec_dono())
  with check (user_id = (select auth.uid()) or user_id = public.prospec_dono());
create policy prospec_ct_del on public.prospec_contatos for delete to authenticated
  using (user_id = (select auth.uid()));
revoke all on public.prospec_contatos from anon;
grant select, insert, update, delete on public.prospec_contatos to authenticated;

-- Quem é da equipe não troca o dono nem o telefone do contato; carimba quem alterou e quando.
create or replace function public.prospec_ct_guarda()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is distinct from old.user_id then
    new.user_id := old.user_id;
    new.tel := old.tel;
    new.criado_em := old.criado_em;
  end if;
  new.atualizado_por := auth.uid();
  new.atualizado_em := now();
  return new;
end $$;
drop trigger if exists prospec_ct_guarda on public.prospec_contatos;
create trigger prospec_ct_guarda before update on public.prospec_contatos
  for each row execute function public.prospec_ct_guarda();
