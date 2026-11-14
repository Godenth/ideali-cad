// "Banco de mentira" para os testes de tela: um Supabase falso, na memória da página.
// A tela roda o código DE VERDADE (login, carregamentos, gravações); só o servidor é trocado por isto.
// Uso (Playwright):
//   const {preparar} = require('./banco-de-mentira');
//   await preparar(page, {usuario:{id,email}, db:{tabela:[linhas]}, rpc:{nome: valorOuFuncaoEmTexto}});
//   await page.goto(URL);
// Depois, na página: window.__BANCO (tabelas), window.__CHAMADAS (o que a tela pediu), window.__FALTOU (tabelas sem dados).

function codigo(fix) {
  return `(function(){
  var FIX=${JSON.stringify(fix)};
  var DB=FIX.db||{}, RPC=FIX.rpc||{}, U=FIX.usuario||null;
  window.__BANCO=DB; window.__CHAMADAS=[]; window.__FALTOU={}; window.__GRAVOU=[];
  function uuid(){return 'xxxxxxxx-xxxx-4xxx-8xxx-xxxxxxxxxxxx'.replace(/x/g,function(){return (Math.random()*16|0).toString(16);});}
  function ok(d,extra){var r={data:d,error:null,status:200};if(extra)for(var k in extra)r[k]=extra[k];return r;}
  function Q(t){this.t=t;this.f=[];this.op='select';this.ord=[];this.lim=null;this.rng=null;this.um=0;this.patch=null;this.novos=null;this.ret=false;this.cnt=false;this.head=false;}
  Q.prototype.select=function(c,o){if(this.op!=='select')this.ret=true;if(o&&o.count)this.cnt=true;if(o&&o.head)this.head=true;return this;};
  ['eq','neq','gt','gte','lt','lte','is','like','ilike','in','contains'].forEach(function(op){Q.prototype[op]=function(c,v){this.f.push([op,c,v]);return this;};});
  Q.prototype.not=function(c,op,v){this.f.push(['not_'+op,c,v]);return this;};
  Q.prototype.or=function(){return this;};Q.prototype.match=function(o){for(var k in o)this.f.push(['eq',k,o[k]]);return this;};
  Q.prototype.filter=function(c,op,v){this.f.push([op,c,v]);return this;};
  Q.prototype.order=function(c,o){this.ord.push([c,!(o&&o.ascending===false)]);return this;};
  Q.prototype.limit=function(n){this.lim=n;return this;};Q.prototype.range=function(a,b){this.rng=[a,b];return this;};
  Q.prototype.single=function(){this.um=1;return this;};Q.prototype.maybeSingle=function(){this.um=2;return this;};
  Q.prototype.insert=function(r){this.op='insert';this.novos=Array.isArray(r)?r:[r];return this;};
  Q.prototype.upsert=function(r,o){this.op='upsert';this.novos=Array.isArray(r)?r:[r];this.conf=o&&o.onConflict;return this;};
  Q.prototype.update=function(p){this.op='update';this.patch=p;return this;};
  Q.prototype.delete=function(){this.op='delete';return this;};
  Q.prototype.abortSignal=function(){return this;};Q.prototype.throwOnError=function(){return this;};
  function casa(row,f){var v=row[f[1]],x=f[2];switch(f[0]){
    case 'eq':return v===x||String(v)===String(x);case 'neq':return !(v===x||String(v)===String(x));
    case 'gt':return v>x;case 'gte':return v>=x;case 'lt':return v<x;case 'lte':return v<=x;
    case 'is':return x===null?v==null:v===x;case 'not_is':return x===null?v!=null:v!==x;
    case 'in':return (x||[]).some(function(y){return y===v||String(y)===String(v);});case 'not_in':return true;
    case 'like':case 'ilike':return new RegExp('^'+String(x).replace(/[.*+?^\${}()|[\\]\\\\]/g,'\\\\$&').replace(/%/g,'.*')+'$','i').test(String(v==null?'':v));
    case 'contains':return true;default:return true;}}
  Q.prototype.roda=function(){var self=this,T=DB[this.t];if(!T){window.__FALTOU[this.t]=(window.__FALTOU[this.t]||0)+1;T=DB[this.t]=[];}
    var sel=function(){return T.filter(function(r){return self.f.every(function(f){return casa(r,f);});});},d;
    if(this.op==='select'){d=sel();var n=d.length;this.ord.slice().reverse().forEach(function(o){d.sort(function(a,b){var x=a[o[0]],y=b[o[0]];if(x==null&&y==null)return 0;if(x==null)return 1;if(y==null)return -1;return (x<y?-1:x>y?1:0)*(o[1]?1:-1);});});
      if(this.rng)d=d.slice(this.rng[0],this.rng[1]+1);if(this.lim!=null)d=d.slice(0,this.lim);
      d=JSON.parse(JSON.stringify(d));if(this.head)return ok(null,{count:n});
      if(this.um)return d.length?ok(d[0]):(this.um===1?{data:null,error:{code:'PGRST116',message:'no rows'},status:406}:ok(null));return ok(d,this.cnt?{count:n}:null);}
    if(this.op==='insert'||this.op==='upsert'){var out=[];this.novos.forEach(function(r){var ex=null;
        if(self.op==='upsert'){var ks=(self.conf||'id').split(',');ex=T.filter(function(x){return ks.every(function(k){return x[k]!=null&&String(x[k])===String(r[k]);});})[0];}
        if(ex){for(var k in r)ex[k]=r[k];out.push(ex);}else{var n2={};for(var k2 in r)n2[k2]=r[k2];if(n2.id==null)n2.id=uuid();if(n2.criado_em==null)n2.criado_em=new Date().toISOString();if(n2.user_id==null&&U)n2.user_id=U.id;T.push(n2);out.push(n2);}});
      window.__GRAVOU.push({t:this.t,op:this.op,n:out.length});d=JSON.parse(JSON.stringify(out));return this.um?ok(d[0]||null):ok(this.ret?d:null);}
    if(this.op==='update'){d=sel();d.forEach(function(r){for(var k in self.patch)r[k]=self.patch[k];});window.__GRAVOU.push({t:this.t,op:'update',n:d.length,patch:this.patch});d=JSON.parse(JSON.stringify(d));return this.um?ok(d[0]||null):ok(this.ret?d:null);}
    if(this.op==='delete'){d=sel();d.forEach(function(r){T.splice(T.indexOf(r),1);});window.__GRAVOU.push({t:this.t,op:'delete',n:d.length});return ok(this.ret?d:null);}
    return ok(null);};
  Q.prototype.then=function(a,b){var self=this;return new Promise(function(res){setTimeout(function(){var r;try{r=self.roda();}catch(e){r={data:null,error:{message:String(e)}};}res(r);},FIX.atraso||5);}).then(a,b);};
  Q.prototype.catch=function(b){return this.then(null,b);};
  function rpc(n,args){window.__CHAMADAS.push(n);var v=RPC[n],r;
    if(v&&typeof v==='object'&&v.__erro)r={data:null,error:v.__erro};
    else if(typeof v==='string'&&v.indexOf('function')===0){try{r=ok((new Function('return ('+v+')'))()(args||{},DB,U));}catch(e){r={data:null,error:{message:String(e)}};}}
    else if(v!==undefined)r=ok(JSON.parse(JSON.stringify(v)));
    else if(n==='sou_admin')r=ok(false);
    else r={data:null,error:{code:'PGRST202',message:'Could not find the function public.'+n+' in the schema cache'}};
    var q={then:function(a,b){return new Promise(function(res){setTimeout(function(){res(r);},FIX.atraso||5);}).then(a,b);},catch:function(b){return this.then(null,b);},single:function(){return this;},maybeSingle:function(){return this;},select:function(){return this;}};return q;}
  var ouvintes=[],sess=U?{user:U,access_token:'falso',expires_at:9999999999}:null;
  var cli={
    from:function(t){return new Q(t);},rpc:rpc,
    auth:{onAuthStateChange:function(cb){ouvintes.push(cb);setTimeout(function(){cb(sess?'SIGNED_IN':'INITIAL_SESSION',sess);},20);return {data:{subscription:{unsubscribe:function(){}}}};},
      getSession:function(){return Promise.resolve({data:{session:sess},error:null});},getUser:function(){return Promise.resolve({data:{user:U},error:null});},
      signOut:function(){sess=null;ouvintes.forEach(function(cb){cb('SIGNED_OUT',null);});return Promise.resolve({error:null});},
      signInWithPassword:function(){sess={user:U};ouvintes.forEach(function(cb){cb('SIGNED_IN',sess);});return Promise.resolve({data:{session:sess,user:U},error:null});},
      signUp:function(){return Promise.resolve({data:{user:U,session:sess},error:null});},resetPasswordForEmail:function(){return Promise.resolve({data:{},error:null});},
      updateUser:function(){return Promise.resolve({data:{user:U},error:null});},mfa:{listFactors:function(){return Promise.resolve({data:{totp:[],all:[]},error:null});},getAuthenticatorAssuranceLevel:function(){return Promise.resolve({data:{currentLevel:'aal1',nextLevel:'aal1'},error:null});}}},
    storage:{from:function(b){return {createSignedUrl:function(p){return Promise.resolve({data:{signedUrl:'about:blank#'+p},error:null});},
      createSignedUrls:function(ps){return Promise.resolve({data:(ps||[]).map(function(p){return {path:p,signedUrl:'about:blank#'+p,error:null};}),error:null});},
      upload:function(p){window.__GRAVOU.push({t:'storage:'+b,op:'upload',path:p});return Promise.resolve({data:{path:p},error:null});},remove:function(){return Promise.resolve({data:[],error:null});},
      list:function(){return Promise.resolve({data:[],error:null});},download:function(){return Promise.resolve({data:new Blob(['x']),error:null});},getPublicUrl:function(p){return {data:{publicUrl:'about:blank#'+p}};}};}},
    functions:{invoke:function(n){window.__CHAMADAS.push('fn:'+n);return Promise.resolve({data:null,error:{message:'sem servidor no teste'}});}},
    channel:function(){var c={on:function(){return c;},subscribe:function(){return c;},unsubscribe:function(){return c;}};return c;},removeChannel:function(){},removeAllChannels:function(){}
  };
  window.supabase={createClient:function(){return cli;}};
})();`;
}

async function preparar(page, fix) {
  // a biblioteca verdadeira e as fontes de fora não entram no teste
  await page.route(/supabase-js|fonts\.googleapis|fonts\.gstatic|open-meteo|ipapi|ipwho|nominatim|youtube|ytimg/, r => r.abort());
  await page.addInitScript(codigo(fix));
}
module.exports = { preparar, codigo };
