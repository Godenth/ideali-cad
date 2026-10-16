-- =====================================================================
-- Ideali CAD · Migração 021 · Números do perfil da Rede
-- rede_stats(alvo): devolve só NÚMEROS agregados dos trabalhos entregues de um cadista
-- (quantidade, elementos, % no prazo, dias médios, desde quando, tipos mais feitos).
-- Só responde se o perfil do alvo está PUBLICADO (ou se é o próprio usuário).
-- Nunca devolve clientes, pacientes, valores ou pedidos individuais.
-- Calculado no servidor: o cadista não consegue inflar os próprios números.
-- =====================================================================
create or replace function public.rede_stats(alvo uuid)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  with ok as (
    select 1 from public.perfil_rede p
    where p.user_id = alvo and (p.publicado or alvo = auth.uid())
  ),
  feitos as (
    select pe.* from public.pedidos pe
    where pe.user_id = alvo and pe.deleted_at is null
      and (pe.enviado_em is not null or pe.status in ('finalizado','arquivado'))
      and exists (select 1 from ok)
  ),
  tipos as (
    select coalesce(t.nome, 'Outros') as nome, count(*) as n
    from feitos f left join public.tipos_trabalho t on t.id = f.tipo_trabalho_id
    group by 1 order by 2 desc limit 8
  )
  select case when not exists (select 1 from ok) then null else jsonb_build_object(
    'trabalhos', (select count(*) from feitos),
    'elementos', (select coalesce(sum(greatest(coalesce(cardinality(elementos),0),1)),0) from feitos),
    'no_prazo', (select case when count(*) filter (where prazo is not null and enviado_em is not null) = 0 then null
                   else round(100.0 * count(*) filter (where prazo is not null and enviado_em is not null and enviado_em <= prazo)
                        / count(*) filter (where prazo is not null and enviado_em is not null)) end from feitos),
    'dias_medio', (select round(avg(enviado_em - recebido_em)::numeric, 1) from feitos where enviado_em is not null and recebido_em is not null and enviado_em >= recebido_em),
    'desde', (select min(recebido_em) from public.pedidos where user_id = alvo and deleted_at is null),
    'tipos', coalesce((select jsonb_agg(jsonb_build_object('nome', nome, 'n', n)) from tipos), '[]'::jsonb)
  ) end;
$$;
revoke all on function public.rede_stats(uuid) from public, anon;
grant execute on function public.rede_stats(uuid) to authenticated;
