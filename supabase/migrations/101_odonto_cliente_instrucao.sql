alter table public.odo_clientes
  add column if not exists instrucao_padrao text;

comment on column public.odo_clientes.instrucao_padrao is 'Instrucao recorrente que entra automaticamente no e-mail da Ana para a Inove';
