-- =====================================================================
-- 074 · Ideali Odonto · FONTE ÚNICA DOS PEDIDOS (Fase 1)
--
-- Ideia: a conta do LABORATÓRIO é a verdade. A clínica só LÊ a parte dela, por UMA
-- leitura só (odo_clinica_pedidos), que já entrega etapa, prazo e valor prontos.
--
-- O que muda:
--   1. Etapa do pedido calculada num lugar só (odo_etapa). Antes estava escrita em 2 funções
--      do banco e em vários pontos da tela, e uma delas nem conhecia "Desenhado"/"Maquiagem".
--   2. Prazo calculado no banco (feriados + regra das 13h), o mesmo para clínica e laboratório.
--   3. Pedido ARQUIVADO no laboratório (saiu do quadro) aparece como "Entregue" para a clínica,
--      em vez de "atrasado há 290 dias".
--   4. Pedido APAGADO no laboratório não aparece mais para a clínica (antes aparecia).
--   5. Pedido com vários itens: a clínica vê a etapa do item MAIS ATRASADO (antes via a do
--      último item mexido).
--   6. Sem limite de 300 pedidos.
--   7. Índices que faltavam.
--
-- Segurança (mesmas regras de sempre):
--   * a clínica só recebe pedidos dela: os que ela enviou e os do cliente que o laboratório
--     ligou à conta dela (vínculo ACEITO);
--   * VALORES e fechamentos só para o DONO da clínica; funcionário recebe os pedidos sem valor;
--   * nada de anotações internas do laboratório (obs, descrição, cadista).
--
-- Não apaga nem altera nenhum pedido. Pode rodar de novo. Rode depois da 073.
-- =====================================================================

-- ---------- 1. Feriados (nacionais + Rio de Janeiro) ----------
create table if not exists public.odo_feriados (
  dia  date primary key,
  nome text not null
);
alter table public.odo_feriados enable row level security;
drop policy if exists odo_feriados_ler on public.odo_feriados;
create policy odo_feriados_ler on public.odo_feriados for select to authenticated using (true);
revoke all on public.odo_feriados from anon, public;
grant select on public.odo_feriados to authenticated;

insert into public.odo_feriados (dia, nome) values
  ('2026-01-01','Confraternização Universal'), ('2026-01-20','São Sebastião (Rio)'), ('2026-02-16','Carnaval'), ('2026-02-17','Carnaval'),
  ('2026-04-03','Sexta-feira Santa'), ('2026-04-21','Tiradentes'), ('2026-04-23','São Jorge (Rio)'), ('2026-05-01','Dia do Trabalho'),
  ('2026-06-04','Corpus Christi'), ('2026-09-07','Independência'), ('2026-10-12','Nossa Senhora Aparecida'), ('2026-11-02','Finados'),
  ('2026-11-15','Proclamação da República'), ('2026-11-20','Consciência Negra'), ('2026-12-25','Natal'),
  ('2027-01-01','Confraternização Universal'), ('2027-01-20','São Sebastião (Rio)'), ('2027-02-08','Carnaval'), ('2027-02-09','Carnaval'),
  ('2027-03-26','Sexta-feira Santa'), ('2027-04-21','Tiradentes'), ('2027-04-23','São Jorge (Rio)'), ('2027-05-01','Dia do Trabalho'),
  ('2027-05-27','Corpus Christi'), ('2027-09-07','Independência'), ('2027-10-12','Nossa Senhora Aparecida'), ('2027-11-02','Finados'),
  ('2027-11-15','Proclamação da República'), ('2027-11-20','Consciência Negra'), ('2027-12-25','Natal')
on conflict (dia) do nothing;

-- ---------- 2. Prazo: dia útil, faixa por tipo de trabalho, data final ----------
create or replace function public.odo_dia_util(d date) returns boolean
language sql stable set search_path = '' as $$
  select extract(isodow from d) < 6 and not exists (select 1 from public.odo_feriados f where f.dia = d);
$$;

-- faixa em dias úteis: protocolo 10 · metalocerâmica 7 a 10 · o resto 5 a 7
create or replace function public.odo_prazo_faixa(txt text) returns int[]
language sql immutable set search_path = '' as $$
  select case
    when t ~ 'protocolo' then array[10, 10]
    when t ~ '(metalo|metal ?ceram|porcelana sobre metal)' then array[7, 10]
    else array[5, 7] end
  from (select translate(lower(coalesce(txt, '')), 'âÂáÁãÃàÀéÉêÊíÍóÓôÔõÕúÚçÇ', 'aaaaaaaaeeeeiioooooouucc') as t) x;
