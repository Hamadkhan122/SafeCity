# Features for the real screen photos downloaded by 21_download_screen_photos.py
# (phones held in hand, monitors, TVs, laptop screens - photos where a screen is the main subject).
# Expects them (max 640 px) in data_extra/screen_web/. Split by search query.
import glob, numpy as np, random
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
F=sorted(glob.glob("data_extra/screen_web/*"))
src=lambda f: f.replace("\\","/").split("/")[-1].rsplit("_",1)[0]
srcs=sorted(set(map(src,F))); random.Random(3).shuffle(srcs); te=set(srcs[:2])
for s,sel in [("train",[f for f in F if src(f) not in te]),("test",[f for f in F if src(f) in te])]:
    V=3 if s=="train" else 1
    np.savez(f"embsw_{s}.npz",X=np.stack([emb(sel,v) for v in range(V)]),y=np.full(len(sel),5),f=np.array(sel)); print(s,len(sel),te,flush=True)
