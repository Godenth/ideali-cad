-- =====================================================================
-- 073 · Ideali Odonto · Financeiro da clínica passa a contar TAMBÉM os pedidos que o
-- laboratório lançou para ela (os que não vieram pelo sistema: e-mail, WhatsApp, balcão).
-- Antes só apareciam os pedidos enviados pelo sistema, por isso o mês ficava zerado
-- e não dava para voltar aos meses anteriores.
--
-- Segurança (igual à 061/067):
--   * Só o DONO da clínica (auth.uid(), funcionário não vê financeiro).
--   * Só os pedidos do cliente que o laboratório ligou a essa clínica (vínculo ACEITO).
--   * Só campos do pedido (paciente, trabalho, dentes, qtd, valor, etapa, datas). Nada de
--     anotações internas do laboratório.
-- Rode DEPOIS da 067. Pode rodar de novo.
-- =====================================================================
create or replace function public.odo_clinica_fin() returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then null else jsonb_build_object(
    'pedidos', coalesce((select jsonb_agg(x.j order by x.criado desc) from (
        -- pedidos que a clínica mandou pelo sistema
        select p.criado_em as criado, jsonb_build_object(
          'id', p.id, 'envio', e.id, 'lab_id', e.lab_id, 'lab', l.nome, 'paciente', p.paciente, 'trabalho', p.trabalho, 'dentes', p.dentes,
          'qtd', p.qtd, 'valor', p.valor, 'status', p.status, 'enviado_inove', p.enviado_inove, 'cor', p.cor,
          'criado', p.criado_em, 'finalizado', p.finalizado_em, 'entregue', p.entregue_em) as j
        from public.odo_pedidos p join public.odo_ped_env e on e.id = p.envio_id join public.odo_empresas l on l.id = e.lab_id
        where e.user_id = auth.uid() and p.user_id = l.user_id
        union all
        -- pedidos que o laboratório lançou para o cliente ligado a esta clínica
        select p.criado_em, jsonb_build_object(
          'id', p.id, 'envio', null, 'lab_id', l.id, 'lab', l.nome, 'paciente', p.paciente, 'trabalho', p.trabalho, 'dentes', p.dentes,
          'qtd', p.qtd, 'valor', p.valor, 'status', p.status, 'enviado_inove', p.enviado_inove, 'cor', p.cor,
          'criado', p.criado_em, 'finalizado', p.finalizado_em, 'entregue', p.entregue_em)
        from public.odo_lab_vinculos v
        join public.odo_empresas l on l.id = v.lab_id
        join public.odo_pedidos p on p.user_id = l.user_id and p.cliente_id = v.cliente_id
        where v.user_id = auth.uid() and v.status = 'aceito' and v.cliente_id is not null
          and p.envio_id is null and p.status not in ('orcamento')
      ) x), '[]'::jsonb),
    'meses', coalesce((select jsonb_agg(jsonb_build_object('lab_id', v.lab_id, 'lab', l.nome, 'ano', m.ano, 'mes', m.mes, 'valor', m.valor_mes,
        'pago', coalesce((select sum(g.valor) from public.odo_fin_pagamentos g where g.mes_id = m.id and g.anulado_em is null), 0)) order by m.ano desc, m.mes desc)
      from public.odo_lab_vinculos v join public.odo_empresas l on l.id = v.lab_id
      join public.odo_fin_meses m on m.cliente_id = v.cliente_id and m.user_id = l.user_id
      where v.user_id = auth.uid() and v.status = 'aceito' and v.cliente_id is not null), '[]'::jsonb)) end;
$$;
revoke all on function public.odo_clinica_fin() from public, anon;
grant execute on function public.odo_clinica_fin() to authenticated;

select 'ok: 073 aplicada' as resultado;
