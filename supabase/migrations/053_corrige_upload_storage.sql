-- =====================================================================
-- 053 · Corrige o envio de arquivos no projeto inteiro (Ideali CAD + Ideali Odonto).
-- A regra "portfolio_dono_envia" contava as fotos do portfólio olhando a própria tabela
-- de arquivos dentro da regra. O banco entende isso como "recursão infinita" e recusa
-- QUALQUER envio de arquivo ("The database schema is invalid or incompatible").
-- Agora a contagem é feita por uma função própria. O limite continua o mesmo: até 12 fotos
-- por pessoa no portfólio, e cada um só envia na própria pasta.
-- =====================================================================
create or replace function public.portfolio_qtd_meu() returns int
language sql stable security definer set search_path = '' as $$
  select count(*)::int from storage.objects o
  where o.bucket_id = 'portfolio' and (storage.foldername(o.name))[1] = (select auth.uid())::text;
$$;
revoke all on function public.portfolio_qtd_meu() from public, anon;
grant execute on function public.portfolio_qtd_meu() to authenticated;

drop policy if exists portfolio_dono_envia on storage.objects;
create policy portfolio_dono_envia on storage.objects for insert to authenticated
  with check (bucket_id = 'portfolio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.portfolio_qtd_meu() < 13);

select 'ok: 053 aplicada' as resultado;
