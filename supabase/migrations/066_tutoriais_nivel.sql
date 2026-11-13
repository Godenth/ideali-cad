-- =====================================================================
-- 066 · Tutoriais: nível do vídeo (básico, intermediário, avançado)
-- Rode DEPOIS da 064. Pode rodar de novo.
-- =====================================================================
alter table public.tutoriais add column if not exists nivel text
  check (nivel in ('basico','intermediario','avancado'));
select 'ok: 066 aplicada' as resultado;
