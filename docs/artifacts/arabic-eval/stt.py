import os,sys,json,re,subprocess,unicodedata,concurrent.futures as cf
from corpus import C
for l in open(os.path.expanduser("~/.config/rawi/.env")):
    if l.startswith("GROQ_API_KEY="): KEY=l.split("=",1)[1].strip().strip('"')
def norm(s):
    s=unicodedata.normalize("NFKC",s)
    s=re.sub(r"[ً-ْـ]","",s)            # diacritics, tatweel
    s=s.replace("أ","ا").replace("إ","ا").replace("آ","ا").replace("ى","ي").replace("ة","ه")
    s=re.sub(r"[^\w\s]"," ",s.lower()); return " ".join(s.split())
def ed(a,b):
    p=list(range(len(b)+1))
    for i,x in enumerate(a,1):
        c=[i]
        for j,y in enumerate(b,1): c.append(min(p[j]+1,c[-1]+1,p[j-1]+(x!=y)))
        p=c
    return p[-1]
def cer(ref,hyp):
    r,h=norm(ref),norm(hyp); return ed(r,h)/max(1,len(r))
def call(path,lang=None,prompt=None,model="whisper-large-v3-turbo"):
    cmd=["curl","-s","https://api.groq.com/openai/v1/audio/transcriptions","-H",f"Authorization: Bearer {KEY}",
         "-F",f"model={model}","-F","temperature=0","-F","response_format=verbose_json","-F",f"file=@{path}"]
    if lang: cmd+=["-F",f"language={lang}"]
    if prompt: cmd+=["-F",f"prompt={prompt}"]
    import time
    for attempt in range(6):
        d=json.loads(subprocess.run(cmd,capture_output=True,text=True).stdout)
        if "error" in d and "ate limit" in d["error"].get("message",""):
            m=re.search(r"try again in ([\dhms\.]+)",d["error"]["message"]); time.sleep(8*(attempt+1)); continue
        break
    if "error" in d: return {"error":d["error"].get("message","")[:200]}
    lp=[s["avg_logprob"] for s in d.get("segments",[])]
    return {"lang":d.get("language"),"text":d.get("text","").strip(),"lp":sum(lp)/len(lp) if lp else None}
if __name__=="__main__":
    modes=[("auto",None,None),("ar","ar",None),("en","en",None)]
    jobs=[(id,m) for id,k,s in C for m in modes]
    def run(j):
        id,(name,lang,pr)=j; return id,name,call(f"audio/{id}.wav",lang,pr)
    res={}
    with cf.ThreadPoolExecutor(2) as ex:
        for id,name,r in ex.map(run,jobs): res.setdefault(id,{})[name]=r
    json.dump(res,open("stt_results.json","w"),ensure_ascii=False,indent=1)
    print(f"{'id':12}{'kind':11}{'auto-lang':10}{'cerAuto':8}{'cerAr':7}{'cerEn':7}  auto-text")
    for id,k,segs in C:
        ref=" ".join(t for l,t in segs); r=res[id]
        f=lambda m: f"{cer(ref,r[m]['text']):.2f}" if 'text' in r[m] else 'err'
        print(f"{id:12}{k:11}{str(r['auto'].get('lang')):10}{f('auto'):8}{f('ar'):7}{f('en'):7}  {r['auto'].get('text','')[:60]}")
