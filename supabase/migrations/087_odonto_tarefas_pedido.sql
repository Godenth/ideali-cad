-- 087 · Tarefas: ligar a tarefa a um pedido do cliente. Guarda o id do pedido e um texto curto (nº + paciente) para mostrar no cartão.
-- Não dá acesso a nada: a tarefa continua só do dono (RLS da 083) e o pedido só abre se for da própria conta. Pode rodar mais de uma vez.
alter table public.odo_tarefas add column if not exists pedido_id uuid;
alter table public.odo_tarefas add column if not exists pedido_txt text;
alter table public.odo_tarefas drop constraint if exists odo_tarefas_pedido_txt_tam;
alter table public.odo_tarefas add constraint odo_tarefas_pedido_txt_tam check (pedido_txt is null or char_length(pedido_txt) <= 160);
