-- =====================================================================
-- 102 · Ideali Odonto · O laboratório atribui um cliente (empresa) a uma conta Ideali.
-- • Estender odo_lab_vinculos basta: ela já guarda laboratório, cliente, convidado e status;
--   faltavam só origem, e-mail e rótulo para o novo fluxo conviver com o de 056.
-- • O convidado escolhe apenas o rótulo (dono/funcionário); o dono da empresa nunca muda.
-- • Sem conta, o convite fica pendente pelo e-mail até o cadastro. A reautenticação é nativa
--   do Supabase Auth e fica na frente, não nesta migration.
-- • Senha e código ficam só na tela (reautenticação nativa do Supabase Auth); risco aceito pelo dono.
-- • Nenhuma leitura de pedidos/financeiro aqui (tarefa 5) e nenhuma permissão direta nova.
-- Pode rodar de novo.
-- Atenção: a 102 já recria odo_lab_convida com o WHERE correto; re-executar a 056 ou a 068 depois dela volta a versão sem WHERE e deve ser evitado.
-- =====================================================================

begin;

-- convites por e-mail sem conta: user_id pode ficar nulo, mantendo a FK para auth.users
alter table public.odo_lab_vinculos alter column user_id drop not null;
alter table public.odo_lab_vinculos add column if not exists email_convite text check (char_length(email_convite) <= 120);
alter table public.odo_lab_vinculos add column if not exists papel text check (papel in ('dono','funcionario'));
alter table public.odo_lab_vinculos add column if not exists origem text not null default 'clinica_para_lab'
  check (origem in ('clinica_para_lab','lab_para_conta'));
alter table public.odo_lab_vinculos add column if not exists cancelado_em timestamptz;
alter table public.odo_lab_vinculos add column if not exists removido_em timestamptz;

-- regra antiga vale so no fluxo antigo; fluxo novo usa o indice por lab+cliente+e-mail
do $$
declare c record;
begin
  for c in
    select conname, pg_get_constraintdef(oid) as def
      from pg_constraint
     where conrelid = 'public.odo_lab_vinculos'::regclass
       and contype = 'u'
       and (
            conname in ('odo_lab_vinculos_user_id_lab_id_key', 'odo_lab_vinculos_user_id_lab_id_origem_key')
         or pg_get_constraintdef(oid) ~* '^unique \(user_id, lab_id(, origem)?\)$'
         or pg_get_constraintdef(oid) ~* '^unique \(lab_id, user_id(, origem)?\)$'
       )
       and conname <> 'odo_lab_vinculos_clinica_lab_unico'
  loop
    execute format('alter table public.odo_lab_vinculos drop constraint %I', c.conname);
  end loop;
end $$;

create unique index if not exists odo_lab_vinculos_clinica_lab_unico
  on public.odo_lab_vinculos (user_id, lab_id) where origem = 'clinica_para_lab';

-- o status antigo (pendente/aceito/recusado) ganha cancelado e removido
do $$
declare c record;
begin
  for c in select conname, pg_get_constraintdef(oid) as def from pg_constraint
             where conrelid = 'public.odo_lab_vinculos'::regclass and contype = 'c'
               and pg_get_constraintdef(oid) ilike '%status%'
  loop
    if c.def not ilike '%cancelado%' then
      execute format('alter table public.odo_lab_vinculos drop constraint %I', c.conname);
    end if;
  end loop;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.odo_lab_vinculos'::regclass
                    and conname = 'odo_lab_vinculos_status_check') then
    alter table public.odo_lab_vinculos add constraint odo_lab_vinculos_status_check
      check (status in ('pendente','aceito','recusado','cancelado','removido'));
  end if;
end $$;

-- um mesmo e-mail não pode receber dois convites do mesmo cliente no mesmo laboratório
create unique index if not exists odo_lab_vinculos_atribui_unico
  on public.odo_lab_vinculos (lab_id, cliente_id, lower(email_convite))
  where origem = 'lab_para_conta';

-- apagar só vale para o fluxo antigo; no fluxo novo o usuário é o convidado
drop policy if exists odo_lab_vinculos_apaga on public.odo_lab_vinculos;
create policy odo_lab_vinculos_apaga on public.odo_lab_vinculos for delete to authenticated
  using (origem = 'clinica_para_lab' and user_id = (select public.odo_conta()));

