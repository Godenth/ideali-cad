-- 082 · Home: a animação conta cada cadastro que passa até chegar no total.
-- odo_home_lista(): um cartão para CADA cadastro que entra no total (contas + pré-cadastros sem repetir + empresas).
--   · primeiro nome só de quem está aberto na Rede (conta) ou na Rede (pré-cadastro); os outros passam sem nome (cargo + UF).
--   · cidade de conta respeita "mostrar cidade". Nada de sobrenome, e-mail, telefone, foto ou id.
-- odo_mapa_publico(): o total passa a somar também as empresas (o texto da home já diz "profissionais e empresas").
-- Pode rodar mais de uma vez.
create or replace function public.odo_home_lista() returns jsonb
language sql volatile security definer set search_path = '' as $$
  with contas as (
    select case when p.aberto then nullif(initcap(split_part(trim(p.nome),' ',1)),'') end as n,
           coalesce(nullif(trim(p.cargo),''), p.prof) as t,
           case when p.aberto and coalesce((p.vis->>'cidade')::boolean,true) then nullif(initcap(trim(p.cidade)),'') end as c,
           upper(p.uf) as uf
      from public.odo_perfis p),
  pre as (
    select distinct on (coalesce(nullif(lower(trim(email)),''), nullif(regexp_replace(coalesce(whatsapp,''),'\D','','g'),''), id::text))
           case when x.na_rede and char_length(split_part(btrim(coalesce(x.nome,'')),' ',1)) >= 2
                then initcap(split_part(btrim(x.nome),' ',1)) end as n,
           coalesce(x.profissao, case when x.empresa_tipo is not null then 'Empresa' else 'Profissional' end) as t,
           case when x.na_rede then nullif(initcap(btrim(coalesce(x.cidade,''))),'') end as c,
           upper(btrim(x.uf)) as uf
      from public.odo_pre_cadastros x
     where x.aceito_por is null
     order by coalesce(nullif(lower(trim(email)),''), nullif(regexp_replace(coalesce(whatsapp,''),'\D','','g'),''), id::text), x.criado_em),
  emp as (
    select nullif(trim(e.nome),'') as n,
           case e.tipo when 'clinica' then 'Clínica' when 'lab' then 'Laboratório' when 'centro' then 'Centro radiológico'
                       when 'auto' then 'Autônomo' when 'dental' then 'Dental' when 'escola' then 'Escola' else 'Empresa' end as t,
           nullif(trim(e.cidade),'') as c, upper(e.uf) as uf
      from public.odo_empresas e)
  select coalesce(jsonb_agg(jsonb_build_object('n',n,'t',t,'c',c,'uf',uf) order by random()),'[]'::jsonb)
    from (select n,t,c,uf from contas union all select n,t,c,uf from pre union all select * from emp) z
$$;
revoke all on function public.odo_home_lista() from public;
grant execute on function public.odo_home_lista() to anon, authenticated;

create or replace function public.odo_mapa_publico() returns jsonb
language sql stable security definer set search_path = '' as $$
  with contas as (select count(*)::int n from public.odo_perfis),
  pre as (select count(distinct coalesce(nullif(lower(trim(email)),''), nullif(regexp_replace(coalesce(whatsapp,''),'\D','','g'),''), id::text))::int n
            from public.odo_pre_cadastros where aceito_por is null),
  emp as (select count(*)::int n from public.odo_empresas),
  ufs as (select distinct upper(trim(uf)) uf from (
            select uf from public.odo_perfis union all
            select uf from public.odo_empresas union all
            select uf from public.odo_pre_cadastros) x
          where upper(trim(coalesce(uf,''))) in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'))
  select jsonb_build_object('total',(select n from contas)+(select n from pre)+(select n from emp),
                            'ufs',coalesce((select jsonb_agg(uf order by uf) from ufs),'[]'::jsonb),
                            'em',now())
$$;
revoke all on function public.odo_mapa_publico() from public;
grant execute on function public.odo_mapa_publico() to anon, authenticated;
