-- 078 · Cartões da animação da página inicial (computador).
-- Pública (sem login), então entrega o MÍNIMO e respeita o que cada pessoa escolheu no perfil:
--   · pessoas: só quem está "aberto" na Rede; primeiro nome SÓ se a pessoa ligou "mostrar nome";
--     cidade SÓ se ligou "mostrar cidade"; cargo (ou profissão) e UF.
--   · clínicas, laboratórios e empresas: nome, tipo, cidade e UF (são negócios).
--   · pré-cadastros NUNCA aparecem. Nada de sobrenome, e-mail, telefone, foto ou id.
-- Até 60 cartões, em ordem aleatória. Pode rodar mais de uma vez.
create or replace function public.odo_home_cartoes() returns jsonb
language sql volatile security definer set search_path = '' as $$
  with pes as (
    select case when coalesce((p.vis->>'nome')::boolean,false)
                then nullif(split_part(trim(p.nome),' ',1),'') end as n,
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
