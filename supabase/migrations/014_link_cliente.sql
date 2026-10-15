-- =====================================================================
-- Ideali CAD · Migração 014 · Link de acompanhamento para o cliente
-- Um link secreto por cliente (32 bytes aleatórios). Quem tem o link vê
-- os pedidos DAQUELE cliente e os arquivos deles, sem login, até o cadista
-- cancelar. O navegador nunca lê esta tabela de outro usuário: RLS por dono,
-- e criar/cancelar só pelas funções abaixo. A página pública fala com a
-- função "portal", que valida o token no servidor.
-- =====================================================================

create table public.links_cliente (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users(id) on delete cascade,
  cliente_id     uuid not null,
  token          text not null unique check (token ~ '^[A-Za-z0-9_-]{40,64}$'),
  criado_em      timestamptz not null default now(),
  revogado_em    timestamptz,
  ultimo_acesso  timestamptz,
  foreign key (cliente_id, user_id) references public.clientes (id, user_id) on delete cascade
);
create unique index links_cliente_ativo on public.links_cliente (cliente_id) where revogado_em is null;
alter table public.links_cliente enable row level security;
create policy links_cliente_ver on public.links_cliente for select to authenticated using (user_id = auth.uid());

create or replace function public.criar_link_cliente(cid uuid)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare tk text;
begin
  if not public.pode_escrever() then raise exception 'Conta bloqueada' using errcode = '42501'; end if;
  if not exists (select 1 from public.clientes c where c.id = cid and c.user_id = auth.uid() and c.deleted_at is null) then
    raise exception 'Cliente não encontrado';
  end if;
  update public.links_cliente set revogado_em = now() where cliente_id = cid and user_id = auth.uid() and revogado_em is null;
  tk := translate(encode(gen_random_bytes(32), 'base64'), '+/=', '-_');
  insert into public.links_cliente (user_id, cliente_id, token) values (auth.uid(), cid, tk);
  return tk;
end $$;
revoke all on function public.criar_link_cliente(uuid) from public, anon;
grant execute on function public.criar_link_cliente(uuid) to authenticated;

create or replace function public.revogar_link_cliente(cid uuid)
returns void language sql security definer set search_path = public as $$
  update public.links_cliente set revogado_em = now()
  where cliente_id = cid and user_id = auth.uid() and revogado_em is null;
$$;
revoke all on function public.revogar_link_cliente(uuid) from public, anon;
grant execute on function public.revogar_link_cliente(uuid) to authenticated;
