-- Teste da 074 (fonte única). Roda tudo dentro de uma transação e desfaz no fim: não deixa nada no banco.
-- Uso (banco de TESTE com as migrações aplicadas e auth.uid() lendo a config t.uid):
--   psql -v ON_ERROR_STOP=1 -f tests/sql/074_fonte_unica.teste.sql
begin;
create or replace function pg_temp.ok(cond boolean, msg text) returns void language plpgsql as $$
begin if cond is not true then raise exception 'FALHOU: %', msg; end if; raise notice 'ok  %', msg; end $$;
create or replace function pg_temp.como(u uuid) returns void language sql as $$ select set_config('t.uid', coalesce(u::text, ''), true); $$;

-- ---------- cenário ----------
insert into auth.users (id) values
 ('10000000-0000-0000-0000-000000000001'),  -- LAB (dono do laboratório)
 ('10000000-0000-0000-0000-000000000002'),  -- CLINICA A (dona)
 ('10000000-0000-0000-0000-000000000003'),  -- FUNCIONARIO da clínica A
 ('10000000-0000-0000-0000-000000000004'),  -- CLINICA B
 ('10000000-0000-0000-0000-000000000005');  -- OUTRO LABORATÓRIO
insert into public.odo_empresas (id, user_id, tipo, nome) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','lab','Lab Teste'),
 ('20000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000005','lab','Outro Lab');
insert into public.odo_clientes (id, user_id, reg, nome) values
 ('30000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-000000000001', 1,'Cliente A'),
 ('30000000-0000-0000-0000-00000000000b','10000000-0000-0000-0000-000000000001', 2,'Cliente B'),
 ('30000000-0000-0000-0000-00000000000c','10000000-0000-0000-0000-000000000001', 3,'Cliente sem conta');
insert into public.odo_lab_vinculos (id, user_id, lab_id, lab_nome, status, cliente_id) values
 ('40000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','Lab Teste','aceito','30000000-0000-0000-0000-00000000000a'),
 ('40000000-0000-0000-0000-00000000000b','10000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000001','Lab Teste','aceito','30000000-0000-0000-0000-00000000000b');
insert into public.odo_membros (dono_id, user_id, nome, cargo, ativo) values
 ('10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000003','Funcionária','Administrativo',true);

-- envios da clínica (A: um aceito com 2 itens e um esperando; B: um aceito)
insert into public.odo_ped_env (id, user_id, vinculo_id, lab_id, paciente, itens, status, enviado_em, criado_em) values
 ('50000000-0000-0000-0000-0000000000a1','10000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-00000000000a','20000000-0000-0000-0000-000000000001','PACIENTE-A-ENVIO','[{"trabalho":"Coroa zircônia"},{"trabalho":"Protocolo zircônia"}]','aceito','2026-11-09 10:00-03','2026-11-09 10:00-03'),
 ('50000000-0000-0000-0000-0000000000a2','10000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-00000000000a','20000000-0000-0000-0000-000000000001','PACIENTE-A-ESPERA','[{"trabalho":"Coroa metalocerâmica"}]','enviado','2026-11-10 14:00-03','2026-11-10 14:00-03'),
 ('50000000-0000-0000-0000-0000000000b1','10000000-0000-0000-0000-000000000004','40000000-0000-0000-0000-00000000000b','20000000-0000-0000-0000-000000000001','PACIENTE-B-ENVIO','[{"trabalho":"Coroa"}]','aceito','2026-11-09 10:00-03','2026-11-09 10:00-03');

