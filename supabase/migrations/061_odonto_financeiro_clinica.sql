-- =====================================================================
-- 061 · Ideali Odonto · Financeiro da clínica (o que ela mandou para cada laboratório e quanto custou).
-- • Quando o laboratório aceita um pedido digital, o valor sai sozinho da tabela de preços
--   do laboratório (preço do trabalho × quantidade de elementos), se o trabalho for achado na tabela.
--   O laboratório pode mudar o valor depois, normalmente.
-- • A clínica vê, só dos pedidos que ELA mandou: paciente, trabalho, dentes, quantidade, valor,
--   etapa e datas. E, se o laboratório ligou essa clínica a um cliente, o fechamento do mês
--   (valor do mês, quanto foi pago, quanto falta). Nada de anotações internas do laboratório.
-- Rode DEPOIS da 057. Pode rodar de novo.
-- =====================================================================
create or replace function public.odo_pedido_preco_tabela() returns trigger
language plpgsql security definer set search_path = '' as $$
declare pr public.odo_precos;
begin
  if new.envio_id is null or new.valor is not null or coalesce(new.trabalho,'') = '' then return new; end if;
  select * into pr from public.odo_precos where user_id = new.user_id and lower(nome) = lower(new.trabalho) and valor is not null limit 1;
  if pr.id is null then
    select * into pr from public.odo_precos where user_id = new.user_id and valor is not null and char_length(nome) >= 4
       and position(lower(nome) in lower(new.trabalho)) > 0 order by char_length(nome) desc limit 1;
  end if;
  if pr.id is not null then new.valor := round(pr.valor * greatest(coalesce(new.qtd,1),1), 2); end if;
  return new;
end $$;
drop trigger if exists odo_pedidos_preco_tabela on public.odo_pedidos;
create trigger odo_pedidos_preco_tabela before insert on public.odo_pedidos
  for each row execute function public.odo_pedido_preco_tabela();

create or replace function public.odo_clinica_fin() returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then null else jsonb_build_object(
    'pedidos', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'envio', e.id, 'lab_id', e.lab_id, 'lab', l.nome, 'paciente', p.paciente, 'trabalho', p.trabalho, 'dentes', p.dentes,
        'qtd', p.qtd, 'valor', p.valor, 'status', p.status, 'enviado_inove', p.enviado_inove, 'cor', p.cor,
        'criado', p.criado_em, 'finalizado', p.finalizado_em, 'entregue', p.entregue_em) order by p.criado_em desc)
      from public.odo_pedidos p join public.odo_ped_env e on e.id = p.envio_id join public.odo_empresas l on l.id = e.lab_id
      where e.user_id = auth.uid() and p.user_id = l.user_id), '[]'::jsonb),
    'meses', coalesce((select jsonb_agg(jsonb_build_object('lab_id', v.lab_id, 'lab', l.nome, 'ano', m.ano, 'mes', m.mes, 'valor', m.valor_mes,
        'pago', coalesce((select sum(g.valor) from public.odo_fin_pagamentos g where g.mes_id = m.id and g.anulado_em is null), 0)) order by m.ano desc, m.mes desc)
      from public.odo_lab_vinculos v join public.odo_empresas l on l.id = v.lab_id
      join public.odo_fin_meses m on m.cliente_id = v.cliente_id and m.user_id = l.user_id
      where v.user_id = auth.uid() and v.status = 'aceito' and v.cliente_id is not null), '[]'::jsonb)) end;
$$;
revoke all on function public.odo_clinica_fin() from public, anon;
grant execute on function public.odo_clinica_fin() to authenticated;

select 'ok: 061 aplicada' as resultado;
