# Normal (undamaged) road / path surfaces with tree shadows, painted lines and sun patches.
# Hard negatives for road_damage: shadows of leaves look like cracks to the model.
import glob, random, os, numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
R=random.Random(5); rng=np.random.default_rng(5)
src=sorted(glob.glob("comma10k/imgs/*"))
SP=sorted(glob.glob("data/train/normal/street_people*"))
def noise(W,H):
    m=np.zeros((H,W),np.float32)
    for sc,wt in ((28,1.),(56,.6),(110,.4)):
        g=rng.random((H//sc+2,W//sc+2)).astype(np.float32)
        m+=wt*np.asarray(Image.fromarray((g*255).astype(np.uint8)).resize((W+sc,H+sc),Image.BICUBIC),np.float32)[:H,:W]/255
    return m/m.max()
def shadow(W,H,top=0):
    n=noise(W,H); t=np.quantile(n,R.uniform(.35,.7)); m=(n>t).astype(np.float32)
    m[:int(top*H)]=0
    return Image.fromarray((m*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(R.uniform(2,6)))
def addshadow(im,top=0):
    W,H=im.size; m=shadow(W,H,top); k=R.uniform(.35,.7)
    dark=np.clip(np.asarray(im,np.float32)*k*np.array([.9,.95,1.1]),0,255).astype(np.uint8)
    return Image.composite(Image.fromarray(dark),im,m)
def line(im,top=0):
    d=ImageDraw.Draw(im); W,H=im.size; col=R.choice([(230,200,40),(240,240,240),(220,180,30)]); x=R.uniform(.2,.8)*W
    d.line([(x,top*H),(x+R.uniform(-.4,.4)*W,H)],fill=col,width=R.randint(3,12)); return im
def make(f):
    im=Image.open(f).convert("RGB")
    while np.asarray(im.resize((32,32))).mean()<70: im=Image.open(R.choice(src)).convert("RGB")   # skip night
    W,H=im.size
    r=R.random()
    if r<.3:            # pavement under pedestrians (real sidewalk photos)
        p=Image.open(R.choice(SP)).convert("RGB"); w,h=p.size
        im=p.crop((0,int(h*.6),w,h)); c=min(im.size); x0=R.randint(0,im.width-c); im=im.crop((x0,0,x0+c,c)).resize((448,448))
        if R.random()<.6: im=addshadow(im)
    elif r<.6:          # whole scene, shadows on the road part
        im=im.crop((0,0,W,int(H*.8))); im=im.resize((448,int(448*im.height/im.width)))
        if R.random()<.35: im=ImageEnhance.Color(im).enhance(R.uniform(0,.6))
        im=addshadow(im,top=.55)
        c=im.height; x0=R.randint(0,im.width-c); im=im.crop((x0,0,x0+c,c))
    else:               # close-up of the road surface
        c=R.uniform(.12,.22)*H; x0=R.uniform(.25*W,.75*W-c); y0=R.uniform(.58*H,.8*H-c)
        im=im.crop((int(x0),int(y0),int(x0+c),int(y0+c))).resize((448,448),Image.BICUBIC)
        if R.random()<.5: im=ImageEnhance.Color(im).enhance(R.uniform(0,.6))
        if R.random()<.4: im=line(im)
        if R.random()<.85: im=addshadow(im)
    im=ImageEnhance.Brightness(im).enhance(R.uniform(.8,1.3))
    return im.resize((224,224),Image.BOX)
if __name__=="__main__":
    R.shuffle(src); n=len(src); parts={"train":src[:int(n*.7)],"validation":src[int(n*.7):int(n*.85)],"test":src[int(n*.85):]}
    N={"train":1200,"validation":150,"test":150}
    for s,fs in parts.items():
        os.makedirs(f"data_extra/road_shadow/{s}",exist_ok=True)
        for i in range(N[s]): make(R.choice(fs)).save(f"data_extra/road_shadow/{s}/roadshadow_{i:04d}.jpg",quality=90)
        print(s,flush=True)
