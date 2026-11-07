-- =====================================================================
-- 051 · Ideali Odonto · Especialidades, modalidade e FUNÇÃO PRINCIPAL do protético.
-- Função principal: 'nao' = de bancada (analógico), 'so' = digital (CAD/CAM), 'mais' = os dois.
-- Aparece no cartão da Rede ("Protético digital (CAD/CAM)") e entra na busca ("cadista").
-- Telefone e e-mail continuam escondidos. Pode rodar mais de uma vez sem problema.
-- =====================================================================
alter table public.odo_pre_cadastros add column if not exists especialidades text check (char_length(especialidades) <= 200);
alter table public.odo_pre_cadastros add column if not exists modalidade text check (char_length(modalidade) <= 60);
alter table public.odo_pre_cadastros add column if not exists funcao text check (funcao in ('nao','so','mais'));

-- Pré-cadastros na Rede (só primeiro nome)
drop function if exists public.odo_rede_pre(text);
create function public.odo_rede_pre(f_uf text default null)
returns table (id text, primeiro_nome text, letras_sobrenome int, profissao text, cidade text, uf text, especialidades text, modalidade text, funcao text)
language sql stable security definer set search_path = '' as $$
  select 'C'||lpad((abs(hashtext(p.id::text)) % 100000)::text,5,'0'),
         nullif(split_part(btrim(coalesce(p.nome,'')),' ',1),''),
         greatest(0, char_length(btrim(coalesce(p.nome,''))) - char_length(split_part(btrim(coalesce(p.nome,'')),' ',1)) - 1),
         p.profissao, p.cidade, p.uf, p.especialidades, p.modalidade, p.funcao
  from public.odo_pre_cadastros p
  where p.na_rede and p.aceito_por is null and auth.uid() is not null
    and (f_uf is null or p.uf = f_uf)
  order by p.criado_em desc
  limit 3000;
$$;
revoke all on function public.odo_rede_pre(text) from public, anon;
grant execute on function public.odo_rede_pre(text) to authenticated;

-- Perfis completos na Rede: mesma função de antes + a função principal do protético
drop function if exists public.odo_rede_profs(text, text);
create function public.odo_rede_profs(f_uf text default null, f_cidade text default null)
returns table (id text, nome text, prof text, cargo text, idade smallint, sexo text, uf text, cidade text,
               formacao text, resumo text, softs jsonb, pos jsonb, cursos jsonb, exp jsonb, tem_foto boolean, funcao text)
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
    ((p.vis->>'foto')::boolean and p.foto is not null),
    case when (p.prof = 'Protético' or coalesce(p.cadastro->'outras','[]'::jsonb) ? 'Protético')
          and p.cadastro->>'digital' in ('nao','so','mais')
         then p.cadastro->>'digital' else null end
  from public.odo_perfis p
  where p.aberto and auth.uid() is not null
    and (f_uf is null or p.uf = f_uf)
    and (f_cidade is null or ((p.vis->>'cidade')::boolean and lower(p.cidade) = lower(f_cidade)))
  order by p.atualizado_em desc
  limit 200;
$$;
revoke all on function public.odo_rede_profs(text,text) from public, anon;
grant execute on function public.odo_rede_profs(text,text) to authenticated;

select 'ok: 051 aplicada' as resultado;
