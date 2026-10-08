import glob, numpy as np, tensorflow as tf
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
for s in ["train","validation","test"]:
    F=sorted(glob.glob(f"data/{s}/screen/*")); V=3 if s=="train" else 1
    np.savez(f"embs_{s}.npz",X=np.stack([emb(F,v) for v in range(V)]),f=np.array(F)); print(s,flush=True)
