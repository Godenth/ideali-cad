-- =====================================================================
-- 069 · Ideali Odonto · Histórico de pagamentos para a clínica
-- A clínica vê, mês a mês, o que o laboratório lançou para ela: valor do mês, pagamentos,
-- extrato e comprovantes. Só leitura.
--
-- Segurança:
--   * Só os meses do cliente que o laboratório ligou à conta da clínica (vínculo ACEITO).
--   * Só o dono da clínica (financeiro: funcionário não vê).
--   * Não mostra nada interno do laboratório (comissão, conferência da Inove, observações).
--   * Arquivos: a clínica só abre o extrato e os comprovantes desses meses (URL assinada),
--     nenhum outro arquivo do laboratório.
-- Rode DEPOIS da 068. Pode rodar de novo.
-- =====================================================================
create or replace function public.odo_clinica_pagamentos() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(x order by (x->>'ano')::int desc, (x->>'mes')::int desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', m.id, 'lab_id', l.id, 'lab', l.nome, 'ano', m.ano, 'mes', m.mes,
      'valor', m.valor_mes + m.valor_componente, 'quitado', m.quitado, 'extrato', m.extrato_path,
      'pagamentos', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'valor', g.valor, 'data', coalesce(g.data, g.criado_em::date),
                                                                  'comprovante', g.comprovante_path) order by coalesce(g.data, g.criado_em::date))
                              from public.odo_fin_pagamentos g where g.mes_id = m.id and g.anulado_em is null), '[]'::jsonb)) as x
    from public.odo_lab_vinculos v
    join public.odo_empresas l on l.id = v.lab_id
    join public.odo_fin_meses m on m.cliente_id = v.cliente_id and m.user_id = l.user_id
    where v.user_id = auth.uid() and v.status = 'aceito' and v.cliente_id is not null
      and (m.valor_mes + m.valor_componente > 0 or exists (select 1 from public.odo_fin_pagamentos g where g.mes_id = m.id and g.anulado_em is null))
  ) q;
$$;
revoke all on function public.odo_clinica_pagamentos() from public, anon;
grant execute on function public.odo_clinica_pagamentos() to authenticated;

-- arquivo do financeiro que pertence a um mês da própria clínica?
create or replace function public.odo_fin_arquivo_da_clinica(p_nome text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.odo_lab_vinculos v
      join public.odo_empresas l on l.id = v.lab_id
      join public.odo_fin_meses m on m.cliente_id = v.cliente_id and m.user_id = l.user_id
     where v.user_id = auth.uid() and v.status = 'aceito' and v.cliente_id is not null
       and (m.extrato_path = p_nome
            or exists (select 1 from public.odo_fin_pagamentos g where g.mes_id = m.id and g.anulado_em is null and g.comprovante_path = p_nome)));
$$;
revoke all on function public.odo_fin_arquivo_da_clinica(text) from public, anon;
grant execute on function public.odo_fin_arquivo_da_clinica(text) to authenticated;

drop policy if exists odonto_fin_clinica_ler on storage.objects;
create policy odonto_fin_clinica_ler on storage.objects for select to authenticated
  using (bucket_id = 'odonto-fin' and public.odo_fin_arquivo_da_clinica(name));

select 'ok: 069 aplicada' as resultado;
