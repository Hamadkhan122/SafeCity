import os, glob, numpy as np, tensorflow as tf
from PIL import Image, ImageEnhance
M="models/safecity_mobilenetv2_fighting_finetuned.keras"
m=tf.keras.models.load_model(M)
inp=tf.keras.Input((224,224,3)); x=m.get_layer("rescaling")(inp); x=m.get_layer("mobilenetv2_1.00_224")(x, training=False); x=m.get_layer("global_average_pooling2d")(x)
fe=tf.keras.Model(inp,x); fe.save("feat_extractor.keras")
CL=["accident","fighting","fire","normal","road_damage"]
rng=np.random.default_rng(0)
def aug(im):
    w,h=im.size; s=rng.uniform(0.7,1.0); cw,ch=int(w*s),int(h*s); x0=rng.integers(0,w-cw+1); y0=rng.integers(0,h-ch+1)
    im=im.crop((x0,y0,x0+cw,y0+ch)).resize((224,224))
    im=ImageEnhance.Brightness(im).enhance(rng.uniform(0.6,1.4)); im=ImageEnhance.Color(im).enhance(rng.uniform(0.6,1.4))
    if rng.random()<0.5: im=im.transpose(Image.FLIP_LEFT_RIGHT)
    return im
for split in ["train","validation","test"]:
    X=[];Y=[];F=[]
    for ci,c in enumerate(CL):
        for f in sorted(glob.glob(f"data/{split}/{c}/*")): F.append(f);Y.append(ci)
    variants=3 if split=="train" else 1
    for v in range(variants):
        batch=[];out=[]
        for f in F:
            im=Image.open(f).convert("RGB").resize((224,224))
            if v==1: im=im.transpose(Image.FLIP_LEFT_RIGHT)
            if v==2: im=aug(im)
            batch.append(np.asarray(im,np.float32))
            if len(batch)==64: out.append(fe.predict(np.stack(batch),verbose=0)); batch=[]
        if batch: out.append(fe.predict(np.stack(batch),verbose=0))
        X.append(np.concatenate(out)); print(split,v,flush=True)
    np.savez(f"emb_{split}.npz",X=np.stack(X),y=np.array(Y),f=np.array(F))
print("done")
