-- =====================================================================
-- 055 · Ideali Odonto · A Inove anexa extratos e comprovantes pela Ana (entra direto).
-- Rode DEPOIS da 054.
-- O que a conta da Inove passa a poder fazer na conta do laboratório parceiro, e SÓ isso:
--   • enviar arquivo (PDF/foto) para as pastas "extratos" e "comprovantes" do laboratório
--     (não troca nem apaga arquivo nenhum);
--   • anexar o extrato de um mês;
--   • lançar o cliente num mês que ainda não existe (com o valor do extrato);
--   • lançar um pagamento com comprovante (já fica "confirmado pela Inove").
-- Ela continua sem poder editar valores, apagar ou mudar qualquer outra coisa.
-- Tudo que a Inove faz fica marcado com "lançado pela Inove" e a data.
-- =====================================================================

-- arquivos: a Inove só ENVIA, e só nas pastas certas do laboratório parceiro
drop policy if exists odonto_fin_inove_envia on storage.objects;
create policy odonto_fin_inove_envia on storage.objects for insert to authenticated
  with check (bucket_id = 'odonto-fin'
    and (storage.foldername(name))[2] in ('extratos','comprovantes')
    and public.odo_parceiro_de_txt((storage.foldername(name))[1]));

alter table public.odo_fin_pagamentos add column if not exists lancado_por text check (char_length(lancado_por) <= 40);
alter table public.odo_fin_meses add column if not exists extrato_por text check (char_length(extrato_por) <= 40);

-- anexar o extrato de um mês
create or replace function public.odo_inove_extrato(p_mes uuid, p_path text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare m public.odo_fin_meses;
begin
  select * into m from public.odo_fin_meses where id = p_mes;
  if m.id is null then raise exception 'Mês não encontrado'; end if;
  if not (m.user_id = auth.uid() or public.odo_parceiro_de(m.user_id)) then raise exception 'Sem permissão'; end if;
  if p_path is null or p_path not like m.user_id::text || '/extratos/%' or char_length(p_path) > 300 then raise exception 'Arquivo inválido'; end if;
  update public.odo_fin_meses set extrato_path = p_path, extrato_recebido = true,
         extrato_por = case when m.user_id = auth.uid() then 'laboratorio' else 'inove' end
   where id = m.id;
  return true;
end $$;

-- lançar o cliente num mês que ainda não existe
create or replace function public.odo_inove_lanca_mes(p_dono uuid, p_cliente uuid, p_ano int, p_mes int, p_valor numeric) returns uuid
language plpgsql security definer set search_path = '' as $$
declare c public.odo_clientes; nid uuid;
begin
  if not (p_dono = auth.uid() or public.odo_parceiro_de(p_dono)) then raise exception 'Sem permissão'; end if;
  select * into c from public.odo_clientes where id = p_cliente and user_id = p_dono;
  if c.id is null then raise exception 'Cliente inválido'; end if;
  if p_mes < 1 or p_mes > 12 or p_ano < 2020 or p_ano > 2100 or p_valor < 0 or p_valor > 1000000 then raise exception 'Valores inválidos'; end if;
  select id into nid from public.odo_fin_meses where user_id = p_dono and cliente_id = p_cliente and ano = p_ano and mes = p_mes limit 1;
  if nid is not null then return nid; end if;
  insert into public.odo_fin_meses (user_id, cliente_id, cliente_reg, ano, mes, valor_mes, obs)
  values (p_dono, p_cliente, c.reg, p_ano, p_mes, round(p_valor, 2), case when p_dono = auth.uid() then null else 'Lançado pela Inove' end)
  returning id into nid;
  return nid;
end $$;

-- lançar pagamento com comprovante
create or replace function public.odo_inove_pagamento(p_mes uuid, p_valor numeric, p_data date, p_path text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare m public.odo_fin_meses; nid uuid; eu boolean;
begin
  select * into m from public.odo_fin_meses where id = p_mes;
  if m.id is null then raise exception 'Mês não encontrado'; end if;
  eu := m.user_id = auth.uid();
  if not (eu or public.odo_parceiro_de(m.user_id)) then raise exception 'Sem permissão'; end if;
  if p_valor is null or p_valor <= 0 or p_valor > 1000000 then raise exception 'Valor inválido'; end if;
  if p_path is null or p_path not like m.user_id::text || '/comprovantes/%' or char_length(p_path) > 300 then raise exception 'Arquivo inválido'; end if;
  if p_data is null or p_data > current_date + 1 or p_data < date '2020-01-01' then raise exception 'Data inválida'; end if;
  perform set_config('odo.inove_confirma','1',true);
  insert into public.odo_fin_pagamentos (user_id, mes_id, valor, data, comprovante_path, conferencia, lancado_por, inove_ok_em, inove_ok_por)
  values (m.user_id, m.id, round(p_valor, 2), p_data, p_path, 'ok', case when eu then 'laboratorio' else 'inove' end,
          case when eu then null else now() end, case when eu then null else auth.uid() end)
  returning id into nid;
  perform set_config('odo.inove_confirma','',true);
  return nid;
end $$;

revoke all on function public.odo_inove_extrato(uuid, text) from public, anon;
revoke all on function public.odo_inove_lanca_mes(uuid, uuid, int, int, numeric) from public, anon;
revoke all on function public.odo_inove_pagamento(uuid, numeric, date, text) from public, anon;
grant execute on function public.odo_inove_extrato(uuid, text) to authenticated;
grant execute on function public.odo_inove_lanca_mes(uuid, uuid, int, int, numeric) to authenticated;
grant execute on function public.odo_inove_pagamento(uuid, numeric, date, text) to authenticated;

select 'ok: 055 aplicada' as resultado;
