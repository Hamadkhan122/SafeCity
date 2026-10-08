import glob, numpy as np
exec(open("scripts_v2/05_extract_features_screen.py").read().split("for s in")[0])
for s in ["train","validation","test"]:
    for c,ci in [("fighting",1),("normal",3)]:
        F=sorted(glob.glob(f"data/{s}/{c}/airt_*")); V=3 if s=="train" else 1
        np.savez(f"emba_{s}_{c}.npz",X=np.stack([emb(F,v) for v in range(V)]),y=np.full(len(F),ci),f=np.array(F))
    print(s,flush=True)
