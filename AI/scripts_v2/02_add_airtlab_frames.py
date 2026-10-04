import cv2, glob, os, random
from PIL import Image
random.seed(5)
for kind,cls,pref in [("violent","fighting","airt_fight"),("non-violent","normal","airt_nonviol")]:
    vids=sorted(glob.glob(f"airt/violence-detection-dataset/{kind}/cam1/*.mp4")); random.shuffle(vids)
    n=len(vids); cut=[int(n*.8),int(n*.9)]
    for vi,v in enumerate(vids):
        s="train" if vi<cut[0] else ("validation" if vi<cut[1] else "test")
        cap=cv2.VideoCapture(v); N=int(cap.get(cv2.CAP_PROP_FRAME_COUNT)); k=6 if s=="train" else 3
        for j in range(k):
            cap.set(cv2.CAP_PROP_POS_FRAMES,int(N*(0.2+0.6*j/max(1,k-1)))); ok,fr=cap.read()
            if not ok: continue
            Image.fromarray(cv2.cvtColor(fr,cv2.COLOR_BGR2RGB)).resize((224,224)).save(f"data/{s}/{cls}/{pref}_{os.path.basename(v)[:-4]}_{j}.jpg",quality=92)
    print(kind,n)
for s in ["train","validation","test"]: print(s,{c:len(os.listdir(f"data/{s}/{c}")) for c in sorted(os.listdir(f"data/{s}"))})
