-- Ideali CAD · Migração 015 · Tratamento do cliente (Dr., Dra., Protético…)
alter table public.clientes add column titulo text check (char_length(titulo) <= 20);
