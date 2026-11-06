-- 040 · Ideali Odonto: guarda as respostas completas do cadastro (outras profissões, o que sabe fazer,
-- como trabalha, onde topa trabalhar e a entrevista com a Ana). Mesma regra (RLS) do perfil: só o dono lê e grava.
-- A Rede (odo_rede_profs) continua NÃO entregando este campo.
alter table public.odo_perfis add column if not exists cadastro jsonb not null default '{}'::jsonb;
alter table public.odo_perfis drop constraint if exists odo_perfis_cadastro_tam;
alter table public.odo_perfis add constraint odo_perfis_cadastro_tam check (pg_column_size(cadastro) < 30000);
