-- 089 · Perfil da empresa na Rede (laboratórios, clínicas, lojas).
-- · coluna perfil (jsonb) em odo_empresas: sobre, especialidades, softwares, máquinas, prazos, entrega, horário,
--   WhatsApp/Instagram com cadeado (só aparecem se a empresa abrir), logo, capa e fotos por categoria (até 5 cada).
-- · bucket PRIVADO odonto-empresa: a empresa grava na própria pasta (<conta>/...); quem tem conta confirmada só LÊ (URL assinada).
-- · odo_empresa_perfil(id): devolve só o que é público para quem tem conta. Endereço = só cidade/UF.
-- Pode rodar mais de uma vez.
alter table public.odo_empresas add column if not exists perfil jsonb not null default '{}'::jsonb;
alter table public.odo_empresas drop constraint if exists odo_empresas_perfil_tam;
alter table public.odo_empresas add constraint odo_empresas_perfil_tam check (pg_column_size(perfil) < 60000);

create or replace function public.odo_nao_provisoria() returns boolean
language sql stable set search_path = '' as $$ select not coalesce((auth.jwt()->>'is_anonymous')::boolean, false) $$;
grant execute on function public.odo_nao_provisoria() to anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('odonto-empresa', 'odonto-empresa', false, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists odonto_empresa_ler on storage.objects;
create policy odonto_empresa_ler on storage.objects for select to authenticated
  using (bucket_id = 'odonto-empresa' and public.odo_nao_provisoria());
drop policy if exists odonto_empresa_gravar on storage.objects;
create policy odonto_empresa_gravar on storage.objects for insert to authenticated
  with check (bucket_id = 'odonto-empresa' and (storage.foldername(name))[1] = (select public.odo_conta())::text);
drop policy if exists odonto_empresa_trocar on storage.objects;
create policy odonto_empresa_trocar on storage.objects for update to authenticated
  using (bucket_id = 'odonto-empresa' and (storage.foldername(name))[1] = (select public.odo_conta())::text)
  with check (bucket_id = 'odonto-empresa' and (storage.foldername(name))[1] = (select public.odo_conta())::text);
drop policy if exists odonto_empresa_apagar on storage.objects;
create policy odonto_empresa_apagar on storage.objects for delete to authenticated
  using (bucket_id = 'odonto-empresa' and (storage.foldername(name))[1] = (select public.odo_conta())::text);

-- id público = o mesmo da lista da Rede ('E' + 5 dígitos); 'eu' = a minha própria empresa (prévia)
create or replace function public.odo_empresa_perfil(p_id text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null or not public.odo_nao_provisoria() then null else (
    select jsonb_build_object(
      'id', 'E'||lpad((abs(hashtext(e.id::text)) % 100000)::text,5,'0'),
      'nome', e.nome, 'tipo', e.tipo, 'cidade', e.cidade, 'uf', e.uf, 'eu', e.user_id = public.odo_conta(),
      'sobre', e.perfil->'sobre', 'esp', e.perfil->'esp', 'softs', e.perfil->'softs', 'maqs', e.perfil->'maqs',
      'prazos', e.perfil->'prazos', 'entrega', e.perfil->'entrega', 'horario', e.perfil->'horario',
      'logo', e.perfil->'logo', 'capa', e.perfil->'capa', 'fotos', e.perfil->'fotos',
      'whats', case when coalesce((e.perfil->>'whats_ab')::boolean,false) then e.perfil->'whats' end,
      'insta', case when coalesce((e.perfil->>'insta_ab')::boolean,false) then e.perfil->'insta' end,
      'tem_whats', coalesce(e.perfil->>'whats','') <> '', 'tem_insta', coalesce(e.perfil->>'insta','') <> '',
      'vagas', (select coalesce(jsonb_agg(jsonb_build_object('cargo',v->>'cargo','area',v->>'area','det',v->>'det','quando',v->>'quando')),'[]'::jsonb)
                  from jsonb_array_elements(case when jsonb_typeof(e.dados->'vagas')='array' then e.dados->'vagas' else '[]'::jsonb end) v))
    from public.odo_empresas e
    where (p_id = 'eu' and e.user_id = public.odo_conta())
       or (p_id <> 'eu' and 'E'||lpad((abs(hashtext(e.id::text)) % 100000)::text,5,'0') = p_id)
    limit 1) end
$$;
revoke all on function public.odo_empresa_perfil(text) from public;
grant execute on function public.odo_empresa_perfil(text) to authenticated;

-- a lista da Rede passa a mostrar as especialidades que a empresa marcou
create or replace function public.odo_rede_empresas()
 returns table(id text, nome text, tipo text, uf text, cidade text, tags text, pre boolean)
 language sql stable security definer set search_path to '' as $$
  select * from (
  select 'E'||lpad((abs(hashtext(e.id::text)) % 100000)::text,5,'0'), e.nome,
         case when e.tipo = 'centro' then 'lab' else e.tipo end, e.uf, e.cidade,
         nullif((select string_agg(x, ' · ') from (select jsonb_array_elements_text(case when jsonb_typeof(e.perfil->'esp')='array' then e.perfil->'esp' else '[]'::jsonb end) x limit 4) q),''),
         false
  from public.odo_empresas e
  where auth.uid() is not null and e.user_id <> auth.uid() and e.tipo in ('clinica','lab','centro','dental')
  union all
  select 'F'||lpad((abs(hashtext(p.id::text)) % 100000)::text,5,'0'), p.empresa_nome,
         p.empresa_tipo, p.uf, p.cidade, p.especialidades, true
  from public.odo_pre_cadastros p
  where auth.uid() is not null and p.na_rede and p.aceito_por is null
    and p.empresa_tipo is not null and nullif(btrim(p.empresa_nome),'') is not null
  limit 3000
  ) _g where public.odo_nao_provisoria();
$$;
