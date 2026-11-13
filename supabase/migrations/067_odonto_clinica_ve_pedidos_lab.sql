-- =====================================================================
-- 067 · Ideali Odonto · A clínica vê os pedidos que o laboratório lançou para ela
-- Pedido do dono em 13/11/2026: os clientes (clínicas) viram usuários. Os pedidos que o
-- laboratório já tem lançados para aquele cliente aparecem na conta da clínica como se ela
-- mesma tivesse mandado, com a etapa em tempo real. Daqui pra frente a clínica manda os dela.
--
-- Segurança:
--   * A clínica só LÊ, e só os pedidos do cliente que o laboratório ligou à conta dela
--     (odo_lab_vinculos.cliente_id, vínculo ACEITO). Nada de editar, nada de outros clientes.
--   * A leitura é por função (security definer) que devolve só os campos do pedido;
--     a tabela odo_pedidos continua fechada (sem política nova).
--   * Só o dono do laboratório escolhe qual cliente dele é aquela clínica.
-- Pode rodar de novo.
-- =====================================================================

-- 1) O laboratório diz: "esta clínica conectada é o meu cliente X"
create or replace function public.odo_lab_vincula_cliente(p_vinculo uuid, p_cliente uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.odo_lab_vinculos v join public.odo_empresas e on e.id = v.lab_id
                  where v.id = p_vinculo and e.user_id = auth.uid()) then
    raise exception 'vinculo_nao_e_seu';
  end if;
  if p_cliente is not null and not exists (select 1 from public.odo_clientes c where c.id = p_cliente and c.user_id = auth.uid()) then
    raise exception 'cliente_nao_e_seu';
  end if;
  update public.odo_lab_vinculos set cliente_id = p_cliente where id = p_vinculo;
end $$;
revoke all on function public.odo_lab_vincula_cliente(uuid, uuid) from public, anon;
grant execute on function public.odo_lab_vincula_cliente(uuid, uuid) to authenticated;

-- 2) A clínica lê os pedidos do laboratório que são dela (sem os que ela mesma mandou pelo sistema)
create or replace function public.odo_clinica_pedidos_lab() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(x order by x->>'criado_em' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', p.id, 'lab_id', e.id, 'lab_nome', e.nome, 'numero', p.numero, 'paciente', p.paciente,
      'trabalho', p.trabalho, 'dentes', to_jsonb(coalesce(p.dentes, '{}'::smallint[])), 'material', p.material, 'cor', p.cor,
      'sobre_implante', p.sobre_implante, 'prazo', p.prazo, 'urgente', p.urgente, 'criado_em', p.criado_em,
      'etapa', case
          when p.status = 'cancelado' then 'Cancelado'
          when p.status = 'entregue' then 'Entregue'
          when p.status = 'finalizado' then 'Pronto'
          when p.status = 'producao' and p.tipo = 'cad' and p.enviado_inove then 'Enviado para fresagem'
          when p.status = 'producao' then 'Em produção'
          when p.status = 'aguardando' then 'Aguardando informação'
          else 'Desenho CAD' end) as x
    from public.odo_lab_vinculos v
    join public.odo_empresas e on e.id = v.lab_id
    join public.odo_pedidos p on p.user_id = e.user_id and p.cliente_id = v.cliente_id
    where v.user_id = auth.uid() and v.status = 'aceito' and v.cliente_id is not null
      and p.envio_id is null and p.status <> 'orcamento'
    order by p.criado_em desc
    limit 300) q;
$$;
revoke all on function public.odo_clinica_pedidos_lab() from public, anon;
grant execute on function public.odo_clinica_pedidos_lab() to authenticated;

select 'ok: 067 aplicada' as resultado;
