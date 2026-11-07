-- =====================================================================
-- 056 · Ideali Odonto · Aba Laboratório: o dentista convida o laboratório pelo ID.
-- • Toda empresa ganha um número (ID). O Ideali Lab é o ID 01.
--   O número é dado pelo sistema e ninguém consegue trocar.
-- • Procurar um ID só mostra nome, cidade e estado, e só de laboratório.
-- • O convite fica "aguardando" até o laboratório aceitar ou recusar.
-- • Cada um só vê os próprios convites (quem convidou e o laboratório convidado).
-- Pode rodar de novo.
-- =====================================================================
create sequence if not exists public.odo_empresas_codigo_seq start 2;
drop trigger if exists odo_empresas_codigo on public.odo_empresas;
alter table public.odo_empresas add column if not exists codigo int;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'odo_empresas_codigo_key') then
    alter table public.odo_empresas add constraint odo_empresas_codigo_key unique (codigo);
  end if;
end $$;

-- Ideali Lab = 01 (o laboratório da conta administradora mais antiga)
update public.odo_empresas set codigo = 1
 where id = (select e.id from public.odo_empresas e join public.admins a on a.user_id = e.user_id
              where e.tipo = 'lab' order by e.criado_em limit 1)
   and not exists (select 1 from public.odo_empresas where codigo = 1);
-- as outras empresas ganham número na ordem em que foram criadas
do $$ declare r record; begin
  for r in select id from public.odo_empresas where codigo is null order by criado_em loop
    update public.odo_empresas set codigo = nextval('public.odo_empresas_codigo_seq') where id = r.id;
  end loop;
end $$;

-- o número é sempre do sistema: na criação vem da sequência, e depois nunca muda
create or replace function public.odo_empresa_codigo_fixo() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then new.codigo := nextval('public.odo_empresas_codigo_seq');
  else new.codigo := old.codigo; end if;
  return new;
end $$;
drop trigger if exists odo_empresas_codigo on public.odo_empresas;
create trigger odo_empresas_codigo before insert or update on public.odo_empresas
  for each row execute function public.odo_empresa_codigo_fixo();

-- convites dentista → laboratório
create table if not exists public.odo_lab_vinculos (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade, -- quem convidou
  lab_id        uuid not null references public.odo_empresas(id) on delete cascade,
  lab_nome      text check (char_length(lab_nome) <= 80),
  lab_local     text check (char_length(lab_local) <= 80),
  quem_nome     text check (char_length(quem_nome) <= 80),
  status        text not null default 'pendente' check (status in ('pendente','aceito','recusado')),
  criado_em     timestamptz not null default now(),
  respondido_em timestamptz,
  unique (user_id, lab_id)
);
alter table public.odo_lab_vinculos enable row level security;
revoke all on public.odo_lab_vinculos from anon;
drop policy if exists odo_lab_vinculos_ve on public.odo_lab_vinculos;
create policy odo_lab_vinculos_ve on public.odo_lab_vinculos for select to authenticated
  using (user_id = (select auth.uid())
         or exists (select 1 from public.odo_empresas e where e.id = lab_id and e.user_id = (select auth.uid())));
drop policy if exists odo_lab_vinculos_apaga on public.odo_lab_vinculos;
create policy odo_lab_vinculos_apaga on public.odo_lab_vinculos for delete to authenticated
  using (user_id = (select auth.uid()));
-- inserir e responder só pelas funções abaixo

-- procurar laboratório pelo ID (só nome, cidade e estado)
create or replace function public.odo_lab_busca(p_codigo int) returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then null else
    (select jsonb_build_object('codigo', e.codigo, 'nome', e.nome, 'cidade', e.cidade, 'uf', e.uf)
       from public.odo_empresas e where e.codigo = p_codigo and e.tipo = 'lab') end;
$$;

-- enviar convite
create or replace function public.odo_lab_convida(p_codigo int) returns uuid
language plpgsql security definer set search_path = '' as $$
declare eu uuid := auth.uid(); l public.odo_empresas; nm text; nid uuid; n int;
begin
  if eu is null then raise exception 'Entre na sua conta'; end if;
  select * into l from public.odo_empresas where codigo = p_codigo and tipo = 'lab';
  if l.id is null then raise exception 'Laboratório não encontrado'; end if;
  if l.user_id = eu then raise exception 'Esse é o seu próprio laboratório'; end if;
  select count(*) into n from public.odo_lab_vinculos where user_id = eu and criado_em > now() - interval '1 day';
  if n >= 30 then raise exception 'Muitos convites hoje. Tente amanhã.'; end if;
  select coalesce((select e.nome from public.odo_empresas e where e.user_id = eu),
                  (select p.nome from public.odo_perfis p where p.user_id = eu)) into nm;
  insert into public.odo_lab_vinculos (user_id, lab_id, lab_nome, lab_local, quem_nome)
  values (eu, l.id, l.nome, left(concat_ws(' / ', l.cidade, l.uf), 80), left(nm, 80))
  on conflict (user_id, lab_id) do update set status = case when public.odo_lab_vinculos.status = 'recusado' then 'pendente' else public.odo_lab_vinculos.status end,
                                              respondido_em = case when public.odo_lab_vinculos.status = 'recusado' then null else public.odo_lab_vinculos.respondido_em end
  returning id into nid;
  return nid;
end $$;

-- o laboratório aceita ou recusa
create or replace function public.odo_lab_responde(p_id uuid, p_ok boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  update public.odo_lab_vinculos v set status = case when p_ok then 'aceito' else 'recusado' end, respondido_em = now()
   where v.id = p_id and exists (select 1 from public.odo_empresas e where e.id = v.lab_id and e.user_id = auth.uid());
  return found;
end $$;

revoke all on function public.odo_lab_busca(int) from public, anon;
revoke all on function public.odo_lab_convida(int) from public, anon;
revoke all on function public.odo_lab_responde(uuid, boolean) from public, anon;
grant execute on function public.odo_lab_busca(int) to authenticated;
grant execute on function public.odo_lab_convida(int) to authenticated;
grant execute on function public.odo_lab_responde(uuid, boolean) to authenticated;
grant select, delete on public.odo_lab_vinculos to authenticated;

select 'ok: 056 aplicada' as resultado,
       (select nome from public.odo_empresas where codigo = 1) as id_01;
