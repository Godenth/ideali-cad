-- =====================================================================
-- Ideali CAD · Migração 013 · Plano grátis (sem arquivos)
-- Quem não está em teste nem com assinatura ativa continua usando o sistema
-- normalmente (clientes, pedidos, financeiro), mas não guarda arquivos.
--  · pode_escrever(): qualquer conta que não foi bloqueada pelo administrador
--    (status 'vencida' passa a significar "bloqueada").
--  · pode_arquivar(): só teste válido ou assinatura ativa. É o que libera
--    o envio de arquivos (Cloudflare R2) na função "arquivos".
-- =====================================================================

create or replace function public.pode_arquivar()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.assinaturas a
    where a.user_id = auth.uid()
      and (
        (a.status = 'teste' and a.teste_ate > now())
        or (a.status = 'ativa' and (a.vence_em is null or a.vence_em > now()))
      )
  );
$$;
revoke all on function public.pode_arquivar() from public, anon;
grant execute on function public.pode_arquivar() to authenticated;

create or replace function public.pode_escrever()
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
revoke all on function public.pode_escrever() from public, anon;
grant execute on function public.pode_escrever() to authenticated;
