(function (root, factory) {
  var api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.RawiEngine = api;
})(this, function () {
'use strict';
/* ====================== cleanup engine (approximates the app) ====================== */
var EN_FILL={um:1,umm:1,uh:1,uhh:1,uhm:1,er:1,erm:1,ah:1,hmm:1,hm:1};
var AR_FILL={'اممم':1,'امم':1,'ااه':1,'اه':1,'همم':1,'ممم':1,'اااا':1};
var LEAD={so:1,okay:1,ok:1,well:1,'يعني':1,'طيب':1};
var MARK=[['sorry','i','mean'],['no','i','mean'],['i','mean'],['no','wait'],['لا','قصدي'],['لا','اقصد'],['قصدي'],['اقصد']];
var ORD={en:['first','second','third','fourth','fifth'],ar:['اولا','ثانيا','ثالثا','رابعا','خامسا']};
var DAYS=/\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/gi;
function na(w){return w.toLowerCase().replace(/[.,!?؟،:;"“”()]/g,'').replace(/[ً-ٟـ]/g,'').replace(/[أإآ]/g,'ا').replace(/ى/g,'ي')}
function arN(s){return (s.match(/[؀-ۿ]/g)||[]).length}
function lnN(s){return (s.match(/[A-Za-z]/g)||[]).length}
function clean(raw){
  var w=raw.trim().split(/\s+/).filter(Boolean).map(function(x){return{w:x,n:na(x),del:0}});
  var fills=0,corr=0,i,j,lead=true;
  for(i=0;i<w.length;i++){
    if(EN_FILL[w[i].n]||AR_FILL[w[i].n]){w[i].del='f';fills++;continue}
    if(lead&&LEAD[w[i].n]){w[i].del='f';fills++;continue}
    lead=false;
  }
  for(i=0;i<w.length;i++){
    if(w[i].del)continue;
    for(var m=0;m<MARK.length;m++){
      var mk=MARK[m],ok=true,idx=[],p=i;
      for(var k=0;k<mk.length;k++){while(p<w.length&&w[p].del)p++;if(p>=w.length||w[p].n!==mk[k]){ok=false;break}idx.push(p);p++}
      if(!ok)continue;
      var nxt=p;while(nxt<w.length&&w[nxt].del)nxt++;
      var prev=i-1;while(prev>=0&&w[prev].del)prev--;
      if(nxt>=w.length||prev<0)continue;
      w[prev].del='c';idx.forEach(function(x){w[x].del='c'});corr++;
      break;
    }
  }
  var kept=w.filter(function(x){return!x.del}).map(function(x){return x.w});
  var joined=kept.join(' '),text,list=false;
  var ordL=arN(joined)>lnN(joined)?ORD.ar:ORD.en;
  var pos=[],from=0;
  for(j=0;j<ordL.length;j++){
    var f=-1;for(i=from;i<kept.length;i++){if(na(kept[i])===ordL[j]){f=i;break}}
    if(f<0)break;pos.push(f);from=f+1;
  }
  if(pos.length>=2){
    list=true;
    var intro=kept.slice(0,pos[0]).join(' ');
    var items=pos.map(function(s,q){return kept.slice(s+1,q+1<pos.length?pos[q+1]:kept.length).join(' ').replace(/[,،]\s*$/,'').replace(/\s+(and|و)$/i,'')});
    text=(intro?polish(intro,true)+':\n':'')+items.map(function(t,q){return(q+1)+'. '+cap1(t)}).join('\n');
  }else text=polish(joined,false);
  var A=arN(text),L=lnN(text);
  return{tokens:w,text:text,tag:A&&L>=3?'AR + EN':(A?'AR':'EN'),fills:fills,corr:corr,list:list};
}
function cap1(s){return s.replace(/^([a-z])/,function(c){return c.toUpperCase()})}
function polish(s,noEnd){
  if(!s)return s;
  s=s.replace(/\bi\b/g,'I').replace(DAYS,function(d){return d[0].toUpperCase()+d.slice(1).toLowerCase()});
  s=s.replace(/(^|[.!?]\s+)([a-z])/g,function(m,a,b){return a+b.toUpperCase()});
  if(arN(s))s=s.replace(/,/g,'،');
  if(!noEnd&&!/[.!?؟]$/.test(s)){
    var fw=s.split(/\s+/)[0].toLowerCase();
    var q=/^(what|when|where|why|how|who|can|could|would|should|do|does|did|is|are|will|هل|متى|وين|ليش|كيف|وش|ايش|كم|اين|أين|لماذا|ماذا)$/.test(fw);
    s+=q?(arN(s)>lnN(s)?'؟':'?'):'.';
  }
  return s;
}


return { clean: clean, polish: polish, na: na };
});
