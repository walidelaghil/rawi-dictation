from pol import *; from polcases import CASES
import concurrent.futures as cf, sys, json
AR_RULES = "\n\nLanguage: write the result in the same language and script the speaker used. Never translate. Arabic stays Arabic, English words stay in English letters exactly where they were spoken, and a sentence that mixes both keeps both."
RULES2 = """

Language: write the result in the same language and script the speaker used. Never translate. Arabic stays Arabic. English words stay in English letters exactly where they were spoken, and a sentence that mixes both keeps both.
Arabic dialect is the speaker's own voice, not an error. Keep dialect words as spoken (عايز، دلوقتي، ابغى، وش، شو، بكرة) and do not rewrite them into formal Arabic. Keep the spelling as dictated and do not add diacritics or tanween."""
VARIANTS={
 "120b shipped":("openai/gpt-oss-120b",SHIPPED,"low"),
 "120b +rules2":("openai/gpt-oss-120b",SHIPPED+RULES2,"low"),
 "20b +rules2":("openai/gpt-oss-20b",SHIPPED+RULES2,"low"),
}
def check(c,out):
    id,raw,must,mn=c; fails=[]
    if arabic_ratio(raw)>0 and arabic_ratio(out)<arabic_ratio(raw)*0.6: fails.append("translated/less Arabic")
    lw=set(latin_words(raw)); ow=set(latin_words(out))
    miss=[w for w in lw if w not in ow and w!="um"]
    if miss: fails.append("lost Latin: "+",".join(miss))
    for m in must:
        if m not in out: fails.append("missing '"+m+"'")
    for m in mn:
        if m in out: fails.append("still has '"+m+"'")
    if re.search(r"[ً-ْ]",out) and not re.search(r"[ً-ْ]",raw): fails.append("added tashkeel")
    return fails
res={}
def run(j):
    v,c=j; m,s,e=VARIANTS[v]; out,err,t=chat(m,s,f"<transcript>{c[1]}</transcript>",e); return v,c[0],out,err,t
with cf.ThreadPoolExecutor(3) as ex:
    for v,i,out,err,t in ex.map(run,[(v,c) for r in range(3) for v in VARIANTS for c in CASES]): res.setdefault(v,{}).setdefault(i,[]).append((out,err,t))
json.dump(res,open("exp5.json","w"),ensure_ascii=False,indent=1)
for v in VARIANTS:
    tot=0;ok=0;lat=[];bad={}
    for c in CASES:
        for out,err,t in res[v][c[0]]:
            tot+=1; lat.append(t); f=check(c,out) if out else ["ERR"]
            if not f: ok+=1
            else: bad.setdefault(c[0],[]).append(f[0])
    print(f"== {v}: {ok}/{tot} pass, median {sorted(lat)[len(lat)//2]:.2f}s  fails: { {k:len(x) for k,x in bad.items()} }")
