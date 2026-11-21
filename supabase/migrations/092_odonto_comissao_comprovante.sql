-- =====================================================================
-- 092 · Ideali Odonto · Comissão: campo comprovante_path
-- Adiciona coluna para guardar o caminho do comprovante no bucket
-- privado "odonto-fin" (<user_id>/comissoes/<id>.<ext>).
-- Pode rodar de novo sem erro (IF NOT EXISTS / ADD COLUMN IF NOT EXISTS).
-- =====================================================================

alter table public.odo_fin_comissoes
  add column if not exists comprovante_path text
    check (char_length(comprovante_path) <= 300);

select 'ok: 092 pronta' as resultado;
