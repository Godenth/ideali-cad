-- Ideali CAD · 023
-- 1) Espaço para arquivos: contas NOVAS começam com 1 GB (antes 5 GB).
--    Contas que já existem ficam como estão. Quem assinar mais espaço (10 GB),
--    o administrador libera no painel Admin (campo "Espaço (GB)").
alter table public.assinaturas alter column limite_bytes set default 1073741824; -- 1 GB

-- 2) IA dos agentes: contagem de uso para a trava contra abuso.
--    Só o servidor (função "agente", com a chave de serviço) grava aqui.
--    Cada conta só consegue LER o próprio uso.
create table if not exists public.ia_uso (
  user_id  uuid not null references auth.users(id) on delete cascade,
  dia      date not null default (now() at time zone 'America/Sao_Paulo')::date,
  n        integer not null default 0,
  primary key (user_id, dia)
);
alter table public.ia_uso enable row level security;
create policy ia_uso_ler_proprio on public.ia_uso for select using (auth.uid() = user_id);

create table if not exists public.ia_global (
  dia  date primary key,
  n    integer not null default 0
);
alter table public.ia_global enable row level security;
-- sem política: ninguém pelo app lê ou grava; só a chave de serviço.

-- Consome 1 pergunta, respeitando a trava por conta e o teto do sistema.
-- Devolve: ok (pode perguntar), motivo ('conta' | 'sistema') quando não pode.
create or replace function public.ia_consumir(uid uuid, max_conta int, max_sistema int)
returns json language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'America/Sao_Paulo')::date; nc int; ns int;
begin
  insert into ia_global(dia, n) values (d, 0) on conflict (dia) do nothing;
  select n into ns from ia_global where dia = d for update;
  if ns >= max_sistema then return json_build_object('ok', false, 'motivo', 'sistema'); end if;
  insert into ia_uso(user_id, dia, n) values (uid, d, 0) on conflict (user_id, dia) do nothing;
  select n into nc from ia_uso where user_id = uid and dia = d for update;
  if nc >= max_conta then return json_build_object('ok', false, 'motivo', 'conta'); end if;
  update ia_uso set n = n + 1 where user_id = uid and dia = d;
  update ia_global set n = n + 1 where dia = d;
  return json_build_object('ok', true, 'conta', nc + 1, 'sistema', ns + 1);
end $$;
revoke all on function public.ia_consumir(uuid, int, int) from public, anon, authenticated;
grant execute on function public.ia_consumir(uuid, int, int) to service_role;
