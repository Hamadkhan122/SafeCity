import numpy as np, tensorflow as tf, re, os
def load(s):
    parts=[np.load(f"emb_{s}.npz"),np.load(f"emba_{s}_fighting.npz"),np.load(f"emba_{s}_normal.npz")]
    X=np.concatenate([p["X"] for p in parts],1); F=np.concatenate([p["f"] for p in parts]); return X,F
peopleword=re.compile(r"groom|diver|ballplayer|player|bride|soldier|uniform|suit|jersey|gown|kimono|abaya|sarong|bikini|swimming_trunks|miniskirt|cowboy|academic|lab_coat|military|wig|sunglass|mask|bonnet|cap|hat|stole|cardigan|jean|sweatshirt|apron|poncho|vestment|pajama|brassiere|maillot|fur_coat|trench|overskirt|hoopskirt|cloak|neck_brace|crutch|stretcher|barbershop|unicycle|bicycle|horse_cart|snorkel|ski|paddle|rugby|basketball|volleyball|croquet|puck|balance_beam|parallel_bars|horizontal_bar|dumbbell|barbell|stage|wreck|library|restaurant|bakery|toyshop|bookshop|tobacco|confectionery|shoe_shop|butcher|grocery|scoreboard|torch|whistle|accordion|banjo|violin|cello|flute|trombone|sax|harmonica|drum|guitar|oboe|cornet|bassoon|french_horn|maraca|panpipe|ocarina|harp|marimba|gong|chain_mail|cuirass|breastplate|bulletproof|stethoscope|lipstick|hair_spray|face_powder|sombrero|mortarboard|turnstile|carousel|dock|pier|bobsled|dogsled|canoe|speedboat|gondola",re.I)
def lab(f):
    b=os.path.basename(f)
    if b.startswith(("street_people","airt_")): return 1
    if "/fighting/" in f: return 1
    if b.startswith(("objects","junk","road_normal")) or "/road_damage/" in f: return 0
    if b.startswith("misc"): return -1  # names unknown after renaming -> skip
    return -1
for s in ["train","validation","test"]:
    X,F=load(s); y=np.array([lab(f) for f in F]); m=y>=0
    globals()[s]=(X[:,m] if s=="train" else X[0][m], y[m])
Xtr,ytr=train; Xtr=Xtr.reshape(-1,1280); ytr=np.tile(ytr,3)
print("train pos/neg",ytr.sum(),len(ytr)-ytr.sum())
tf.keras.utils.set_random_seed(4)
h=tf.keras.Sequential([tf.keras.Input((1280,)),tf.keras.layers.Dropout(0.4),tf.keras.layers.Dense(1,activation="sigmoid",kernel_regularizer=tf.keras.regularizers.l2(1e-4))])
h.compile(tf.keras.optimizers.Adam(1e-3),loss="binary_crossentropy",metrics=["accuracy"])
cw={0:len(ytr)/(2*(ytr==0).sum()),1:len(ytr)/(2*(ytr==1).sum())}
h.fit(Xtr,ytr,validation_data=validation,epochs=30,batch_size=128,class_weight=cw,verbose=0,callbacks=[tf.keras.callbacks.EarlyStopping(patience=5,restore_best_weights=True)])
for n,(X,y) in [("val",validation),("test",test)]:
    p=h.predict(X,verbose=0)[:,0]>0.5; print(n,"acc",round((p==y).mean(),4),"recall person",round(p[y==1].mean(),3),"no-person correct",round((~p[y==0]).mean(),3))
h.save("person_head.keras")
