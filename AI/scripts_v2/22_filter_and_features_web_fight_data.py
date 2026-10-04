# Web fight data (downloaded by 20_download_fight_web_data.py into D:\Downloads\fight_data):
#  1. fight photos are kept only if YOLOv8n-pose finds 2+ people (large, close together)
#     -> removes cartoons, title cards, single news anchors from the YouTube frames
#  2. features (embw_*.npz), split by search query / video so test sources are unseen
# Expects the photos (max 320 px) in data_extra/web/fighting and data_extra/web/normal.
import glob, numpy as np, json, random, sys
sys.path.insert(0, 'scripts_v2')
pose = __import__('17_pose_fight_rule')
from PIL import Image
out={}
for f in sorted(glob.glob("data_extra/web/fighting/*")):
    im=Image.open(f).convert("RGB"); W,H=im.size; p=[d for d in pose.people(im) if d[4]>=0.5]
    P=[d for d in p if d[3]-d[1]>=0.25]
    ok=False
    for a in range(len(P)):
        for b in range(a+1,len(P)):
            A,B=P[a],P[b]; ha,hb=A[3]-A[1],B[3]-B[1]; mh=(ha+hb)/2
            if min(ha,hb)/max(ha,hb)<0.5: continue
            d=np.hypot(((A[0]+A[2])-(B[0]+B[2]))/2*W/H,((A[1]+A[3])-(B[1]+B[3]))/2)/mh
            if d<=1.3: ok=True
    out[f]=ok
json.dump(out,open("webfilter.json","w")); print("kept",sum(out.values()),"of",len(out))

import tensorflow as tf
from PIL import ImageEnhance
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
keep=json.load(open("webfilter.json"))
F=[f for f,v in keep.items() if v]+sorted(glob.glob("data_extra/web/normal/*"))
# split by source (video id / query) so frames of one video are not in train AND test
def src(f):
    b=f.replace("\\","/").split("/")[-1]; return b.rsplit("_",1)[0]
srcs=sorted(set(src(f) for f in F)); random.Random(7).shuffle(srcs)
te=set(srcs[:len(srcs)//8])
for s,sel in [("train",[f for f in F if src(f) not in te]),("test",[f for f in F if src(f) in te])]:
    y=np.array([1 if "fighting" in f.replace("\\","/").split("/") else 3 for f in sel]); V=3 if s=="train" else 1
    np.savez(f"embw_{s}.npz",X=np.stack([emb(sel,v) for v in range(V)]),y=y,f=np.array(sel)); print(s,len(sel),np.bincount(y),flush=True)
