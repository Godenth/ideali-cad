// Supabase falso para testar as telas sem internet. Registra cada gravação em window.__ops.
(function(){
  var U='dddddddd-0000-0000-0000-000000000004';
  var tabelas={perfis:[{user_id:U,nome:'Danilo',preferencias:{}}],assinaturas:[{user_id:U,plano:'basico',status:'teste',teste_ate:new Date(Date.now()+13*864e5).toISOString(),limite_bytes:5368709120,bytes_usados:0}],
    clientes:[],tipos_trabalho:[],precos_cliente:[],faixas_desconto:[],pagamentos:[],pedidos:[],arquivos:[],links_cliente:[],perfil_rede:[]};
  window.__ops=[];var cbs=[],sessao=null;
  function Q(t){this.t=t;this.f=[];}
  Q.prototype.select=function(){this.op='select';return this;};
  Q.prototype.eq=function(c,v){this.f.push([c,v]);return this;};
  Q.prototype.range=function(){return this;};Q.prototype.limit=function(){return this;};Q.prototype.is=function(){return this;};Q.prototype.order=function(){return this;};
  Q.prototype.maybeSingle=function(){this.single=true;return this;};
  Q.prototype.insert=function(r){this.op='insert';this.row=r;return this;};
  Q.prototype.update=function(r){this.op='update';this.row=r;return this;};
  Q.prototype.upsert=function(r){this.op='upsert';this.row=r;return this;};
  Q.prototype.then=function(ok,ko){var me=this;return Promise.resolve().then(function(){
    var rows=tabelas[me.t];
    if(me.op==='insert'){window.__ops.push({op:'insert',t:me.t,row:JSON.parse(JSON.stringify(me.row))});rows.push(Object.assign({},me.row,{criado_em:new Date().toISOString()}));return {error:null};}
    if(me.op==='upsert'){window.__ops.push({op:'upsert',t:me.t,row:JSON.parse(JSON.stringify(me.row))});var ex=rows.filter(function(r){return r.user_id===me.row.user_id;})[0];if(ex)Object.assign(ex,me.row);else rows.push(Object.assign({},me.row));return {error:null};}
    var sel=rows.filter(function(r){return me.f.every(function(f){return r[f[0]]===f[1];});});
    if(me.op==='update'){window.__ops.push({op:'update',t:me.t,row:JSON.parse(JSON.stringify(me.row)),where:me.f});sel.forEach(function(r){Object.assign(r,me.row);});return {error:null};}
    return {data:me.single?(sel[0]||null):JSON.parse(JSON.stringify(sel)),error:null};
  }).then(ok,ko);};
  var client={
    from:function(t){return new Q(t);},
    auth:{
      onAuthStateChange:function(cb){cbs.push(cb);setTimeout(function(){cb('INITIAL_SESSION',sessao);},0);return {data:{subscription:{unsubscribe:function(){}}}};},
      getSession:function(){return Promise.resolve({data:{session:sessao}});},
      signInWithPassword:function(c){sessao={user:{id:U,email:c.email}};cbs.forEach(function(cb){cb('SIGNED_IN',sessao);});return Promise.resolve({data:{session:sessao},error:null});},
      signUp:function(c){return Promise.resolve({data:{session:null,user:{id:U}},error:null});},
      resend:function(c){return Promise.resolve({data:{},error:null});},
      signOut:function(){sessao=null;cbs.forEach(function(cb){cb('SIGNED_OUT',null);});return Promise.resolve({error:null});},
      resetPasswordForEmail:function(){return Promise.resolve({error:null});},
      updateUser:function(){return Promise.resolve({error:null});},
      mfa:{_f:null,_aal:'aal1',
        listFactors:function(){var f=this._f;return Promise.resolve({data:{all:f?[f]:[],totp:f?[f]:[]},error:null});},
        getAuthenticatorAssuranceLevel:function(){return Promise.resolve({data:{currentLevel:this._aal,nextLevel:this._f&&this._f.status==='verified'?'aal2':'aal1'},error:null});},
        enroll:function(){this._f={id:'fac1',status:'unverified',factor_type:'totp'};return Promise.resolve({data:{id:'fac1',totp:{qr_code:'data:image/svg+xml;utf8,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%22200%22 height=%22200%22><rect width=%22200%22 height=%22200%22 fill=%22%23000%22/></svg>',secret:'ABCDEF123456'}},error:null});},
        unenroll:function(){this._f=null;return Promise.resolve({error:null});},
        challengeAndVerify:function(o){if(o.code!=='123456')return Promise.resolve({error:{message:'invalid'}});this._f.status='verified';this._aal='aal2';return Promise.resolve({data:{},error:null});}}
    },
    rpc:function(n,a){window.__ops.push({op:'rpc',name:n,args:a});
      if(n==='criar_link_cliente')return Promise.resolve({data:'TesteTokenSecreto_abcdefghijklmnopqrstuvwxyz012',error:null});
      if(n==='rede_stats')return Promise.resolve({data:{trabalhos:8,elementos:34,no_prazo:100,dias_medio:0.4,desde:'2026-09-02',tipos:[{nome:'Coroa sobre implante',n:4},{nome:'Faceta',n:2},{nome:'Placa de bruxismo',n:1},{nome:'Protocolo',n:1}]},error:null});
      if(n==='sou_admin')return Promise.resolve({data:true,error:null});
      if(n==='admin_metricas')return Promise.resolve({data:[
        {user_id:U,visto_em:new Date().toISOString(),dispositivo:'computador',seg_hoje:5400,seg_7d:36000,seg_30d:140000,seg_total:260000,dias_ativos_30:22,pedidos_total:312,pedidos_30d:48,clientes_total:27,cidade:'São Paulo',uf:'SP'},
        {user_id:'eeee',visto_em:new Date(Date.now()-3*36e5).toISOString(),dispositivo:'celular',seg_hoje:0,seg_7d:7200,seg_30d:21000,seg_total:21000,dias_ativos_30:6,pedidos_total:14,pedidos_30d:14,clientes_total:4,cidade:'Belo Horizonte',uf:'MG'},
        {user_id:'ffff',visto_em:null,dispositivo:null,seg_hoje:0,seg_7d:0,seg_30d:0,seg_total:0,dias_ativos_30:0,pedidos_total:0,pedidos_30d:0,clientes_total:0,cidade:null,uf:null}],error:null});
      if(n==='admin_assinantes')return Promise.resolve({data:[
        {user_id:U,email:'dan@x.com',nome:'Danilo',telefone:'',cidade:'São Paulo',plano:'vitrine',status:'ativa',teste_ate:null,vence_em:null,limite_bytes:53687091200,bytes_usados:0,cadastro:new Date().toISOString(),ultimo_acesso:new Date().toISOString(),admin:true},
        {user_id:'eeee',email:'ana@lab.com',nome:'Ana Cadista',telefone:'(31) 9999-0000',cidade:'BH',plano:'basico',status:'teste',teste_ate:new Date(Date.now()+5*864e5).toISOString(),vence_em:null,limite_bytes:5368709120,bytes_usados:120000000,cadastro:new Date(Date.now()-9*864e5).toISOString(),ultimo_acesso:new Date().toISOString(),admin:false},
        {user_id:'ffff',email:'beto@cad.com',nome:'Beto',telefone:'',cidade:'',plano:'basico',status:'teste',teste_ate:new Date(Date.now()-2*864e5).toISOString(),vence_em:null,limite_bytes:5368709120,bytes_usados:0,cadastro:new Date(Date.now()-16*864e5).toISOString(),ultimo_acesso:null,admin:false}],error:null});
      return Promise.resolve({data:null,error:null});},
    storage:{from:function(b){return {
      upload:function(p,blob,o){window.__ops.push({op:'upload',b:b,p:p,size:blob.size,type:blob.type});window.__blobs=window.__blobs||{};window.__blobs[p]=URL.createObjectURL(blob);return Promise.resolve({data:{path:p},error:null});},
      createSignedUrls:function(ps){return Promise.resolve({data:ps.map(function(p){return {path:p,signedUrl:(window.__blobs||{})[p]||''};}),error:null});},
      remove:function(ps){window.__ops.push({op:'remove',b:b,ps:ps});return Promise.resolve({data:[],error:null});}};}},
    functions:{invoke:function(n,o){window.__ops.push({op:'fn',name:n,body:o.body});if(n==='arquivos'){var b=o.body||{};if(b.acao==='preparar')return Promise.resolve({data:{key:'k/'+b.pedido_id+'/x.zip',url:location.origin+'/__put'},error:null});if(b.acao==='confirmar')return Promise.resolve({data:{id:(crypto.randomUUID?crypto.randomUUID():String(Math.random())),pedido_id:b.pedido_id,origem:'upload',nome:b.nome,tamanho_zip:window.__putSize||1,tamanho_original:b.tamanho_original,criado_em:new Date().toISOString()},error:null});if(b.acao==='baixar')return Promise.resolve({data:{url:location.origin+'/__get'},error:null});}if(n==='clima')return Promise.resolve({data:{temp:24.6,simbolo:window.__simbolo||'partlycloudy_day',min:17.2,max:28.9,atualizado:new Date().toISOString(),fonte:'MET Norway'},error:null});return Promise.resolve({data:{ok:true},error:null});}}
  };
  window.supabase={createClient:function(){return client;}};
  window.__U=U;
})();
