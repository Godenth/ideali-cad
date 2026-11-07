-- =====================================================================
-- 051 · Ideali Odonto · Pré-cadastros com especialidades e modalidade (lista de cadistas).
-- Especialidades (ex.: CAD/CAM · Resina · Emax) e modalidade (ex.: Home office)
-- passam a aparecer no cartão da Rede e entram na busca. Telefone e e-mail continuam escondidos.
-- =====================================================================
alter table public.odo_pre_cadastros add column if not exists especialidades text check (char_length(especialidades) <= 200);
alter table public.odo_pre_cadastros add column if not exists modalidade text check (char_length(modalidade) <= 60);

drop function if exists public.odo_rede_pre(text);
create function public.odo_rede_pre(f_uf text default null)
returns table (id text, primeiro_nome text, letras_sobrenome int, profissao text, cidade text, uf text, especialidades text, modalidade text)
language sql stable security definer set search_path = '' as $$
  select 'C'||lpad((abs(hashtext(p.id::text)) % 100000)::text,5,'0'),
         nullif(split_part(btrim(coalesce(p.nome,'')),' ',1),''),
         greatest(0, char_length(btrim(coalesce(p.nome,''))) - char_length(split_part(btrim(coalesce(p.nome,'')),' ',1)) - 1),
         p.profissao, p.cidade, p.uf, p.especialidades, p.modalidade
  from public.odo_pre_cadastros p
  where p.na_rede and p.aceito_por is null and auth.uid() is not null
    and (f_uf is null or p.uf = f_uf)
  order by p.criado_em desc
  limit 3000;
$$;
revoke all on function public.odo_rede_pre(text) from public, anon;
grant execute on function public.odo_rede_pre(text) to authenticated;

select 'ok: 051 aplicada' as resultado;
