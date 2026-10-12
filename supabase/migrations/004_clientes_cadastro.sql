-- =====================================================================
-- Ideali CAD · Migração 004 · Cadastro de clientes mais completo
-- nome (primeiro nome) + sobrenome obrigatórios no app, empresa opcional,
-- tipo laboratório ou clínica/consultório (valor 'dentista' mantido no banco),
-- CPF ou CNPJ opcional, guardado só com números.
-- Clientes antigos continuam válidos (sobrenome fica vazio até ser editado).
-- As regras de acesso (RLS) da tabela clientes não mudam.
-- =====================================================================

alter table public.clientes
  add column sobrenome text check (char_length(sobrenome) <= 80),
  add column empresa   text check (char_length(empresa) <= 100),
  add column documento text check (documento ~ '^([0-9]{11}|[0-9]{14})$');
