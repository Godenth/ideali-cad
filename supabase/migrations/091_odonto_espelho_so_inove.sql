-- =====================================================================
-- 091 · Ideali Odonto · Conta espelho "só a aba Inove".
-- O dono pode convidar um parceiro que vê SÓ a aba Inove (financeiro com a Inove:
-- meses, pagamentos, comprovantes, extratos e os nomes dos clientes).
-- Esse parceiro NÃO vê pedidos, tabela de preços, cadistas nem o perfil do dono.
-- O parceiro "tudo" (o que já existia) continua igual. Ninguém ganha escrita nova.
-- Pode rodar de novo.
-- =====================================================================
alter table public.odo_parceiros add column if not exists escopo text not null default 'tudo';
alter table public.odo_parceiros drop constraint if exists odo_parceiros_escopo_ck;
alter table public.odo_parceiros add constraint odo_parceiros_escopo_ck check (escopo in ('tudo','inove'));

-- parceiro com acesso a TUDO (escopo 'tudo')
create or replace function public.odo_parceiro_tudo_de(dono uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.odo_parceiros p where p.dono_id = dono and p.parceiro_id = (select auth.uid()) and p.ativo and p.escopo = 'tudo');
$$;
revoke all on function public.odo_parceiro_tudo_de(uuid) from public, anon;
grant execute on function public.odo_parceiro_tudo_de(uuid) to authenticated;

-- o que NÃO é da aba Inove passa a exigir o parceiro "tudo"
do $t$ declare t text; begin
  foreach t in array array['odo_perfis','odo_precos','odo_pedidos','odo_cadistas'] loop
    execute format('drop policy if exists %I on public.%I', t||'_espelho', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.odo_parceiro_tudo_de(user_id))', t||'_espelho', t);
  end loop; end $t$;
-- continuam para qualquer parceiro ativo (é o que a aba Inove usa): odo_empresas, odo_clientes,
-- odo_fin_config, odo_fin_meses, odo_fin_pagamentos, odo_fin_comissoes, odo_fin_leituras e o bucket odonto-fin.

select 'ok: conta espelho só Inove pronta' as resultado;
