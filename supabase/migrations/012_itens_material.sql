-- =====================================================================
-- Ideali CAD · Migração 012 · Trabalho por elemento, material e fresadora
-- itens:  um registro por dente, com tipo de trabalho e scanbody próprios
--         [{"d":36,"t":"<tipo_id>","imp":true,"m":"Neodent","c":"Cone Morse"}]
-- extras: trabalhos sem dente (ex.: Modelo 3D) [{"t":"<tipo_id>","q":1}]
-- material e fresadora valem para o pedido todo.
-- As regras de acesso (RLS) da tabela pedidos não mudam.
-- =====================================================================

alter table public.pedidos
  add column itens     jsonb not null default '[]'::jsonb check (jsonb_typeof(itens) = 'array' and pg_column_size(itens) < 32000),
  add column extras    jsonb not null default '[]'::jsonb check (jsonb_typeof(extras) = 'array' and pg_column_size(extras) < 8000),
  add column material  text check (char_length(material) <= 60),
  add column fresadora text check (fresadora in ('3 eixos','4 eixos'));
