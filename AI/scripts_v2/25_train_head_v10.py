# Train the 6-class head v10 (current app model):
#   set ALLLIVE=1 ; python scripts_v2/25_train_head_v10.py v6,old 2 head_v10.keras
# = head v9 data (scripts 16) + real photos of screens from our test videos (script 24, weight 2)
#   + live camera frames as "normal".
# UFC / MMA / boxing photos and videos are relabelled "normal": a sports match is not an incident
# (and a UFC picture shown on a screen must not pass as a Fight report).
import numpy as np, tensorflow as tf, sys, os, glob
from PIL import Image
os.environ.setdefault("SW","2.5")
src=open("scripts_v2/16_train_head_v9.py").read()
pre=src.split("Xtr,ytr,_,wtr=load")[0]
exec(pre)
DROP_RDD=True   # leave out RDD street-view road photos (normal roads were accepted)
TRAIN_VIDS=sys.argv[1].split(",") if sys.argv[1]!="none" else []; RW=float(sys.argv[2]); OUT=sys.argv[3]
import json
SPORT=["8lKirrARb0w", "9SVjp9L8W0g", "FwRMKRKcnj8", "JmRMnUkO0U8", "Kx3a-nx4tCM", "XQ0nS_Mn5GM", "XZdE-PX0iqQ", "aGNBapYb7rM", "h_auGwiEfGo", "qChW79bdo60"]; SPORTQ=("img_ufc","img_mma","img_boxing")
def is_sport(f):
    b=f.split("/")[-1]; return b.startswith(SPORTQ) or any(b.startswith("vid_"+v+"_") for v in SPORT)
RELABEL=os.environ.get("RELABEL","1")=="1"
Xtr,ytr,ftr,wtr=load("train"); Xva,yva,_,_=load("validation")
if RELABEL:
    m=np.array(["web/fighting" in f.replace("\\","/") and is_sport(f) for f in ftr]); ytr=ytr.copy(); ytr[m]=3; print("relabelled sport",m.sum(),flush=True)
Xtr=Xtr.reshape(-1,1280); ytr=np.tile(ytr,3); wtr=np.tile(wtr,3); Xva=Xva[0]
add=[]
for v in TRAIN_VIDS:
    e=np.load(f"embr_{v}.npz")["X"].reshape(-1,1280); add.append((e,5))
e=np.load("embr_live.npz"); keep=np.array([(os.environ.get("ALLLIVE")=="1") or ("/v5_" not in f) for f in e["f"]]); add.append((e["X"][keep].reshape(-1,1280),3))
for X,l in add: Xtr=np.concatenate([Xtr,X]); ytr=np.concatenate([ytr,np.full(len(X),l)]); wtr=np.concatenate([wtr,np.full(len(X),RW)])
cw={i:len(ytr)/(6*np.sum(ytr==i)) for i in range(6)}; sw=wtr*np.array([cw[k] for k in ytr])
tf.keras.utils.set_random_seed(3)
head=tf.keras.Sequential([tf.keras.Input((1280,)),tf.keras.layers.Dropout(0.4),tf.keras.layers.Dense(6,activation="softmax",kernel_regularizer=tf.keras.regularizers.l2(1e-4))])
head.compile(tf.keras.optimizers.Adam(1e-3),loss="sparse_categorical_crossentropy",metrics=["accuracy"])
head.fit(Xtr,ytr,sample_weight=sw,validation_data=(Xva,yva),epochs=40,batch_size=128,verbose=0,callbacks=[tf.keras.callbacks.EarlyStopping(patience=6,restore_best_weights=True,monitor="val_loss")])
head.save(OUT)
P=lambda X: head.predict(X,verbose=0)
res={}
for v in ["v6","old"]: res[v]=P(np.load(f"embr_{v}.npz")["X"][:,0])[:,5]
for v in ["v6","old"]: res[v+"_fight"]=P(np.load(f"embr_{v}.npz")["X"][:,0])[:,1]
e=np.load("embr_live.npz"); m=np.array(["/v5_" in f for f in e["f"]]); res["live_v5(test)"]=P(e["X"][m][:,0])[:,5]
fe=tf.keras.models.load_model("feat_extractor.keras")
def L(fs): return fe.predict(np.stack([np.asarray(Image.open(f).convert("RGB").resize((224,224),Image.BOX),np.float32) for f in fs]),verbose=0,batch_size=64)
inc=[f for c in ["accident","fire","fighting","road_damage"] for f in sorted(glob.glob(f"data/test/{c}/*"))]
Pi=P(L(inc)); res["incidentFP"]=Pi[:,5]
res["neutralFP"]=P(L(sorted(glob.glob("firesmoke/FIRE-SMOKE-DATASET/Test/Neutral/*"))))[:,5]
res["imagenetFP"]=P(L(sorted(glob.glob("imagenet-sample-images/*.JPEG"))))[:,5]
A=P(L(sorted(glob.glob("data/test/accident/*"))))
for th in (.4,.5):
    print("RES",OUT,"train=",TRAIN_VIDS,"th",th," ".join(f"{k}:{np.mean(v>=th):.2f}" for k,v in res.items()),"accident_pass:%.3f"%np.mean((A[:,0]>=.5)&(A[:,5]<th)))
