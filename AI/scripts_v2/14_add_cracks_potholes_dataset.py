# Road damage data from the "Cracks and Potholes in Road Images" dataset (Passos et al., UNIVALI)
# full photos + crops around marked potholes/cracks = road_damage
# crops of the same roads with NO marked damage = normal (teaches damage, not camera style)
import glob, random, os, numpy as np
from PIL import Image, ImageFilter
R=random.Random(9)
D="Cracks-and-Potholes-in-Road-Images-Dataset/Dataset"   # git clone https://github.com/biankatpas/Cracks-and-Potholes-in-Road-Images-Dataset
ds=[d for d in sorted(glob.glob(D+"/*")) if len(glob.glob(d+"/*"))==4]
R.shuffle(ds); n=len(ds); parts={"train":ds[:int(n*.8)],"validation":ds[int(n*.8):int(n*.9)],"test":ds[int(n*.9):]}
def masks(d):
    b=d+"/"+os.path.basename(d)
    c=np.asarray(Image.open(b+"_CRACK.png").convert("L"))>0; p=np.asarray(Image.open(b+"_POTHOLE.png").convert("L"))>0
    return Image.open(b+"_RAW.jpg").convert("RGB"),c,p
def crop_sq(im,cx,cy,s):
    W,H=im.size; x0=int(np.clip(cx-s/2,0,W-s)); y0=int(np.clip(cy-s/2,0,H-s)); return (x0,y0,x0+int(s),y0+int(s))
for s,dl in parts.items():
    for c in ["road_damage","normal"]: os.makedirs(f"data_extra/cracks_potholes/{s}/{c}",exist_ok=True)
    k=0
    for d in dl:
        im,cm,pm=masks(d); W,H=im.size; dmg=cm|pm
        dil=np.asarray(Image.fromarray((dmg*255).astype(np.uint8)).filter(ImageFilter.MaxFilter(31)))>0
        name=os.path.basename(d)
        if pm.mean()>0.002 or cm.mean()>0.006:
            im.crop((0,int(H*.15),W,H)).resize((224,224),Image.BOX).save(f"data_extra/cracks_potholes/{s}/road_damage/brfull_{name}.jpg",quality=92)
        # damage crops
        ys,xs=np.where(pm if pm.sum()>400 else cm)
        for j in range(2 if len(xs) else 0):
            i=R.randrange(len(xs)); sz=R.uniform(.22,.45)*W; box=crop_sq(im,xs[i],ys[i],sz)
            sub=dmg[box[1]:box[3],box[0]:box[2]]
            if pm[box[1]:box[3],box[0]:box[2]].mean()>0.02 or sub.mean()>0.035:
                im.crop(box).resize((224,224),Image.BOX).save(f"data_extra/cracks_potholes/{s}/road_damage/brcrop_{name}_{j}.jpg",quality=92)
        # clean crops (no marked damage nearby), road area = lower 65%
        for j in range(4):
            sz=R.uniform(.18,.35)*W; cx=R.uniform(.15,.85)*W; cy=R.uniform(.5,.92)*H; box=crop_sq(im,cx,cy,sz)
            if dil[box[1]:box[3],box[0]:box[2]].mean()==0:
                im.crop(box).resize((224,224),Image.BOX).save(f"data_extra/cracks_potholes/{s}/normal/brclean_{name}_{j}.jpg",quality=92); break
    print(s,{c:len(os.listdir(f"data_extra/cracks_potholes/{s}/{c}")) for c in ["road_damage","normal"]},flush=True)
