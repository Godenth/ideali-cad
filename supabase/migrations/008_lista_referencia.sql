-- =====================================================================
-- Ideali CAD · Migração 008 · Lista padrão igual à referência (placa de bruxismo por elemento)
-- Antes o navegador criava a lista no primeiro acesso; com o sistema aberto
-- em mais de uma aba ao mesmo tempo, ela era criada repetida.
-- Agora a lista de referência (R$ 0,00) nasce junto com a conta, no banco.
-- =====================================================================

-- Cadastro: perfil + 14 dias de teste + lista de referência.
create or replace function public.novo_usuario()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.perfis (user_id, nome)
  values (new.id, left(coalesce(new.raw_user_meta_data->>'nome', ''), 80));

  insert into public.assinaturas (user_id, status, teste_ate)
  values (new.id, 'teste', now() + interval '14 days');

  insert into public.tipos_trabalho (user_id, nome, forma, valor_padrao, criado_em)
  select new.id, r.nome, r.forma, 0, now() + r.ordem * interval '1 millisecond'
  from (values
    ('Coroa sobre dente','elemento',1), ('Coroa sobre implante','elemento',2), ('Faceta','elemento',3),
    ('Inlay / Onlay','elemento',4), ('Pôntico','elemento',5), ('Provisório com aleta','elemento',6),
    ('Placa de bruxismo','elemento',7), ('Enceramento digital (planejamento)','elemento',8),
    ('Protocolo (superior ou inferior)','trabalho',9), ('Protocolo completo (superior + inferior)','trabalho',10),
    ('Modelo adicional','trabalho',11)
  ) as r(nome, forma, ordem)
  order by r.ordem;
  return new;
end $$;
revoke all on function public.novo_usuario() from public, anon, authenticated;
