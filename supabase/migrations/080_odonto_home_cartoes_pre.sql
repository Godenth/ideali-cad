-- 080 · Cartões da home: inclui também os pré-cadastros que estão na Rede (a maior parte dos 2.000 nomes).
-- Mostra o mesmo que a Rede já mostra deles: primeiro nome, profissão, cidade e UF. Nada de sobrenome, e-mail ou telefone.
-- Pode rodar mais de uma vez.
create or replace function public.odo_home_cartoes() returns jsonb
language sql volatile security definer set search_path = '' as $$
  with pes as (
    select nullif(initcap(split_part(trim(p.nome),' ',1)),'') as n,
           coalesce(nullif(trim(p.cargo),''), p.prof) as t,
           case when coalesce((p.vis->>'cidade')::boolean,true) then nullif(initcap(trim(p.cidade)),'') end as c,
           p.uf as uf
      from public.odo_perfis p
     where p.aberto
     order by random() limit 25),
  pre as (
    select nullif(initcap(split_part(btrim(coalesce(p.nome,'')),' ',1)),'') as n,
           p.profissao as t, nullif(initcap(btrim(coalesce(p.cidade,''))),'') as c, upper(btrim(p.uf)) as uf
      from public.odo_pre_cadastros p
     where p.na_rede and p.aceito_por is null and p.profissao is not null
       and char_length(split_part(btrim(coalesce(p.nome,'')),' ',1)) >= 2
     order by random() limit 30),
  emp as (
    select nullif(trim(e.nome),'') as n,
           case e.tipo when 'clinica' then 'Clínica' when 'lab' then 'Laboratório' when 'centro' then 'Centro radiológico'
                       when 'auto' then 'Autônomo' when 'dental' then 'Dental' when 'escola' then 'Escola' else 'Empresa' end as t,
           nullif(trim(e.cidade),'') as c, e.uf as uf
      from public.odo_empresas e
     where e.tipo <> 'auto'
     order by random() limit 15)
  select coalesce(jsonb_agg(jsonb_build_object('n',n,'t',t,'c',c,'uf',uf) order by random()),'[]'::jsonb)
    from (select * from pes union all select * from pre union all select * from emp) x
$$;
revoke all on function public.odo_home_cartoes() from public;
grant execute on function public.odo_home_cartoes() to anon, authenticated;
