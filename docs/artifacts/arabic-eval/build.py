import subprocess,os,wave,sys
from corpus import C,AR,EN
V={"ar":AR,"en":EN}
for id,kind,segs in C:
    parts=[]
    for i,(l,t) in enumerate(segs):
        a=f"audio/{id}.{i}.aiff"; w=f"audio/{id}.{i}.wav"
        subprocess.run(["say","-v",V[l],"-o",a,t],check=True)
        subprocess.run(["ffmpeg","-y","-loglevel","error","-i",a,"-ar","16000","-ac","1",w],check=True)
        parts.append(w)
    out=f"audio/{id}.wav"
    with wave.open(out,"wb") as o:
        o.setnchannels(1);o.setsampwidth(2);o.setframerate(16000)
        for p in parts:
            with wave.open(p) as r: o.writeframes(r.readframes(r.getnframes()))
            o.writeframes(b"\x00\x00"*3200)
    for p in parts: os.remove(p); os.remove(p.replace(".wav",".aiff"))
print("built",len(C))