$$;

-- n-ésimo dia útil a partir do início. Regra das 13h (horário de Brasília): recebido antes das 13h
-- de um dia útil, esse dia já conta; senão começa no próximo dia útil. O prazo vence às 18h dessa data.
create or replace function public.odo_prazo_dia(inicio timestamptz, n int) returns date
language plpgsql stable set search_path = '' as $$
declare loc timestamp; d date; k int := 1;
begin
  if inicio is null or n is null or n < 1 then return null; end if;
  loc := inicio at time zone 'America/Sao_Paulo';
  d := loc::date;
  if not (public.odo_dia_util(d) and extract(hour from loc) < 13) then
    loop d := d + 1; exit when public.odo_dia_util(d); end loop;
  end if;
  while k < n loop
    d := d + 1;
    if public.odo_dia_util(d) then k := k + 1; end if;
  end loop;
  return d;
end $$;

-- ---------- 3. Etapa do pedido: UM lugar só ----------
create or replace function public.odo_etapa(p_status text, p_tipo text, p_desenho_feito boolean, p_enviado_inove boolean,
                                            p_em_maquiagem boolean, p_arquivado boolean) returns text
language sql immutable set search_path = '' as $$
  select case
    when p_status = 'cancelado' then 'Cancelado'
    when p_status = 'entregue' then 'Entregue'
    -- arquivado = o laboratório tirou do quadro: para a clínica, está encerrado
    when coalesce(p_arquivado, false) and p_status in ('desenho', 'aguardando', 'producao', 'finalizado') then 'Entregue'
    when p_status = 'finalizado' then 'Pronto'
    when p_status = 'aguardando' then 'Aguardando informação'
    when p_status = 'producao' and coalesce(p_em_maquiagem, false) then 'Maquiagem'
    when p_status = 'producao' and p_tipo = 'cad' and coalesce(p_enviado_inove, false) then 'Enviado para fresagem'
    when p_status = 'producao' then 'Em produção'
    when p_status = 'desenho' and coalesce(p_desenho_feito, false) then 'Desenhado'
    when p_status = 'desenho' then 'Desenho CAD'
    else null end;
$$;

-- etapa de um envio com vários itens: pendência ganha; senão vale o item mais atrasado
create or replace function public.odo_envio_etapa(p_envio uuid) returns text
language sql stable security definer set search_path = '' as $$
  with it as (
    select public.odo_etapa(p.status, p.tipo, p.desenho_feito, p.enviado_inove, p.em_maquiagem, p.arquivado) as et
      from public.odo_pedidos p where p.envio_id = p_envio and p.apagado is not true),
  o as (
    select et, case et when 'Desenho CAD' then 1 when 'Desenhado' then 2 when 'Em produção' then 3 when 'Enviado para fresagem' then 4
                       when 'Maquiagem' then 5 when 'Pronto' then 6 when 'Entregue' then 7 end as n
      from it where et is not null)
  select case
    when not exists (select 1 from o) then null
    when exists (select 1 from o where et = 'Aguardando informação') then 'Aguardando informação'
    when not exists (select 1 from o where n is not null) then 'Cancelado'
    else (select et from o where n is not null order by n limit 1) end;
$$;
revoke all on function public.odo_envio_etapa(uuid) from public, anon, authenticated;

-- ---------- 4. Prazo recomeça quando a pendência é resolvida (vale também para pedido lançado pelo laboratório) ----------
alter table public.odo_pedidos add column if not exists prazo_inicio timestamptz;

create or replace function public.odo_pedido_prazo() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.status = 'aguardando' and new.status is distinct from 'aguardando' then
    new.prazo_inicio := now();
  end if;
  return new;
end $$;
drop trigger if exists odo_pedidos_prazo on public.odo_pedidos;
create trigger odo_pedidos_prazo before update on public.odo_pedidos
  for each row execute function public.odo_pedido_prazo();

