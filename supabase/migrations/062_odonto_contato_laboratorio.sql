-- =====================================================================
-- 062 · Ideali Odonto · Dados de contato do laboratório para as clínicas parceiras.
-- O laboratório preenche em Minha empresa (WhatsApp, telefone, e-mail, endereço, horário,
-- site, Instagram e logo). A clínica conectada vê esses dados na aba Laboratórios parceiros.
-- Só aparece o que o próprio laboratório preencheu (nada vem do pré-cadastro).
-- A clínica só vê laboratórios com quem tem convite; nada de equipe, vagas, financeiro ou ajustes.
-- Rode DEPOIS da 056. Pode rodar de novo.
-- =====================================================================
create or replace function public.odo_labs_parceiros() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'vinculo', v.id, 'lab_id', e.id, 'status', v.status, 'codigo', e.codigo, 'nome', e.nome, 'cidade', e.cidade, 'uf', e.uf, 'rt', e.rt,
      'contato', coalesce(e.dados->'contato', '{}'::jsonb))), '[]'::jsonb)
  from public.odo_lab_vinculos v join public.odo_empresas e on e.id = v.lab_id
  where v.user_id = auth.uid() and v.status in ('pendente','aceito');
$$;
revoke all on function public.odo_labs_parceiros() from public, anon;
grant execute on function public.odo_labs_parceiros() to authenticated;
select 'ok: 062 aplicada' as resultado;
