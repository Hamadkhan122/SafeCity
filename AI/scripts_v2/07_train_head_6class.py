import numpy as np, tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix
CL=["accident","fighting","fire","normal","road_damage","screen"]
def load(s):
    a=np.load(f"emb_{s}.npz"); b=np.load(f"embs_{s}.npz")
    c1=np.load(f"emba_{s}_fighting.npz"); c2=np.load(f"emba_{s}_normal.npz"); b2=np.load(f"embs2_{s}.npz")
    X=np.concatenate([a["X"],b["X"],c1["X"],c2["X"],b2["X"]],1); y=np.concatenate([a["y"],np.full(len(b["f"]),5),c1["y"],c2["y"],np.full(len(b2["f"]),5)])
    return X,y,np.concatenate([a["f"],b["f"],c1["f"],c2["f"],b2["f"]])
Xtr,ytr,_=load("train"); Xva,yva,_=load("validation"); Xte,yte,fte=load("test")
Xtr=Xtr.reshape(-1,Xtr.shape[-1]); ytr=np.tile(ytr,3); Xva=Xva[0]; Xte=Xte[0]
cw={i:len(ytr)/(6*np.sum(ytr==i)) for i in range(6)}; print("class weights",{CL[k]:round(v,2) for k,v in cw.items()})
tf.keras.utils.set_random_seed(3)
head=tf.keras.Sequential([tf.keras.Input((1280,)),tf.keras.layers.Dropout(0.4),tf.keras.layers.Dense(6,activation="softmax",kernel_regularizer=tf.keras.regularizers.l2(1e-4))])
head.compile(tf.keras.optimizers.Adam(1e-3),loss="sparse_categorical_crossentropy",metrics=["accuracy"])
head.fit(Xtr,ytr,validation_data=(Xva,yva),epochs=40,batch_size=128,class_weight=cw,verbose=0,
         callbacks=[tf.keras.callbacks.EarlyStopping(patience=6,restore_best_weights=True,monitor="val_loss")])
for n,X,y in [("VAL",Xva,yva),("TEST",Xte,yte)]:
    p=head.predict(X,verbose=0).argmax(1); print(n,"acc",round((p==y).mean(),4)); print(classification_report(y,p,target_names=CL,digits=3)); print(confusion_matrix(y,p))
head.save("head.keras")
