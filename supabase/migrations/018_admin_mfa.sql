-- Ideali CAD · Migração 018 · Verificação em duas etapas do administrador
-- Depois que o administrador cadastra um app autenticador, as funções de administração
-- só respondem numa sessão confirmada com o código (aal2).
create or replace function public.admin_seguro()
returns boolean language sql stable security definer set search_path = public, auth as $$
  select public.sou_admin() and (
    coalesce(auth.jwt()->>'aal','aal1') = 'aal2'
    or not exists (select 1 from auth.mfa_factors f where f.user_id = auth.uid() and f.status = 'verified')
  );
$$;
revoke all on function public.admin_seguro() from public, anon;
grant execute on function public.admin_seguro() to authenticated;

do $$
declare fn text; def text;
begin
  foreach fn in array array['public.admin_assinantes()','public.admin_metricas()',
    'public.admin_altera_assinatura(uuid,text,text,timestamptz,timestamptz,bigint,boolean)'] loop
    def := pg_get_functiondef(fn::regprocedure);
    def := replace(def, 'if not public.sou_admin() then', 'if not public.admin_seguro() then');
    execute def;
  end loop;
end $$;
