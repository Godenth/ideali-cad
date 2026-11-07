-- =====================================================================
-- 050 · Ideali Odonto · Pré-cadastros visíveis na Rede (com o mínimo de dados).
-- Pedido do dono em 06/11/2026: os contatos do formulário do GoDenth (que marcaram
-- "quero fazer parte da rede de profissionais") aparecem na Rede.
-- Aparece SÓ: primeiro nome, profissão, cidade/UF. O sobrenome NÃO sai do banco
-- (vai só a quantidade de letras, para a tela desenhar o borrão).
-- Telefone e e-mail NUNCA saem. Quando a pessoa aceita o convite, vira perfil normal.
-- =====================================================================
alter table public.odo_pre_cadastros add column if not exists na_rede boolean not null default true;
alter table public.odo_pre_cadastros add column if not exists tem_negocio boolean;

create or replace function public.odo_rede_pre(f_uf text default null)
returns table (id text, primeiro_nome text, letras_sobrenome int, profissao text, cidade text, uf text)
language sql stable security definer set search_path = '' as $$
  select 'C'||lpad((abs(hashtext(p.id::text)) % 100000)::text,5,'0'),
         nullif(split_part(btrim(coalesce(p.nome,'')),' ',1),''),
         greatest(0, char_length(btrim(coalesce(p.nome,''))) - char_length(split_part(btrim(coalesce(p.nome,'')),' ',1)) - 1),
         p.profissao, p.cidade, p.uf
  from public.odo_pre_cadastros p
  where p.na_rede and p.aceito_por is null and auth.uid() is not null
    and (f_uf is null or p.uf = f_uf)
  order by p.criado_em desc
  limit 3000;
$$;
revoke all on function public.odo_rede_pre(text) from public, anon;
grant execute on function public.odo_rede_pre(text) to authenticated;

select 'ok: 050 aplicada' as resultado;
