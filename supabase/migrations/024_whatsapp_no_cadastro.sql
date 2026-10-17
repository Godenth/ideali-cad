-- Ideali CAD · 024: o WhatsApp informado no cadastro já vai para o perfil.
create or replace function public.novo_usuario()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  insert into public.perfis (user_id, nome, telefone)
  values (new.id, left(coalesce(new.raw_user_meta_data->>'nome', ''), 80),
          nullif(left(regexp_replace(coalesce(new.raw_user_meta_data->>'telefone', ''), '[^0-9()+ -]', '', 'g'), 20), ''));

  insert into public.assinaturas (user_id, status, teste_ate)
  values (new.id, 'teste', now() + interval '14 days');

  insert into public.tipos_trabalho (user_id, nome, forma, valor_padrao, criado_em)
  select new.id, r.nome, r.forma, 0, now() + r.ordem * interval '1 millisecond'
  from (values
    ('Elemento sobre dente','elemento',1), ('Elemento sobre implante','elemento',2), ('Faceta','elemento',3),
    ('Inlay / Onlay','elemento',4), ('Pôntico','elemento',5), ('Provisório com aleta','elemento',6),
    ('Placa de bruxismo','elemento',7), ('Enceramento digital (planejamento)','elemento',8),
    ('Protocolo (superior ou inferior)','trabalho',9), ('Protocolo completo (superior + inferior)','trabalho',10),
    ('Modelo 3D','trabalho',11)
  ) as r(nome, forma, ordem)
  order by r.ordem;
  return new;
end $function$;
