-- =====================================================================
-- 052 · Ideali Odonto · Empresas pré-cadastradas (laboratórios, clínicas e lojas) na Rede.
-- Na Rede aparece: nome da empresa + cidade/estado + especialidades. Telefone, e-mail e
-- nome do dono continuam escondidos. Quando o dono aceita o convite, a empresa dele
-- já nasce na conta (função empresa liberada). Pode rodar mais de uma vez.
-- =====================================================================
alter table public.odo_pre_cadastros add column if not exists empresa_nome text check (char_length(empresa_nome) <= 120);
alter table public.odo_pre_cadastros add column if not exists empresa_tipo text check (empresa_tipo in ('lab','clinica','dental'));

-- Profissionais pré-cadastrados: quem é só empresa (sem profissão) não aparece como pessoa
create or replace function public.odo_rede_pre(f_uf text default null)
returns table (id text, primeiro_nome text, letras_sobrenome int, profissao text, cidade text, uf text, especialidades text, modalidade text, funcao text)
language sql stable security definer set search_path = '' as $$
  select 'C'||lpad((abs(hashtext(p.id::text)) % 100000)::text,5,'0'),
         nullif(split_part(btrim(coalesce(p.nome,'')),' ',1),''),
         greatest(0, char_length(btrim(coalesce(p.nome,''))) - char_length(split_part(btrim(coalesce(p.nome,'')),' ',1)) - 1),
         p.profissao, p.cidade, p.uf, p.especialidades, p.modalidade, p.funcao
  from public.odo_pre_cadastros p
  where p.na_rede and p.aceito_por is null and auth.uid() is not null
    and not (p.empresa_tipo is not null and p.profissao is null)
    and (f_uf is null or p.uf = f_uf)
  order by p.criado_em desc
  limit 3000;
$$;
revoke all on function public.odo_rede_pre(text) from public, anon;
grant execute on function public.odo_rede_pre(text) to authenticated;

-- Empresas da Rede: as que já têm conta (odo_empresas) + as pré-cadastradas ainda não confirmadas
drop function if exists public.odo_rede_empresas();
create function public.odo_rede_empresas()
returns table (id text, nome text, tipo text, uf text, cidade text, tags text, pre boolean)
language sql stable security definer set search_path = '' as $$
  select 'E'||lpad((abs(hashtext(e.id::text)) % 100000)::text,5,'0'), e.nome,
         case when e.tipo = 'centro' then 'lab' else e.tipo end, e.uf, e.cidade, null::text, false
  from public.odo_empresas e
  where auth.uid() is not null and e.user_id <> auth.uid() and e.tipo in ('clinica','lab','centro','dental')
  union all
  select 'F'||lpad((abs(hashtext(p.id::text)) % 100000)::text,5,'0'), p.empresa_nome,
         p.empresa_tipo, p.uf, p.cidade, p.especialidades, true
  from public.odo_pre_cadastros p
  where auth.uid() is not null and p.na_rede and p.aceito_por is null
    and p.empresa_tipo is not null and nullif(btrim(p.empresa_nome),'') is not null
  limit 3000;
$$;
revoke all on function public.odo_rede_empresas() from public, anon;
grant execute on function public.odo_rede_empresas() to authenticated;

-- Aceitar convite: se for empresa, a empresa já nasce na conta da pessoa
create or replace function public.odo_pre_aceita(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.odo_pre_cadastros; eu uuid := auth.uid(); nm text;
begin
  if eu is null then raise exception 'Entre na sua conta'; end if;
  select * into r from public.odo_pre_cadastros where token = p_token;
  if r.id is null then raise exception 'Convite inválido'; end if;
  if r.aceito_por is not null and r.aceito_por <> eu then raise exception 'Este convite já foi usado'; end if;
  update public.odo_pre_cadastros set aceito_por = eu, aceito_em = coalesce(aceito_em, now()), aberto_em = coalesce(aberto_em, now()) where id = r.id;
  nm := left(btrim(coalesce(r.empresa_nome,'')), 80);
  if r.empresa_tipo is not null and char_length(nm) >= 2 then
    insert into public.odo_empresas (user_id, tipo, nome, uf, cidade, papel)
    values (eu, r.empresa_tipo, nm,
            case when r.uf ~ '^[A-Z]{2}$' then r.uf else null end,
            left(r.cidade, 60), 'faz')
    on conflict (user_id) do nothing;
  end if;
  return jsonb_build_object('nome', r.nome, 'whatsapp', r.whatsapp, 'profissao', r.profissao, 'cidade', r.cidade, 'uf', r.uf,
                            'empresa_nome', r.empresa_nome, 'empresa_tipo', r.empresa_tipo);
end $$;
revoke all on function public.odo_pre_aceita(text) from public, anon;
grant execute on function public.odo_pre_aceita(text) to authenticated;

select 'ok: 052 aplicada' as resultado;
