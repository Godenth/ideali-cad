-- Pendencia com conferencia do protetico: pausa e retomada do prazo
alter table public.odo_pedidos
  add column if not exists pendencia_aguardando_conferencia boolean not null default false,
  add column if not exists pendencia_pausada_em timestamptz;

comment on column public.odo_pedidos.pendencia_aguardando_conferencia is 'Cliente respondeu; falta a conferencia final do protetico';
comment on column public.odo_pedidos.pendencia_pausada_em is 'Inicio da pausa do prazo por pendencia';

create or replace function public.odo_pedido_prazo() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.aguardando_pendencia and not coalesce(old.aguardando_pendencia, false) then
    new.pendencia_pausada_em := coalesce(old.pendencia_pausada_em, now());
  end if;

  if coalesce(old.aguardando_pendencia, false) and not new.aguardando_pendencia then
    if old.pendencia_pausada_em is not null then
      new.prazo_inicio := coalesce(new.prazo_inicio, old.prazo_inicio, old.criado_em, now())
                          + (now() - old.pendencia_pausada_em);
    end if;
    new.pendencia_aguardando_conferencia := false;
    new.pendencia_pausada_em := null;
  end if;

  if old.status = 'aguardando' and new.status is distinct from 'aguardando' then
    new.prazo_inicio := now();
  end if;
  return new;
end $$;

create or replace function public.odo_ped_msg_confere() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.lado = 'clinica' then
    if new.pedido_id is not null then
      update public.odo_pedidos
         set pendencia_aguardando_conferencia = true
       where id = new.pedido_id and aguardando_pendencia and not pendencia_aguardando_conferencia;
    elsif new.envio_id is not null then
      update public.odo_pedidos
         set pendencia_aguardando_conferencia = true
       where envio_id = new.envio_id and aguardando_pendencia and not pendencia_aguardando_conferencia;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists odo_ped_msgs_confere on public.odo_ped_msgs;
create trigger odo_ped_msgs_confere after insert on public.odo_ped_msgs
  for each row execute function public.odo_ped_msg_confere();

create or replace function public.odo_ped_pend_responde(p_id uuid, p_texto text default null) returns boolean
language plpgsql security definer set search_path = '' as $$
declare p public.odo_pedidos; dono uuid := public.odo_conta();
begin
  select * into p from public.odo_pedidos where id = p_id and user_id = dono;
  if p.id is null then raise exception 'sem_acesso'; end if;
  if not p.aguardando_pendencia then raise exception 'sem_pendencia'; end if;
  update public.odo_pedidos
     set pendencia_aguardando_conferencia = true,
         obs = left(coalesce(obs, '') || E'\n[Cliente confirmou pendência ' ||
                   to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') || '] ' ||
                   coalesce(nullif(trim(p_texto), ''), 'aguardando conferência do laboratório'), 4000)
   where id = p_id;
  return true;
end $$;
revoke all on function public.odo_ped_pend_responde(uuid, text) from public, anon;
grant execute on function public.odo_ped_pend_responde(uuid, text) to authenticated;

create or replace function public.odo_pedido_cli(p public.odo_pedidos, p_inicio timestamptz, p_valor boolean) returns jsonb
language plpgsql stable set search_path = '' as $$ 
declare et text; aberto boolean; parado boolean; fx int[]; ini timestamptz; j jsonb;
begin
  et := public.odo_etapa(p.status, p.tipo, p.desenho_feito, p.enviado_inove, p.em_maquiagem, p.arquivado);
  parado := coalesce(et = 'Aguardando informação', false) or coalesce(p.aguardando_pendencia, false);
  aberto := coalesce(et in ('Desenho CAD', 'Desenhado', 'Em produção', 'Enviado para fresagem', 'Maquiagem', 'Aguardando informação'), false);
  j := jsonb_build_object(
    'id', p.id, 'numero', p.numero, 'paciente', p.paciente, 'trabalho', p.trabalho, 'material', p.material,
    'sobre_implante', p.sobre_implante, 'dentes', to_jsonb(coalesce(p.dentes, '{}'::smallint[])), 'qtd', p.qtd, 'cor', p.cor,
    'tipo', p.tipo, 'urgente', p.urgente, 'status', p.status, 'etapa', et, 'aberto', aberto, 'parado', parado,
    'falta_info', case when parado then p.falta_info end, 'enviado_inove', p.enviado_inove,
    'aguardando_pendencia', p.aguardando_pendencia, 'motivo_pendencia', p.motivo_pendencia,
    'pendencia_aguardando_conferencia', p.pendencia_aguardando_conferencia,
    'criado_em', p.criado_em, 'finalizado_em', p.finalizado_em, 'entregue_em', p.entregue_em, 'atualizado_em', p.atualizado_em);
  if aberto and not parado then
    ini := coalesce(p.prazo_inicio, p_inicio, p.criado_em);
    fx := public.odo_prazo_faixa(coalesce(p.trabalho, '') || ' ' || coalesce(p.material, ''));
    j := j || jsonb_build_object('prazo_inicio', ini, 'faixa', to_jsonb(fx),
                                 'prazo_min', public.odo_prazo_dia(ini, fx[1]), 'prazo_max', public.odo_prazo_dia(ini, fx[2]));
  end if;
  if p_valor then j := j || jsonb_build_object('valor', p.valor); end if;
  return j;
end $$;
