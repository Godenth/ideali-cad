-- =====================================================================
-- Ideali CAD · Migração 003 · Conta mestre (administrador do sistema)
-- O administrador vê e gerencia só CADASTRO e ASSINATURA dos cadistas.
-- Clientes, pedidos e pacientes continuam visíveis apenas para o dono (LGPD).
-- Ser administrador é definido só no banco (tabela admins), nunca no navegador.
-- =====================================================================

create table public.admins (
  user_id   uuid primary key references auth.users(id) on delete cascade,
  criado_em timestamptz not null default now()
);
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;   -- ninguém lê nem grava pelo app

-- Histórico de tudo que o administrador altera.
create table public.admin_log (
  id         bigserial primary key,
  admin_id   uuid not null,
  alvo_id    uuid not null,
  acao       text not null,
  antes      jsonb,
  depois     jsonb,
  criado_em  timestamptz not null default now()
);
alter table public.admin_log enable row level security;
revoke all on public.admin_log from anon, authenticated;

create or replace function public.sou_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;
revoke all on function public.sou_admin() from public, anon;
grant execute on function public.sou_admin() to authenticated;

-- Lista de assinantes (só para administrador).
create or replace function public.admin_assinantes()
returns table (
  user_id uuid, email text, nome text, telefone text, cidade text,
  plano text, status text, teste_ate timestamptz, vence_em timestamptz,
  limite_bytes bigint, bytes_usados bigint, cadastro timestamptz, ultimo_acesso timestamptz,
  admin boolean
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.sou_admin() then
    raise exception 'Acesso restrito ao administrador' using errcode = '42501';
  end if;
  return query
    select u.id, u.email::text, p.nome, p.telefone, p.cidade,
           a.plano, a.status, a.teste_ate, a.vence_em, a.limite_bytes, a.bytes_usados,
           u.created_at, u.last_sign_in_at,
           exists (select 1 from public.admins ad where ad.user_id = u.id)
    from auth.users u
    left join public.perfis p on p.user_id = u.id
    left join public.assinaturas a on a.user_id = u.id
    order by u.created_at desc;
end $$;
revoke all on function public.admin_assinantes() from public, anon;
grant execute on function public.admin_assinantes() to authenticated;

-- Altera a assinatura de um cadista (só administrador). Campos nulos ficam como estão.
create or replace function public.admin_altera_assinatura(
  alvo uuid,
  novo_status text default null,
  novo_plano text default null,
  novo_vence_em timestamptz default null,
  novo_teste_ate timestamptz default null,
  novo_limite_bytes bigint default null,
  limpar_vencimento boolean default false
)
returns void language plpgsql security definer set search_path = public as $$
declare antes jsonb; depois jsonb;
begin
  if not public.sou_admin() then
    raise exception 'Acesso restrito ao administrador' using errcode = '42501';
  end if;
  select to_jsonb(a) into antes from public.assinaturas a where a.user_id = alvo;
  if antes is null then raise exception 'Assinante não encontrado'; end if;

  update public.assinaturas set
    status       = coalesce(novo_status, status),
    plano        = coalesce(novo_plano, plano),
    vence_em     = case when limpar_vencimento then null else coalesce(novo_vence_em, vence_em) end,
    teste_ate    = coalesce(novo_teste_ate, teste_ate),
    limite_bytes = coalesce(novo_limite_bytes, limite_bytes)
  where user_id = alvo;

  select to_jsonb(a) into depois from public.assinaturas a where a.user_id = alvo;
  insert into public.admin_log (admin_id, alvo_id, acao, antes, depois)
  values (auth.uid(), alvo, 'altera_assinatura', antes, depois);
end $$;
revoke all on function public.admin_altera_assinatura(uuid,text,text,timestamptz,timestamptz,bigint,boolean) from public, anon;
grant execute on function public.admin_altera_assinatura(uuid,text,text,timestamptz,timestamptz,bigint,boolean) to authenticated;
