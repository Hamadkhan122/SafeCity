# Real photos OF screens from our own test videos (phone camera pointed at a laptop showing a UFC
# picture, and at another phone showing an accident picture) + live camera frames (negatives).
# Frames are cut from the screen recordings of the camera preview, app screens removed,
# saved in data_extra/real_recapture/{v6,old,live}/. 10 augmented views per frame -> embr_*.npz
import glob, numpy as np
from PIL import Image, ImageEnhance, ImageFilter
import tensorflow as tf
fe=tf.keras.models.load_model("feat_extractor.keras"); rng=np.random.default_rng(11)
def aug(im):
    w,h=im.size; s=rng.uniform(0.6,1.0); cw,ch=int(w*s),int(h*s*rng.uniform(.8,1.2)); ch=min(ch,h)
    x0=rng.integers(0,w-cw+1); y0=rng.integers(0,h-ch+1); im=im.crop((x0,y0,x0+cw,y0+ch))
    im=ImageEnhance.Brightness(im).enhance(rng.uniform(.6,1.4)); im=ImageEnhance.Color(im).enhance(rng.uniform(.6,1.3))
    if rng.random()<.3: im=im.filter(ImageFilter.GaussianBlur(rng.uniform(.5,2)))
    if rng.random()<.5: im=im.transpose(Image.FLIP_LEFT_RIGHT)
    if rng.random()<.3: im=im.rotate(rng.choice([90,270]),expand=True)
    return im.resize((224,224),Image.BOX)
def E(files,V):
    X=[]
    for f in files:
        im=Image.open(f).convert("RGB"); b=[np.asarray(im.resize((224,224),Image.BOX),np.float32)]+[np.asarray(aug(im),np.float32) for _ in range(V-1)]
        X.append(fe.predict(np.stack(b),verbose=0))
    return np.stack(X)   # [n, V, 1280]
for name in ["v6","old","live"]:
    F=sorted(glob.glob(f"data_extra/real_recapture/{name}/*.jpg")); np.savez(f"embr_{name}.npz",X=E(F,10),f=np.array(F)); print(name,len(F),flush=True)
