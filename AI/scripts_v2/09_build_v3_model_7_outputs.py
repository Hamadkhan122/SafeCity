import numpy as np, tensorflow as tf, glob, os
from PIL import Image
import skimage.data as sd
fe=tf.keras.models.load_model("feat_extractor.keras"); head=tf.keras.models.load_model("head.keras"); ph=tf.keras.models.load_model("person_head.keras")
inp=tf.keras.Input((224,224,3),name="image"); f=fe(inp)
d1=tf.keras.layers.Dense(6,activation="softmax",name="incident"); d2=tf.keras.layers.Dense(1,activation="sigmoid",name="person")
d1.build((None,1280)); d2.build((None,1280)); d1.set_weights(head.layers[-1].get_weights()); d2.set_weights(ph.layers[-1].get_weights())
out=tf.keras.layers.Concatenate(name="probs")([d1(f), d2(f)])
full=tf.keras.Model(inp,out); full.save("safecity_incident_v3.keras")
def pp(im):
    x=np.expand_dims(np.asarray(im.convert("RGB").resize((224,224)),np.float32),0); return full.predict(x,verbose=0)[0]
L=["accident","fighting","fire","normal","road_damage","screen"]
def show(name,im):
    p=pp(im); print(f"{name[:22]:22s} top={L[p[:6].argmax()]:11s} {p[:6].max():.2f} person={p[6]:.2f}")
for f in sorted(glob.glob("test_images/*")): show(os.path.basename(f),Image.open(f))
for k in ["astronaut","coffee","chelsea","horse","cat","camera","rocket","page","brick","grass"]:
    v=np.asarray(getattr(sd,k)()); v=np.stack([v]*3,-1) if v.ndim==2 else v[...,:3]; show(k,Image.fromarray(v.astype(np.uint8)))
show("white_wall",Image.fromarray(np.full((300,300,3),235,np.uint8)))
for f in sorted(glob.glob("Mask_RCNN/images/*")): show(os.path.basename(f),Image.open(f))
