-- =====================================================================
-- 058 · Ideali CAD · Pagamento parcial.
-- Quando o cliente paga MENOS do que os pedidos somam, a diferença agora pode ficar
-- em aberto (em vez de virar desconto). O sistema guarda quanto já foi recebido de cada
-- pedido e quais pagamentos foram parciais. Cada um continua vendo só os próprios dados.
-- Pode rodar de novo.
-- =====================================================================
alter table public.pedidos add column if not exists recebido_parcial numeric(10,2) not null default 0
  check (recebido_parcial >= 0);
alter table public.pagamentos add column if not exists parciais jsonb not null default '[]'::jsonb
  check (jsonb_typeof(parciais) = 'array' and pg_column_size(parciais) < 8000);
select 'ok: 058 aplicada' as resultado;
