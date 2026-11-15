-- 079 · Cartões da home: mostra o PRIMEIRO nome de quem está aberto na Rede (decisão do dono do sistema).
-- Continua sem sobrenome, e-mail, telefone, foto ou id; quem não está aberto na Rede e pré-cadastros não aparecem.
-- Cidade continua respeitando "mostrar cidade". Pode rodar mais de uma vez.
create or replace function public.odo_home_cartoes() returns jsonb
language sql volatile security definer set search_path = '' as $$
  with pes as (
    select nullif(initcap(split_part(trim(p.nome),' ',1)),'') as n,
           coalesce(nullif(trim(p.cargo),''), p.prof) as t,
           case when coalesce((p.vis->>'cidade')::boolean,true) then nullif(trim(p.cidade),'') end as c,
           p.uf as uf
      from public.odo_perfis p
     where p.aberto
     order by random() limit 40),
  emp as (
    select nullif(trim(e.nome),'') as n,
           case e.tipo when 'clinica' then 'Clínica' when 'lab' then 'Laboratório' when 'centro' then 'Centro radiológico'
                       when 'auto' then 'Autônomo' when 'dental' then 'Dental' when 'escola' then 'Escola' else 'Empresa' end as t,
           nullif(trim(e.cidade),'') as c, e.uf as uf
      from public.odo_empresas e
     where e.tipo <> 'auto'
     order by random() limit 20)
  select coalesce(jsonb_agg(jsonb_build_object('n',n,'t',t,'c',c,'uf',uf) order by random()),'[]'::jsonb)
    from (select * from pes union all select * from emp) x
$$;
revoke all on function public.odo_home_cartoes() from public;
grant execute on function public.odo_home_cartoes() to anon, authenticated;
