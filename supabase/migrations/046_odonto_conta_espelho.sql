-- =====================================================================
-- 046 · Ideali Odonto · Conta espelho (parceiro que VÊ tudo e NÃO edita nada).
-- Pedido do dono em 06/11/2026: a Inove (dona do negócio, fabrica e emite nota)
-- acompanha tudo da conta do laboratório, sem poder editar.
--
-- Como funciona:
--   * O dono cria um convite (odo_parceiros) e manda o link.
--   * O parceiro entra com o login DELE e aceita (função odo_parceiro_aceita).
--   * O banco ganha políticas SÓ DE LEITURA (select) para o parceiro aceito e ativo.
--     Nenhuma política de escrita é dada: inserir, alterar ou apagar continua só para o dono.
--   * O dono corta o acesso a qualquer momento (ativo = false) e ele some na hora.
-- =====================================================================
create table if not exists public.odo_parceiros (
  id          uuid primary key default gen_random_uuid(),
  dono_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  parceiro_id uuid references auth.users(id) on delete cascade,
  nome        text not null check (char_length(nome) between 1 and 80),
  token       text not null unique default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  expira_em   timestamptz not null default now() + interval '7 days',
  ativo       boolean not null default true,
  aceito_em   timestamptz,
  criado_em   timestamptz not null default now(),
  unique (dono_id, parceiro_id)
);
alter table public.odo_parceiros enable row level security;
drop policy if exists odo_parceiros_dono on public.odo_parceiros;
create policy odo_parceiros_dono on public.odo_parceiros for all to authenticated
  using (dono_id = (select auth.uid())) with check (dono_id = (select auth.uid()));
drop policy if exists odo_parceiros_parceiro on public.odo_parceiros;
create policy odo_parceiros_parceiro on public.odo_parceiros for select to authenticated
  using (parceiro_id = (select auth.uid()));
revoke all on public.odo_parceiros from anon;

-- o dono não escolhe quem é o parceiro nem troca o convite: isso só acontece ao aceitar
create or replace function public.odo_parceiros_trava() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.parceiro_id := null; new.aceito_em := null;
    new.token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    new.expira_em := now() + interval '7 days';
  else
    new.dono_id := old.dono_id; new.token := old.token; new.criado_em := old.criado_em;
    if coalesce(current_setting('odo.aceitando', true), '') <> '1' then
      new.parceiro_id := old.parceiro_id; new.aceito_em := old.aceito_em; new.expira_em := old.expira_em;
    end if;
  end if;
  return new; end $$;
drop trigger if exists odo_parceiros_trava on public.odo_parceiros;
create trigger odo_parceiros_trava before insert or update on public.odo_parceiros for each row execute function public.odo_parceiros_trava();

-- aceitar o convite (com o login do parceiro)
create or replace function public.odo_parceiro_aceita(p_token text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare d uuid; eu uuid := auth.uid();
begin
  if eu is null then raise exception 'Entre na sua conta para aceitar'; end if;
  perform set_config('odo.aceitando', '1', true);
  update public.odo_parceiros set parceiro_id = eu, aceito_em = now()
   where token = p_token and ativo and parceiro_id is null and expira_em > now() and dono_id <> eu
     and not exists (select 1 from public.odo_parceiros x where x.dono_id = odo_parceiros.dono_id and x.parceiro_id = eu)
  returning dono_id into d;
  if d is null then
    select dono_id into d from public.odo_parceiros where token = p_token and parceiro_id = eu and ativo;
  end if;
  if d is null then raise exception 'Convite inválido, vencido ou cancelado'; end if;
  return d;
end $$;
revoke all on function public.odo_parceiro_aceita(text) from public, anon;
grant execute on function public.odo_parceiro_aceita(text) to authenticated;

-- "eu sou parceiro ativo deste dono?"
create or replace function public.odo_parceiro_de(dono uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.odo_parceiros p where p.dono_id = dono and p.parceiro_id = (select auth.uid()) and p.ativo);
$$;
create or replace function public.odo_parceiro_de_txt(dono text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.odo_parceiros p where p.dono_id::text = dono and p.parceiro_id = (select auth.uid()) and p.ativo);
$$;
revoke all on function public.odo_parceiro_de(uuid) from public, anon;
revoke all on function public.odo_parceiro_de_txt(text) from public, anon;
grant execute on function public.odo_parceiro_de(uuid) to authenticated;
grant execute on function public.odo_parceiro_de_txt(text) to authenticated;

-- leitura (só select) para o parceiro em todas as tabelas da conta
do $t$ declare t text; begin
  foreach t in array array['odo_perfis','odo_empresas','odo_clientes','odo_precos','odo_pedidos','odo_cadistas',
                           'odo_fin_config','odo_fin_meses','odo_fin_pagamentos','odo_fin_comissoes'] loop
    execute format('drop policy if exists %I on public.%I', t||'_espelho', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.odo_parceiro_de(user_id))', t||'_espelho', t);
  end loop; end $t$;

-- comprovantes e extratos: o parceiro só abre (leitura)
drop policy if exists odonto_fin_espelho on storage.objects;
create policy odonto_fin_espelho on storage.objects for select to authenticated
  using (bucket_id = 'odonto-fin' and public.odo_parceiro_de_txt((storage.foldername(name))[1]));

select 'ok: conta espelho pronta' as resultado;
