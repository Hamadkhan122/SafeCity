import glob, numpy as np
exec(open("scripts_v2/05_extract_features_screen.py").read().split("for s in")[0])
for s in ["train","validation","test"]:
    F=sorted(glob.glob(f"data/{s}/screen/screen2_*")); V=3 if s=="train" else 1
    np.savez(f"embs2_{s}.npz",X=np.stack([emb(F,v) for v in range(V)]),f=np.array(F)); print(s,flush=True)