-- pedidos na conta do laboratório
insert into public.odo_pedidos (id, user_id, numero, cliente_id, paciente, tipo, trabalho, qtd, valor, status, arquivado, apagado, envio_id, desenho_feito, enviado_inove, obs, descricao, criado_em) values
 ('60000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',1,'30000000-0000-0000-0000-00000000000a','PACIENTE-A-LAB','cad','Coroa zircônia',1,300,'producao',false,false,null,true,true,'OBS-INTERNA-SECRETA','DESCRICAO-INTERNA','2026-11-09 09:00-03'),
 ('60000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',2,'30000000-0000-0000-0000-00000000000a','PACIENTE-A-ANTIGO','cad','E-max',1,null,'producao',true,false,null,true,true,null,null,'2026-01-13 09:00-03'),
 ('60000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001',3,'30000000-0000-0000-0000-00000000000a','PACIENTE-A-APAGADO','cad','Coroa',1,100,'producao',false,true,null,false,false,null,null,'2026-11-01 09:00-03'),
 ('60000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001',4,'30000000-0000-0000-0000-00000000000a','PACIENTE-A-ORCAMENTO','cad','Coroa',1,100,'orcamento',false,false,null,false,false,null,null,'2026-11-01 09:00-03'),
 ('60000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000001',5,'30000000-0000-0000-0000-00000000000b','PACIENTE-B-LAB','cad','Coroa',1,555,'desenho',false,false,null,false,false,null,null,'2026-11-09 09:00-03'),
 ('60000000-0000-0000-0000-000000000006','10000000-0000-0000-0000-000000000001',6,'30000000-0000-0000-0000-00000000000c','PACIENTE-SEM-CONTA','cad','Coroa',1,666,'desenho',false,false,null,false,false,null,null,'2026-11-09 09:00-03'),
 ('60000000-0000-0000-0000-000000000007','10000000-0000-0000-0000-000000000001',7,'30000000-0000-0000-0000-00000000000a','PACIENTE-A-ENVIO','cad','Coroa zircônia',1,350,'desenho',false,false,'50000000-0000-0000-0000-0000000000a1',false,false,null,null,'2026-11-09 11:00-03'),
 ('60000000-0000-0000-0000-000000000008','10000000-0000-0000-0000-000000000001',8,'30000000-0000-0000-0000-00000000000a','PACIENTE-A-ENVIO','cad','Protocolo zircônia',1,2500,'producao',false,false,'50000000-0000-0000-0000-0000000000a1',true,true,null,null,'2026-11-09 11:00-03'),
 ('60000000-0000-0000-0000-000000000009','10000000-0000-0000-0000-000000000001',9,'30000000-0000-0000-0000-00000000000b','PACIENTE-B-ENVIO','cad','Coroa',1,400,'desenho',false,false,'50000000-0000-0000-0000-0000000000b1',false,false,null,null,'2026-11-09 11:00-03');
insert into public.odo_fin_meses (id, user_id, cliente_id, ano, mes, valor_mes) values
 ('70000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-00000000000a',2026,10,1000),
 ('70000000-0000-0000-0000-00000000000b','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-00000000000b',2026,10,777);
insert into public.odo_fin_pagamentos (user_id, mes_id, valor, data) values
 ('10000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-00000000000a',400,'2026-11-01');

-- ---------- 1. clínica A (dona) ----------
select pg_temp.como('10000000-0000-0000-0000-000000000002');
create temp table ra on commit drop as select public.odo_clinica_pedidos() as j;
select pg_temp.ok((select (j->>'dono')::boolean from ra), 'A: reconhecida como dona');
select pg_temp.ok((select jsonb_array_length(j->'pedidos') from ra) = 2, 'A: vê 2 pedidos lançados pelo laboratório (não vê apagado nem orçamento)');
select pg_temp.ok((select jsonb_array_length(j->'envios') from ra) = 2, 'A: vê os 2 envios dela');
select pg_temp.ok((select j::text from ra) not like '%PACIENTE-B%', 'A: NADA da clínica B');
select pg_temp.ok((select j::text from ra) not like '%PACIENTE-SEM-CONTA%', 'A: nada de cliente sem conta');
select pg_temp.ok((select j::text from ra) not like '%APAGADO%' and (select j::text from ra) not like '%ORCAMENTO%', 'A: pedido apagado e orçamento ficam de fora');
select pg_temp.ok((select j::text from ra) not like '%SECRETA%' and (select j::text from ra) not like '%DESCRICAO-INTERNA%', 'A: anotações internas do laboratório não saem');
select pg_temp.ok((select x->>'etapa' from ra, jsonb_array_elements(j->'pedidos') x where x->>'paciente'='PACIENTE-A-ANTIGO') = 'Entregue', 'A: pedido arquivado no laboratório aparece como Entregue');
select pg_temp.ok((select (x->>'aberto')::boolean from ra, jsonb_array_elements(j->'pedidos') x where x->>'paciente'='PACIENTE-A-ANTIGO') = false, 'A: arquivado não conta como em andamento (não fica "atrasado")');
select pg_temp.ok((select x ? 'prazo_max' from ra, jsonb_array_elements(j->'pedidos') x where x->>'paciente'='PACIENTE-A-ANTIGO') = false, 'A: pedido encerrado não tem prazo');
select pg_temp.ok((select x->>'etapa' from ra, jsonb_array_elements(j->'pedidos') x where x->>'paciente'='PACIENTE-A-LAB') = 'Enviado para fresagem', 'A: etapa do pedido em produção');
select pg_temp.ok((select x->>'prazo_max' from ra, jsonb_array_elements(j->'pedidos') x where x->>'paciente'='PACIENTE-A-LAB') = '2026-11-17', 'A: prazo 5 a 7 dias úteis a partir de 09/11 9h = até 17/11');
select pg_temp.ok((select (x->>'valor')::numeric from ra, jsonb_array_elements(j->'pedidos') x where x->>'paciente'='PACIENTE-A-LAB') = 300, 'A: dona vê o valor');
select pg_temp.ok((select jsonb_array_length(x->'partes') from ra, jsonb_array_elements(j->'envios') x where x->>'paciente'='PACIENTE-A-ENVIO') = 2, 'A: envio com 2 itens traz os 2');
select pg_temp.ok((select x->>'etapa' from ra, jsonb_array_elements(j->'envios') x where x->>'paciente'='PACIENTE-A-ENVIO') = 'Desenho CAD', 'A: envio com 2 itens mostra a etapa do item mais atrasado');
select pg_temp.ok((select x->>'prazo_max' from ra, jsonb_array_elements(j->'envios') x where x->>'paciente'='PACIENTE-A-ENVIO') = '2026-11-23', 'A: envio com protocolo = 10 dias úteis a partir de 09/11 10h (pula o feriado de 20/11) = 23/11');
select pg_temp.ok((select x->>'prazo_max' from ra, jsonb_array_elements(j->'envios') x where x->>'paciente'='PACIENTE-A-ESPERA') = '2026-11-25', 'A: envio esperando o laboratório, metalocerâmica enviada 10/11 às 14h = até 25/11');
select pg_temp.ok((select jsonb_array_length(j->'meses') from ra) = 1 and (select (j->'meses'->0->>'valor')::numeric from ra) = 1000 and (select (j->'meses'->0->>'pago')::numeric from ra) = 400, 'A: fechamento do mês (1000) e pago (400), só o dela');

