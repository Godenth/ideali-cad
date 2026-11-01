-- 037: logo do cadista (aparece nos PDFs de extrato, cobrança e relatórios).
-- Guardado como imagem pequena (já reduzida no navegador) dentro do próprio perfil, protegido pela mesma regra (RLS) do perfil.
alter table public.perfis add column if not exists logo text;
alter table public.perfis drop constraint if exists perfis_logo_tam;
alter table public.perfis add constraint perfis_logo_tam check (logo is null or (char_length(logo) <= 300000 and logo like 'data:image/%'));