-- 1) O dono do laboratório atribui um cliente a uma conta pelo e-mail
create or replace function public.odo_lab_atribui_conta(p_cliente uuid, p_email text, p_papel text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare eu uuid := auth.uid(); l public.odo_empresas; v_email text; v_user uuid; nid uuid;
begin
  if eu is null then raise exception 'Entre na sua conta'; end if;
  select * into l from public.odo_empresas where user_id = public.odo_conta() and tipo = 'lab';
  if l.id is null then raise exception 'Laboratório não encontrado'; end if;
  if p_cliente is null or not exists (select 1 from public.odo_clientes c
       where c.id = p_cliente and c.user_id = public.odo_conta()) then
    raise exception 'cliente_nao_e_seu';
  end if;
  if p_papel is null or p_papel not in ('dono','funcionario') then raise exception 'papel_invalido'; end if;
  if p_email is null or char_length(trim(p_email)) = 0 or char_length(trim(p_email)) > 120
     or trim(p_email) !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'email_invalido';
  end if;
  v_email := lower(trim(p_email));
  if exists (select 1 from public.odo_lab_vinculos v where v.origem='lab_para_conta' and v.lab_id=l.id and v.cliente_id=p_cliente and lower(v.email_convite)=v_email and v.status='aceito') then raise exception 'ja_atribuido'; end if;
  select u.id into v_user from auth.users u
   where lower(u.email) = v_email and u.email_confirmed_at is not null limit 1;
  insert into public.odo_lab_vinculos
    (user_id, lab_id, lab_nome, cliente_id, email_convite, papel, origem, status)
  values
    (v_user, l.id, left(l.nome, 80), p_cliente, v_email, p_papel, 'lab_para_conta', 'pendente')
  on conflict (lab_id, cliente_id, lower(email_convite)) where origem = 'lab_para_conta'
  do update set user_id = excluded.user_id, lab_nome = excluded.lab_nome, papel = excluded.papel,
                status = 'pendente', respondido_em = null, cancelado_em = null, removido_em = null
  returning id into nid;
  return nid;
end $$;

-- 2) Depois do login/cadastro, os convites do e-mail confirmado passam a ser da conta
create or replace function public.odo_conta_reivindica_convites() returns int
language plpgsql security definer set search_path = '' as $$
declare eu uuid := auth.uid(); v_email text; n int;
begin
  if eu is null then raise exception 'Entre na sua conta'; end if;
  select lower(u.email) into v_email from auth.users u
   where u.id = eu and u.email_confirmed_at is not null;
  if v_email is null then return 0; end if;
  update public.odo_lab_vinculos v set user_id = eu
   where v.origem = 'lab_para_conta' and v.user_id is null and v.status = 'pendente'
     and lower(v.email_convite) = v_email;
  get diagnostics n = row_count;
  return n;
end $$;

-- 3) O convidado aceita ou recusa (só rótulo, sem virar dono de nada)
create or replace function public.odo_atribui_responde(p_id uuid, p_ok boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Entre na sua conta'; end if;
  update public.odo_lab_vinculos v
     set status = case when p_ok then 'aceito' else 'recusado' end, respondido_em = now()
   where v.id = p_id and v.origem = 'lab_para_conta' and v.user_id = auth.uid()
     and v.status = 'pendente'
     and exists (select 1 from auth.users u where u.id = auth.uid() and u.email_confirmed_at is not null);
  return found;
end $$;

-- 4) O laboratório cancela um convite ainda pendente
create or replace function public.odo_atribui_cancela(p_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Entre na sua conta'; end if;
  update public.odo_lab_vinculos v set status = 'cancelado', cancelado_em = now()
   where v.id = p_id and v.origem = 'lab_para_conta' and v.status = 'pendente'
     and exists (select 1 from public.odo_empresas e where e.id = v.lab_id and e.user_id = public.odo_conta());
  return found;
end $$;

-- 5) O laboratório remove o acesso aceito (sem apagar o histórico)
create or replace function public.odo_atribui_remove(p_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Entre na sua conta'; end if;
  update public.odo_lab_vinculos v set status = 'removido', removido_em = now()
   where v.id = p_id and v.origem = 'lab_para_conta' and v.status = 'aceito'
     and exists (select 1 from public.odo_empresas e where e.id = v.lab_id and e.user_id = public.odo_conta());
  return found;
end $$;

-- 6) Os convites da conta logada
create or replace function public.odo_atribui_minhas() returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then '[]'::jsonb else
    coalesce((select jsonb_agg(x order by x->>'criado_em' desc) from (
      select jsonb_build_object(
        'id', v.id, 'cliente_id', v.cliente_id, 'empresa', c.nome,
        'lab_id', v.lab_id, 'lab', e.nome, 'papel', v.papel, 'status', v.status,
        'criado_em', v.criado_em, 'respondido_em', v.respondido_em,
        'cancelado_em', v.cancelado_em, 'removido_em', v.removido_em) as x
      from public.odo_lab_vinculos v
      join public.odo_clientes c on c.id = v.cliente_id
      join public.odo_empresas e on e.id = v.lab_id
      where v.user_id = auth.uid() and v.origem = 'lab_para_conta'
      order by v.criado_em desc limit 300) q), '[]'::jsonb) end;
$$;