-- ---------- 2. funcionária da clínica A ----------
select pg_temp.como('10000000-0000-0000-0000-000000000003');
create temp table rf on commit drop as select public.odo_clinica_pedidos() as j;
select pg_temp.ok((select (j->>'dono')::boolean from rf) = false, 'Funcionária: não é dona');
select pg_temp.ok((select jsonb_array_length(j->'pedidos') from rf) = 2 and (select jsonb_array_length(j->'envios') from rf) = 2, 'Funcionária: vê os mesmos pedidos da clínica');
select pg_temp.ok((select j::text from rf) not like '%"valor"%', 'Funcionária: NENHUM valor');
select pg_temp.ok((select jsonb_array_length(j->'meses') from rf) = 0, 'Funcionária: nenhum fechamento');
select pg_temp.ok((select j::text from rf) not like '%PACIENTE-B%', 'Funcionária: nada da clínica B');

-- ---------- 3. clínica B ----------
select pg_temp.como('10000000-0000-0000-0000-000000000004');
create temp table rb on commit drop as select public.odo_clinica_pedidos() as j;
select pg_temp.ok((select jsonb_array_length(j->'pedidos') from rb) = 1 and (select jsonb_array_length(j->'envios') from rb) = 1, 'B: vê só o pedido e o envio dela');
select pg_temp.ok((select j::text from rb) not like '%PACIENTE-A%', 'B: NADA da clínica A');
select pg_temp.ok((select (j->'meses'->0->>'valor')::numeric from rb) = 777, 'B: fechamento dela (777), não o da A');

-- ---------- 4. quem não é clínica ----------
select pg_temp.como('10000000-0000-0000-0000-000000000005');
select pg_temp.ok((select jsonb_array_length(j->'pedidos') + jsonb_array_length(j->'envios') + jsonb_array_length(j->'meses') from (select public.odo_clinica_pedidos() j) q) = 0, 'Outro laboratório: não recebe nada');
select pg_temp.como(null);
select pg_temp.ok(public.odo_clinica_pedidos() is null, 'Sem login: não recebe nada');
select pg_temp.ok(not has_function_privilege('anon', 'public.odo_clinica_pedidos()', 'execute'), 'Visitante sem login não pode nem chamar a leitura');
select pg_temp.ok(not has_function_privilege('authenticated', 'public.odo_envio_etapa(uuid)', 'execute'), 'Função interna de etapa não é chamável de fora');

