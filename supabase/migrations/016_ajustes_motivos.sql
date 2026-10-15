-- Ideali CAD · Migração 016 · Motivo de cada ajuste pedido pelo cliente (para as Análises)
alter table public.pedidos add column ajustes_motivos text[] not null default '{}' check (coalesce(array_length(ajustes_motivos,1),0) <= 60);
