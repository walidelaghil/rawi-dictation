/* Rawi landing page: UI. Copy and demo data live in copy.js, cleanup in engine.js. */
(function(){
'use strict';
var clean=RawiEngine.clean,polish=RawiEngine.polish,na=RawiEngine.na;
/* ====================== helpers + state ====================== */
var $=function(s,r){return(r||document).querySelector(s)},$$=function(s,r){return Array.prototype.slice.call((r||document).querySelectorAll(s))};
var RM=window.matchMedia&&matchMedia('(prefers-reduced-motion: reduce)').matches;
function esc(s){return String(s).replace(/[&<>"]/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
function tk(tokens){return tokens.map(function(x){return x.del?'<del class="'+(x.del==='c'?'c':'f')+'">'+esc(x.w)+'</del>':esc(x.w)}).join(' ')}
var S={ui:'ar',speak:'ar',fx:0,de:'Slack',dc:false,sn:0,cm:0,cmDone:false,tf:0,last:null,hrs:80,rate:50};
function t(k){return T[S.ui][k]}
function fade(el){if(RM)return;el.classList.remove('fade');void el.offsetWidth;el.classList.add('fade')}
function mkTabs(host,labels,cur,on,keys){
  host.innerHTML='';
  labels.forEach(function(l,i){
    var b=document.createElement('button');b.type='button';b.className='tab';b.setAttribute('role','tab');
    b.setAttribute('aria-selected',String(keys?keys[i]===cur:i===cur));b.textContent=l;
    b.addEventListener('click',function(){on(keys?keys[i]:i)});host.appendChild(b);
  });
}

/* ====================== hero demo ====================== */
function waveBars(){var h='';for(var i=0;i<34;i++){var v=14+Math.round(46*Math.abs(Math.sin(i*.55))*(.55+.45*Math.abs(Math.cos(i*.21))));h+='<i style="--i:'+i+';--h:'+v+'px"></i>'}return h}
$('#wave').innerHTML=waveBars();
var typing=null;
function typeInto(el,text,instant){
  clearInterval(typing);el.classList.remove('ph');
  if(instant||RM){el.textContent=text;return}
  var i=0,c=document.createElement('span');c.className='caret';el.textContent='';
  typing=setInterval(function(){i+=2;el.textContent=text.slice(0,i);el.appendChild(c);if(i>=text.length){clearInterval(typing);c.remove()}},14);
}
var pend=null;
function showWave(on){var w=$('#wave');if(w)w.hidden=!on}
function process(raw){
  raw=(raw||'').trim();if(!raw)return;
  clearTimeout(pend);
  if(RM){render(raw);return}
  showWave(true);
  pend=setTimeout(function(){showWave(false);render(raw)},450);
}
function render(raw){
  var r=clean(raw);S.last=raw;
  $('#heard').innerHTML='<span class="lbl">'+esc(t('heardL'))+': </span>'+tk(r.tokens);
  $('#tag').textContent=r.tag;
  typeInto($('#typed'),r.text);
  var c=[];if(r.fills)c.push(t('fill')(r.fills));if(r.corr)c.push(t('corr'));if(r.list)c.push(t('list'));c.push(t('punct'));
  $('#notes').innerHTML='<span class="lbl">'+esc(t('did'))+'</span>'+c.map(function(x){return'<span class="chip">'+esc(x)+'</span>'}).join('');
}
function resetOut(){
  $('#typed').className='ph';$('#typed').textContent=t('empty');$('#heard').innerHTML='';$('#notes').innerHTML='';$('#tag').textContent=S.speak==='ar'?'AR':'EN';
}
function buildSamples(){
  var h=$('#samples');h.innerHTML='<span class="lbl">'+esc(t('samples'))+'</span>';
  SAMPLES.forEach(function(s){var b=document.createElement('button');b.type='button';b.className='chip';b.textContent=s.n[S.ui];
    b.addEventListener('click',function(){S.speak=s.l;syncSeg();$('#typeIn').value=s.t;process(s.t)});h.appendChild(b)});
}
function syncSeg(){$$('[data-sl]').forEach(function(x){x.setAttribute('aria-pressed',String(x.dataset.sl===S.speak))})}
$$('[data-sl]').forEach(function(b){b.addEventListener('click',function(){S.speak=b.dataset.sl;syncSeg()})});
var typeTimer=null;
$('#typeIn').addEventListener('input',function(){clearTimeout(typeTimer);var v=this.value;typeTimer=setTimeout(function(){if(v.trim())process(v);else resetOut()},450)});


/* ====================== sections ====================== */
function renderFx(){
  mkTabs($('#fxTabs'),t('fxTabs'),S.fx,function(i){S.fx=i;renderFx()});
  var r=clean(FX[S.ui][S.fx]);
  $('#fxPanel').innerHTML='<div><span class="lbl">'+esc(t('said'))+'</span><div class="big" dir="auto">'+tk(r.tokens)+'</div></div><div><span class="lbl">'+esc(t('typedS'))+'</span><div class="big" dir="auto">'+esc(r.text)+'</div></div><div class="why">'+esc(t('fxWhy')[S.fx])+'</div>';
  fade($('#fxPanel'));
}
function renderDe(){
  var keys=['Slack','Jira','Mail','Docs'];
  mkTabs($('#deTabs'),keys,S.de,function(k){S.de=k;renderDe()},keys);
  $('#deSaid').innerHTML='<span class="lbl">'+esc(t('snSaid'))+'</span>'+esc(DEST.said[S.ui]);
  var o=$('#deOut');o.innerHTML='<span class="lbl">'+esc(S.de)+'</span>'+esc(DEST[S.ui][S.de]);fade(o);
}
function renderDc(){
  var heard=S.dc?'Rawi':'Rawal';
  $('#dcSent').innerHTML=esc(t('dcS')(heard)).replace(heard,S.dc?'<mark>'+heard+'</mark>':'<span class="hot">'+heard+'</span>');
  var b=$('#dcBtn');b.textContent=S.dc?t('dcReset'):t('dcBtn');
  $('#dcOk').textContent=S.dc?t('dcOk'):'';
  $('#dcList').innerHTML=S.dc?'<span class="chip">Rawi</span>':'';
}
$('#dcBtn').addEventListener('click',function(){S.dc=!S.dc;renderDc()});
function renderSn(){
  var h=$('#snTrig');h.innerHTML='<span class="lbl">'+esc(t('snSaid'))+'</span>';
  SNIP.forEach(function(s,i){var b=document.createElement('button');b.type='button';b.className='chip';b.setAttribute('aria-pressed',String(i===S.sn));b.textContent=s.k[S.ui];
    b.addEventListener('click',function(){S.sn=i;renderSn()});h.appendChild(b)});
  var s=SNIP[S.sn],o=$('#snOut');
  o.innerHTML='<span class="lbl">'+esc(s.s[S.ui])+'</span><span dir="auto">'+esc(s.sv[S.ui])+'<mark dir="ltr">'+esc(s.v)+'</mark></span>';fade(o);
}
function renderCmd(){
  var l=$('#cmdList');l.innerHTML='';
  CMDS.forEach(function(c,i){var b=document.createElement('button');b.type='button';b.className='cmd';b.setAttribute('aria-pressed',String(i===S.cm));
    b.innerHTML='<b dir="ltr">'+esc(c.k)+'</b>'+(c.off?'<span>'+esc(t('cmOff'))+'</span>':'');
    b.addEventListener('click',function(){S.cm=i;S.cmDone=false;S.cmWave=true;renderCmd()});l.appendChild(b)});
  var c=CMDS[S.cm],sd=c.said[S.ui];
  var p=$('#cmdPill');
  p.innerHTML='<div><span class="lbl">'+esc(t('cmSaid'))+'</span><div class="said"><b dir="ltr">'+esc(sd[0])+'</b> '+esc(sd[1])+'</div></div>'+
   '<div class="will"><span class="lbl">'+esc(t('cmWill'))+'</span><p>'+esc(c.will[S.ui])+'</p>'+
   (S.cmDone?'<span class="ok">'+esc(t('cmDone'))+'</span>':'<div class="row"><button class="btn pri sm" id="cmRun" type="button">'+esc(t('cmRun'))+'</button><button class="btn sm" id="cmNo" type="button">'+esc(t('cmCancel'))+'</button></div>')+'</div>'+
   '<p class="times">'+esc(t('cmTimes'))+'</p>';
  var r=$('#cmRun');if(r)r.addEventListener('click',function(){S.cmDone=true;renderCmd()});
  var n=$('#cmNo');if(n)n.addEventListener('click',function(){S.cmDone=false;renderCmd()});
  if(S.cmWave){S.cmWave=false;if(!RM){var w=document.createElement('div');w.className='wave';w.setAttribute('aria-hidden','true');w.innerHTML=waveBars();p.appendChild(w);setTimeout(function(){w.remove()},450)}}
}
function renderTf(){
  $('#tfSrc').textContent=TF_SRC;
  var h=$('#tfSay');h.innerHTML='<span class="lbl">'+esc(t('tfSay'))+'</span>';
  TF.forEach(function(x,i){var b=document.createElement('button');b.type='button';b.setAttribute('aria-pressed',String(i===S.tf));b.textContent=x.n[S.ui];
    b.addEventListener('click',function(){S.tf=i;S.tfWave=true;renderTf()});h.appendChild(b)});
  var hint=document.createElement('p');hint.className='hint';hint.textContent=t('tfHint');h.appendChild(hint);
  var x=TF[S.tf],r=$('#tfRes');r.textContent=x.o;r.className='res'+(x.ar?' rtl':'');r.lang=x.ar?'ar':'en';r.dir=x.ar?'rtl':'ltr';
  if(S.tfWave){S.tfWave=false;if(!RM){var pn=r.parentNode,w=document.createElement('div');w.className='wave';w.setAttribute('aria-hidden','true');w.innerHTML=waveBars();pn.appendChild(w);setTimeout(function(){w.remove()},450)}}
}
function renderStatic(){
  $('#imgIn').alt=t('imgIn');$('#imgVc').alt=t('imgVc');
  $('#pvGrid').innerHTML=t('pv').map(function(x){return'<div><h3>'+esc(x[0])+'</h3><p>'+esc(x[1])+'</p></div>'}).join('');
  (function(){
        var BUILD=90,MAINT=30;
    var me=[['https://www.waleedelaghil.com/','Website','<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3.2 3 14.8 0 18M12 3c-3 3.2-3 14.8 0 18"/>'],['https://www.linkedin.com/in/waleed-elaghil/','LinkedIn','<rect x="3" y="3" width="18" height="18" rx="4"/><path d="M8 10v6M8 7.5v.01M12 16v-6M12 12.5c0-1.4 1-2.5 2.4-2.5s2.1 1 2.1 2.6V16"/>'],['https://waleedelaghil.substack.com/','Substack','<path d="M5 4h14M5 8h14M5 12h14v9l-7-4-7 4z"/>']];
    $('#offer').innerHTML='<div class="of-a"><span class="badge">'+esc(t('ofBadge'))+'</span><h2 data-h="ofH"></h2>'
      +'<div class="of-price" aria-label="$29, was $40"><span class="now"><sup>$</sup>29</span><span class="was">$40</span></div>'
      +'<p class="of-note">'+esc(t('ofNote'))+'</p>'
      +'<div class="of-cta"><a class="btn pri" href="#buy" aria-disabled="true">'+esc(t('ofBuy'))+'</a><a class="btn" href="https://github.com/walidelaghil/rawi-dictation" target="_blank" rel="noopener noreferrer">'+esc(t('ofVibe'))+'</a></div>'
      +'<p class="of-fine">'+esc(t('ofFine'))+'</p>'
      +'<div class="of-by"><div class="of-me"><img src="assets/waleed.png" width="48" height="48" alt="Waleed Elaghil"><div><small>'+esc(t('ofBy'))+'</small><b dir="ltr">Waleed Elaghil</b></div></div><div class="of-links">'
      +me.map(function(x){return'<a href="'+x[0]+'" target="_blank" rel="noopener noreferrer" aria-label="'+x[1]+'" title="'+x[1]+'"><svg viewBox="0 0 24 24" aria-hidden="true">'+x[2]+'</svg></a>'}).join('')+'</div></div></div>'
      +'<div class="of-b"><div class="phil"><span class="lbl">'+esc(t('phL'))+'</span><h3>'+esc(t('phH'))+'</h3><p>'+esc(t('phP'))+'</p></div>'
      +'<ul class="ticks">'+t('phU').map(function(x){return'<li>'+x+'</li>'}).join('')+'</ul>'
      +'<div class="mcalc"><h4>'+esc(t('mcH'))+'</h4><p class="mc-p">'+esc(t('mcP'))+'</p>'
      +'<div class="mc-row"><span>'+esc(t('mcBuild'))+'</span><b dir="ltr">'+BUILD+' h</b></div>'
      +'<div class="mc-row"><span>'+esc(t('mcMaint'))+'</span><b dir="ltr">~'+MAINT+' h / yr</b></div>'
      +'<label class="mc-in"><span>'+esc(t('mcRate'))+'</span><span class="mc-box" dir="ltr">$<input type="number" id="rIn" min="1" max="1000" value="'+S.rate+'"></span></label>'
      +'<div class="tot" aria-live="polite"><div><span>'+esc(t('mcTot'))+'</span><b id="cDiy"></b></div><div><span>'+esc(t('mcSave'))+'</span><b id="cSave" class="sv"></b></div><small id="cHrs"></small></div></div></div>';
    $$('[data-h]',$('#offer')).forEach(function(e){e.innerHTML=t(e.dataset.h)});
    function upd(){S.rate=Math.max(0,+$('#rIn').value||0);var h=BUILD+MAINT,d=h*S.rate,f=function(n){return'$'+Math.round(n).toLocaleString('en-US')};$('#cDiy').textContent=f(d);$('#cSave').textContent=f(Math.max(0,d-29));$('#cHrs').textContent=t('mcHrs2').replace('{h}',h)}
    $('#rIn').addEventListener('input',upd);upd();
  })();
  $('#faqList').innerHTML=t('fq').map(function(x){return'<details><summary><span>'+esc(x[0])+'</span></summary><p>'+esc(x[1])+'</p></details>'}).join('');
}
function applyLang(){
  var d=document.documentElement;d.lang=S.ui;d.dir=S.ui==='ar'?'rtl':'ltr';
  $$('[data-t]').forEach(function(e){e.textContent=t(e.dataset.t)});
  $$('[data-h]').forEach(function(e){e.innerHTML=t(e.dataset.h)});
  $$('.lang').forEach(function(b){b.textContent=t('lang');b.setAttribute('aria-label',S.ui==='ar'?'Switch to English':'التبديل إلى العربية')});
  $('#typeIn').placeholder=t('ph');
  buildSamples();renderFx();renderDe();renderDc();renderSn();renderCmd();renderTf();renderStatic();
  if(S.last)process(S.last);else resetOut();
}
$$('.lang').forEach(function(b){b.addEventListener('click',function(){S.ui=S.ui==='ar'?'en':'ar';S.speak=S.ui;syncSeg();applyLang()})});
(function(){var n=$('.nav'),on=false;function f(){var v=window.scrollY>260;if(v!==on){on=v;n.classList.toggle('show',v)}}window.addEventListener('scroll',f,{passive:true});f()})();

/* ====================== reveal on scroll (IntersectionObserver) ====================== */
if('IntersectionObserver' in window&&!RM){
  var io=new IntersectionObserver(function(es){es.forEach(function(e){if(e.isIntersecting){e.target.classList.add('in');io.unobserve(e.target)}})},{threshold:.08});
  $$('.rv').forEach(function(e){io.observe(e)});
}else $$('.rv').forEach(function(e){e.classList.add('in')});

applyLang();
/* start with a real example already shown, so the first screen has something to read */
S.speak='ar';syncSeg();$('#typeIn').value=SAMPLES[0].t;process(SAMPLES[0].t);

(function(){
  var md=$('#modal'),last=null;
  function open(from){
    last=from||document.activeElement;md.hidden=false;document.body.classList.add('mopen');
    requestAnimationFrame(function(){md.classList.add('open');$('.mx',md).focus()});
  }
  function close(){
    md.classList.remove('open');document.body.classList.remove('mopen');
    setTimeout(function(){md.hidden=true},RM?0:250);
    if(last&&last.focus)last.focus();
  }
  document.addEventListener('click',function(e){
    var a=e.target.closest('a[href="#pricing"],a[href="#buy"]');
    if(a){e.preventDefault();if(a.getAttribute('href')==='#pricing')open(a);return}
    if(e.target===md||e.target.closest('.mx'))close();
  });
  document.addEventListener('keydown',function(e){if(e.key==='Escape'&&!md.hidden)close()});
})();
})();
