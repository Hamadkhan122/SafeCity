import numpy as np, glob, os, tensorflow as tf
from PIL import Image
import skimage.data as sd
L=["accident","fighting","fire","normal","road_damage","screen","person"]
def I(p): it=tf.lite.Interpreter(p); it.allocate_tensors(); return it
inc=I("../safecity/assets/models/incident_mobilenetv2.tflite"); har=I("../safecity/assets/models/harassment_mobilenetv2.tflite")
def run(it,x): it.set_tensor(it.get_input_details()[0]["index"],x); it.invoke(); return it.get_tensor(it.get_output_details()[0]["index"])[0]
MAP={"Accident":"accident","Fire":"fire","Road Damage":"road_damage","Fight":"fighting"}; L2C={v:k for k,v in MAP.items()}
def verdict(im,cat):
    x=np.expand_dims(np.asarray(im.convert("RGB").resize((224,224)),np.float32),0)
    p=dict(zip(L,run(inc,x))); cls={k:v for k,v in p.items() if k!="person"}; top=max(cls,key=cls.get); tp=cls[top]
    people=cat in("Fight","Harassment")
    if cat=="Harassment": raw=run(har,x)[1]
    elif cat=="Fight": raw=max(p["fighting"],run(har,x)[1])
    else: raw=p[MAP[cat]]
    if p["screen"]>=.5: return False,0,"screen"
    lk=L2C.get(top)
    if lk and lk!=cat and tp>=.8 and not(people and lk=="Fight"): return False,.1,f"looks like {lk}"
    if cat=="Fight":
        ok=raw>=.5; return ok,raw,"" if ok else "no fighting"
    if people:
        ok=p["person"]>=.5 or raw>=.5; return ok,(.6+.4*raw if ok else .1),"" if ok else "no people"
    ok=raw>=.5; return ok,raw,"" if ok else "no incident"
def status(im,cat,gps=1.0,desc=0.5):
    ok,s,why=verdict(im,cat)
    conf=.3*s+.1*desc+.25*gps+.15*1+.2*.5
    return ("Verified" if ok and conf>=.6 else "Rejected"),why
def rate(files,cat):
    r=[status(Image.open(f),cat)[0] for f in files]; return f"{r.count('Verified')}/{len(r)} verified"
T="test_images/"
print("== real incident photos (should be Verified)")
print("test accident -> Accident  ", rate(sorted(glob.glob("data/test/accident/*")),"Accident"))
print("test fire     -> Fire      ", rate(sorted(glob.glob("data/test/fire/*")),"Fire"))
print("test road     -> Road Dmg  ", rate(sorted(glob.glob("data/test/road_damage/*")),"Road Damage"))
print("test fighting -> Fight     ", rate(sorted(glob.glob("data/test/fighting/*")),"Fight"))
print("street people -> Fight     ", rate(sorted(glob.glob("data/test/normal/street_people*")),"Fight"))
print("internet fight photos -> Fight", rate(sorted(glob.glob(T+"[Ff]ight*")),"Fight"))
print("internet fight photos -> Harassment", rate(sorted(glob.glob(T+"[Ff]ight*")),"Harassment"))
print("internet accident/fire", [status(Image.open(T+f),c) for f,c in [("accident.jfif","Accident"),("accident-1.jpg","Accident"),("fire.jpg","Fire"),("fire-1.jfif","Fire")]])
print("== fake / wrong photos (should be Rejected)")
print("test normal -> Accident   ", rate(sorted(glob.glob("data/test/normal/*")),"Accident"))
print("test normal -> Fire       ", rate(sorted(glob.glob("data/test/normal/*")),"Fire"))
print("objects/junk -> Harassment", rate(sorted(glob.glob("data/test/normal/objects*")+glob.glob("data/test/normal/junk*")),"Harassment"))
print("screens -> Harassment     ", rate(sorted(glob.glob("data/test/screen/*")),"Harassment"))
print("screens -> Accident       ", rate(sorted(glob.glob("data/test/screen/*")),"Accident"))
for k in ["coffee","cat","brick","grass"]:
    v=np.asarray(getattr(sd,k)()); v=np.stack([v]*3,-1) if v.ndim==2 else v[...,:3]
    print(k, "Harassment:",status(Image.fromarray(v.astype(np.uint8)),"Harassment"), "Accident:",status(Image.fromarray(v.astype(np.uint8)),"Accident"))
print("white wall Harassment:",status(Image.fromarray(np.full((300,300,3),235,np.uint8)),"Harassment"))