-- ---------- 5. O envio da clínica acompanha o pedido do laboratório (mesma regra de etapa) ----------
create or replace function public.odo_ped_env_etapa_sync() returns trigger
language plpgsql security definer set search_path = '' as $$
declare et text; entrou boolean; saiu boolean;
begin
  if new.envio_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status
     and new.enviado_inove is not distinct from old.enviado_inove
     and new.falta_info is not distinct from old.falta_info
     and new.desenho_feito is not distinct from old.desenho_feito
     and new.em_maquiagem is not distinct from old.em_maquiagem
     and new.arquivado is not distinct from old.arquivado
     and new.apagado is not distinct from old.apagado
     and new.tipo is not distinct from old.tipo then return new; end if;
  et := public.odo_envio_etapa(new.envio_id);
  if et is null then return new; end if;
  -- este item acabou de entrar em pendência (ou a pergunta mudou) / acabou de sair dela
  entrou := new.status = 'aguardando' and (tg_op = 'INSERT' or old.status <> 'aguardando' or new.falta_info is distinct from old.falta_info);
  saiu   := tg_op = 'UPDATE' and old.status = 'aguardando' and new.status <> 'aguardando';
  update public.odo_ped_env
     set etapa = et,
         etapa_em = case when etapa is distinct from et then now() else etapa_em end,
         falta_info = case when new.status = 'aguardando' then new.falta_info
                           when et = 'Aguardando informação' then falta_info
                           else null end,
         resposta    = case when entrou then null else resposta end,
         resposta_ok = case when entrou then null else resposta_ok end,
         prazo_inicio = case when saiu and et <> 'Aguardando informação' then now() else prazo_inicio end
   where id = new.envio_id and lab_id in (select e.id from public.odo_empresas e where e.user_id = new.user_id);
  return new;
end $$;

-- acerta a etapa dos envios já aceitos (só os que estiverem diferentes da regra)
update public.odo_ped_env e
   set etapa = x.et
  from (select id, public.odo_envio_etapa(id) as et from public.odo_ped_env where status = 'aceito') x
 where x.id = e.id and x.et is not null and e.etapa is distinct from x.et;

