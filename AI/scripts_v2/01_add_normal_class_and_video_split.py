import os, glob, random, re, shutil, numpy as np
from PIL import Image, ImageOps, ImageFilter, ImageEnhance
random.seed(7); np.random.seed(7)
D="data"
def save(src_img, dst):
    os.makedirs(os.path.dirname(dst),exist_ok=True)
    src_img.convert("RGB").resize((224,224),Image.BILINEAR).save(dst,"JPEG",quality=92)
def load(f, crop_bottom=0):
    im=ImageOps.exif_transpose(Image.open(f)).convert("RGB")
    if crop_bottom: w,h=im.size; im=im.crop((0,0,w,int(h*(1-crop_bottom))))
    return im
# ---- 1. fighting: video-wise re-split of UCF frames (train+val) ----
pool=[]
for s in ["train","validation"]:
    for f in glob.glob(f"{D}/{s}/fighting/*"):
        if not os.path.basename(f).startswith("extra_"): pool.append(f)
vids=sorted({re.sub(r"_x264.*","",os.path.basename(f)) for f in pool})
random.shuffle(vids); valv=set(vids[:max(1,len(vids)*15//100)])
os.makedirs(f"{D}/tmpfight",exist_ok=True)
for f in pool: shutil.move(f,f"{D}/tmpfight/"+os.path.basename(f))
nt=nv=0
for f in glob.glob(f"{D}/tmpfight/*"):
    v=re.sub(r"_x264.*","",os.path.basename(f))
    dst="validation" if v in valv else "train"; shutil.move(f,f"{D}/{dst}/fighting/"+os.path.basename(f))
    nt+=dst=="train"; nv+=dst=="validation"
os.rmdir(f"{D}/tmpfight")
print("fighting UCF videos",len(vids),"val videos",len(valv),"frames train",nt,"val",nv)
# ---- 2. normal class ----
def split_put(files, name, ntr, nva, nte, crop=0):
    random.shuffle(files); parts=[("train",files[:ntr]),("validation",files[ntr:ntr+nva]),("test",files[ntr+nva:ntr+nva+nte])]
    for s,fs in parts:
        for i,f in enumerate(fs):
            try: save(load(f,crop),f"{D}/{s}/normal/{name}_{i:04d}.jpg")
            except Exception as e: print("bad",f,e)
    print(name,[len(fs) for _,fs in parts])
split_put(glob.glob("clothing-co-parsing/photos/*.jpg"),"street_people",1000,150,150)
split_put(glob.glob("clothing-dataset-small/*/*/*.jpg"),"objects",600,100,100)
split_put(glob.glob("comma10k/imgs/*.png"),"road_normal",420,90,90,crop=0.22)
bad=re.compile(r"volcano|fire|torch|candle|wreck|crash|lighter|matchstick|stove",re.I)
inet=[f for f in glob.glob("imagenet-sample-images/*.JPEG") if not bad.search(f)]
split_put(inet,"misc",690,150,150)
# synthetic junk: solid, gradients, noise, blur/dark versions of misc images
syn=[]
for i in range(300):
    k=i%5
    if k==0: a=np.full((224,224,3),np.random.randint(0,256,3),np.uint8)
    elif k==1:
        g=np.linspace(0,1,224)[:,None,None]; c1,c2=np.random.randint(0,256,(2,3)); a=(c1*(1-g)+c2*g).repeat(224,1).astype(np.uint8)
    elif k==2: a=np.clip(np.random.normal(np.random.randint(40,200),np.random.randint(5,60),(224,224,3)),0,255).astype(np.uint8)
    else:
        im=load(random.choice(inet)).resize((224,224))
        im=im.filter(ImageFilter.GaussianBlur(np.random.uniform(4,12))) if k==3 else ImageEnhance.Brightness(im).enhance(np.random.uniform(0.05,0.25))
        a=np.array(im)
    syn.append(Image.fromarray(a))
for i,im in enumerate(syn):
    s="train" if i<200 else ("validation" if i<250 else "test"); save(im,f"{D}/{s}/normal/junk_{i:04d}.jpg")
for s in ["train","validation","test"]:
    print(s,{c:len(os.listdir(f"{D}/{s}/{c}")) for c in sorted(os.listdir(f"{D}/{s}"))})
