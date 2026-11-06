-- =====================================================================
-- 039 · Ideali Odonto · Etapa 1: perfil profissional (currículo) com cadeados
-- Mesmo login do Ideali CAD (Supabase Auth). Cada pessoa vê e edita só o próprio perfil (RLS).
-- Na Rede, ninguém lê a tabela direto: a função odo_rede_profs() entrega SÓ os campos com cadeado aberto.
-- Fotos ficam no bucket PRIVADO "odonto-fotos", na pasta do próprio usuário, com acesso por URL assinada.
-- =====================================================================

create table if not exists public.odo_perfis (
  user_id     uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  nome        text not null check (char_length(nome) between 3 and 80),
  whats       text check (whats is null or whats ~ '^[0-9]{10,11}$'),
  prof        text not null check (prof in ('Dentista','Protético','ASB / TSB','Corporativo','Indústria e comércio','Estudante')),
  cargo       text check (char_length(cargo) <= 80),
  idade       smallint not null check (idade between 14 and 90),
  sexo        text not null check (sexo in ('Feminino','Masculino','Prefiro não informar')),
  uf          text not null check (uf ~ '^[A-Z]{2}$'),
  cidade      text not null check (char_length(cidade) between 2 and 60),
  formacao    text check (char_length(formacao) <= 120),
  situacao    text check (situacao in ('Cursando','Concluído','Trancado') or situacao is null),
  instituicao text check (char_length(instituicao) <= 120),
  resumo      text check (char_length(resumo) <= 600),
  softs       jsonb not null default '[]'::jsonb,   -- [["Exocad","a"], ...]  b=básico m=médio a=avançado
  pos         jsonb not null default '[]'::jsonb,   -- ["Prótese sobre implante", ...]
  cursos      jsonb not null default '[]'::jsonb,
  exp         jsonb not null default '[]'::jsonb,   -- [{"cargo":"Cadista","empresa":"Lab X","anos":3}, ...]
  vis         jsonb not null default '{"foto":false,"nome":false,"idade":false,"sexo":false,"cidade":true,"empresas":true,"cursos":true}'::jsonb,
  foto        text check (foto is null or char_length(foto) <= 200),  -- caminho no bucket odonto-fotos
  aberto      boolean not null default true,        -- aparece na Rede
  criado_em   timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint odo_perfis_json_tam check (pg_column_size(softs)+pg_column_size(pos)+pg_column_size(cursos)+pg_column_size(exp) < 40000)
);

alter table public.odo_perfis enable row level security;
drop policy if exists odo_perfis_dono on public.odo_perfis;
create policy odo_perfis_dono on public.odo_perfis for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.odo_perfis from anon;

create or replace function public.odo_perfis_toca() returns trigger language plpgsql as $$
begin new.atualizado_em := now(); new.user_id := old.user_id; return new; end $$;
drop trigger if exists odo_perfis_toca on public.odo_perfis;
create trigger odo_perfis_toca before update on public.odo_perfis for each row execute function public.odo_perfis_toca();

-- Rede: lista de profissionais respeitando os cadeados. Só usuários logados.
create or replace function public.odo_rede_profs(f_uf text default null, f_cidade text default null)
returns table (id text, nome text, prof text, cargo text, idade smallint, sexo text, uf text, cidade text,
               formacao text, resumo text, softs jsonb, pos jsonb, cursos jsonb, exp jsonb, tem_foto boolean)
language sql stable security definer set search_path = public as $$
  select
    'P'||lpad((abs(hashtext(p.user_id::text)) % 10000)::text,4,'0'),
    case when (p.vis->>'nome')::boolean then p.nome else null end,
    p.prof, p.cargo,
    case when (p.vis->>'idade')::boolean then p.idade else null end,
    case when (p.vis->>'sexo')::boolean then p.sexo else null end,
    p.uf,
    case when (p.vis->>'cidade')::boolean then p.cidade else null end,
    p.formacao, p.resumo, p.softs, p.pos,
    case when (p.vis->>'cursos')::boolean then p.cursos else '[]'::jsonb end,
    case when (p.vis->>'empresas')::boolean then p.exp
         else coalesce((select jsonb_agg(e - 'empresa') from jsonb_array_elements(p.exp) e),'[]'::jsonb) end,
    ((p.vis->>'foto')::boolean and p.foto is not null)
  from public.odo_perfis p
  where p.aberto and auth.uid() is not null
    and (f_uf is null or p.uf = f_uf)
    and (f_cidade is null or ((p.vis->>'cidade')::boolean and lower(p.cidade) = lower(f_cidade)))
  order by p.atualizado_em desc
  limit 200;
$$;
revoke all on function public.odo_rede_profs(text,text) from public, anon;
grant execute on function public.odo_rede_profs(text,text) to authenticated;

-- Fotos: bucket privado, cada um só mexe na própria pasta (odonto-fotos/<user_id>/...).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('odonto-fotos','odonto-fotos', false, 524288, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false;

drop policy if exists odonto_fotos_dono on storage.objects;
create policy odonto_fotos_dono on storage.objects for all to authenticated
  using (bucket_id = 'odonto-fotos' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'odonto-fotos' and (storage.foldername(name))[1] = (select auth.uid())::text);