-- ---------- 6. Um pedido, do jeito que a clínica pode ver ----------
create or replace function public.odo_pedido_cli(p public.odo_pedidos, p_inicio timestamptz, p_valor boolean) returns jsonb
language plpgsql stable set search_path = '' as $$
declare et text; aberto boolean; parado boolean; fx int[]; ini timestamptz; j jsonb;
begin
  et := public.odo_etapa(p.status, p.tipo, p.desenho_feito, p.enviado_inove, p.em_maquiagem, p.arquivado);
  parado := coalesce(et = 'Aguardando informação', false);
  aberto := coalesce(et in ('Desenho CAD', 'Desenhado', 'Em produção', 'Enviado para fresagem', 'Maquiagem', 'Aguardando informação'), false);
  j := jsonb_build_object(
    'id', p.id, 'numero', p.numero, 'paciente', p.paciente, 'trabalho', p.trabalho, 'material', p.material,
    'sobre_implante', p.sobre_implante, 'dentes', to_jsonb(coalesce(p.dentes, '{}'::smallint[])), 'qtd', p.qtd, 'cor', p.cor,
    'tipo', p.tipo, 'urgente', p.urgente, 'status', p.status, 'etapa', et, 'aberto', aberto, 'parado', parado,
    'falta_info', case when parado then p.falta_info end, 'enviado_inove', p.enviado_inove,
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
revoke all on function public.odo_pedido_cli(public.odo_pedidos, timestamptz, boolean) from public, anon, authenticated;

-- ---------- 7. A LEITURA ÚNICA DA CLÍNICA ----------
create or replace function public.odo_clinica_pedidos() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare eu uuid := auth.uid(); conta uuid; dono boolean; r_env jsonb; r_ped jsonb; r_mes jsonb := '[]'::jsonb;
begin
  if eu is null then return null; end if;
  conta := public.odo_conta();
  dono := (conta = eu);     -- funcionário da clínica não vê valores

  -- (a) o que a clínica enviou pelo sistema, com os pedidos que o laboratório abriu a partir de cada envio
  select coalesce(jsonb_agg(x.j order by x.criado desc), '[]'::jsonb) into r_env
  from (
    select e.criado_em as criado,
           to_jsonb(e) || jsonb_build_object('lab_nome', l.nome)
           || case
                when a.partes is not null then jsonb_build_object(
                     'partes', a.partes, 'etapa', coalesce(public.odo_envio_etapa(e.id), e.etapa),
                     'aberto', a.aberto, 'parado', a.parado, 'prazo_min', a.pmin, 'prazo_max', a.pmax, 'faixa', a.faixa)
                when e.status = 'enviado' then jsonb_build_object(
                     'aberto', true, 'parado', false, 'faixa', to_jsonb(public.odo_prazo_faixa(e.itens::text)),
                     'prazo_min', public.odo_prazo_dia(coalesce(e.enviado_em, e.criado_em), (public.odo_prazo_faixa(e.itens::text))[1]),
                     'prazo_max', public.odo_prazo_dia(coalesce(e.enviado_em, e.criado_em), (public.odo_prazo_faixa(e.itens::text))[2]))
                when e.status = 'aceito' then jsonb_build_object('etapa', 'Cancelado', 'aberto', false, 'parado', false)
                else jsonb_build_object('aberto', false, 'parado', false) end as j
    from public.odo_ped_env e
    join public.odo_empresas l on l.id = e.lab_id
    left join lateral (
      select jsonb_agg(c.j order by c.numero) as partes,
             bool_or((c.j->>'aberto')::boolean) as aberto,
             bool_or((c.j->>'parado')::boolean) as parado,
             max((c.j->>'prazo_min')::date) as pmin,
             max((c.j->>'prazo_max')::date) as pmax,
             (array_agg(c.j->'faixa' order by (c.j->>'prazo_max')::date desc) filter (where c.j ? 'prazo_max'))[1] as faixa
      from (select p.numero, public.odo_pedido_cli(p, coalesce(e.prazo_inicio, e.enviado_em), dono) as j
              from public.odo_pedidos p
             where p.envio_id = e.id and p.user_id = l.user_id and p.apagado is not true) c
    ) a on true
    where e.user_id = conta
  ) x;

  -- (b) o que o laboratório lançou para o cliente ligado a esta clínica (WhatsApp, e-mail, balcão, sistema antigo)
  select coalesce(jsonb_agg(x.j order by x.criado desc), '[]'::jsonb) into r_ped
  from (
    select p.criado_em as criado,
           public.odo_pedido_cli(p, p.criado_em, dono) || jsonb_build_object('lab_id', l.id, 'lab_nome', l.nome) as j
    from public.odo_lab_vinculos v
    join public.odo_empresas l on l.id = v.lab_id
    join public.odo_pedidos p on p.user_id = l.user_id and p.cliente_id = v.cliente_id
    where v.user_id = conta and v.status = 'aceito' and v.cliente_id is not null
      and p.envio_id is null and p.apagado is not true and p.status <> 'orcamento'
  ) x;

  -- (c) fechamentos do mês e quanto já foi pago: só o dono
  if dono then
    select coalesce(jsonb_agg(jsonb_build_object('lab_id', v.lab_id, 'lab', l.nome, 'ano', m.ano, 'mes', m.mes, 'valor', m.valor_mes,
             'pago', coalesce((select sum(g.valor) from public.odo_fin_pagamentos g where g.mes_id = m.id and g.anulado_em is null), 0))
             order by m.ano desc, m.mes desc), '[]'::jsonb) into r_mes
    from public.odo_lab_vinculos v
    join public.odo_empresas l on l.id = v.lab_id
    join public.odo_fin_meses m on m.cliente_id = v.cliente_id and m.user_id = l.user_id
    where v.user_id = conta and v.status = 'aceito' and v.cliente_id is not null;
  end if;

  return jsonb_build_object('dono', dono, 'envios', r_env, 'pedidos', r_ped, 'meses', r_mes, 'agora', now());
end $$;
revoke all on function public.odo_clinica_pedidos() from public, anon;
grant execute on function public.odo_clinica_pedidos() to authenticated;

-- ---------- 8. As leituras antigas passam a usar a mesma regra (para quem ainda estiver com a tela antiga aberta) ----------
create or replace function public.odo_clinica_pedidos_lab() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(x order by x->>'criado_em' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', p.id, 'lab_id', e.id, 'lab_nome', e.nome, 'numero', p.numero, 'paciente', p.paciente,
      'trabalho', p.trabalho, 'dentes', to_jsonb(coalesce(p.dentes, '{}'::smallint[])), 'material', p.material, 'cor', p.cor,
      'sobre_implante', p.sobre_implante, 'prazo', p.prazo, 'urgente', p.urgente, 'criado_em', p.criado_em,
      'etapa', coalesce(public.odo_etapa(p.status, p.tipo, p.desenho_feito, p.enviado_inove, p.em_maquiagem, p.arquivado), 'Desenho CAD')) as x
    from public.odo_lab_vinculos v
    join public.odo_empresas e on e.id = v.lab_id
    join public.odo_pedidos p on p.user_id = e.user_id and p.cliente_id = v.cliente_id
    where v.user_id = public.odo_conta() and v.status = 'aceito' and v.cliente_id is not null
      and p.envio_id is null and p.apagado is not true and p.status <> 'orcamento'
    order by p.criado_em desc
    limit 300) q;
