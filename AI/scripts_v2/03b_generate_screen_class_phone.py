# Extra realistic screen recaptures: phone held in hand + close-up of a screen
import os, glob, random, io, numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
import sys; sys.path.insert(0,"scripts_v2"); exec(open("scripts_v2/03_generate_screen_class.py").read().split("if __name__")[0])
#from screen_gen import display_effect, perspective, glare  # reuse helpers
R2=random.Random(23); rng2=np.random.default_rng(23)
SKIN=[(224,172,140),(198,134,98),(160,106,74),(240,200,170),(120,80,56)]
def ui_bars(cv):
    d=ImageDraw.Draw(cv); W,H=cv.size; dark=R2.random()<0.5; c=(20,20,20) if dark else (245,245,245)
    if R2.random()<0.8: d.rectangle([0,0,W,int(H*R2.uniform(.03,.07))],fill=c)        # status bar
    if R2.random()<0.6: d.rectangle([0,0,W,int(H*R2.uniform(.08,.14))],fill=c); d.rounded_rectangle([int(W*.06),int(H*.03),int(W*.94),int(H*.1)],radius=12,fill=(60,60,60) if dark else (225,225,225))
    if R2.random()<0.6:
        y=int(H*R2.uniform(.86,.93)); d.rectangle([0,y,W,H],fill=c)
        for k in range(4): d.ellipse([int(W*(.12+.22*k)),y+8,int(W*(.12+.22*k))+18,y+26],fill=(140,140,140))
    return cv
def phone_screen(content):
    W,H=(450,900) if R2.random()<0.6 else (900,450)
    cv=Image.new("RGB",(W,H),(0,0,0)); s=R2.uniform(.6,1.0)
    c=content.resize((int(W*s),int(W*s*0.75)) if W<H else (int(H*s/0.75),int(H*s)))
    cv.paste(c,((W-c.width)//2,(H-c.height)//2)); cv=ui_bars(cv)
    b=int(min(W,H)*R2.uniform(.03,.07)); body=Image.new("RGBA",(W+2*b,H+2*b),(0,0,0,0)); d=ImageDraw.Draw(body)
    col=tuple(int(x) for x in rng2.integers(10,70,3))+(255,); d.rounded_rectangle([0,0,body.width-1,body.height-1],radius=int(b*2.5),fill=col)
    body.paste(display_effect(cv).resize((W,H)).convert("RGBA"),(b,b)); return body
def fingers(img):
    d=ImageDraw.Draw(img,"RGBA"); W,H=img.size; col=R2.choice(SKIN)
    for _ in range(R2.randint(1,4)):
        side=R2.choice(["l","r","b"]); w,h=R2.uniform(.08,.16)*W,R2.uniform(.12,.25)*H
        if side=="l": x,y=R2.uniform(-.05,.15)*W,R2.uniform(.3,.9)*H
        elif side=="r": x,y=R2.uniform(.85,1.0)*W,R2.uniform(.3,.9)*H
        else: x,y=R2.uniform(.2,.8)*W,R2.uniform(.85,1.0)*H
        d.ellipse([x-w/2,y-h/2,x+w/2,y+h/2],fill=col+(255,))
    return img
def make_phone(content,bg):
    body=phone_screen(content).rotate(R2.uniform(-25,25),expand=True,resample=Image.BICUBIC)
    out=ImageEnhance.Brightness(bg.resize((672,672)).filter(ImageFilter.GaussianBlur(R2.uniform(0,4)))).enhance(R2.uniform(.5,1.1))
    sc=R2.uniform(.75,1.4)*672/max(body.size); body=body.resize((int(body.width*sc),int(body.height*sc)))
    x=R2.randint(-body.width//6,max(1,672-body.width*5//6)); y=R2.randint(-body.height//6,max(1,672-body.height*5//6))
    out.paste(body,(x,y),body); out=fingers(out); return out
def make_closeup(content):
    cv=ui_bars(content.resize((800,800)).copy()) if R2.random()<.6 else content.resize((800,800))
    cv=display_effect(cv).resize((800,800))
    a=np.asarray(cv,np.float32); a=a*R2.uniform(.6,.9)+R2.uniform(30,80)   # washed out
    out=Image.fromarray(np.clip(a,0,255).astype(np.uint8)).resize((672,672))
    if R2.random()<.8:  # diagonal glare streak
        g=Image.new("L",(672,672),0); d=ImageDraw.Draw(g); x0=R2.uniform(-300,600)
        d.polygon([(x0,0),(x0+R2.uniform(80,250),0),(x0+R2.uniform(-200,200)+200,672),(x0+R2.uniform(-200,200),672)],fill=int(R2.uniform(40,120)))
        out=Image.composite(Image.new("RGB",(672,672),(255,255,255)),out,g.filter(ImageFilter.GaussianBlur(40)))
    out=out.rotate(R2.uniform(-6,6),resample=Image.BICUBIC,expand=False,fillcolor=(20,20,20))
    return out
if __name__=="__main__":
    N={"train":1500,"validation":250,"test":250}
    for s,n in N.items():
        cont=[f for c in ["accident","fighting","fire","road_damage","normal"] for f in glob.glob(f"data/{s}/{c}/*") if "screen" not in f]
        bgs=[f for p in ["objects","misc","street_people","road_normal"] for f in glob.glob(f"data/{s}/normal/{p}_*")]
        for i in range(n):
            c=Image.open(R2.choice(cont)).convert("RGB")
            im=make_phone(c,Image.open(R2.choice(bgs)).convert("RGB")) if i%2==0 else make_closeup(c)
            im=im.filter(ImageFilter.GaussianBlur(R2.uniform(0,1.0))).resize((224,224),Image.BILINEAR)
            b=io.BytesIO(); im.save(b,"JPEG",quality=R2.randint(60,92)); open(f"data/{s}/screen/screen2_{i:04d}.jpg","wb").write(b.getvalue())
        print(s,n)
