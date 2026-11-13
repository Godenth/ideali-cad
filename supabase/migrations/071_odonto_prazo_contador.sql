-- =====================================================================
-- 071 · Ideali Odonto · Contador de prazo do pedido
-- * O prazo conta a partir do ENVIO da clínica (aceito ou não).
-- * Quando o laboratório marca "Aguardando informação", escreve o que falta: a clínica vê o aviso
--   e o contador para. Quando o laboratório retoma, o contador ZERA e começa de novo.
-- Rode DEPOIS da 070. Pode rodar de novo.
-- =====================================================================
alter table public.odo_pedidos add column if not exists falta_info text check (char_length(falta_info) <= 500);
alter table public.odo_ped_env add column if not exists falta_info text check (char_length(falta_info) <= 500);
alter table public.odo_ped_env add column if not exists prazo_inicio timestamptz;

create or replace function public.odo_ped_env_etapa_sync() returns trigger
language plpgsql security definer set search_path = '' as $$
declare et text;
begin
  if new.envio_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status
     and new.enviado_inove is not distinct from old.enviado_inove
     and new.falta_info is not distinct from old.falta_info then return new; end if;
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
    update public.odo_ped_env
       set etapa = et, etapa_em = now(),
           falta_info = case when new.status = 'aguardando' then new.falta_info else null end,
           prazo_inicio = case when tg_op = 'UPDATE' and old.status = 'aguardando' and new.status <> 'aguardando' then now() else prazo_inicio end
     where id = new.envio_id and lab_id in (select e.id from public.odo_empresas e where e.user_id = new.user_id);
  end if;
  return new;
end $$;

select 'ok: 071 aplicada' as resultado;
