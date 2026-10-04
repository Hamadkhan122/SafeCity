# Close-up recaptures: photo of a phone / monitor screen where the screen fills most of the frame.
# Simulates display pixel grid (moire after resampling), washed-out contrast, colour cast,
# glare, slight perspective, partial bezel and fingers, defocus, sensor noise, JPEG.
import os, glob, random, io, numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
R=random.Random(77); rng=np.random.default_rng(77)
SKIN=[(224,172,140),(198,134,98),(160,106,74),(240,200,170),(120,80,56)]
S=1000
def pixel_grid(a):
    # RGB sub-pixel stripes / dot grid with random period and angle
    p=R.uniform(2.2,7.0); ang=np.deg2rad(R.uniform(-8,8)); st=R.uniform(.15,.55)
    yy,xx=np.mgrid[0:S,0:S].astype(np.float32)
    u=(xx*np.cos(ang)+yy*np.sin(ang))/p; v=(-xx*np.sin(ang)+yy*np.cos(ang))/p
    m=np.zeros((S,S,3),np.float32)
    for c in range(3):
        m[...,c]=0.5+0.5*np.cos(2*np.pi*(u-c/3.0))
    if R.random()<0.6: m*= (0.75+0.25*np.cos(2*np.pi*v))[...,None]
    return a*((1-st)+st*m*1.6)
def display(img):
    a=np.asarray(img.resize((S,S),Image.BICUBIC),np.float32)
    if R.random()<0.85: a=pixel_grid(a)
    g=R.uniform(.7,1.0); a=255*(np.clip(a,0,255)/255)**g
    a=a*R.uniform(.55,.9)+R.uniform(20,90)                      # lifted blacks / washed out
    cast=np.array([R.uniform(.85,1.05),R.uniform(.9,1.05),R.uniform(.95,1.2)]) if R.random()<.6 else np.array([R.uniform(1.0,1.15),R.uniform(.95,1.05),R.uniform(.8,.95)])
    a=a*cast
    # vignetting / uneven brightness of the panel
    yy,xx=np.mgrid[0:S,0:S]/S; cx,cy=R.uniform(.2,.8),R.uniform(.2,.8)
    a=a*(1-R.uniform(0,.35)*((xx-cx)**2+(yy-cy)**2))[...,None]
    return Image.fromarray(np.clip(a,0,255).astype(np.uint8))
def glare(im):
    W,H=im.size; g=Image.new("L",(W,H),0); d=ImageDraw.Draw(g)
    for _ in range(R.randint(1,2)):
        if R.random()<.5:
            x0=R.uniform(-.3,1)*W; d.polygon([(x0,0),(x0+R.uniform(.1,.35)*W,0),(x0+R.uniform(-.2,.4)*W,H),(x0+R.uniform(-.4,.1)*W,H)],fill=int(R.uniform(40,140)))
        else:
            x,y,r=R.uniform(0,W),R.uniform(0,H),R.uniform(.08,.3)*W; d.ellipse([x-r,y-r,x+r,y+r],fill=int(R.uniform(60,180)))
    return Image.composite(Image.new("RGB",(W,H),(255,255,255)),im,g.filter(ImageFilter.GaussianBlur(W*.05)))
def perspective(im,bg):
    W,H=im.size; j=lambda: R.uniform(-.06,.10)*W
    quad=(j(),j(), j(),H-j(), W-j(),H-j(), W-j(),j())   # source quad -> output square
    out=im.transform((W,H),Image.QUAD,quad,Image.BICUBIC,fillcolor=bg)
    return out
def bezel(im):
    W,H=im.size; d=ImageDraw.Draw(im); col=tuple(int(x) for x in rng.integers(5,60,3))
    for side in R.sample(["t","b","l","r"],R.choice([0,1,1,2,2,3])):
        w=int(R.uniform(.02,.12)*W)
        if side=="t": d.rectangle([0,0,W,w],fill=col)
        if side=="b": d.rectangle([0,H-w,W,H],fill=col)
        if side=="l": d.rectangle([0,0,w,H],fill=col)
        if side=="r": d.rectangle([W-w,0,W,H],fill=col)
    return im
def fingers(im):
    d=ImageDraw.Draw(im); W,H=im.size; col=R.choice(SKIN)
    for _ in range(R.randint(1,3)):
        side=R.choice(["l","r","b","t"]); w,h=R.uniform(.10,.22)*W,R.uniform(.15,.35)*H
        x={"l":R.uniform(-.05,.08),"r":R.uniform(.92,1.05),"b":R.uniform(.1,.9),"t":R.uniform(.1,.9)}[side]*W
        y={"l":R.uniform(.2,.9),"r":R.uniform(.2,.9),"b":R.uniform(.95,1.05),"t":R.uniform(-.05,.05)}[side]*H
        d.ellipse([x-w/2,y-h/2,x+w/2,y+h/2],fill=col)
    return im.filter(ImageFilter.GaussianBlur(1))
def ui(im):
    d=ImageDraw.Draw(im); W,H=im.size; dark=R.random()<.5; c=(18,18,18) if dark else (246,246,246)
    r=R.random()
    if r<.25: d.rectangle([0,0,W,int(H*R.uniform(.03,.06))],fill=c)
    elif r<.45:
        h=int(H*R.uniform(.07,.12)); d.rectangle([0,0,W,h],fill=c); d.rounded_rectangle([int(W*.08),int(h*.25),int(W*.92),int(h*.8)],radius=14,fill=(60,60,60) if dark else (222,222,222))
    return im
def make(content):
    cv=content.convert("RGB")
    if R.random()<.5: cv=ui(cv.resize((800,800)))
    im=display(cv)
    if R.random()<.7: im=perspective(im,tuple(int(x) for x in rng.integers(5,60,3)))
    if R.random()<.6: im=bezel(im)
    if R.random()<.75: im=glare(im)
    if R.random()<.4: im=fingers(im)
    im=im.rotate(R.uniform(-5,5),resample=Image.BICUBIC,fillcolor=(20,20,20))
    im=im.filter(ImageFilter.GaussianBlur(R.uniform(0.3,2.5)))
    a=np.asarray(im,np.float32)+rng.normal(0,R.uniform(1,6),(S,S,3)); im=Image.fromarray(np.clip(a,0,255).astype(np.uint8))
    if R.random()<.5:  # crop (zoomed-in shot)
        c=R.uniform(.7,1.0)*S; x=R.uniform(0,S-c); y=R.uniform(0,S-c); im=im.crop((int(x),int(y),int(x+c),int(y+c)))
    return im.resize((224,224),Image.BOX)
if __name__=="__main__":
    N={"train":2000,"validation":170,"test":150}
    for s,n in N.items():
        cont=[f for c in ["accident","fighting","fire","road_damage","normal"] for f in glob.glob(f"data/{s}/{c}/*")]
        cont+= [f for f in glob.glob(f"data/{s}/accident/*")+glob.glob(f"data/{s}/fire/*")]   # incident content more often
        for i in range(n):
            im=make(Image.open(R.choice(cont)))
            b=io.BytesIO(); im.save(b,"JPEG",quality=R.randint(60,92)); os.makedirs(f"data_extra/screen_closeup/{s}",exist_ok=True); open(f"data_extra/screen_closeup/{s}/screen3_{i:04d}.jpg","wb").write(b.getvalue())
        print(s,n,flush=True)
