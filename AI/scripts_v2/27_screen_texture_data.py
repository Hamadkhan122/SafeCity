# Screen-texture model, part 1: training patches (128x128) at native camera resolution.
# Positive = a picture shown on a screen (simulated sub-pixel grid, aliasing moire, Bayer colour
# moire, glare, defocus) photographed by a simulated phone camera. Negative = real photos (roads,
# dashcam, everyday scenes, people) through the same camera simulation or untouched.
#   python scripts_v2/27_screen_texture_data.py train 11 ; python scripts_v2/27_screen_texture_data.py val 12
# Texture (recapture) patches at NATIVE camera resolution.
# Positive: a picture shown on an LCD / OLED screen and photographed by a phone camera
#   -> display sub-pixel grid + aliasing moire + Bayer colour moire.
# Negative: a real scene photographed by the same simulated camera (same blur, Bayer, noise,
#   sharpening, JPEG), so the ONLY difference is the screen.
import glob, random, io, os, sys, numpy as np, cv2
R=random.Random(int(sys.argv[2]) if len(sys.argv)>2 else 1); rng=np.random.default_rng(R.randint(0,10**6))
P=128
def content_pool(split):
    fs=[]
    for c in ["accident","fighting","fire","normal","road_damage"]: fs+=glob.glob(f"data/{split}/{c}/*")
    fs+=glob.glob(f"firesmoke/FIRE-SMOKE-DATASET/{'Train' if split=='train' else 'Test'}/*/*")
    return fs
def native_pool(split):
    a=sorted(glob.glob("ls_Cracks-and-Potholes-in-Road-Images-Dataset/Dataset/*/*_RAW.jpg"))+sorted(glob.glob("comma10k/imgs/*"))
    a+=sorted(glob.glob("firesmoke/FIRE-SMOKE-DATASET/*/*/*"))+sorted(glob.glob("imagenet-sample-images/*.JPEG"))
    a+=sorted(glob.glob("data_extra/negc/*.jpg"))   # web photos of people / places (native-resolution crops)
    a=[f for f in a]; R2=random.Random(5); R2.shuffle(a); n=len(a)
    return a[:int(n*.85)] if split=="train" else a[int(n*.85):]
def camera(img):
    """img float32 HxWx3 0..255 (scene radiance on the sensor) -> simulated phone JPEG patch"""
    if R.random()<.9: img=cv2.GaussianBlur(img,(0,0),R.uniform(.4,1.3))         # lens / focus
    h,w=img.shape[:2]
    if R.random()<.8:                                                            # Bayer CFA + demosaic
        bay=np.zeros((h,w),np.float32)
        bay[0::2,0::2]=img[0::2,0::2,2]; bay[0::2,1::2]=img[0::2,1::2,1]; bay[1::2,0::2]=img[1::2,0::2,1]; bay[1::2,1::2]=img[1::2,1::2,0]
        img=cv2.cvtColor(np.clip(bay,0,255).astype(np.uint8),cv2.COLOR_BayerRG2RGB).astype(np.float32)
    img=img+rng.normal(0,R.uniform(.5,5),img.shape).astype(np.float32)        # sensor noise
    if R.random()<.6: img=cv2.bilateralFilter(np.clip(img,0,255).astype(np.uint8),5,R.uniform(10,40),3).astype(np.float32)  # denoise
    if R.random()<.7:                                                            # sharpening
        b=cv2.GaussianBlur(img,(0,0),1.0); img=img+R.uniform(.2,1.2)*(img-b)
    img=np.clip(img,0,255).astype(np.uint8)
    ok,buf=cv2.imencode(".jpg",img,[cv2.IMWRITE_JPEG_QUALITY,R.randint(65,95)])
    return cv2.imdecode(buf,1)
