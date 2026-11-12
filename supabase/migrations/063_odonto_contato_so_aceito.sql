-- =====================================================================
-- 063 · Ideali Odonto · CORREÇÃO DE SEGURANÇA
-- O contato do laboratório só aparece para a clínica DEPOIS que o laboratório ACEITA o convite.
-- (Antes, um convite ainda pendente já mostrava os dados — qualquer conta podia convidar
--  um laboratório pelo ID e ver o contato.) Nada de pré-cadastro, nada de outro usuário.
-- Pode rodar de novo.
-- =====================================================================
create or replace function public.odo_labs_parceiros() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'vinculo', v.id, 'lab_id', e.id, 'status', v.status, 'codigo', e.codigo, 'nome', e.nome, 'cidade', e.cidade, 'uf', e.uf, 'rt', e.rt,
      'contato', case when v.status = 'aceito' then coalesce(e.dados->'contato', '{}'::jsonb) else '{}'::jsonb end)), '[]'::jsonb)
  from public.odo_lab_vinculos v join public.odo_empresas e on e.id = v.lab_id
  where v.user_id = auth.uid() and v.status in ('pendente','aceito');
$$;
revoke all on function public.odo_labs_parceiros() from public, anon;
grant execute on function public.odo_labs_parceiros() to authenticated;

-- Conferência: quais contas tinham convite com o laboratório que usava aquele pré-cadastro
-- (essas são as únicas que podem ter visto o e-mail/WhatsApp enquanto a 062 antiga estava ativa).
select v.status, v.quem_nome, v.criado_em, e.nome as laboratorio
  from public.odo_lab_vinculos v join public.odo_empresas e on e.id = v.lab_id
 where exists (select 1 from public.odo_pre_cadastros p where p.aceito_por = e.user_id)
 order by v.criado_em;
