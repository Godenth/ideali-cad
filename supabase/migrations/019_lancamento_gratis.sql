-- =====================================================================
-- Ideali CAD · Migração 019 · Lançamento grátis com tudo liberado
-- Enquanto durar o lançamento, qualquer conta não bloqueada pelo administrador
-- pode guardar arquivos (respeitando o limite de espaço de cada conta, limite_bytes).
-- Para voltar ao modelo com planos, reaplicar a versão da migração 013.
-- =====================================================================
create or replace function public.pode_arquivar()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.assinaturas a
    where a.user_id = auth.uid()
      and a.status <> 'vencida'
  );
$$;
revoke all on function public.pode_arquivar() from public, anon;
grant execute on function public.pode_arquivar() to authenticated;
