-- =====================================================================
-- Ideali CAD · Migração 007 · Sem tipos de trabalho repetidos
-- Remove repetidos já criados (fica o mais antigo; só apaga os que não estão
-- em nenhum pedido nem tabela de preço de cliente) e impede novos repetidos:
-- um nome por conta (itens na lixeira não contam).
-- =====================================================================

-- Remove repetidos (fica o mais antigo de cada nome). Só apaga os que não
--    estão em nenhum pedido nem em tabela de preço de cliente.
delete from public.tipos_trabalho t
using (
  select id, row_number() over (partition by user_id, lower(nome) order by criado_em, id) rn
  from public.tipos_trabalho where deleted_at is null
) d
where t.id = d.id and d.rn > 1
  and not exists (select 1 from public.pedidos p where p.tipo_trabalho_id = t.id)
  and not exists (select 1 from public.precos_cliente c where c.tipo_trabalho_id = t.id);

-- Um nome por conta (itens na lixeira não contam).
create unique index tipos_nome_unico on public.tipos_trabalho (user_id, lower(nome)) where deleted_at is null;

