-- =====================================================================
-- 105 - Ideali Odonto - desconto no valor do mês (financeiro / Inove)
-- Adiciona o campo de desconto (em R$) por mês do cliente.
-- Não altera dados existentes: todos ficam com desconto 0.
-- Não muda permissões: as políticas (RLS) da tabela continuam as mesmas.
-- =====================================================================
alter table public.odo_fin_meses
  add column if not exists valor_desconto numeric(10,2) not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'odo_fin_meses_valor_desconto_check'
      and conrelid = 'public.odo_fin_meses'::regclass
  ) then
    alter table public.odo_fin_meses
      add constraint odo_fin_meses_valor_desconto_check check (valor_desconto >= 0);
  end if;
end $$;
