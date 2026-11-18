# the shipped policy end to end: >=2s auto -> v3 + primer; shorter -> turbo no prompt. Fresh calls, not reused results.
from stt import *
import concurrent.futures as cf, os, json, collections
P="أهلا، كيف الحال؟ Let's talk about the project. يعني خلنا نكمل الشغل tomorrow."
ref={i:" ".join(t for l,t in s) for i,k,s in C}; kind={i:k for i,k,s in C}
def new(i):
    d=(os.path.getsize(f"audio/{i}.wav")-44)/32000
    return call(f"audio/{i}.wav",None,P if d>=2 else None,"whisper-large-v3" if d>=2 else "whisper-large-v3-turbo")
def old(i): return call(f"audio/{i}.wav",None,None,"whisper-large-v3-turbo")
ids=[i for i,_,_ in C]
with cf.ThreadPoolExecutor(2) as ex: N=dict(zip(ids,ex.map(new,ids))); O=dict(zip(ids,ex.map(old,ids)))
for name,R in [("before (turbo auto)",O),("after (policy)",N)]:
    agg=collections.defaultdict(list); fails=[]
    for i in ids:
        c=cer(ref[i],R[i]["text"]); agg[kind[i]].append(c)
        if c>0.3: fails.append(i)
    allv=[x for v in agg.values() for x in v]
    print(name.ljust(20),{k:round(sum(v)/len(v),2) for k,v in agg.items()},"mean",round(sum(allv)/len(allv),3),"fails",len(fails),fails)
