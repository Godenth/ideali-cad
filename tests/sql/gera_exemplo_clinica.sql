-- Gera um exemplo REALISTA da resposta de odo_clinica_pedidos() (dona e funcionária) para os testes de tela.
-- Tudo dentro de uma transação que é desfeita: não deixa nada no banco de teste.
\set QUIET on
\pset format unaligned
\pset tuples_only on
begin;
insert into auth.users (id) values ('10000000-0000-0000-0000-000000000001'),('10000000-0000-0000-0000-000000000002'),('10000000-0000-0000-0000-000000000003');
insert into public.odo_empresas (id, user_id, tipo, nome) values ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','lab','Ideali Lab');
insert into public.odo_clientes (id, user_id, reg, nome) values ('30000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-000000000001', 8,'Fernando 021 Dental Barra');
insert into public.odo_lab_vinculos (id, user_id, lab_id, lab_nome, status, cliente_id) values
 ('40000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','Ideali Lab','aceito','30000000-0000-0000-0000-00000000000a');
insert into public.odo_membros (dono_id, user_id, nome, cargo, ativo) values ('10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000003','Gilmara','Administrativo',true);

-- 29 pedidos antigos do sistema antigo: ainda "em produção", mas ARQUIVADOS, sem preço (o caso do "atrasado 295 dias")
insert into public.odo_pedidos (user_id, numero, cliente_id, paciente, tipo, trabalho, material, dentes, qtd, cor, valor, status, arquivado, enviado_inove, desenho_feito, criado_em)
select '10000000-0000-0000-0000-000000000001', g, '30000000-0000-0000-0000-00000000000a',
       (array['Leyliane Fernandes Dantas','Fernanda Ferreira Antunes','Rodrigo Nascimento de Oliveira','Cláudio Malibeu Bentes','Francisca Rafaela Rosa','Ronald Grey'])[1 + g % 6],
       'cad', (array['Zirconia','E-max'])[1 + g % 2], (array['zirconia','E-max'])[1 + g % 2], array[(array[27,36,46,14,11,21])[1 + g % 6]]::smallint[], 1, (array['A2','A3','BL2'])[1 + g % 3],
       null, 'producao', true, true, true, timestamptz '2026-01-13 10:00-03' + (g * interval '7 days')
  from generate_series(1, 29) g;
-- 150 entregues ao longo do ano (parte com preço, parte sem)
insert into public.odo_pedidos (user_id, numero, cliente_id, paciente, tipo, trabalho, material, dentes, qtd, cor, valor, status, arquivado, enviado_inove, desenho_feito, criado_em, entregue_em)
select '10000000-0000-0000-0000-000000000001', 100 + g, '30000000-0000-0000-0000-00000000000a',
       (array['Leonardo da Cunha Mello','Cristina Poça da Conceição','Jennifer Duarte Marques','Rogério de Oliveira Coelho','Camila da Cunha Wanzeller','Michel Felipe Magalhães','Armando de Santana Alves','Josué Oliveira Carvalho','Luiz Carlos Carneiro','Meuri Luiza Vedovello'])[1 + g % 10],
       'cad', (array['Coroa zircônia','E-max','Coroa e-max','Zircônia','Protocolo zircônia','Faceta E.max'])[1 + g % 6], (array['Zircônia','E-max','E-max','Zircônia','Zircônia','E-max'])[1 + g % 6],
       array[(array[17,36,35,14,46,27,26,37,11,21,12,22])[1 + g % 12]]::smallint[], 1, (array['A2','A3','BL2','A3,5'])[1 + g % 4],
       case when g % 3 = 0 then null when g % 6 = 4 then 2500 else 350 end, 'entregue', true, true, true,
       timestamptz '2026-01-05 10:00-03' + (g * interval '2 days'), timestamptz '2026-01-12 16:00-03' + (g * interval '2 days')
  from generate_series(1, 150) g;