$$;
revoke all on function public.odo_clinica_pedidos_lab() from public, anon;
grant execute on function public.odo_clinica_pedidos_lab() to authenticated;

create or replace function public.odo_clinica_fin() returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then null else jsonb_build_object(
    'pedidos', coalesce((select jsonb_agg(x.j order by x.criado desc) from (
        select p.criado_em as criado, jsonb_build_object(
          'id', p.id, 'envio', e.id, 'lab_id', e.lab_id, 'lab', l.nome, 'paciente', p.paciente, 'trabalho', p.trabalho, 'dentes', p.dentes,
          'qtd', p.qtd, 'valor', p.valor, 'status', p.status, 'enviado_inove', p.enviado_inove, 'cor', p.cor, 'material', p.material,
          'criado', p.criado_em, 'finalizado', p.finalizado_em, 'entregue', p.entregue_em) as j
        from public.odo_pedidos p join public.odo_ped_env e on e.id = p.envio_id join public.odo_empresas l on l.id = e.lab_id
        where e.user_id = auth.uid() and p.user_id = l.user_id and p.apagado is not true
        union all
        select p.criado_em, jsonb_build_object(
          'id', p.id, 'envio', null, 'lab_id', l.id, 'lab', l.nome, 'paciente', p.paciente, 'trabalho', p.trabalho, 'dentes', p.dentes,
          'qtd', p.qtd, 'valor', p.valor, 'status', p.status, 'enviado_inove', p.enviado_inove, 'cor', p.cor, 'material', p.material,
          'criado', p.criado_em, 'finalizado', p.finalizado_em, 'entregue', p.entregue_em)
        from public.odo_lab_vinculos v
        join public.odo_empresas l on l.id = v.lab_id
        join public.odo_pedidos p on p.user_id = l.user_id and p.cliente_id = v.cliente_id
        where v.user_id = auth.uid() and v.status = 'aceito' and v.cliente_id is not null
          and p.envio_id is null and p.apagado is not true and p.status not in ('orcamento')
      ) x), '[]'::jsonb),
    'meses', coalesce((select jsonb_agg(jsonb_build_object('lab_id', v.lab_id, 'lab', l.nome, 'ano', m.ano, 'mes', m.mes, 'valor', m.valor_mes,
        'pago', coalesce((select sum(g.valor) from public.odo_fin_pagamentos g where g.mes_id = m.id and g.anulado_em is null), 0)) order by m.ano desc, m.mes desc)
      from public.odo_lab_vinculos v join public.odo_empresas l on l.id = v.lab_id
      join public.odo_fin_meses m on m.cliente_id = v.cliente_id and m.user_id = l.user_id
      where v.user_id = auth.uid() and v.status = 'aceito' and v.cliente_id is not null), '[]'::jsonb)) end;
$$;
revoke all on function public.odo_clinica_fin() from public, anon;
grant execute on function public.odo_clinica_fin() to authenticated;

-- ---------- 9. Índices que faltavam ----------
create index if not exists odo_pedidos_cliente      on public.odo_pedidos (cliente_id) where cliente_id is not null;
create index if not exists odo_pedidos_envio        on public.odo_pedidos (envio_id)   where envio_id is not null;
create index if not exists odo_lab_vinculos_lab     on public.odo_lab_vinculos (lab_id);
create index if not exists odo_lab_vinculos_cliente on public.odo_lab_vinculos (cliente_id) where cliente_id is not null;

-- permissões das funções de calendário (contas simples, sem dado de ninguém)
revoke all on function public.odo_dia_util(date) from public, anon;
revoke all on function public.odo_prazo_faixa(text) from public, anon;
revoke all on function public.odo_prazo_dia(timestamptz, int) from public, anon;
revoke all on function public.odo_etapa(text, text, boolean, boolean, boolean, boolean) from public, anon;
grant execute on function public.odo_dia_util(date) to authenticated;
grant execute on function public.odo_prazo_faixa(text) to authenticated;
grant execute on function public.odo_prazo_dia(timestamptz, int) to authenticated;
grant execute on function public.odo_etapa(text, text, boolean, boolean, boolean, boolean) to authenticated;

select 'ok: 074 aplicada' as resultado;
