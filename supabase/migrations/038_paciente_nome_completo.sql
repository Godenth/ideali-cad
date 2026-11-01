-- 038: o paciente pode ter o nome completo (antes era só iniciais, até 40 letras).
-- Os dados continuam visíveis só para o dono da conta (RLS em todas as tabelas).
do $$
declare c record;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.pedidos'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%paciente%'
  loop
    execute format('alter table public.pedidos drop constraint %I', c.conname);
  end loop;
end $$;
alter table public.pedidos add constraint pedidos_paciente_tam check (char_length(paciente) between 1 and 80);
comment on column public.pedidos.paciente is 'Nome do paciente (até 80 letras). Visível só para o dono da conta.';
