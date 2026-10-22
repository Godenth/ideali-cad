-- Pedido cancelado e pausado (marcações à parte; a etapa do pedido continua guardada).
alter table public.pedidos add column if not exists cancelado_em timestamptz,
  add column if not exists cancelado_motivo text check (cancelado_motivo is null or char_length(cancelado_motivo) <= 200),
  add column if not exists pausado_em timestamptz;
-- Perfil da Rede: pedido cancelado não conta como trabalho comprovado.
CREATE OR REPLACE FUNCTION public.rede_stats(alvo uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ok as (
    select 1 from public.perfil_rede p
    where p.user_id = alvo and (p.publicado or alvo = auth.uid())
  ),
  prontos as (
    select pe.* from public.pedidos pe
    where pe.user_id = alvo and pe.deleted_at is null and pe.cancelado_em is null
      and pe.status in ('finalizado','arquivado')
      and exists (select 1 from ok)
  ),
  -- Só entra no perfil público o pedido finalizado com STL e HTML de verdade guardados (conferidos pelo servidor).
  feitos as (
    select pr.* from prontos pr
    where exists (select 1 from public.arquivos a where a.pedido_id = pr.id and a.user_id = alvo and a.deleted_at is null
                    and (a.conteudo->>'ok')::boolean and coalesce((a.conteudo->>'stl')::int,0) > 0)
      and exists (select 1 from public.arquivos a where a.pedido_id = pr.id and a.user_id = alvo and a.deleted_at is null
                    and (a.conteudo->>'ok')::boolean and coalesce((a.conteudo->>'html')::int,0) > 0)
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
    'desde', (select min(recebido_em) from feitos),
    'verificados', true,
    'sem_comprovar', case when alvo = auth.uid() then (select count(*) from prontos) - (select count(*) from feitos) else null end,
    'tipos', coalesce((select jsonb_agg(jsonb_build_object('nome', nome, 'n', n)) from tipos), '[]'::jsonb)
  ) end;
$function$;