-- 5 de novembro, em andamento de verdade (lançados pelo laboratório a partir do e-mail)
insert into public.odo_pedidos (user_id, numero, cliente_id, paciente, tipo, trabalho, material, dentes, qtd, cor, valor, status, arquivado, enviado_inove, desenho_feito, em_maquiagem, falta_info, criado_em) values
 ('10000000-0000-0000-0000-000000000001', 301,'30000000-0000-0000-0000-00000000000a','Vitor Marques Barbosa','cad','Coroa zircônia','Zircônia','{14}',1,'A2',350,'desenho',false,false,false,false,null, now() - interval '1 day'),
 ('10000000-0000-0000-0000-000000000001', 302,'30000000-0000-0000-0000-00000000000a','Janesson Caíque de Jesus Bispo','cad','Coroa zircônia','Zircônia','{46}',1,'BL1',350,'desenho',false,false,true,false,null, now() - interval '2 days'),
 ('10000000-0000-0000-0000-000000000001', 303,'30000000-0000-0000-0000-00000000000a','Rosanna Pozza','cad','Coroa E.max','E.max','{17}',1,'BL2',420,'producao',false,true,true,false,null, now() - interval '4 days'),
 ('10000000-0000-0000-0000-000000000001', 304,'30000000-0000-0000-0000-00000000000a','Zoe de Mello','cad','Coroa zircônia','Zircônia','{47}',1,'A3',350,'producao',false,true,true,true,null, now() - interval '6 days'),
 ('10000000-0000-0000-0000-000000000001', 305,'30000000-0000-0000-0000-00000000000a','Rafaela Alves de Oliveira','cad','Coroa zircônia','Zircônia','{17}',1,'A3',350,'aguardando',false,false,false,false,'Escaneamento do antagonista veio cortado. Pode mandar de novo?', now() - interval '3 days'),
 ('10000000-0000-0000-0000-000000000001', 306,'30000000-0000-0000-0000-00000000000a','Paciente Apagado','cad','Coroa','', '{11}',1,'A1',100,'producao',false,false,false,false,null, now() - interval '3 days');
update public.odo_pedidos set apagado = true where numero = 306;
-- pelo sistema: um esperando o laboratório aceitar, um aceito com 2 itens (etapas diferentes), um recusado
insert into public.odo_ped_env (id, user_id, vinculo_id, lab_id, dentista_nome, paciente, itens, cor, status, enviado_em, criado_em, respondido_em, motivo) values
 ('50000000-0000-0000-0000-0000000000a1','10000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-00000000000a','20000000-0000-0000-0000-000000000001','Fernando','Antonio Carlos','[{"trabalho":"Coroa metalocerâmica","dentes":[35,36]}]','A3,5','enviado', now() - interval '3 hours', now() - interval '3 hours', null, null),
 ('50000000-0000-0000-0000-0000000000a2','10000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-00000000000a','20000000-0000-0000-0000-000000000001','Fernando','Maria Souza','[{"trabalho":"Coroa zircônia","dentes":[11]},{"trabalho":"Protocolo zircônia","dentes":[]}]','BL2','aceito', now() - interval '5 days', now() - interval '5 days', now() - interval '5 days', null),
 ('50000000-0000-0000-0000-0000000000a3','10000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-00000000000a','20000000-0000-0000-0000-000000000001','Fernando','João Lima','[{"trabalho":"Placa de bruxismo","dentes":[]}]',null,'recusado', now() - interval '20 days', now() - interval '20 days', now() - interval '19 days', 'Não fazemos placa.');
insert into public.odo_pedidos (user_id, numero, cliente_id, paciente, tipo, trabalho, material, dentes, qtd, cor, valor, status, enviado_inove, desenho_feito, envio_id, criado_em) values
 ('10000000-0000-0000-0000-000000000001', 307,'30000000-0000-0000-0000-00000000000a','Maria Souza','cad','Coroa zircônia','Zircônia','{11}',1,'BL2',350,'producao',true,true,'50000000-0000-0000-0000-0000000000a2', now() - interval '5 days'),
 ('10000000-0000-0000-0000-000000000001', 308,'30000000-0000-0000-0000-00000000000a','Maria Souza','cad','Protocolo zircônia','Zircônia',null,1,'BL2',2500,'desenho',false,false,'50000000-0000-0000-0000-0000000000a2', now() - interval '5 days');
-- fechamentos: outubro em aberto, setembro quitado
insert into public.odo_fin_meses (id, user_id, cliente_id, ano, mes, valor_mes) values
 ('70000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-00000000000a',2026,10,4534),
 ('70000000-0000-0000-0000-000000000009','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-00000000000a',2026,9,6646);
insert into public.odo_fin_pagamentos (user_id, mes_id, valor, data) values ('10000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000009',6646,'2026-11-04');

select set_config('t.uid','10000000-0000-0000-0000-000000000002',true);
\o tests/dados/clinica_dona.json
select public.odo_clinica_pedidos();
\o
select set_config('t.uid','10000000-0000-0000-0000-000000000003',true);
\o tests/dados/clinica_funcionaria.json
select public.odo_clinica_pedidos();
\o
rollback;