def screen_capture(src):
    """picture on a screen -> sensor image of size ~P*2 (then crop P)"""
    S=P*2
    k=R.choice([R.uniform(.55,1.6),R.uniform(1.6,4.0),R.uniform(4,9)])        # camera pixels per display pixel
    nd=int(S/k)+4                                                                # display pixels needed
    # display content: random crop of the source picture, at display resolution
    H,W=src.shape[:2]; c=R.uniform(.15,1.0)*min(H,W); x0=R.uniform(0,W-c); y0=R.uniform(0,H-c)
    disp=cv2.resize(src[int(y0):int(y0+c),int(x0):int(x0+c)],(nd,nd),interpolation=cv2.INTER_AREA).astype(np.float32)
    disp=255*(disp/255)**R.uniform(.8,1.2)
    # sub-pixel layout: each display pixel = 3x3 block (RGB stripes) or PenTile-like
    sub=3; up=np.repeat(np.repeat(disp,sub,0),sub,1)
    mask=np.zeros((sub,sub,3),np.float32)
    if R.random()<.7:
        for ci in range(3): mask[:,ci,2-ci if R.random()<.5 else ci]=1.0       # vertical RGB stripes
    else:
        mask[0,0,0]=mask[0,2,0]=1; mask[1,1,1]=mask[0,1,1]=mask[2,1,1]=1; mask[2,0,2]=mask[2,2,2]=1   # diamond-ish
    gap=R.choice([R.uniform(.0,.35),R.uniform(.35,.8)]); mask=mask*(1-gap)+gap*mask.mean()
    up=up*np.tile(mask,(nd,nd,1))*R.uniform(2.2,3.0)
    # project onto the sensor: rotation + scale (+ slight perspective)
    ang=R.uniform(-12,12); sc=S/(nd*sub)*R.uniform(1.0,1.15)
    M=cv2.getRotationMatrix2D((nd*sub/2,nd*sub/2),ang,sc); M[0,2]+=S/2-nd*sub/2; M[1,2]+=S/2-nd*sub/2
    if R.random()<.5:
        src_pts=np.float32([[0,0],[nd*sub,0],[nd*sub,nd*sub],[0,nd*sub]]); j=R.uniform(0,.08)*S
        dst=cv2.transform(src_pts[None],M)[0]+rng.uniform(-j,j,(4,2)).astype(np.float32)
        sensor=cv2.warpPerspective(up,cv2.getPerspectiveTransform(src_pts,dst),(S,S),flags=cv2.INTER_LINEAR)
    else:
        # INTER_LINEAR = point sampling of the grid -> aliasing moire when k is small
        sensor=cv2.warpAffine(up,M,(S,S),flags=cv2.INTER_LINEAR)
    # screen look: lifted blacks, colour cast, glare
    sensor=sensor*R.uniform(.7,1.0)+R.uniform(0,40)
    sensor=sensor*np.array([R.uniform(.9,1.05),R.uniform(.95,1.05),R.uniform(.95,1.15)],np.float32)
    if R.random()<.4:
        yy,xx=np.mgrid[0:S,0:S]; cx,cy=R.uniform(0,S),R.uniform(0,S)
        sensor+=R.uniform(10,80)*np.exp(-((xx-cx)**2+(yy-cy)**2)/(2*(R.uniform(.2,.6)*S)**2))[...,None]
    if R.random()<.35: sensor=cv2.GaussianBlur(sensor,(0,0),R.uniform(1.0,2.2))   # defocused shot: grid fades, moire stays
    return sensor
def real_capture(f):
    im=cv2.imread(f)
    if im is None: return None
    im=im[:,:,::-1].astype(np.float32); H,W=im.shape[:2]; S=P*2
    if min(H,W)<S: im=cv2.resize(im,None,fx=S/min(H,W)*1.05,fy=S/min(H,W)*1.05,interpolation=cv2.INTER_CUBIC); H,W=im.shape[:2]
    s=R.uniform(1.0,min(2.0,min(H,W)/S))                                         # also slightly downscaled views
    c=int(S*s); x0=R.randint(0,W-c); y0=R.randint(0,H-c)
    im=cv2.resize(im[y0:y0+c,x0:x0+c],(S,S),interpolation=cv2.INTER_AREA)
    return im
def crop(img):
    h,w=img.shape[:2]; x=R.randint(0,w-P); y=R.randint(0,h-P); return img[y:y+P,x:x+P]
if __name__=="__main__":
    split=sys.argv[1]; N={"train":9000,"val":1500}[split]
    cont=content_pool("train" if split=="train" else "test"); nat=native_pool("train" if split=="train" else "test")
    X=np.zeros((2*N,P,P,3),np.uint8); y=np.zeros(2*N,np.uint8); i=0
    while i<2*N:
        if i%2==0:
            src=cv2.imread(R.choice(cont))
            if src is None: continue
            img=camera(np.clip(screen_capture(src[:,:,::-1].astype(np.float32)),0,255)); lab=1
        else:
            im=real_capture(R.choice(nat))
            if im is None: continue
            img=camera(im) if R.random()<.5 else np.clip(im,0,255).astype(np.uint8); lab=0
        X[i]=crop(img); y[i]=lab; i+=1
        if i%2000==0: print(split,i,flush=True)
    np.savez_compressed(f"tex_{split}.npz",X=X,y=y)
