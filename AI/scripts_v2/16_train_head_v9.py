# Train the 6-class head v9 (current app model):
# SW = weight of the real screen photos (default 2.5: screen photos must be caught).
#   python scripts_v2/16_train_head_v9.py nordd 1.0 head_v9.keras
# nordd = leave out the RDD street-view "road_damage" photos (most show a normal-looking road).
# Uses features from scripts 04-06, 05b, 15, 19, 22 (web fight photos) and 23 (web screen photos).
import numpy as np, tensorflow as tf, sys, glob
from PIL import Image
CL=["accident","fighting","fire","normal","road_damage","screen"]
DROP_RDD = len(sys.argv)>1 and sys.argv[1]=="nordd"
W3 = float(sys.argv[2]) if len(sys.argv)>2 else 1.0     # weight of screen close-ups
USE6 = True
import os; SW=float(os.environ.get('SW','2.5')); WW=float(os.environ.get('WW','1.0')); NOSMOKE=int(os.environ.get('NOSMOKE','0'))
RDDW = float(sys.argv[4]) if len(sys.argv)>4 else 1.0   # weight of RDD street-view road_damage photos
def load(s):
    parts=[]
    a=np.load(f"emb_{s}.npz"); keep=np.ones(len(a["y"]),bool)
    if DROP_RDD and s=="train": keep=a["y"]!=4
    parts.append((a["X"][:,keep],a["y"][keep],a["f"][keep],np.where(a["y"][keep]==4,RDDW,1.0)))
    for fn,lab in [("embs",5),("embs2",5)]:
        b=np.load(f"{fn}_{s}.npz"); parts.append((b["X"],np.full(len(b["f"]),lab),b["f"],1.0))
    for fn in ["emba_%s_fighting","emba_%s_normal"]:
        c=np.load((fn%s)+".npz"); parts.append((c["X"],c["y"],c["f"],1.0))
    b3=np.load(f"embs3_{s}.npz"); parts.append((b3["X"],np.full(len(b3["f"]),5),b3["f"],W3))
    n3=np.load(f"embn_{s}.npz"); parts.append((n3["X"],np.full(len(n3["f"]),3),n3["f"],1.0))
    bb=np.load(f"embb_{s}.npz"); parts.append((bb["X"],bb["y"],bb["f"],1.0))
    if USE6:
        e6=np.load(f"emb6_{s}.npz"); k=np.array([NOSMOKE==0 or "fsSmoke" not in f for f in e6["f"]])
        parts.append((e6["X"][:,k],e6["y"][k],e6["f"][k],1.0))
    if s in ("train","test"):
        ew=np.load(f"embw_{s}.npz"); parts.append((ew["X"],ew["y"],ew["f"],WW))
        es=np.load(f"embsw_{s}.npz"); parts.append((es["X"],es["y"],es["f"],SW))
    X=np.concatenate([p[0] for p in parts],1); y=np.concatenate([p[1] for p in parts]); f=np.concatenate([p[2] for p in parts]); w=np.concatenate([np.broadcast_to(np.asarray(p[3],float),(len(p[1]),)) for p in parts])
    return X,y,f,w
Xtr,ytr,_,wtr=load("train"); Xva,yva,fva,_=load("validation"); Xte,yte,fte,_=load("test")
Xtr=Xtr.reshape(-1,1280); ytr=np.tile(ytr,3); wtr=np.tile(wtr,3); Xva=Xva[0]; Xte=Xte[0]
cw={i:len(ytr)/(6*np.sum(ytr==i)) for i in range(6)}; sw=wtr*np.array([cw[k] for k in ytr])
tf.keras.utils.set_random_seed(3)
head=tf.keras.Sequential([tf.keras.Input((1280,)),tf.keras.layers.Dropout(0.4),tf.keras.layers.Dense(6,activation="softmax",kernel_regularizer=tf.keras.regularizers.l2(1e-4))])
head.compile(tf.keras.optimizers.Adam(1e-3),loss="sparse_categorical_crossentropy",metrics=["accuracy"])
head.fit(Xtr,ytr,sample_weight=sw,validation_data=(Xva,yva),epochs=40,batch_size=128,verbose=0,callbacks=[tf.keras.callbacks.EarlyStopping(patience=6,restore_best_weights=True,monitor="val_loss")])
p=head.predict(Xte,verbose=0); pa=p.argmax(1)
print("TEST acc %.4f"%(pa==yte).mean(), "per-class recall", {CL[c]:round(float(np.mean(pa[yte==c]==c)),3) for c in range(6)})
grp=lambda key: np.array([key in f.replace("\\","/") for f in fte])
for name,key,c in [("brazil dmg","cracks_potholes/test/road_damage",4),("brazil clean","cracks_potholes/test/normal",3),("RDD road","data/test/road_damage/",4),("road shadow","road_shadow/test",3),("closeup screens","screen_closeup/test",5),("firesmoke fire","v6/test/fire/fsFire",2),("firesmoke smoke","v6/test/fire/fsSmoke",2),("firesmoke neutral","v6/test/normal/fsNeutral",3),("fsd fight","v6/test/fighting",1),("fsd nofight","v6/test/normal/fsd",3),("web fight","web/fighting",1),("web normal","web/normal",3),("web screens","screen_web",5)]:
    g=grp(key); print("  %-15s n=%d  correct %.3f"%(name,g.sum(),np.mean(pa[g]==c)))
print("  fire recall(p>=.5) %.3f  screen>=.35 on fire %.3f"%(np.mean(p[yte==2,2]>=.5),np.mean(p[yte==2,5]>=.35)))
head.save(sys.argv[3] if len(sys.argv)>3 else "head_v5.keras")
# our phone frames
fe=tf.keras.models.load_model("feat_extractor.keras")
def T(f): return float(f.split('_')[1][:-4])
rv=sorted(glob.glob("test_images/phone_video/t_*.jpg"))   # frames of our own test video (optional)
park=[f for f in rv if 103.5<=T(f)<=113]; scr=[f for f in rv if 222.5<=T(f)<=236]; live=[f for f in rv if 22<=T(f)<=49.5 or 103.5<=T(f)<=113]
P=lambda fs: head.predict(fe.predict(np.stack([np.asarray(Image.open(f).convert("RGB").crop((0,130,576,900)).resize((224,224),Image.BOX),np.float32) for f in fs]),verbose=0),verbose=0)
if park and scr: print("  park path road>=.5: %d/%d   screen frames screen>=.35: %d/%d   live frames screen>=.35: %d/%d"%((P(park)[:,4]>=.5).sum(),len(park),(P(scr)[:,5]>=.35).sum(),len(scr),(P(live)[:,5]>=.35).sum(),len(live)))
inet=sorted(glob.glob("imagenet-sample-images/*.JPEG")); Pi=head.predict(fe.predict(np.stack([np.asarray(Image.open(f).convert("RGB").resize((224,224),Image.BOX),np.float32) for f in inet]),verbose=0,batch_size=64),verbose=0)
print("  imagenet: screen>=.35 %.3f road>=.5 %.3f"%(np.mean(Pi[:,5]>=.35),np.mean(Pi[:,4]>=.5)))
