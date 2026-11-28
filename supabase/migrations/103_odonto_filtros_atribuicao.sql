-- =====================================================================
-- 103 · Ideali Odonto · filtros da conta atribuída (Tarefa 5, continuação da 102)
-- • Base exata: odo_clinica_meses, odo_clinica_pedidos e odo_clinica_pagamentos vêm da 075;
--   odo_clinica_pedidos_lab e odo_clinica_fin vêm da 074.
-- • Só ACRESCENTA o caminho novo: vínculo origem='lab_para_conta', status='aceito',
--   cancelado_em is null e removido_em is null, com leitura pelo cliente_id e lab_id dele.
-- • No caminho novo a leitura é sempre de auth.uid(). Nunca de odo_conta() nem da variável conta:
--   um funcionário interno da clínica (odo_membros) não passa a ver os valores da conta atribuída.
-- • O ramo antigo (clinica_para_lab) de cada função continua idêntico à versão de base, em comportamento.
-- • Funcionário da conta atribuída VÊ valores: o rótulo papel não esconde preço, extrato nem pagamento.
--   A regra antiga do dono da clínica (dono = conta = usuário) não foi alterada por causa disso.
-- • Nenhuma coluna nova, nenhuma mudança de dados e nenhuma permissão nova além das existentes.
-- • Pode rodar de novo.
-- ATENÇÃO: reexecutar a 074 ou a 075 depois desta 103 VOLTA as funções antigas (sem o caminho novo)
-- e deve ser evitado. Se isso acontecer, rode esta 103 novamente.
-- =====================================================================

begin;

-- ---------- 1. Meses/extrato/pagamentos da clínica (base 075) ----------
-- p_conta continua sendo a conta informada por quem chama; o ramo antigo não ganhou
-- nenhuma comparação com auth.uid(). O ramo novo lê somente a conta atribuída a quem chamou.
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
     where v.cliente_id is not null and v.status = 'aceito' and (
         (v.origem = 'clinica_para_lab' and v.user_id = p_conta
          and (m.valor_mes > 0 or m.extrato_path is not null
               or exists (select 1 from public.odo_fin_pagamentos g where g.mes_id = m.id and g.anulado_em is null)))
         or
         (v.origem = 'lab_para_conta' and v.user_id = auth.uid()
          and v.cancelado_em is null and v.removido_em is null))
  ) x;
$$;
revoke all on function public.odo_clinica_meses(uuid) from public, anon, authenticated;

-- ---------- 2. Leitura única da clínica (base 075) ----------
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
    where v.cliente_id is not null and v.status = 'aceito' and (
        v.user_id = conta
        or
        (v.origem = 'lab_para_conta' and v.user_id = eu
         and v.cancelado_em is null and v.removido_em is null))
      and p.envio_id is null and p.apagado is not true and p.status <> 'orcamento'
  ) x;

  -- (c) fechamentos do mês: só o dono. A conta (pago, crédito, falta, situação) é a MESMA da tela do laboratório.
  if dono then r_mes := public.odo_clinica_meses(conta); end if;

  return jsonb_build_object('dono', dono, 'envios', r_env, 'pedidos', r_ped, 'meses', r_mes, 'agora', now());
end $$;
revoke all on function public.odo_clinica_pedidos() from public, anon;
grant execute on function public.odo_clinica_pedidos() to authenticated;

-- ---------- 3. Histórico antigo (base 075): exatamente como era ----------
create or replace function public.odo_clinica_pagamentos() returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then '[]'::jsonb else public.odo_clinica_meses(auth.uid()) end;
$$;
revoke all on function public.odo_clinica_pagamentos() from public, anon;
grant execute on function public.odo_clinica_pagamentos() to authenticated;

-- ---------- 4. Pedidos da clínica no laboratório (base 074) ----------
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
    where v.cliente_id is not null and v.status = 'aceito' and (
        v.user_id = public.odo_conta()
        or
        (v.origem = 'lab_para_conta' and v.user_id = auth.uid()
         and v.cancelado_em is null and v.removido_em is null))
      and p.envio_id is null and p.apagado is not true and p.status <> 'orcamento'
    order by p.criado_em desc
    limit 300) q;
$$;
revoke all on function public.odo_clinica_pedidos_lab() from public, anon;
grant execute on function public.odo_clinica_pedidos_lab() to authenticated;

-- ---------- 5. Financeiro antigo da clínica (base 074): pedidos e meses ----------
-- Os envios continuam exatamente como na 074: só e.user_id = auth.uid(), sem ramo novo.
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
        where v.cliente_id is not null and v.status = 'aceito' and (
            (v.origem = 'clinica_para_lab' and v.user_id = auth.uid())
            or
            (v.origem = 'lab_para_conta' and v.user_id = auth.uid()
             and v.cancelado_em is null and v.removido_em is null))
          and p.envio_id is null and p.apagado is not true and p.status not in ('orcamento')
      ) x), '[]'::jsonb),
    'meses', coalesce((select jsonb_agg(jsonb_build_object('lab_id', v.lab_id, 'lab', l.nome, 'ano', m.ano, 'mes', m.mes, 'valor', m.valor_mes,
        'pago', coalesce((select sum(g.valor) from public.odo_fin_pagamentos g where g.mes_id = m.id and g.anulado_em is null), 0)) order by m.ano desc, m.mes desc)
      from public.odo_lab_vinculos v join public.odo_empresas l on l.id = v.lab_id
      join public.odo_fin_meses m on m.cliente_id = v.cliente_id and m.user_id = l.user_id
      where v.cliente_id is not null and v.status = 'aceito' and (
          (v.origem = 'clinica_para_lab' and v.user_id = auth.uid())
          or
          (v.origem = 'lab_para_conta' and v.user_id = auth.uid()
           and v.cancelado_em is null and v.removido_em is null))), '[]'::jsonb)) end;
$$;
revoke all on function public.odo_clinica_fin() from public, anon;
grant execute on function public.odo_clinica_fin() to authenticated;

select 'ok: 103 aplicada' as resultado;

commit;
