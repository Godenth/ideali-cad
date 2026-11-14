-- =====================================================================
-- 075 · Ideali Odonto · FINANCEIRO COM UMA CONTA SÓ (continuação da 074)
--
-- Problema: a situação do mês (quanto vale, quanto foi pago, quanto falta) era calculada de
-- jeitos diferentes em cada lugar:
--   * na tela do laboratório: valor do mês, pagamentos, crédito do mês anterior, "quitado";
--   * no Histórico da clínica: somava "valor do mês + componentes" (mostrava A MAIS do que você cobra);
--   * no Financeiro/Painel da clínica: valor - pago, sem crédito e sem olhar "quitado".
--
-- Agora existe UMA função no banco (odo_fin_mes_resumo) com a regra da tela do laboratório,
-- e a clínica recebe o resultado pronto. O que a clínica vê é igual ao que você vê.
--
-- Segurança: igual à 074 (só o dono da clínica, só o cliente ligado à conta dela).
-- Não altera nenhum dado. Pode rodar de novo. Rode depois da 074.
-- =====================================================================

-- ---------- 1. A situação de um mês, calculada num lugar só ----------
-- Regra (a mesma da tela Financeiro do laboratório):
--   pago     = soma dos pagamentos não anulados
--   crédito  = o que sobrou do mês anterior do mesmo cliente (pagou a mais), se "abater" não foi desligado
--   falta    = valor do mês - pago - crédito (nunca negativo; zero se o mês está marcado como quitado)
--   situação = pago · parcial · aberto · zero (mês sem valor e sem pagamento)
create or replace function public.odo_fin_mes_resumo(m public.odo_fin_meses) returns jsonb
language plpgsql stable set search_path = '' as $$
declare pago numeric; ant numeric := 0; cred numeric := 0; resta numeric; pt numeric; a int; ms int; pv_id uuid; pv_valor numeric;
begin
  select coalesce(sum(g.valor), 0) into pago from public.odo_fin_pagamentos g where g.mes_id = m.id and g.anulado_em is null;
  a  := case when m.mes = 1 then m.ano - 1 else m.ano end;
  ms := case when m.mes = 1 then 12 else m.mes - 1 end;
  select x.id, x.valor_mes into pv_id, pv_valor from public.odo_fin_meses x
   where x.user_id = m.user_id and x.ano = a and x.mes = ms
     and (x.cliente_id = m.cliente_id or (m.cliente_id is null and x.cliente_id is null and x.cliente_reg = m.cliente_reg))
   limit 1;
  if pv_id is not null then
    select coalesce(sum(g.valor), 0) - pv_valor into ant from public.odo_fin_pagamentos g where g.mes_id = pv_id and g.anulado_em is null;
    if abs(ant) < 0.005 then ant := 0; end if;
  end if;
  if ant > 0 and m.abater_credito is not false then cred := ant; end if;
  resta := round(m.valor_mes - pago - cred, 2);
  pt := round(pago + cred, 2);
  return jsonb_build_object(
    'valor', m.valor_mes, 'pago', pago, 'credito', cred, 'pago_total', pt,
    'falta', case when coalesce(m.quitado, false) then 0 else greatest(0, resta) end,
    'quitado', coalesce(m.quitado, false),
    'situacao', case when coalesce(m.quitado, false) or (m.valor_mes > 0 and resta <= 0.005) then 'pago'
                     when m.valor_mes = 0 and pt = 0 then 'zero'
                     when pt > 0 then 'parcial'
                     else 'aberto' end);
end $$;
revoke all on function public.odo_fin_mes_resumo(public.odo_fin_meses) from public, anon, authenticated;

-- ---------- 2. Os meses de uma clínica (uso interno das leituras abaixo) ----------
create or replace function public.odo_clinica_meses(p_conta uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(x.j order by x.ano desc, x.mes desc), '[]'::jsonb) from (
    select m.ano, m.mes,
           jsonb_build_object('id', m.id, 'lab_id', v.lab_id, 'lab', l.nome, 'ano', m.ano, 'mes', m.mes, 'extrato', m.extrato_path,
             'pagamentos', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'valor', g.valor, 'data', coalesce(g.data, g.criado_em::date),
                                                                         'comprovante', g.comprovante_path) order by coalesce(g.data, g.criado_em::date), g.criado_em)
                                       from public.odo_fin_pagamentos g where g.mes_id = m.id and g.anulado_em is null), '[]'::jsonb))
           || public.odo_fin_mes_resumo(m) as j
      from public.odo_lab_vinculos v
      join public.odo_empresas l on l.id = v.lab_id
      join public.odo_fin_meses m on m.cliente_id = v.cliente_id and m.user_id = l.user_id
     where v.user_id = p_conta and v.status = 'aceito' and v.cliente_id is not null
       and (m.valor_mes > 0 or m.extrato_path is not null
            or exists (select 1 from public.odo_fin_pagamentos g where g.mes_id = m.id and g.anulado_em is null))
  ) x;
$$;
revoke all on function public.odo_clinica_meses(uuid) from public, anon, authenticated;

-- ---------- 3. A leitura única da clínica passa a trazer os meses já com a situação pronta ----------
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

  -- (c) fechamentos do mês: só o dono. A conta (pago, crédito, falta, situação) é a MESMA da tela do laboratório.
  if dono then r_mes := public.odo_clinica_meses(conta); end if;

  return jsonb_build_object('dono', dono, 'envios', r_env, 'pedidos', r_ped, 'meses', r_mes, 'agora', now());
end $$;
revoke all on function public.odo_clinica_pedidos() from public, anon;
grant execute on function public.odo_clinica_pedidos() to authenticated;

-- ---------- 4. Histórico antigo (para quem estiver com a tela antiga aberta): mesmos números ----------
-- Antes somava "valor do mês + componentes". Agora é o valor do mês, igual à tela do laboratório.
create or replace function public.odo_clinica_pagamentos() returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then '[]'::jsonb else public.odo_clinica_meses(auth.uid()) end;
$$;
revoke all on function public.odo_clinica_pagamentos() from public, anon;
grant execute on function public.odo_clinica_pagamentos() to authenticated;

select 'ok: 075 aplicada' as resultado;
