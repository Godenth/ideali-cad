-- =====================================================================
-- Ideali CAD · Teste de segurança com duas contas (rodar no SQL Editor)
-- Cria duas contas falsas, testa e DESFAZ TUDO no final.
-- O resultado aparece como uma mensagem de "erro" em vermelho:
-- isso é proposital, é o jeito de desfazer o teste sem deixar nada gravado.
-- Leia a lista: todas as linhas devem começar com OK.
-- =====================================================================
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid();
  cli uuid; ped uuid; n int; r text[] := '{}'; v text;
begin
  insert into auth.users (instance_id,id,aud,role,email,raw_user_meta_data,created_at,updated_at)
  values ('00000000-0000-0000-0000-000000000000',a,'authenticated','authenticated','teste-a@idealicad.invalid','{"nome":"Cadista A"}',now(),now()),
         ('00000000-0000-0000-0000-000000000000',b,'authenticated','authenticated','teste-b@idealicad.invalid','{"nome":"Cadista B"}',now(),now());
  select count(*) into n from public.assinaturas where user_id in (a,b) and status='teste' and teste_ate > now()+interval '13 days';
  r := r || (case when n=2 then 'OK cadastro cria perfil + 14 dias de teste' else 'FALHOU cadastro' end);
  r := r || (case when not has_table_privilege('authenticated','public.clientes','DELETE') and not has_table_privilege('authenticated','public.pedidos','DELETE') then 'OK sem permissao de apagar (so lixeira)' else 'FALHOU DELETE liberado' end);
  r := r || (case when not has_table_privilege('anon','public.clientes','SELECT') then 'OK visitante sem login nao le nada' else 'FALHOU anon le' end);

  perform set_config('request.jwt.claims', json_build_object('sub',a,'role','authenticated')::text, true);
  set local role authenticated;
  insert into public.clientes (nome) values ('Lab. do A') returning id into cli;
  insert into public.pedidos (cliente_id,paciente,elementos,valor) values (cli,'M.A.S.','{11,21}',160) returning id into ped;
  insert into public.pedidos (cliente_id,paciente) values (cli,'J.C.');
  select string_agg(numero::text,',' order by numero) into v from public.pedidos;
  r := r || (case when v='1,2' then 'OK numeracao #1, #2' else 'FALHOU numeracao '||coalesce(v,'') end);
  begin insert into public.arquivos (pedido_id,origem,nome,storage_key,tamanho_zip) values (ped,'upload','x.zip','k',1); r:=r||'FALHOU upload pelo navegador'::text; exception when others then r:=r||'OK navegador nao registra upload'::text; end;
  begin update public.assinaturas set status='ativa'; get diagnostics n = row_count; r:=r||(case when n=0 then 'OK nao altera a propria assinatura' else 'FALHOU alterou assinatura' end); exception when others then r:=r||'OK nao altera a propria assinatura'::text; end;

  perform set_config('request.jwt.claims', json_build_object('sub',b,'role','authenticated')::text, true);
  select (select count(*) from public.clientes)+(select count(*) from public.pedidos)+(select count(*) from public.arquivos) into n;
  r := r || (case when n=0 then 'OK B nao enxerga nada de A' else 'FALHOU B ve '||n||' registros de A' end);
  select count(*) into n from public.perfis;
  r := r || (case when n=1 then 'OK B so ve o proprio perfil' else 'FALHOU perfis: '||n end);
  update public.clientes set nome='hackeado'; update public.pedidos set valor=0;
  begin insert into public.pedidos (cliente_id,paciente) values (cli,'Z'); r:=r||'FALHOU B usou cliente de A'::text; exception when others then r:=r||'OK B nao usa cliente de A'::text; end;

  perform set_config('request.jwt.claims', json_build_object('sub',a,'role','authenticated')::text, true);
  select nome into v from public.clientes where id=cli;
  r := r || (case when v='Lab. do A' then 'OK edicao de B nao afetou A' else 'FALHOU' end);
  select valor::text into v from public.pedidos where id=ped;
  r := r || (case when v='160.00' then 'OK valor de A intacto' else 'FALHOU valor '||coalesce(v,'') end);

  reset role;
  update public.assinaturas set status='vencida' where user_id=a;
  set local role authenticated;
  begin insert into public.clientes (nome) values ('novo'); r:=r||'FALHOU vencida gravou'::text; exception when others then r:=r||'OK vencida nao grava'::text; end;
  select count(*) into n from public.clientes;
  r := r || (case when n=1 then 'OK vencida continua lendo' else 'FALHOU leitura' end);
  reset role;
  raise exception 'RESULTADO (tudo desfeito, nada foi gravado): %', array_to_string(r, ' | ');
end $$;
