-- =====================================================================
-- 059 · Ideali Odonto · Arcada do pedido: guarda dente por dente o tipo do trabalho
-- (sobre implante, sobre dente, faceta, pôntico) e o que é UNIDO e o que é UNITÁRIO.
-- Fica no próprio pedido, com a mesma regra de acesso (cada um só vê os seus). Pode rodar de novo.
-- =====================================================================
alter table public.odo_pedidos add column if not exists arcada jsonb
  check (arcada is null or (jsonb_typeof(arcada) = 'array' and jsonb_array_length(arcada) <= 32 and pg_column_size(arcada) < 6000));
select 'ok: 059 aplicada' as resultado;
