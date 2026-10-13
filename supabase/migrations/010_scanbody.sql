-- =====================================================================
-- Ideali CAD · Migração 010 · Scanbody (trabalhos sobre implante)
-- Marca do implante e tipo de conexão/scanbody de cada pedido.
-- As regras de acesso (RLS) da tabela pedidos não mudam.
-- =====================================================================

alter table public.pedidos
  add column implante_marca text check (char_length(implante_marca) <= 60),
  add column implante_tipo  text check (char_length(implante_tipo) <= 60);