-- 7) Os convites que o laboratório fez para um cliente
create or replace function public.odo_atribui_do_lab(p_cliente uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then '[]'::jsonb else
    coalesce((select jsonb_agg(x order by x->>'criado_em' desc) from (
      select jsonb_build_object(
        'id', v.id, 'email_convite', v.email_convite, 'papel', v.papel, 'status', v.status,
        'criado_em', v.criado_em, 'respondido_em', v.respondido_em,
        'cancelado_em', v.cancelado_em, 'removido_em', v.removido_em) as x
      from public.odo_lab_vinculos v
      where v.cliente_id = p_cliente and v.origem = 'lab_para_conta'
        and exists (select 1 from public.odo_empresas e where e.id = v.lab_id and e.user_id = public.odo_conta())
      order by v.criado_em desc limit 300) q), '[]'::jsonb) end;
$$;

-- o laboratório não pode responder o convite que ele mesmo criou (fluxo 056/068)
CREATE OR REPLACE FUNCTION public.odo_lab_responde(p_id uuid, p_ok boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.odo_lab_vinculos v set status = case when p_ok then 'aceito' else 'recusado' end, respondido_em = now()
   where v.id = p_id and v.origem = 'clinica_para_lab' and exists (select 1 from public.odo_empresas e where e.id = v.lab_id and e.user_id = public.odo_conta());
  return found;
end $function$
;

-- não trocar o cliente de uma atribuição nova (lab → conta)
CREATE OR REPLACE FUNCTION public.odo_lab_vincula_cliente(p_vinculo uuid, p_cliente uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not exists (select 1 from public.odo_lab_vinculos v join public.odo_empresas e on e.id = v.lab_id
                  where v.id = p_vinculo and v.origem = 'clinica_para_lab' and e.user_id = public.odo_conta()) then
    raise exception 'vinculo_nao_e_seu';
  end if;
  if p_cliente is not null and not exists (select 1 from public.odo_clientes c where c.id = p_cliente and c.user_id = public.odo_conta()) then
    raise exception 'cliente_nao_e_seu';
  end if;
  update public.odo_lab_vinculos set cliente_id = p_cliente where id = p_vinculo;
end $function$
;

CREATE OR REPLACE FUNCTION public.odo_lab_convida(p_codigo integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare eu uuid := public.odo_conta(); l public.odo_empresas; nm text; nid uuid; n int;
begin
  if not public.odo_nao_provisoria() then raise exception 'Confirme o seu e-mail para usar isto.' using errcode = '42501'; end if;
  if eu is null then raise exception 'Entre na sua conta'; end if;
  select * into l from public.odo_empresas where codigo = p_codigo and tipo = 'lab';
  if l.id is null then raise exception 'Laboratório não encontrado'; end if;
  if l.user_id = eu then raise exception 'Esse é o seu próprio laboratório'; end if;
  select count(*) into n from public.odo_lab_vinculos where user_id = eu and criado_em > now() - interval '1 day';
  if n >= 30 then raise exception 'Muitos convites hoje. Tente amanhã.'; end if;
  select coalesce((select e.nome from public.odo_empresas e where e.user_id = eu),
                  (select p.nome from public.odo_perfis p where p.user_id = eu)) into nm;
  insert into public.odo_lab_vinculos (user_id, lab_id, lab_nome, lab_local, quem_nome, origem)
  values (eu, l.id, l.nome, left(concat_ws(' / ', l.cidade, l.uf), 80), left(nm, 80), 'clinica_para_lab')
  on conflict (user_id, lab_id) where origem = 'clinica_para_lab' do update set status = case when public.odo_lab_vinculos.status = 'recusado' then 'pendente' else public.odo_lab_vinculos.status end,
                                              respondido_em = case when public.odo_lab_vinculos.status = 'recusado' then null else public.odo_lab_vinculos.respondido_em end
  returning id into nid;
  return nid;
end $function$
;

revoke all on function public.odo_lab_atribui_conta(uuid, text, text) from public, anon;
revoke all on function public.odo_conta_reivindica_convites() from public, anon;
revoke all on function public.odo_atribui_responde(uuid, boolean) from public, anon;
revoke all on function public.odo_atribui_cancela(uuid) from public, anon;
revoke all on function public.odo_atribui_remove(uuid) from public, anon;
revoke all on function public.odo_atribui_minhas() from public, anon;
revoke all on function public.odo_atribui_do_lab(uuid) from public, anon;
revoke all on function public.odo_lab_responde(uuid, boolean) from public, anon;
revoke all on function public.odo_lab_vincula_cliente(uuid, uuid) from public, anon;
grant execute on function public.odo_lab_atribui_conta(uuid, text, text) to authenticated;
grant execute on function public.odo_conta_reivindica_convites() to authenticated;
grant execute on function public.odo_atribui_responde(uuid, boolean) to authenticated;
grant execute on function public.odo_atribui_cancela(uuid) to authenticated;
grant execute on function public.odo_atribui_remove(uuid) to authenticated;
grant execute on function public.odo_atribui_minhas() to authenticated;
grant execute on function public.odo_atribui_do_lab(uuid) to authenticated;
grant execute on function public.odo_lab_responde(uuid, boolean) to authenticated;
grant execute on function public.odo_lab_vincula_cliente(uuid, uuid) to authenticated;
revoke insert, update on public.odo_lab_vinculos from authenticated;
grant select, delete on public.odo_lab_vinculos to authenticated;

select 'ok: 102 aplicada' as resultado;

commit;
