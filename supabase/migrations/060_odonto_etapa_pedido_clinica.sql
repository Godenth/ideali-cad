-- =====================================================================
-- 060 · Ideali Odonto · A clínica acompanha a etapa do pedido no laboratório.
-- Quando o laboratório muda a situação de um pedido que veio da clínica (pedido digital),
-- a etapa aparece para a clínica: Desenho CAD, Enviado para fresagem, Em produção,
-- Pronto, Entregue. A clínica vê só a etapa, nada mais do pedido do laboratório
-- (sem valores, sem cliente, sem anotações). Rode DEPOIS da 057. Pode rodar de novo.
-- =====================================================================
alter table public.odo_ped_env add column if not exists etapa text check (char_length(etapa) <= 40);
alter table public.odo_ped_env add column if not exists etapa_em timestamptz;

create or replace function public.odo_ped_env_etapa_sync() returns trigger
language plpgsql security definer set search_path = '' as $$
declare et text;
begin
  if new.envio_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status
     and new.enviado_inove is not distinct from old.enviado_inove then return new; end if;
  et := case
          when new.status = 'cancelado' then 'Cancelado'
          when new.status = 'entregue' then 'Entregue'
          when new.status = 'finalizado' then 'Pronto'
          when new.status = 'producao' and new.tipo = 'cad' and new.enviado_inove then 'Enviado para fresagem'
          when new.status = 'producao' then 'Em produção'
          when new.status = 'aguardando' then 'Aguardando informação'
          when new.status = 'desenho' then 'Desenho CAD'
          else null end;
  if et is not null then
    update public.odo_ped_env set etapa = et, etapa_em = now()
     where id = new.envio_id and lab_id in (select e.id from public.odo_empresas e where e.user_id = new.user_id);
  end if;
  return new;
end $$;
drop trigger if exists odo_pedidos_etapa_clinica on public.odo_pedidos;
create trigger odo_pedidos_etapa_clinica after insert or update on public.odo_pedidos
  for each row execute function public.odo_ped_env_etapa_sync();

select 'ok: 060 aplicada' as resultado;
