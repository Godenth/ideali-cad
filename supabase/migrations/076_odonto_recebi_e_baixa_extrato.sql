-- 076 · A clínica confirma "Recebi" · baixa dos pedidos quando o extrato do mês é anexado
-- Regra: pedido que está no extrato (ou que a clínica confirmou que recebeu) é pedido finalizado.
-- Pode rodar mais de uma vez.

-- 1. Guarda quem confirmou, quando, e como o pedido estava antes (para o laboratório poder desfazer)
alter table public.odo_pedidos add column if not exists recebido_em    timestamptz;
alter table public.odo_pedidos add column if not exists recebido_por   uuid;
alter table public.odo_pedidos add column if not exists recebido_antes text check (char_length(recebido_antes) <= 20);
create index if not exists odo_pedidos_recebido on public.odo_pedidos (user_id, recebido_em) where recebido_em is not null;

-- 2. A clínica clica em "Recebi". Só vale para pedido DELA (enviado por ela, ou lançado pelo laboratório
--    para o cliente ligado à conta dela). Nunca enxerga nem altera pedido de outra clínica.
create or replace function public.odo_clinica_recebi(p_id text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare eu uuid := auth.uid(); conta uuid; n int := 0; v_id uuid;
begin
  if eu is null then raise exception 'sem login'; end if;
  conta := public.odo_conta();
  begin
    v_id := (case when p_id like 'lab-%' then substr(p_id, 5) else p_id end)::uuid;
  exception when others then raise exception 'pedido invalido'; end;

  if p_id like 'lab-%' then
    update public.odo_pedidos p
       set recebido_antes = p.status, status = 'entregue', arquivado = true,
           entregue_em = coalesce(p.entregue_em, now()), recebido_em = now(), recebido_por = eu
     where p.id = v_id and p.envio_id is null and p.apagado is not true and p.arquivado is not true
       and p.status in ('desenho', 'producao', 'finalizado', 'aguardando')
       and exists (select 1 from public.odo_lab_vinculos v join public.odo_empresas l on l.id = v.lab_id
                    where v.user_id = conta and v.status = 'aceito' and v.cliente_id = p.cliente_id and l.user_id = p.user_id);
    get diagnostics n = row_count;
  else
    update public.odo_pedidos p
       set recebido_antes = p.status, status = 'entregue', arquivado = true,
           entregue_em = coalesce(p.entregue_em, now()), recebido_em = now(), recebido_por = eu
     where p.envio_id = v_id and p.apagado is not true and p.arquivado is not true
       and p.status in ('desenho', 'producao', 'finalizado', 'aguardando')
       and exists (select 1 from public.odo_ped_env e join public.odo_empresas l on l.id = e.lab_id
                    where e.id = v_id and e.user_id = conta and l.user_id = p.user_id);
    get diagnostics n = row_count;
  end if;
  if n = 0 then raise exception 'pedido nao encontrado ou ja finalizado'; end if;
  return jsonb_build_object('ok', true, 'n', n);
end $$;
revoke all on function public.odo_clinica_recebi(text) from public, anon;
grant execute on function public.odo_clinica_recebi(text) to authenticated;
