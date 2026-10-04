# Extra real photos (free, GitHub):
import numpy as np
#  - DeepQuestAI Fire-Smoke-Dataset (github.com/DeepQuestAI/Fire-Smoke-Dataset, release v1):
#      Fire + Smoke -> fire, Neutral (offices, buses, traffic, rooms) -> normal
#  - Surveillance fight dataset (github.com/seymanurakti/fight-detection-surv-dataset):
#      fight videos -> fighting, noFight videos -> normal (split by video)
# Then extracts features (emb6_*.npz) for scripts_v2/16_train_head_v6.py
import glob, os, random, cv2, shutil
from PIL import Image
R=random.Random(4)
B="FIRE-SMOKE-DATASET/"
for c,lab in [("Fire","fire"),("Smoke","fire"),("Neutral","normal")]:
    fs=sorted(glob.glob(B+"Train/"+c+"/*")); R.shuffle(fs); nv=len(fs)//10
    for s,sub in [("validation",fs[:nv]),("train",fs[nv:]),("test",sorted(glob.glob(B+"Test/"+c+"/*")))]:
        os.makedirs(f"data_extra/v6/{s}/{lab}",exist_ok=True)
        for f in sub:
            try: Image.open(f).convert("RGB").resize((224,224),Image.BOX).save(f"data_extra/v6/{s}/{lab}/fs{c}_{os.path.basename(f).rsplit('.',1)[0]}.jpg",quality=92)
            except Exception as e: pass
print("firesmoke done",flush=True)
for d,lab in [("fight","fighting"),("noFight","normal")]:
    vs=sorted(glob.glob(f"fight-detection-surv-dataset/{d}/*.mp4")); R.shuffle(vs); n=len(vs)
    for vi,v in enumerate(vs):
        s="train" if vi<n*.8 else ("validation" if vi<n*.9 else "test"); k=4 if s=="train" else 2
        c=cv2.VideoCapture(v); N=int(c.get(7))
        for j in range(k):
            c.set(1,int(N*(0.2+0.6*j/max(1,k-1)))); ok,fr=c.read()
            if ok: os.makedirs(f"data_extra/v6/{s}/{lab}",exist_ok=True); Image.fromarray(cv2.cvtColor(fr,cv2.COLOR_BGR2RGB)).resize((224,224),Image.BOX).save(f"data_extra/v6/{s}/{lab}/fsd_{os.path.basename(v)[:-4]}_{j}.jpg",quality=92)
for s in ["train","validation","test"]: print(s,{c:len(os.listdir(f"data_extra/v6/{s}/{c}")) for c in sorted(os.listdir(f"data_extra/v6/{s}"))})

# ---- features ----
import tensorflow as tf
from PIL import Image, ImageEnhance
fe=tf.keras.models.load_model("feat_extractor.keras")
rng=np.random.default_rng(1)
def aug(im):
    w,h=im.size; s=rng.uniform(0.7,1.0); cw,ch=int(w*s),int(h*s); x0=rng.integers(0,w-cw+1); y0=rng.integers(0,h-ch+1)
    im=im.crop((x0,y0,x0+cw,y0+ch)).resize((224,224)); im=ImageEnhance.Brightness(im).enhance(rng.uniform(0.6,1.4))
    return im.transpose(Image.FLIP_LEFT_RIGHT) if rng.random()<.5 else im
def emb(files,v=0):
    out=[];b=[]
    for f in files:
        im=Image.open(f).convert("RGB").resize((224,224))
        if v==1: im=im.transpose(Image.FLIP_LEFT_RIGHT)
        if v==2: im=aug(im)
        b.append(np.asarray(im,np.float32))
        if len(b)==64: out.append(fe.predict(np.stack(b),verbose=0)); b=[]
    if b: out.append(fe.predict(np.stack(b),verbose=0))
    return np.concatenate(out)
L={"accident":0,"fighting":1,"fire":2,"normal":3,"road_damage":4,"screen":5}
for s in ["train","validation","test"]:
    V=3 if s=="train" else 1
    F=sorted(glob.glob(f"data_extra/v6/{s}/*/*")); y=np.array([L[os.path.basename(os.path.dirname(f))] for f in F])
    np.savez(f"emb6_{s}.npz",X=np.stack([emb(F,v) for v in range(V)]),y=y,f=np.array(F)); print(s,flush=True)
