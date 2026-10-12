-- =====================================================================
-- Ideali CAD · Migração 005 · Cidade e estado (UF)
-- Perfil do cadista ganha o estado; clientes ganham cidade e estado.
-- As regras de acesso (RLS) não mudam.
-- =====================================================================

alter table public.perfis
  add column uf text check (uf in ('AC','AL','AM','AP','BA','CE','DF','ES','GO','MA','MG','MS','MT','PA','PB','PE','PI','PR','RJ','RN','RO','RR','RS','SC','SE','SP','TO'));

alter table public.clientes
  add column cidade text check (char_length(cidade) <= 60),
  add column uf     text check (uf in ('AC','AL','AM','AP','BA','CE','DF','ES','GO','MA','MG','MS','MT','PA','PB','PE','PI','PR','RJ','RN','RO','RR','RS','SC','SE','SP','TO'));