-- ---------- 5. o laboratório mexe e a clínica acompanha ----------
select pg_temp.como('10000000-0000-0000-0000-000000000001');
update public.odo_pedidos set status = 'producao' where id = '60000000-0000-0000-0000-000000000007';
select pg_temp.ok((select etapa from public.odo_ped_env where id = '50000000-0000-0000-0000-0000000000a1') = 'Em produção', 'Item 1 foi para produção: o envio acompanha (item mais atrasado)');
update public.odo_pedidos set status = 'aguardando', falta_info = 'Mande o antagonista' where id = '60000000-0000-0000-0000-000000000007';
select pg_temp.ok((select etapa = 'Aguardando informação' and falta_info = 'Mande o antagonista' from public.odo_ped_env where id = '50000000-0000-0000-0000-0000000000a1'), 'Pendência num item: o envio mostra a pendência e a pergunta');
select pg_temp.como('10000000-0000-0000-0000-000000000002');
select pg_temp.ok((select (x->>'parado')::boolean and x->>'etapa' = 'Aguardando informação' and x->>'falta_info' = 'Mande o antagonista' from (select public.odo_clinica_pedidos() j) q, jsonb_array_elements(j->'envios') x where x->>'paciente'='PACIENTE-A-ENVIO'), 'Clínica vê o envio parado, com a pergunta do laboratório');
select pg_temp.ok(public.odo_ped_env_responde_pend('50000000-0000-0000-0000-0000000000a1', true, 'Pode seguir', '[]'::jsonb) = 'retomado', 'Clínica responde a pendência e o pedido é retomado');
select pg_temp.ok((select status = 'desenho' and prazo_inicio is not null from public.odo_pedidos where id = '60000000-0000-0000-0000-000000000007'), 'Pedido retomado: prazo recomeça agora');
select pg_temp.ok((select etapa <> 'Aguardando informação' and prazo_inicio is not null from public.odo_ped_env where id = '50000000-0000-0000-0000-0000000000a1'), 'Envio sai da pendência e o prazo recomeça');
select pg_temp.como('10000000-0000-0000-0000-000000000001');
update public.odo_pedidos set arquivado = true where envio_id = '50000000-0000-0000-0000-0000000000a1';
select pg_temp.ok((select etapa from public.odo_ped_env where id = '50000000-0000-0000-0000-0000000000a1') = 'Entregue', 'Laboratório arquivou os 2 itens: clínica vê Entregue');
update public.odo_pedidos set apagado = true where id = '60000000-0000-0000-0000-000000000009';
select pg_temp.como('10000000-0000-0000-0000-000000000004');
select pg_temp.ok((select x->>'etapa' = 'Cancelado' and (x->>'aberto')::boolean = false from (select public.odo_clinica_pedidos() j) q, jsonb_array_elements(j->'envios') x limit 1), 'Laboratório apagou o pedido do envio: clínica vê Cancelado, não fica aberto para sempre');

-- ---------- 5b. igual ao mundo real: papel "authenticated", com as regras de acesso (RLS) valendo ----------
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
select pg_temp.como('10000000-0000-0000-0000-000000000001');
set local role authenticated;
update public.odo_pedidos set status = 'aguardando', falta_info = 'Falta a cor' where id = '60000000-0000-0000-0000-000000000001';
update public.odo_pedidos set status = 'producao' where id = '60000000-0000-0000-0000-000000000001';
reset role;
select pg_temp.ok((select prazo_inicio is not null from public.odo_pedidos where id = '60000000-0000-0000-0000-000000000001'), 'Laboratório logado (com RLS) resolve a pendência de um pedido lançado por ele: o prazo recomeça');
select pg_temp.como('10000000-0000-0000-0000-000000000004');
set local role authenticated;
update public.odo_pedidos set status = 'entregue' where id = '60000000-0000-0000-0000-000000000001';
reset role;
select pg_temp.ok((select status from public.odo_pedidos where id = '60000000-0000-0000-0000-000000000001') = 'producao', 'Clínica B logada NÃO consegue mexer em pedido do laboratório');
select pg_temp.como('10000000-0000-0000-0000-000000000002');
set local role authenticated;
create temp table rr on commit drop as select public.odo_clinica_pedidos() as j;
reset role;
select pg_temp.ok((select jsonb_array_length(j->'pedidos') from rr) = 2 and (select j::text from rr) not like '%PACIENTE-B%', 'Clínica A logada (com RLS) chama a leitura única e recebe só o dela');
select pg_temp.como('10000000-0000-0000-0000-000000000002');
set local role authenticated;
create temp table rr2 on commit drop as select count(*) n from public.odo_pedidos;
reset role;
select pg_temp.ok((select n from rr2) = 0, 'Clínica A logada não lê a tabela de pedidos do laboratório direto (só pela leitura única)');

-- ---------- 6. leituras antigas seguem a mesma regra ----------
select pg_temp.como('10000000-0000-0000-0000-000000000002');
select pg_temp.ok((select public.odo_clinica_pedidos_lab()::text) not like '%APAGADO%', 'Leitura antiga também esconde pedido apagado');
select pg_temp.ok((select x->>'etapa' from jsonb_array_elements(public.odo_clinica_pedidos_lab()) x where x->>'paciente'='PACIENTE-A-ANTIGO') = 'Entregue', 'Leitura antiga também mostra arquivado como Entregue');
select pg_temp.ok((select public.odo_clinica_fin()::text) not like '%APAGADO%' and (select public.odo_clinica_fin()::text) not like '%PACIENTE-B%', 'Financeiro antigo: sem apagado e sem dado de outra clínica');

rollback;
\echo TODOS OS TESTES DA 074 PASSARAM
