-- 077 · Números públicos da página inicial: total de cadastros e os estados onde já há gente.
-- Entrega SÓ dois números agregados e a lista de siglas de estados. Nenhum nome, e-mail, telefone ou cidade.
-- Cadastro = conta criada no Ideali (perfil) + pré-cadastro ainda não convertido em conta (sem repetir a mesma pessoa).
-- Pode rodar mais de uma vez.
create or replace function public.odo_mapa_publico() returns jsonb
language sql stable security definer set search_path = '' as $$
  with contas as (select count(*)::int n from public.odo_perfis),
  pre as (select count(distinct coalesce(nullif(lower(trim(email)),''), nullif(regexp_replace(coalesce(whatsapp,''),'\D','','g'),''), id::text))::int n
            from public.odo_pre_cadastros where aceito_por is null),
  ufs as (select distinct upper(trim(uf)) uf from (
            select uf from public.odo_perfis union all
            select uf from public.odo_empresas union all
            select uf from public.odo_pre_cadastros) x
          where upper(trim(coalesce(uf,''))) in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'))
  select jsonb_build_object('total',(select n from contas)+(select n from pre),
                            'ufs',coalesce((select jsonb_agg(uf order by uf) from ufs),'[]'::jsonb),
                            'em',now())
$$;
revoke all on function public.odo_mapa_publico() from public;
grant execute on function public.odo_mapa_publico() to anon, authenticated;
