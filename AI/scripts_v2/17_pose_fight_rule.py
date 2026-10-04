# Export YOLOv8n-pose (Ultralytics, AGPL-3.0, free) to TFLite for the app and
# implement the fight-pose rule used by lib/services/pose_fight_detector.dart.
#   pip install ultralytics
#   yolo export model=yolov8n-pose.pt format=litert imgsz=320   -> pose_yolov8n.tflite
# Run:  python scripts_v2/17_pose_fight_rule.py   (prints the fight-pose score of test_images)

import numpy as np, tensorflow as tf
from PIL import Image
_it=None
def interp():
    global _it
    if _it is None: _it=tf.lite.Interpreter('../safecity/assets/models/pose_yolov8n.tflite'); _it.allocate_tensors()
    return _it
def letterbox(im,S=320):
    im=im.convert('RGB'); W,H=im.size; s=S/max(W,H); w,h=max(1,round(W*s)),max(1,round(H*s))
    r=im.resize((w,h),Image.BOX); c=Image.new('RGB',(S,S),(114,114,114)); ox,oy=(S-w)//2,(S-h)//2; c.paste(r,(ox,oy))
    return c,ox,oy,w,h
def nms(dets,thr=0.5):
    keep=[]
    for d in sorted(dets,key=lambda d:-d[4]):
        ok=True
        for k in keep:
            x1=max(d[0],k[0]);y1=max(d[1],k[1]);x2=min(d[2],k[2]);y2=min(d[3],k[3])
            inter=max(0,x2-x1)*max(0,y2-y1); u=(d[2]-d[0])*(d[3]-d[1])+(k[2]-k[0])*(k[3]-k[1])-inter
            if u>0 and inter/u>thr: ok=False;break
        if ok: keep.append(d)
    return keep
def people(im,conf=0.25,S=320):
    """returns list of (x1,y1,x2,y2,conf,kp[17x3]) normalised to the photo (0..1)"""
    it=interp(); c,ox,oy,w,h=letterbox(im)
    x=(np.asarray(c,np.float32)/255.).transpose(2,0,1)[None]
    it.set_tensor(it.get_input_details()[0]['index'],x); it.invoke(); y=it.get_tensor(it.get_output_details()[0]['index'])[0]*1.0
    y[:4]*=S; y[5::3]*=S; y[6::3]*=S
    dets=[]
    for j in np.where(y[4]>=conf)[0]:
        cx,cy,bw,bh=y[:4,j]; kp=y[5:,j].reshape(17,3).copy()
        kp[:,0]=(kp[:,0]-ox)/w; kp[:,1]=(kp[:,1]-oy)/h
        dets.append(((cx-bw/2-ox)/w,(cy-bh/2-oy)/h,(cx+bw/2-ox)/w,(cy+bh/2-oy)/h,float(y[4,j]),kp))
    return nms(dets)

# ---------------- fight-pose rule (same as the Dart code) ----------------
import numpy as np
KV=0.3
def P_(kp,i,ar): return (kp[i,0]*ar,kp[i,1]) if kp[i,2]>=KV else None
def person(box,kp,ar):
    x1,y1,x2,y2=box[0]*ar,box[1],box[2]*ar,box[3]; h=max(y2-y1,1e-3)
    sh=[p for p in (P_(kp,5,ar),P_(kp,6,ar)) if p]; hp=[p for p in (P_(kp,11,ar),P_(kp,12,ar)) if p]
    torso=max(abs(np.mean([p[1] for p in hp])-np.mean([p[1] for p in sh])),0.15*h) if sh and hp else 0.3*h
    raise_=guard=0; wrists=[]
    for s,e,w in ((5,7,9),(6,8,10)):
        S,E,W=P_(kp,s,ar),P_(kp,e,ar),P_(kp,w,ar)
        if W: wrists.append((W,S))
        if S and W and W[1]<S[1]-0.05*torso: raise_=1
        if S and E and W and W[1]<E[1]-0.2*torso and W[1]<S[1]+0.4*torso: guard+=1
    kick=0
    for a_,k_,o_ in ((15,11,16),(16,12,15)):
        A,Hh,O=P_(kp,a_,ar),P_(kp,k_,ar),P_(kp,o_,ar)
        if A and Hh and O and A[1]<Hh[1]+1.0*torso and A[1]<O[1]-0.8*torso: kick=1
    return dict(box=(x1,y1,x2,y2),h=h,cx=(x1+x2)/2,cy=(y1+y2)/2,torso=torso,raise_=raise_,guard=guard,kick=kick,wrists=wrists)
def strike(p,q):
    x1,y1,x2,y2=q['box']; m=0.05*q['h']; chest=y1+0.55*(y2-y1)
    for W,S in p['wrists']:
        if S is None: continue
        reach=np.hypot(W[0]-S[0],W[1]-S[1])/p['torso']
        horiz=abs(W[0]-S[0])/p['torso']
        if x1-m<=W[0]<=x2+m and y1<=W[1]<=chest and reach>0.5 and horiz>0.45 and W[1]<S[1]+0.6*p['torso']: return 1
    return 0
def rule(boxes,conf,kps,ar,minc=0.5,big=0.2,dmax=1.3):
    idx=[i for i in np.argsort(-np.asarray(conf)) if conf[i]>=minc][:6]
    Ps=[person(boxes[i],kps[i],ar) for i in idx]; Ps=[p for p in Ps if p['h']>=big]
    best=0.0
    for a in range(len(Ps)):
        for b in range(a+1,len(Ps)):
            pa,pb=Ps[a],Ps[b]; mh=(pa['h']+pb['h'])/2
            if min(pa['h'],pb['h'])/max(pa['h'],pb['h'])<0.5: continue
            d=np.hypot(pa['cx']-pb['cx'],pa['cy']-pb['cy'])/mh
            if d>dmax: continue
            s=0.0
            if strike(pa,pb) or strike(pb,pa): s=max(s,0.8)
            if pa['kick'] or pb['kick']: s=max(s,0.8)
            if pa['raise_'] or pb['raise_']: s=max(s,0.65)
            if pa['guard'] and pb['guard']: s=max(s,0.75)
            elif (pa['guard'] or pb['guard']) and d<0.9: s=max(s,0.6)
            best=max(best,s)
    return best

if __name__=="__main__":
    import glob, sys
    for f in sorted(glob.glob("test_images/*")):
        try: im=Image.open(f)
        except Exception: continue
        p=people(im); W,H=im.size
        if not p: print(f,"no people"); continue
        b=np.array([d[:4] for d in p]); c=np.array([d[4] for d in p]); k=np.stack([d[5] for d in p])
        print(f, len(p), "people  fight-pose score %.2f"%rule(b,c,k,W/H))
