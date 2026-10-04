# Synthetic "photo of a screen" generator (laptop / monitor / phone showing a picture)
import os, glob, random, numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
R=random.Random(11); rng=np.random.default_rng(11)
def browser_canvas(content, W=800, H=500):
    dark=R.random()<0.25
    cv=Image.new("RGB",(W,H),(32,33,36) if dark else (255,255,255)); d=ImageDraw.Draw(cv)
    top=0
    if R.random()<0.75:  # browser chrome
        top=int(H*R.uniform(0.08,0.16))
        d.rectangle([0,0,W,top],fill=(222,225,230) if not dark else (53,54,58))
        d.rounded_rectangle([int(W*.12),int(top*.45),int(W*.8),int(top*.85)],radius=8,fill=(255,255,255) if not dark else (32,33,36))
        for i in range(R.randint(1,4)): d.rectangle([10+i*130,4,130+i*130,int(top*.38)],fill=(250,250,250) if not dark else (70,70,75))
    mode=R.random()
    if mode<0.45:  # single big image
        s=R.uniform(0.55,1.0); w=int(W*s); h=int(min(H-top,w*R.uniform(0.6,0.8)))
        cv.paste(content.resize((w,h)),((W-w)//2,top+(H-top-h)//2))
    elif mode<0.75:  # image results grid
        cols=R.randint(3,5); gw=W//cols
        for r in range(3):
            for c in range(cols):
                y=top+10+r*(gw*3//4+8)
                if y>H: break
                im=content if (r==1 and c==1) or R.random()<0.3 else content.transpose(Image.FLIP_LEFT_RIGHT).rotate(0)
                im=ImageEnhance.Brightness(im).enhance(R.uniform(.7,1.3))
                cv.paste(im.resize((gw-8,gw*3//4)),(c*gw+4,y))
    else:  # image + side text lines
        w=int(W*0.55); h=int(w*0.7); cv.paste(content.resize((w,h)),(10,top+10))
        for i in range(12):
            y=top+15+i*22; d.rectangle([w+30,y,w+30+R.randint(80,W-w-50),y+8],fill=(120,120,120))
    return cv
def display_effect(cv):
    a=np.asarray(cv.resize((cv.width*2,cv.height*2),Image.NEAREST),np.float32)
    if R.random()<0.8:  # RGB sub-pixel stripes
        p=np.zeros((1,3,3),np.float32); p[0,0,0]=p[0,1,1]=p[0,2,2]=1
        mask=np.tile(p,(a.shape[0],a.shape[1]//3+1,1))[:, :a.shape[1]]
        st=R.uniform(0.25,0.6); a=a*(1-st)+a*mask*st*3
    if R.random()<0.6:  # pixel grid lines
        g=R.choice([2,3,4]); a[::g,:,:]*=R.uniform(.6,.9); a[:,::g,:]*=R.uniform(.7,.95)
    a=a*R.uniform(.75,1.05)+R.uniform(-10,25); a[...,2]+=R.uniform(0,18)  # screen gamma / blue tint
    return Image.fromarray(np.clip(a,0,255).astype(np.uint8))
def perspective(im, out_size, bg, full):
    W,H=out_size; w,h=im.size
    if full: m=R.uniform(-0.12,0.02); quad=[(W*R.uniform(m,m+.08),H*R.uniform(m,m+.08)),(W*(1-R.uniform(m,m+.08)),H*R.uniform(m,m+.08)),(W*(1-R.uniform(m,m+.08)),H*(1-R.uniform(m,m+.08))),(W*R.uniform(m,m+.08),H*(1-R.uniform(m,m+.08)))]
    else:
        cx,cy=W*R.uniform(.4,.6),H*R.uniform(.35,.55); sw,sh=W*R.uniform(.45,.85)/2,H*R.uniform(.35,.65)/2; j=lambda: R.uniform(-.12,.12)*sw
        quad=[(cx-sw+j(),cy-sh+j()),(cx+sw+j(),cy-sh+j()),(cx+sw+j(),cy+sh+j()),(cx-sw+j(),cy+sh+j())]
    # solve homography mapping output quad -> source rect
    src=[(0,0),(w,0),(w,h),(0,h)]; A=[];B=[]
    for (x,y),(u,v) in zip(quad,src):
        A+= [[x,y,1,0,0,0,-u*x,-u*y],[0,0,0,x,y,1,-v*x,-v*y]]; B+=[u,v]
    coef=np.linalg.solve(np.array(A),np.array(B))
    warped=im.transform((W,H),Image.PERSPECTIVE,coef,Image.BILINEAR)
    mask=Image.new("L",(w,h),255).transform((W,H),Image.PERSPECTIVE,coef,Image.BILINEAR)
    out=bg.resize((W,H)).copy(); out.paste(warped,(0,0),mask); return out
def glare(im):
    if R.random()<0.6:
        W,H=im.size; g=Image.new("L",(W,H),0); d=ImageDraw.Draw(g)
        x,y=R.uniform(0,W),R.uniform(0,H); r=R.uniform(.15,.5)*W; d.ellipse([x-r,y-r*.6,x+r,y+r*.6],fill=int(R.uniform(60,160)))
        g=g.filter(ImageFilter.GaussianBlur(r/3)); im=Image.composite(Image.new("RGB",(W,H),(255,255,255)),im,g)
    return im
def make(content, bg):
    if R.random()<0.15: cv=content.resize((450,800))  # phone screen
    else: cv=browser_canvas(content)
    full=R.random()<0.4
    if not full:  # bezel
        b=int(cv.width*R.uniform(.015,.05)); fr=Image.new("RGB",(cv.width+2*b,cv.height+2*b),tuple(int(x) for x in rng.integers(0,40,3))); fr.paste(cv,(b,b)); cv=fr
    cv=display_effect(cv)
    bg=ImageEnhance.Brightness(bg).enhance(R.uniform(.3,.8))
    out=perspective(cv,(672,672),bg,full)
    out=glare(out).filter(ImageFilter.GaussianBlur(R.uniform(0,1.2)))
    out=out.resize((224,224),Image.BILINEAR if R.random()<.5 else Image.NEAREST)  # aliasing -> moire
    a=np.asarray(out,np.float32)+rng.normal(0,R.uniform(1,6),(224,224,3)); return Image.fromarray(np.clip(a,0,255).astype(np.uint8))
if __name__=="__main__":
    import io
    N={"train":1500,"validation":250,"test":250}
    for s,n in N.items():
        cont=[f for c in ["accident","fighting","fire","road_damage","normal"] for f in glob.glob(f"data/{s}/{c}/*")]
        bgs=[f for p in ["objects","misc","street_people"] for f in glob.glob(f"data/{s}/normal/{p}_*")]
        os.makedirs(f"data/{s}/screen",exist_ok=True)
        for i in range(n):
            im=make(Image.open(R.choice(cont)).convert("RGB"),Image.open(R.choice(bgs)).convert("RGB"))
            b=io.BytesIO(); im.save(b,"JPEG",quality=R.randint(60,92)); open(f"data/{s}/screen/screen_{i:04d}.jpg","wb").write(b.getvalue())
        print(s,n)
