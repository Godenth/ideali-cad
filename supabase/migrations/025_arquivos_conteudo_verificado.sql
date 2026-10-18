-- Conteúdo conferido pelo servidor (o que existe dentro do .zip: STL de verdade, HTML de verdade).
-- Usado pela meta oficial: só conta pedido finalizado com STL e HTML comprovados.
-- Só o servidor (service_role) grava "conteudo"; a data de envio também não pode ser mudada pelo navegador.
alter table public.arquivos add column if not exists conteudo jsonb;

create or replace function public.arquivos_protege_conteudo() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    if tg_op = 'INSERT' then
      new.conteudo := null;
      new.criado_em := now();
    else
      new.conteudo := old.conteudo;
      new.criado_em := old.criado_em;
    end if;
  end if;
  return new;
end $$;

create trigger arquivos_protege_conteudo before insert or update on public.arquivos
  for each row execute function public.arquivos_protege_conteudo();
